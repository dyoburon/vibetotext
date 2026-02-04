"""Output handling - auto-paste at cursor."""

import subprocess
import time
import os
import platform
import tempfile
import pyperclip

SYSTEM = platform.system()
LOG_FILE = os.path.join(tempfile.gettempdir(), "vibetotext_output_debug.log")


def log_debug(msg: str):
    """Write debug message to log file."""
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
        print(f"[DEBUG] {msg}")
    except Exception:
        print(f"[DEBUG] {msg}")


def simulate_paste_windows():
    """Simulate Ctrl+V on Windows using pynput."""
    try:
        from pynput.keyboard import Controller, Key

        log_debug(" Using pynput to paste on Windows...")
        keyboard = Controller()

        # Small delay to ensure any held keys are released
        time.sleep(0.05)

        # Press Ctrl+V
        keyboard.press(Key.ctrl)
        keyboard.press('v')
        keyboard.release('v')
        keyboard.release(Key.ctrl)

        log_debug(" pynput paste successful")
        return True
    except Exception as e:
        log_debug(f" pynput paste failed: {e}")
        return False


def simulate_paste_linux():
    """Simulate Ctrl+V on Linux using xdotool (X11) or pynput fallback."""
    # Try xdotool first (works on X11)
    try:
        log_debug(" Trying xdotool for paste...")
        result = subprocess.run(
            ["xdotool", "key", "ctrl+v"],
            capture_output=True,
            timeout=2
        )
        if result.returncode == 0:
            log_debug(" xdotool paste successful")
            return True
        else:
            log_debug(f" xdotool failed with code {result.returncode}")
    except FileNotFoundError:
        log_debug(" xdotool not found")
    except Exception as e:
        log_debug(f" xdotool failed: {e}")

    # Try wtype (Wayland)
    try:
        log_debug(" Trying wtype for paste...")
        result = subprocess.run(
            ["wtype", "-M", "ctrl", "v", "-m", "ctrl"],
            capture_output=True,
            timeout=2
        )
        if result.returncode == 0:
            log_debug(" wtype paste successful")
            return True
    except FileNotFoundError:
        log_debug(" wtype not found")
    except Exception as e:
        log_debug(f" wtype failed: {e}")

    # Fallback to pynput (may work on some Wayland compositors)
    try:
        from pynput.keyboard import Controller, Key

        log_debug(" Trying pynput for paste...")
        keyboard = Controller()

        time.sleep(0.05)

        keyboard.press(Key.ctrl)
        keyboard.press('v')
        keyboard.release('v')
        keyboard.release(Key.ctrl)

        log_debug(" pynput paste successful")
        return True
    except Exception as e:
        log_debug(f" pynput paste failed: {e}")
        return False


def simulate_paste():
    """Simulate paste keystroke (Ctrl+V on Windows/Linux)."""
    if SYSTEM == 'Windows':
        return simulate_paste_windows()
    else:
        return simulate_paste_linux()


def _copy_to_clipboard_fallback(text: str) -> bool:
    """Try direct clipboard tools when pyperclip fails."""
    # Try wl-copy (Wayland)
    try:
        proc = subprocess.run(["wl-copy"], input=text, text=True, capture_output=True, timeout=2)
        if proc.returncode == 0:
            log_debug(" Clipboard: wl-copy succeeded")
            return True
    except (FileNotFoundError, Exception):
        pass

    # Try xclip (X11)
    try:
        proc = subprocess.run(["xclip", "-selection", "clipboard"], input=text, text=True, capture_output=True, timeout=2)
        if proc.returncode == 0:
            log_debug(" Clipboard: xclip succeeded")
            return True
    except (FileNotFoundError, Exception):
        pass

    # Try xsel (X11)
    try:
        proc = subprocess.run(["xsel", "--clipboard", "--input"], input=text, text=True, capture_output=True, timeout=2)
        if proc.returncode == 0:
            log_debug(" Clipboard: xsel succeeded")
            return True
    except (FileNotFoundError, Exception):
        pass

    return False


def play_notification_sound():
    """Play a notification sound to signal manual paste needed."""
    if SYSTEM == 'Windows':
        try:
            import winsound
            winsound.MessageBeep(winsound.MB_OK)
        except Exception:
            pass  # Silently fail if winsound not available
    else:
        # Linux - try multiple sound paths and players
        sound_paths = [
            "/usr/share/sounds/freedesktop/stereo/complete.oga",
            "/usr/share/sounds/freedesktop/stereo/message.oga",
            "/usr/share/sounds/freedesktop/stereo/bell.oga",
        ]

        # Try paplay first (PulseAudio)
        for sound_path in sound_paths:
            try:
                result = subprocess.run(
                    ["paplay", sound_path],
                    check=False,
                    capture_output=True,
                    timeout=2
                )
                if result.returncode == 0:
                    return
            except (FileNotFoundError, Exception):
                continue

        # Fallback to aplay (ALSA)
        for sound_path in sound_paths:
            try:
                result = subprocess.run(
                    ["aplay", sound_path],
                    check=False,
                    capture_output=True,
                    timeout=2
                )
                if result.returncode == 0:
                    return
            except (FileNotFoundError, Exception):
                continue


def paste_at_cursor(text: str):
    """
    Copy text to clipboard and auto-paste at cursor.
    Falls back to clipboard-only if no Accessibility permission (macOS).
    """
    # Don't replace clipboard with empty or whitespace-only text
    if not text or not text.strip():
        log_debug(" Skipping paste: text is empty or whitespace-only")
        return

    # Copy to clipboard first
    try:
        pyperclip.copy(text)
        log_debug(f" Copied {len(text)} chars to clipboard")
    except Exception:
        # pyperclip failed - try direct clipboard tools
        if not _copy_to_clipboard_fallback(text):
            log_debug(" WARNING: No clipboard mechanism available. Install wl-clipboard (Wayland) or xclip (X11).")
            print(f"[OUTPUT] Text ({len(text)} chars) could not be copied to clipboard.")
            print(f"[OUTPUT] Install: sudo pacman -S wl-clipboard  (for Wayland)")
            return

    if SYSTEM == 'Windows':
        # Windows doesn't need special permission checks
        log_debug(" Windows detected, attempting auto-paste...")
        time.sleep(0.1)  # Wait for hotkey modifiers to be fully released

        if simulate_paste():
            log_debug(" Auto-paste successful")
            return
        else:
            log_debug(" Auto-paste failed, text is in clipboard")
            play_notification_sound()

    else:
        # Linux - try pynput approach
        log_debug(f" {SYSTEM} detected, attempting auto-paste...")
        time.sleep(0.1)

        if simulate_paste():
            log_debug(" Auto-paste successful")
            return
        else:
            log_debug(" Auto-paste failed, text is in clipboard")
            play_notification_sound()
