"""Floating recording indicator with waveform - cross-platform version."""

import json
import os
import platform
import subprocess
import sys
import tempfile
import threading
import queue

# Platform detection
IS_MACOS = platform.system() == "Darwin"
IS_WINDOWS = platform.system() == "Windows"

# Path for IPC - use platform-appropriate temp directory
if IS_WINDOWS:
    _ipc_file = os.path.join(os.environ.get("TEMP", tempfile.gettempdir()), "vibetotext_ui_ipc.json")
else:
    _ipc_file = os.path.join(tempfile.gettempdir(), "vibetotext_ui_ipc.json")

_ui_process = None

# Non-blocking IPC queue and worker thread
_ipc_queue = queue.Queue(maxsize=10)  # Small buffer, drop old frames if full
_ipc_thread = None
_ipc_stop_event = threading.Event()


def _ipc_worker():
    """Background thread that writes IPC data. Runs until stop event is set."""
    while not _ipc_stop_event.is_set():
        try:
            # Wait for data with timeout so we can check stop event
            data = _ipc_queue.get(timeout=0.1)
            _write_ipc_sync(data)
        except queue.Empty:
            continue
        except Exception:
            pass


def _ensure_ipc_thread():
    """Start the IPC worker thread if not running."""
    global _ipc_thread
    if _ipc_thread is None or not _ipc_thread.is_alive():
        _ipc_stop_event.clear()
        _ipc_thread = threading.Thread(target=_ipc_worker, daemon=True)
        _ipc_thread.start()


def _write_ipc_async(data):
    """Queue data for async IPC write. Non-blocking, drops old data if queue full."""
    _ensure_ipc_thread()
    try:
        # Use put_nowait to never block the audio thread
        # If queue is full, drop the oldest item and add new one
        if _ipc_queue.full():
            try:
                _ipc_queue.get_nowait()  # Drop oldest
            except queue.Empty:
                pass
        _ipc_queue.put_nowait(data)
    except Exception:
        pass  # Never block or raise in audio callback path


def _get_cursor_and_screen():
    """Get cursor position and screen bounds - platform-specific."""
    if IS_MACOS:
        try:
            from Quartz import CGEventCreate, CGEventGetLocation
            from AppKit import NSScreen

            # Get cursor position
            event = CGEventCreate(None)
            pos = CGEventGetLocation(event)
            cursor_x, cursor_y = int(pos.x), int(pos.y)

            # Find which screen the cursor is on
            for screen in NSScreen.screens():
                frame = screen.frame()
                if (frame.origin.x <= cursor_x <= frame.origin.x + frame.size.width and
                    frame.origin.y <= cursor_y <= frame.origin.y + frame.size.height):
                    return {
                        "screen_x": int(frame.origin.x),
                        "screen_y": int(frame.origin.y),
                        "screen_w": int(frame.size.width),
                        "screen_h": int(frame.size.height),
                    }

            # Fallback to main screen
            main = NSScreen.mainScreen().frame()
            return {
                "screen_x": int(main.origin.x),
                "screen_y": int(main.origin.y),
                "screen_w": int(main.size.width),
                "screen_h": int(main.size.height),
            }
        except Exception:
            pass

    elif IS_WINDOWS:
        try:
            import ctypes
            from ctypes import wintypes

            # Get cursor position
            class POINT(ctypes.Structure):
                _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

            pt = POINT()
            ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))

            # Get screen dimensions
            screen_w = ctypes.windll.user32.GetSystemMetrics(0)  # SM_CXSCREEN
            screen_h = ctypes.windll.user32.GetSystemMetrics(1)  # SM_CYSCREEN

            return {
                "screen_x": 0,
                "screen_y": 0,
                "screen_w": screen_w,
                "screen_h": screen_h,
            }
        except Exception:
            pass

    # Fallback
    return {"screen_x": 0, "screen_y": 0, "screen_w": 1920, "screen_h": 1080}


def _write_ipc_sync(data):
    """Write data to IPC file atomically (blocking - use from worker thread only)."""
    try:
        # Write to temp file first, then rename (atomic)
        tmp_file = _ipc_file + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(data, f)
        os.replace(tmp_file, _ipc_file)  # Atomic rename
    except Exception:
        pass


def _write_ipc(data):
    """Write data to IPC file - uses sync for control messages, async for waveform."""
    # Control messages (show/hide/stop) use sync write for reliability
    # Waveform updates use async to avoid blocking audio callback
    _write_ipc_sync(data)


def _find_ui_binary():
    """Find the UI binary - either bundled or as a script."""
    # Determine the UI binary name based on platform
    if IS_WINDOWS:
        ui_binary_name = "vibetotext-ui.exe"
        ui_script_name = "ui_tkinter.py"  # Use tkinter on Windows
    else:
        ui_binary_name = "vibetotext-ui"
        ui_script_name = "ui_standalone.py"  # Use native NSPanel on macOS

    # Check if we're running from a PyInstaller bundle
    if getattr(sys, 'frozen', False):
        # Look for bundled UI binary next to the main executable
        base_dir = os.path.dirname(sys.executable)
        ui_binary = os.path.join(base_dir, ui_binary_name)
        print(f"[UI] Looking for UI binary at: {ui_binary}")
        if os.path.exists(ui_binary):
            print(f"[UI] Found bundled UI binary")
            return ui_binary, []

        # Also check in Resources folder (for macOS .app bundles)
        if IS_MACOS:
            resources_dir = os.path.join(os.path.dirname(base_dir), "Resources")
            ui_binary = os.path.join(resources_dir, ui_binary_name)
            print(f"[UI] Looking for UI binary at: {ui_binary}")
            if os.path.exists(ui_binary):
                print(f"[UI] Found UI binary in Resources")
                return ui_binary, []

        print(f"[UI] UI binary not found!")

    # Running from source - use Python to run the standalone script
    ui_script = os.path.join(os.path.dirname(__file__), ui_script_name)
    if os.path.exists(ui_script):
        print(f"[UI] Running from source with script: {ui_script}")
        return sys.executable, [ui_script]

    # Fallback to tkinter version if native not found
    ui_script = os.path.join(os.path.dirname(__file__), "ui_tkinter.py")
    if os.path.exists(ui_script):
        print(f"[UI] Falling back to tkinter UI: {ui_script}")
        return sys.executable, [ui_script]

    return None, None


def _ensure_ui_process():
    """Start the UI process if not running."""
    global _ui_process

    if _ui_process is not None and _ui_process.poll() is None:
        return

    # Find UI binary or script
    ui_exe, ui_args = _find_ui_binary()
    if ui_exe is None:
        print("[UI] Could not find UI binary or script, UI disabled")
        return

    # Clear any old IPC file
    if os.path.exists(_ipc_file):
        os.remove(_ipc_file)

    # Build command
    cmd = [ui_exe] + (ui_args or []) + [_ipc_file]
    print(f"[UI] Starting UI with command: {cmd}")

    # Start the UI process with error logging
    error_log = os.path.join(tempfile.gettempdir(), "vibetotext_ui_error.log")

    # Windows-specific: hide console window
    startupinfo = None
    if IS_WINDOWS:
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = subprocess.SW_HIDE

    with open(error_log, "w") as err_file:
        _ui_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=err_file,
            startupinfo=startupinfo,
        )
    print(f"[UI] UI process started with PID: {_ui_process.pid}")


def _load_orb_position():
    """Load orb position from config file."""
    try:
        config_path = os.path.join(os.path.expanduser("~"), ".vibetotext", "config.json")
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                config = json.load(f)
            return config.get("orb_position", "bottom-center")
    except Exception:
        pass
    return "bottom-center"


def show_recording():
    """Show recording indicator at configured position."""
    _ensure_ui_process()
    screen_info = _get_cursor_and_screen()
    orb_pos = _load_orb_position()

    ipc_data = {
        "recording": True,
        "level": 0.0,
        **screen_info,
    }

    # Pass position info to the UI process
    if isinstance(orb_pos, dict) and "x" in orb_pos and "y" in orb_pos:
        ipc_data["orb_x"] = orb_pos["x"]
        ipc_data["orb_y"] = orb_pos["y"]
    else:
        ipc_data["orb_preset"] = orb_pos

    _write_ipc(ipc_data)


def hide_recording():
    """Switch to idle state (flat line, don't hide)."""
    _write_ipc({"recording": False})


_update_counter = 0


def update_waveform(levels):
    """Update waveform with frequency band levels (list of 0.0 to 1.0).

    IMPORTANT: This is called from the audio callback thread.
    Must be non-blocking to avoid deadlock on stream.stop().
    """
    global _update_counter
    _update_counter += 1
    # Use async write to avoid blocking the audio callback thread
    # This prevents deadlock when stream.stop() waits for callback to complete
    _write_ipc_async({"recording": True, "levels": levels, "seq": _update_counter})


def process_ui_events():
    """No-op for compatibility."""
    pass


def stop_ui():
    """Stop the UI process and IPC worker thread."""
    global _ui_process, _ipc_thread
    _write_ipc({"stop": True})

    # Stop the IPC worker thread
    _ipc_stop_event.set()
    if _ipc_thread is not None:
        _ipc_thread.join(timeout=0.5)
        _ipc_thread = None

    if _ui_process is not None:
        try:
            _ui_process.terminate()
            _ui_process.wait(timeout=1)
        except Exception:
            pass
        _ui_process = None
