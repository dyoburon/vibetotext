"""Unix domain socket server for external transcription requests.

Allows external processes (e.g., Jarvis) to send audio data and receive
transcription results using the already-loaded Whisper model.

Protocol (newline-delimited JSON):
  Request:  {"type": "transcribe", "audio_b64": "<base64 float32>", "sample_rate": 16000}
  Response: {"type": "result", "text": "...", "duration_ms": 450}
  Error:    {"type": "error", "message": "..."}
"""

import base64
import json
import logging
import os
import socket
import threading
import time

import numpy as np

SOCKET_PATH = "/tmp/vibetotext.sock"
LOG_DIR = os.environ.get("TEMP", os.environ.get("TMPDIR", "/tmp"))
LOG_PATH = os.path.join(LOG_DIR, "vibetotext_socket.log")

_log = logging.getLogger("vibetotext.socket")
_log.setLevel(logging.DEBUG)
_fh = logging.FileHandler(LOG_PATH)
_fh.setFormatter(logging.Formatter("[%(asctime)s] %(message)s", datefmt="%H:%M:%S"))
_log.addHandler(_fh)


class TranscriptionSocketServer:
    """Unix domain socket server sharing the loaded Whisper model."""

    def __init__(self, transcriber):
        self.transcriber = transcriber
        self._server_socket: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._running = False

    def start(self):
        """Start the socket server in a daemon thread."""
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        self._server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server_socket.bind(SOCKET_PATH)
        self._server_socket.listen(2)
        self._server_socket.settimeout(1.0)
        self._running = True

        self._thread = threading.Thread(target=self._serve_loop, daemon=True)
        self._thread.start()
        _log.info(f"Listening on {SOCKET_PATH}")

    def stop(self):
        """Stop the socket server and clean up."""
        self._running = False
        if self._server_socket:
            self._server_socket.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

    def _serve_loop(self):
        """Main accept loop (runs in daemon thread)."""
        while self._running:
            try:
                conn, _ = self._server_socket.accept()
                handler = threading.Thread(
                    target=self._handle_client,
                    args=(conn,),
                    daemon=True,
                )
                handler.start()
            except socket.timeout:
                continue
            except OSError as e:
                _log.error(f"Accept loop died: {e}", exc_info=True)
                break

    def _handle_client(self, conn: socket.socket):
        """Handle a single client connection."""
        try:
            conn.settimeout(30.0)
            data = b""
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
                if b"\n" in data:
                    break

            line = data.split(b"\n")[0]
            request = json.loads(line)

            if request.get("type") != "transcribe":
                self._send_response(conn, {"type": "error", "message": f"Unknown type: {request.get('type')}"})
                return

            audio_b64 = request.get("audio_b64", "")
            sample_rate = request.get("sample_rate", 16000)
            raw_bytes = base64.b64decode(audio_b64)
            audio = np.frombuffer(raw_bytes, dtype=np.float32)

            if len(audio) == 0:
                self._send_response(conn, {"type": "error", "message": "Empty audio data"})
                return

            start = time.time()
            text = self.transcriber.transcribe(audio, sample_rate=sample_rate)
            duration_ms = int((time.time() - start) * 1000)

            self._send_response(conn, {
                "type": "result",
                "text": text,
                "duration_ms": duration_ms,
            })

        except Exception as e:
            _log.error(f"Client handler error: {e}", exc_info=True)
            self._send_response(conn, {"type": "error", "message": str(e)})
        finally:
            conn.close()

    def _send_response(self, conn: socket.socket, data: dict):
        """Send JSON response to client."""
        try:
            conn.sendall((json.dumps(data) + "\n").encode())
        except Exception:
            pass
