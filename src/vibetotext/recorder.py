"""Audio recording with hotkey trigger."""

import numpy as np
import sounddevice as sd
from enum import Enum, auto
from typing import Optional
import threading
import queue
import tempfile
import os
import time

# Persistent log file for debugging
_LOG_FILE = os.path.join(tempfile.gettempdir(), 'vibetotext_debug.log')


def _log(msg: str):
    """Write timestamped message to debug log."""
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    try:
        with open(_LOG_FILE, 'a') as f:
            f.write(f"[{timestamp}] {msg}\n")
    except Exception:
        pass


class AudioRecorder:
    """Records audio from microphone."""

    NUM_BARS = 25
    FFT_SIZE = 512
    SMOOTHING = 0.7  # 70% previous, 30% new (like Web Audio smoothingTimeConstant)
    SILENCE_THRESHOLD = 0.08
    MIN_FREQ_BIN = 4  # Skip sub-bass rumble (~125Hz at 16kHz SR)

    def __init__(self, sample_rate: int = 16000, device: int | None = None):
        self.sample_rate = sample_rate
        self.device = device
        self.recording = False
        self.stream = None  # Guard against double-stop
        self.audio_queue = queue.Queue()
        self._audio_data = []
        self.on_level = None  # Callback for audio level updates
        self._prev_levels = np.zeros(self.NUM_BARS)  # For smoothing

    def _callback(self, indata, frames, time, status):
        """Callback for sounddevice stream.

        IMPORTANT: This runs on a real-time audio thread.
        Must NOT do any blocking I/O (file writes, etc.) to avoid deadlock
        when stream.stop() waits for this callback to complete.
        """
        if not self.recording:
            return  # Exit early if not recording (helps with clean shutdown)

        self._audio_data.append(indata.copy())

        # Calculate waveform visualization using FFT frequency analysis
        if self.on_level:
            audio = indata.flatten()

            # Gate on RMS - treat very quiet input as silence
            rms = np.sqrt(np.mean(audio**2))
            base_level = min(1.0, rms * 100)

            if base_level < self.SILENCE_THRESHOLD:
                # Smooth decay to zero
                self._prev_levels *= self.SMOOTHING
                self.on_level(self._prev_levels.tolist())
                return

            # Zero-pad to FFT_SIZE if needed, then compute FFT
            if len(audio) < self.FFT_SIZE:
                audio = np.pad(audio, (0, self.FFT_SIZE - len(audio)))
            else:
                audio = audio[:self.FFT_SIZE]

            # Apply Hanning window to reduce spectral leakage
            window = np.hanning(len(audio))
            spectrum = np.abs(np.fft.rfft(audio * window))

            # Convert to dB-like scale (mimics getByteFrequencyData)
            spectrum = np.clip(spectrum, 1e-10, None)
            spectrum_db = 20 * np.log10(spectrum)
            # Normalize: map roughly -60dB..0dB to 0..1
            spectrum_norm = np.clip((spectrum_db + 60) / 60, 0, 1)

            usable_bins = len(spectrum_norm) - self.MIN_FREQ_BIN
            levels = np.zeros(self.NUM_BARS)

            # Exponential frequency band mapping (more bars for low/mid)
            for i in range(self.NUM_BARS):
                # Map bar index to frequency range with power curve
                lo = int(self.MIN_FREQ_BIN + usable_bins * ((i / self.NUM_BARS) ** 2.5))
                hi = int(self.MIN_FREQ_BIN + usable_bins * (((i + 1) / self.NUM_BARS) ** 2.5))
                hi = max(hi, lo + 1)  # At least one bin per bar

                avg = np.mean(spectrum_norm[lo:hi])

                # Bass reduction for first few bars
                if i < 4:
                    avg *= 0.5 + (i * 0.125)  # 0.5, 0.625, 0.75, 0.875

                levels[i] = avg

            # Temporal smoothing
            levels = self._prev_levels * self.SMOOTHING + levels * (1 - self.SMOOTHING)
            self._prev_levels = levels

            self.on_level(levels.tolist())

    def start(self):
        """Start recording."""
        _log("START: Beginning recording")
        self._audio_data = []
        self._prev_levels = np.zeros(self.NUM_BARS)
        self.recording = True

        # Log audio device info
        try:
            if self.device is not None:
                device_info = sd.query_devices(self.device)
                _log(f"START: Using configured device: {device_info['name']} (index {self.device})")
                print(f"[AUDIO] Using configured device: {device_info['name']} (index {self.device})")
            else:
                device_info = sd.query_devices(kind='input')
                _log(f"START: Using system default: {device_info['name']}")
                print(f"[AUDIO] Using system default: {device_info['name']}")
            print(f"[AUDIO] Sample rate: {self.sample_rate}, Channels: 1")
        except Exception as e:
            _log(f"START: Could not query device info: {e}")
            print(f"[AUDIO] Could not query device info: {e}")

        self.stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype=np.float32,
            callback=self._callback,
            device=self.device,
        )
        self.stream.start()
        _log("START: Stream started successfully")

    def stop(self) -> np.ndarray:
        """Stop recording and return audio data."""
        _log("STOP: Setting recording=False")
        self.recording = False

        # Guard: if stream doesn't exist or was already stopped, return empty
        if self.stream is None:
            _log("STOP: No stream to stop (already stopped or never started)")
            return np.array([], dtype=np.float32)

        # Grab and clear the reference so a concurrent call can't double-stop
        stream = self.stream
        self.stream = None

        # Abort stream (non-blocking, avoids waiting for audio callback)
        _log("STOP: Calling stream.abort()...")
        stop_start = time.time()
        try:
            stream.abort()
            stop_elapsed = time.time() - stop_start
            _log(f"STOP: stream.abort() completed in {stop_elapsed:.3f}s")
        except Exception as e:
            _log(f"STOP: stream.abort() FAILED: {e}")

        _log("STOP: Calling stream.close()...")
        close_start = time.time()
        try:
            stream.close()
            close_elapsed = time.time() - close_start
            _log(f"STOP: stream.close() completed in {close_elapsed:.3f}s")
        except Exception as e:
            _log(f"STOP: stream.close() FAILED: {e}")

        if not self._audio_data:
            _log("STOP: No audio data captured!")
            print("[AUDIO] No audio data captured!")
            return np.array([], dtype=np.float32)

        # Concatenate all recorded chunks
        audio = np.concatenate(self._audio_data, axis=0).flatten()

        # Log audio stats
        duration = len(audio) / self.sample_rate
        max_amplitude = np.max(np.abs(audio)) if len(audio) > 0 else 0
        rms = np.sqrt(np.mean(audio**2)) if len(audio) > 0 else 0
        _log(f"STOP: Captured {duration:.2f}s, max_amp={max_amplitude:.4f}, rms={rms:.6f}")
        print(f"[AUDIO] Captured {duration:.2f}s, {len(audio)} samples")
        print(f"[AUDIO] Max amplitude: {max_amplitude:.4f}, RMS: {rms:.6f}")

        return audio


class _Msg(Enum):
    """Message types for the HotkeyListener worker queue."""
    START = auto()
    STOP = auto()
    TIMEOUT = auto()
    SHUTDOWN = auto()


class HotkeyListener:
    """Listens for multiple hotkeys to toggle recording.

    Architecture: queue-based actor model (deadlock-free by construction).

    The pynput listener thread and timer thread are pure message producers
    that never block.  A single worker thread is the sole consumer,
    processing start/stop/timeout messages sequentially.  Because the
    worker processes messages in FIFO order, recorder.start() always
    completes before recorder.stop() can begin — no races, no locks
    needed on state.

    State machine (owned exclusively by the worker thread):
        IDLE  ---(START msg)---> RECORDING
        RECORDING ---(STOP/TIMEOUT msg)---> PROCESSING
        PROCESSING ---(on_stop complete)---> IDLE
    """

    # Cross-platform key name normalization.
    # On Windows/Linux, pynput reports side-specific names (ctrl_l, alt_r, etc.)
    # We normalize these to generic names to match hotkey definitions.
    _KEY_ALIASES = {
        "ctrl_l": "ctrl", "ctrl_r": "ctrl",
        "alt_l": "alt", "alt_r": "alt",
        "shift_l": "shift", "shift_r": "shift",
        "cmd_l": "cmd", "cmd_r": "cmd",
        "super_l": "cmd", "super_r": "cmd",  # Linux reports Super as super_l/r
    }

    @classmethod
    def _normalize_key(cls, key_name: str) -> str:
        """Normalize platform-specific key names to generic names."""
        return cls._KEY_ALIASES.get(key_name, key_name)

    def __init__(self, hotkeys: dict = None, max_recording_seconds: int = 60):
        if hotkeys is None:
            hotkeys = {"ctrl+shift": "transcribe"}
        self.hotkeys = hotkeys
        self.max_recording_seconds = max_recording_seconds
        self.on_start = None
        self.on_stop = None

        # Pynput thread state (only touched by pynput thread — no lock needed)
        self._pressed = set()

        # Worker thread state (only touched by worker thread — no lock needed)
        self._state = "idle"  # "idle", "recording", "processing"
        self._active_mode = None
        self._active_parts = None
        self._timeout_timer = None

        # The queue is the only synchronization primitive
        self._queue = queue.Queue()

    def _cancel_timeout(self):
        """Cancel any pending timeout timer."""
        if self._timeout_timer:
            self._timeout_timer.cancel()
            self._timeout_timer = None

    def _handle_start(self, mode, parts):
        """Process a START message. Only called by worker thread."""
        if self._state != "idle":
            _log(f"WORKER: Ignoring START({mode}), state={self._state}")
            return

        # Non-recording modes: fire callback immediately, stay idle
        if mode in ("history", "viz"):
            _log(f"WORKER: Instant mode={mode}, calling on_start")
            if self.on_start:
                try:
                    self.on_start(mode)
                except Exception as e:
                    _log(f"WORKER: on_start({mode}) raised: {e}")
            return

        self._state = "recording"
        self._active_mode = mode
        self._active_parts = parts
        _log(f"WORKER: state -> recording, mode={mode}")

        # Start timeout timer (enqueues TIMEOUT, never calls us directly)
        self._cancel_timeout()
        self._timeout_timer = threading.Timer(
            self.max_recording_seconds,
            lambda: self._queue.put_nowait((_Msg.TIMEOUT, None))
        )
        self._timeout_timer.daemon = True
        self._timeout_timer.start()

        # Call on_start — runs to completion before any STOP is processed
        if self.on_start:
            try:
                self.on_start(mode)
            except Exception as e:
                _log(f"WORKER: on_start({mode}) raised: {e}")

    def _handle_stop(self, key_name):
        """Process a STOP message. Only called by worker thread."""
        if self._state != "recording":
            return

        # Only stop if the released key is part of the active hotkey
        if self._active_parts and key_name not in self._active_parts:
            return

        self._do_stop()

    def _handle_timeout(self):
        """Process a TIMEOUT message. Only called by worker thread."""
        if self._state != "recording":
            return  # Already stopped, stale timeout
        _log(f"TIMEOUT: Recording exceeded {self.max_recording_seconds}s")
        print(f"\n[TIMEOUT] Recording exceeded {self.max_recording_seconds}s, auto-stopping...")
        self._do_stop()

    def _do_stop(self):
        """Core stop logic shared by key-release and timeout. Worker thread only."""
        self._cancel_timeout()
        mode = self._active_mode
        self._state = "processing"
        self._active_mode = None
        self._active_parts = None
        _log(f"WORKER: state -> processing, mode={mode}")
        print(f"[HOTKEY] Stopping recording, mode={mode}")

        try:
            if self.on_stop:
                stop_start = time.time()
                self.on_stop(mode)
                _log(f"WORKER: on_stop completed in {time.time() - stop_start:.3f}s")
        except Exception as e:
            _log(f"WORKER: on_stop raised: {e}")
        finally:
            self._state = "idle"
            _log("WORKER: state -> idle")

    def _process_loop(self):
        """Worker thread main loop. Processes messages sequentially."""
        _log("WORKER: Process loop started")
        while True:
            try:
                msg_type, payload = self._queue.get()
            except Exception:
                continue

            if msg_type == _Msg.SHUTDOWN:
                _log("WORKER: Shutdown received")
                break
            elif msg_type == _Msg.START:
                mode, parts = payload
                self._handle_start(mode, parts)
            elif msg_type == _Msg.STOP:
                key_name = payload
                self._handle_stop(key_name)
            elif msg_type == _Msg.TIMEOUT:
                self._handle_timeout()

    # Normalize key names across platforms.
    # On macOS pynput gives "ctrl"/"shift"/"alt" but on Windows gives
    # "ctrl_l"/"ctrl_r"/"shift"/"shift_r"/"alt_l"/"alt_r"/"cmd" (win key).
    _KEY_ALIASES = {
        "ctrl_l": "ctrl",
        "ctrl_r": "ctrl",
        "shift_l": "shift",
        "shift_r": "shift",
        "alt_l": "alt",
        "alt_r": "alt",
        "alt_gr": "alt",
        "cmd_l": "cmd",
        "cmd_r": "cmd",
    }

    def _normalize_key(self, key_name):
        """Normalize platform-specific key names to generic ones."""
        return self._KEY_ALIASES.get(key_name, key_name)

    def start(self, on_start, on_stop):
        """Start listening for hotkeys."""
        from pynput import keyboard

        self.on_start = on_start
        self.on_stop = on_stop

        # Parse all hotkeys
        self._parsed_hotkeys = {}
        for hotkey, mode in self.hotkeys.items():
            parts = set(hotkey.lower().split("+"))
            self._parsed_hotkeys[mode] = parts

        # Start the worker thread before the listener
        self._worker_thread = threading.Thread(
            target=self._process_loop, daemon=True
        )
        self._worker_thread.start()

        def on_press(key):
            try:
                key_name = key.char.lower() if hasattr(key, 'char') and key.char else key.name.lower()
            except AttributeError:
                return

            key_name = self._normalize_key(key_name)

            # Key-repeat guard: ignore if already pressed
            if key_name in self._pressed:
                return
            self._pressed.add(key_name)

            # Check if any hotkey combo is fully pressed
            for mode, parts in sorted(self._parsed_hotkeys.items(),
                                       key=lambda x: len(x[1]), reverse=True):
                if parts.issubset(self._pressed):
                    _log(f"HOTKEY: Pressed {key_name}, enqueuing START mode={mode}")
                    self._queue.put_nowait((_Msg.START, (mode, parts)))
                    break

        def on_release(key):
            try:
                key_name = key.char.lower() if hasattr(key, 'char') and key.char else key.name.lower()
            except AttributeError:
                return

            key_name = self._normalize_key(key_name)
            self._pressed.discard(key_name)
            self._queue.put_nowait((_Msg.STOP, key_name))

        self.listener = keyboard.Listener(on_press=on_press, on_release=on_release)
        self.listener.start()
        _log(f"LISTENER: Started with hotkeys: {list(self._parsed_hotkeys.keys())}")
        return self.listener

    def stop(self):
        """Stop the listener and worker thread."""
        self._queue.put_nowait((_Msg.SHUTDOWN, None))
        if hasattr(self, 'listener'):
            self.listener.stop()
        if hasattr(self, '_worker_thread'):
            self._worker_thread.join(timeout=5)
