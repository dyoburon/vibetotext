"""Audio recording with hotkey trigger."""

import numpy as np
import sounddevice as sd
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

        # Stop stream with timeout detection
        _log("STOP: Calling stream.stop()...")
        stop_start = time.time()
        try:
            self.stream.stop()
            stop_elapsed = time.time() - stop_start
            _log(f"STOP: stream.stop() completed in {stop_elapsed:.3f}s")
        except Exception as e:
            _log(f"STOP: stream.stop() FAILED: {e}")

        _log("STOP: Calling stream.close()...")
        close_start = time.time()
        try:
            self.stream.close()
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


class HotkeyListener:
    """Listens for multiple hotkeys to toggle recording."""

    def __init__(self, hotkeys: dict = None, max_recording_seconds: int = 60):
        """
        Args:
            hotkeys: Dict mapping hotkey strings to mode names.
                     e.g. {"ctrl+shift": "transcribe", "cmd+shift": "greppy"}
            max_recording_seconds: Auto-stop recording after this many seconds (default: 60)
        """
        if hotkeys is None:
            hotkeys = {"ctrl+shift": "transcribe"}
        self.hotkeys = hotkeys
        self.max_recording_seconds = max_recording_seconds
        self.on_start = None  # Called with mode name
        self.on_stop = None   # Called with mode name
        self._pressed = set()
        self._recording = False
        self._active_mode = None
        self._timeout_timer = None
        self._lock = threading.Lock()  # Prevent race condition on key release

    def _cancel_timeout(self):
        """Cancel any pending timeout."""
        if self._timeout_timer:
            self._timeout_timer.cancel()
            self._timeout_timer = None

    def _timeout_stop(self):
        """Called when recording times out."""
        if self._recording:
            print(f"\n[TIMEOUT] Recording exceeded {self.max_recording_seconds}s, auto-stopping...")
            mode = self._active_mode
            self._recording = False
            self._active_mode = None
            self._active_parts = None
            self._pressed.clear()
            if self.on_stop:
                self.on_stop(mode)

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

        def on_press(key):
            try:
                key_name = key.char.lower() if hasattr(key, 'char') and key.char else key.name.lower()
            except AttributeError:
                return

            self._pressed.add(key_name)

            # Check if any hotkey combo is pressed (check longer combos first)
            if not self._recording:
                # Sort by length descending to match most specific first
                for mode, parts in sorted(self._parsed_hotkeys.items(),
                                          key=lambda x: len(x[1]), reverse=True):
                    if parts.issubset(self._pressed):
                        self._recording = True
                        self._active_mode = mode
                        self._active_parts = parts
                        _log(f"HOTKEY: Pressed {key_name}, starting recording mode={mode}")

                        # Start timeout timer
                        self._cancel_timeout()
                        self._timeout_timer = threading.Timer(
                            self.max_recording_seconds,
                            self._timeout_stop
                        )
                        self._timeout_timer.daemon = True
                        self._timeout_timer.start()

                        if self.on_start:
                            self.on_start(mode)
                        break

        def on_release(key):
            try:
                key_name = key.char.lower() if hasattr(key, 'char') and key.char else key.name.lower()
            except AttributeError:
                return

            # Use lock to prevent race condition when both hotkey parts release at once
            # Invoke on_stop OUTSIDE the lock to avoid deadlock with stream.stop()
            should_stop = False
            mode = None
            with self._lock:
                # If any hotkey part is released while recording, stop
                if self._recording and self._active_parts and key_name in self._active_parts:
                    self._cancel_timeout()
                    mode = self._active_mode
                    self._recording = False
                    self._active_mode = None
                    self._active_parts = None
                    # Clear pressed set to avoid stale state
                    self._pressed.clear()
                    should_stop = True
                else:
                    self._pressed.discard(key_name)

            if should_stop:
                _log(f"HOTKEY: Released {key_name}, stopping recording mode={mode}")
                print(f"[HOTKEY] Stopping recording, mode={mode}")
                if self.on_stop:
                    _log(f"HOTKEY: Calling on_stop callback...")
                    stop_start = time.time()
                    self.on_stop(mode)
                    stop_elapsed = time.time() - stop_start
                    _log(f"HOTKEY: on_stop callback completed in {stop_elapsed:.3f}s")

        self.listener = keyboard.Listener(on_press=on_press, on_release=on_release)
        self.listener.start()
        _log(f"LISTENER: Started with hotkeys: {list(self._parsed_hotkeys.keys())}")
        return self.listener
