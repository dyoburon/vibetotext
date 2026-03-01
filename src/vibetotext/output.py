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


def has_accessibility_permission():
    """Check if we have Accessibility permission."""
    try:
        from ApplicationServices import AXIsProcessTrusted
        trusted = AXIsProcessTrusted()
        log_debug(f"AXIsProcessTrusted() = {trusted}")
        return trusted
    except ImportError as e:
        log_debug(f"Failed to import ApplicationServices: {e}")
        return False


def request_accessibility_permission():
    """Prompt user for Accessibility permission."""
    try:
        from ApplicationServices import AXIsProcessTrustedWithOptions
        from Foundation import NSDictionary

        # This will show the system prompt
        options = NSDictionary.dictionaryWithObject_forKey_(
            True,
            "AXTrustedCheckOptionPrompt"
        )
        trusted = AXIsProcessTrustedWithOptions(options)
        log_debug(f"AXIsProcessTrustedWithOptions() = {trusted}")
        return trusted
    except Exception as e:
        log_debug(f"Failed to request permission: {e}")
        return False


def get_running_app_info():
    """Get info about current process for debugging."""
    try:
        import sys
        log_debug(f"Python executable: {sys.executable}")
        log_debug(f"PID: {os.getpid()}")
        log_debug(f"__file__: {__file__}")

        # Get the actual app that needs permission
        from AppKit import NSRunningApplication, NSWorkspace
        current_app = NSRunningApplication.currentApplication()
        log_debug(f"Bundle ID: {current_app.bundleIdentifier()}")
        log_debug(f"Localized Name: {current_app.localizedName()}")
        log_debug(f"Bundle URL: {current_app.bundleURL()}")
        log_debug(f"Executable URL: {current_app.executableURL()}")
    except Exception as e:
        log_debug(f"Failed to get app info: {e}")


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


def simulate_paste_macos():
    """Simulate Cmd+V on macOS using CGEventPost (fast, native)."""
    try:
        from Quartz import (
            CGEventCreateKeyboardEvent,
            CGEventPost,
            kCGHIDEventTap,
            CGEventSetFlags,
            kCGEventFlagMaskCommand,
        )

        log_debug(" Using CGEventPost to paste...")

        # Key code for 'v' is 9
        v_keycode = 9

        # Create key down event with Command modifier
        key_down = CGEventCreateKeyboardEvent(None, v_keycode, True)
        CGEventSetFlags(key_down, kCGEventFlagMaskCommand)

        # Create key up event with Command modifier
        key_up = CGEventCreateKeyboardEvent(None, v_keycode, False)
        CGEventSetFlags(key_up, kCGEventFlagMaskCommand)

        # Post events
        CGEventPost(kCGHIDEventTap, key_down)
        CGEventPost(kCGHIDEventTap, key_up)

        log_debug(" CGEventPost paste successful")
        return True
    except Exception as e:
        log_debug(f" CGEventPost failed: {e}, falling back to AppleScript")
        # Fallback to AppleScript
        try:
            result = subprocess.run(
                ['osascript', '-e', 'tell application "System Events" to keystroke "v" using command down'],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except Exception as e2:
            log_debug(f" AppleScript fallback also failed: {e2}")
            return False


def simulate_paste_linux():
    """Simulate Ctrl+V on Linux using xdotool (X11), wtype (Wayland), or pynput fallback."""
    # Try xdotool first (X11)
    try:
        log_debug(" Trying xdotool for paste...")
        result = subprocess.run(
            ["xdotool", "key", "--clearmodifiers", "ctrl+v"],
            capture_output=True,
            timeout=5
        )
        if result.returncode == 0:
            log_debug(" xdotool paste successful")
            return True
    except FileNotFoundError:
        log_debug(" xdotool not found")
    except Exception as e:
        log_debug(f" xdotool failed: {e}")

    # Try wtype (Wayland)
    try:
        log_debug(" Trying wtype for paste...")
        result = subprocess.run(
            ["wtype", "-M", "ctrl", "-P", "v", "-p", "v", "-m", "ctrl"],
            capture_output=True,
            timeout=5
        )
        if result.returncode == 0:
            log_debug(" wtype paste successful")
            return True
    except FileNotFoundError:
        log_debug(" wtype not found")
    except Exception as e:
        log_debug(f" wtype failed: {e}")

    # Fallback to pynput (works on X11 and some Wayland with XWayland)
    log_debug(" Falling back to pynput for paste...")
    return simulate_paste_windows()


def simulate_paste():
    """Simulate paste keystroke (Cmd+V on macOS, Ctrl+V on Windows/Linux)."""
    if SYSTEM == 'Windows':
        return simulate_paste_windows()
    elif SYSTEM == 'Darwin':
        return simulate_paste_macos()
    else:
        return simulate_paste_linux()


def _copy_to_clipboard_fallback(text: str) -> bool:
    """Try direct clipboard tools when pyperclip fails (Linux)."""
    # Try wl-copy (Wayland)
    try:
        proc = subprocess.run(["wl-copy"], input=text, text=True, capture_output=True, timeout=3)
        if proc.returncode == 0:
            log_debug(" Clipboard: wl-copy succeeded")
            return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Try xclip (X11)
    try:
        proc = subprocess.run(
            ["xclip", "-selection", "clipboard"],
            input=text, text=True, capture_output=True, timeout=3
        )
        if proc.returncode == 0:
            log_debug(" Clipboard: xclip succeeded")
            return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Try xsel (X11)
    try:
        proc = subprocess.run(
            ["xsel", "--clipboard", "--input"],
            input=text, text=True, capture_output=True, timeout=3
        )
        if proc.returncode == 0:
            log_debug(" Clipboard: xsel succeeded")
            return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return False


def play_notification_sound():
    """Play a notification sound to signal manual paste needed."""
    if SYSTEM == 'Darwin':
        subprocess.run(["afplay", "/System/Library/Sounds/Pop.aiff"], check=False)
    elif SYSTEM == 'Windows':
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
            "/usr/share/sounds/ubuntu/stereo/bell.ogg",
        ]
        for sound_path in sound_paths:
            if not os.path.exists(sound_path):
                continue
            # Try paplay (PulseAudio/PipeWire)
            try:
                result = subprocess.run(
                    ["paplay", sound_path],
                    check=False, capture_output=True, timeout=3
                )
                if result.returncode == 0:
                    return
            except (FileNotFoundError, subprocess.TimeoutExpired):
                pass
            # Try aplay (ALSA)
            try:
                result = subprocess.run(
                    ["aplay", sound_path],
                    check=False, capture_output=True, timeout=3
                )
                if result.returncode == 0:
                    return
            except (FileNotFoundError, subprocess.TimeoutExpired):
                pass


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
    except Exception as e:
        log_debug(f" pyperclip.copy failed: {e}, trying fallback clipboard tools")
        if not _copy_to_clipboard_fallback(text):
            log_debug(" WARNING: No clipboard mechanism available")
            print(f"[OUTPUT] Could not copy to clipboard. Install xclip, xsel, or wl-clipboard.")
            return
        log_debug(f" Copied {len(text)} chars to clipboard via fallback")

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

    elif SYSTEM == 'Darwin':
        # macOS needs Accessibility permission
        # Debug: show what app we are
        get_running_app_info()

        # Check permission
        if has_accessibility_permission():
            log_debug(" Have accessibility permission, attempting auto-paste...")
            time.sleep(0.1)  # Wait for hotkey modifiers to be fully released

            if simulate_paste():
                log_debug(" Auto-paste attempted")
                return
            else:
                log_debug(" Auto-paste failed, falling back to sound")
        else:
            log_debug(" No accessibility permission")
            # Try to request it (shows system dialog)
            request_accessibility_permission()

        # Fallback: play sound to signal manual paste needed
        log_debug(" Playing sound for manual paste")
        play_notification_sound()

    else:
        # Linux or other - try pynput approach
        log_debug(f" {SYSTEM} detected, attempting auto-paste...")
        time.sleep(0.1)

        if simulate_paste():
            log_debug(" Auto-paste successful")
            return
        else:
            log_debug(" Auto-paste failed, text is in clipboard")
            play_notification_sound()
