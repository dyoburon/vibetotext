"""Text-to-speech status reports — neural TTS via edge-tts, fire-and-forget."""

import atexit
import asyncio
import json
import os
import platform
import subprocess
import re
import tempfile
import threading
from pathlib import Path

SYSTEM = platform.system()

_active_process: subprocess.Popen | None = None
_tts_lock = threading.Lock()
_stop_event = threading.Event()

# edge-tts voice settings (JARVIS-style: Ryan British, fast & crisp)
_EDGE_VOICE = "en-GB-RyanNeural"
_EDGE_RATE = "+12%"
_EDGE_PITCH = "+1Hz"

# Chunking threshold: texts longer than this many chars get chunked
_CHUNK_THRESHOLD = 100


def _load_config() -> dict:
    """Load TTS settings from ~/.vibetotext/config.json."""
    try:
        config_file = Path.home() / ".vibetotext" / "config.json"
        if config_file.exists():
            with open(config_file, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def stop():
    """Kill the active TTS subprocess if still running."""
    global _active_process
    _stop_event.set()
    with _tts_lock:
        if _active_process is not None:
            try:
                _active_process.kill()
                _active_process.wait(timeout=1)
            except Exception:
                pass
            _active_process = None


def _play_mp3(path: str, first_chunk: bool = True):
    """Play an mp3 file in the background. first_chunk adds startup delay to prevent clipping."""
    try:
        af_args = ["-af", "adelay=300|300"] if first_chunk else []
        if SYSTEM == "Windows":
            try:
                return subprocess.Popen(
                    ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet"] + af_args + [path],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except FileNotFoundError:
                return subprocess.Popen(
                    f'start "" "{path}"',
                    shell=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        elif SYSTEM == "Darwin":
            return subprocess.Popen(
                ["afplay", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            for player in [["mpv", "--no-video", path], ["ffplay", "-nodisp", "-autoexit"] + af_args + [path]]:
                try:
                    return subprocess.Popen(player, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except FileNotFoundError:
                    continue
    except Exception:
        pass
    return None


def _play_mp3_blocking(path: str, first_chunk: bool = True) -> bool:
    """Play an mp3 and wait for it to finish. Returns True if completed."""
    proc = _play_mp3(path, first_chunk=first_chunk)
    if proc is None:
        return False
    global _active_process
    with _tts_lock:
        _active_process = proc
    proc.wait()
    return proc.returncode == 0


def _split_sentences(text: str) -> list[str]:
    """Split text into sentences for chunked playback."""
    # Split on sentence-ending punctuation followed by space or end of string
    parts = re.split(r'(?<=[.!?])\s+', text.strip())
    # Merge very short fragments with the previous sentence
    sentences = []
    for part in parts:
        if sentences and len(sentences[-1]) < 30:
            sentences[-1] += " " + part
        else:
            sentences.append(part)
    return [s for s in sentences if s.strip()]


def _generate_mp3(text: str, voice: str, rate: str, pitch: str, path: str):
    """Generate mp3 from text using edge-tts."""
    import edge_tts
    loop = asyncio.new_event_loop()
    try:
        communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        loop.run_until_complete(communicate.save(path))
    finally:
        loop.close()


def _speak_edge_tts(text: str, config: dict):
    """Generate and play speech using edge-tts (neural voice)."""
    global _active_process

    voice = config.get("tts_voice") or _EDGE_VOICE
    rate = config.get("tts_edge_rate") or _EDGE_RATE
    pitch = config.get("tts_edge_pitch") or _EDGE_PITCH

    # Short text: generate and play in one shot
    if len(text) <= _CHUNK_THRESHOLD:
        mp3_path = os.path.join(tempfile.gettempdir(), "vibetotext_tts.mp3")
        _generate_mp3(text, voice, rate, pitch, mp3_path)
        with _tts_lock:
            _active_process = _play_mp3(mp3_path)
        return

    # Long text: rolling chunks of 2-3 sentences — generate next while playing current
    sentences = _split_sentences(text)
    if not sentences:
        return

    # Group sentences into chunks of ~2-3
    chunks = []
    current_chunk = []
    current_len = 0
    for s in sentences:
        current_chunk.append(s)
        current_len += len(s)
        # Target ~120-200 chars per chunk (2-3 sentences)
        if current_len >= 120:
            chunks.append(" ".join(current_chunk))
            current_chunk = []
            current_len = 0
    if current_chunk:
        chunks.append(" ".join(current_chunk))

    if not chunks:
        return

    tmp_dir = tempfile.gettempdir()

    # Generate first chunk
    path_0 = os.path.join(tmp_dir, "vibetotext_tts_0.mp3")
    _generate_mp3(chunks[0], voice, rate, pitch, path_0)

    if _stop_event.is_set():
        return

    for i, chunk in enumerate(chunks):
        if _stop_event.is_set():
            return

        current_path = os.path.join(tmp_dir, f"vibetotext_tts_{i}.mp3")

        # Start generating next chunk in parallel
        next_thread = None
        if i + 1 < len(chunks):
            next_path = os.path.join(tmp_dir, f"vibetotext_tts_{i + 1}.mp3")
            next_thread = threading.Thread(
                target=_generate_mp3,
                args=(chunks[i + 1], voice, rate, pitch, next_path),
                daemon=True,
            )
            next_thread.start()

        # Play current chunk
        _play_mp3_blocking(current_path, first_chunk=(i == 0))

        # Wait for next chunk to finish generating
        if next_thread:
            next_thread.join()


def _speak_fallback(text: str, config: dict):
    """Fallback to platform TTS when edge-tts is unavailable."""
    global _active_process
    rate = config.get("tts_rate", 185)
    volume = config.get("tts_volume", 80)

    if SYSTEM == "Darwin":
        cmd = ["say", "-r", str(rate), "-v", "Daniel", text]
        _active_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif SYSTEM == "Windows":
        escaped = text.replace("'", "''")
        sapi_rate = max(-10, min(10, round((rate - 200) / 20)))
        ps_cmd = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            f"$s.Rate = {sapi_rate}; $s.Volume = {volume}; "
            f"$s.Speak('{escaped}')"
        )
        _active_process = subprocess.Popen(
            ["powershell", "-NoProfile", "-Command", ps_cmd],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=0x08000000,
        )
    else:
        try:
            cmd = ["espeak-ng", "-s", str(rate), "-a", str(min(200, volume * 2)), text]
            _active_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            cmd = ["spd-say", "-r", str(max(-100, min(100, rate - 200))), text]
            _active_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def speak(text: str) -> None:
    """Speak text — fire-and-forget, cancels previous."""
    config = _load_config()
    if not config.get("tts_enabled", True):
        return
    if not text or not text.strip():
        return

    # Cancel previous speech
    stop()
    _stop_event.clear()

    def _run():
        try:
            _speak_edge_tts(text, config)
        except Exception:
            try:
                _speak_fallback(text, config)
            except Exception:
                pass

    # Run in background thread to avoid blocking
    t = threading.Thread(target=_run, daemon=True)
    t.start()


def _count_words(text: str) -> int:
    return len(text.split())


def _count_paragraphs(text: str) -> int:
    return len([p for p in text.strip().split("\n\n") if p.strip()])


def _count_steps(text: str) -> int:
    return len(re.findall(r"(?m)^[\s]*(?:\d+[\.\):]|[-*])\s", text))


def speak_status(mode: str, text: str, output: str, file_count: int = 0) -> None:
    """Generate and speak a concise JARVIS-style status message."""
    try:
        if mode == "greppy":
            msg = f"Located {file_count} files, sir" if file_count != 1 else "Located one file, sir"
        elif mode == "cleanup":
            n = _count_paragraphs(output)
            msg = f"All tidied up. {n} paragraphs ready"
        elif mode == "plan":
            n = _count_steps(output)
            msg = f"Plan's ready. {n} steps laid out"
        else:
            n = _count_words(text)
            msg = f"Got it. {n} words captured"
        speak(msg)
    except Exception:
        pass


@atexit.register
def _cleanup():
    stop()
