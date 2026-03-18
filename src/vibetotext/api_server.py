"""HTTP API server — exposes TTS and status endpoints for external tools."""

import json
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

from vibetotext.tts import speak

DEFAULT_PORT = 7865


class _Handler(BaseHTTPRequestHandler):
    """Handle API requests."""

    def log_message(self, format, *args):
        # Suppress default stderr logging
        pass

    def _send_json(self, status: int, data: dict):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/status":
            self._send_json(200, {"status": "ok", "service": "vibetotext"})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/speak":
            self._handle_speak()
        else:
            self._send_json(404, {"error": "not found"})

    def _handle_speak(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            data = json.loads(body)
            text = data.get("text", "").strip()

            if not text:
                self._send_json(400, {"error": "missing 'text' field"})
                return

            speak(text)
            self._send_json(200, {"status": "speaking", "text": text})

        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid JSON"})
        except Exception as e:
            self._send_json(500, {"error": str(e)})


class ApiServer:
    """Lightweight HTTP server for TTS and status endpoints."""

    def __init__(self, port: int = DEFAULT_PORT):
        self.port = port
        self._server: HTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self):
        try:
            self._server = HTTPServer(("127.0.0.1", self.port), _Handler)
            self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
            self._thread.start()
            print(f"[API] Server running on http://127.0.0.1:{self.port}")
            print(f"[API]   POST /api/speak  {{\"text\": \"...\"}}")
            print(f"[API]   GET  /api/status")
        except OSError as e:
            print(f"[API] Failed to start server on port {self.port}: {e}")

    def stop(self):
        if self._server:
            self._server.shutdown()
            self._server = None

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"
