"""System tray integration for Windows using pystray."""

import sys
import threading

# Only import pystray on Windows
IS_WINDOWS = sys.platform == "win32"


def _create_tray_icon_image():
    """Create a simple tray icon image programmatically using Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont

        # Create a 64x64 icon with the app's pink accent color
        size = 64
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        # Draw a rounded rectangle background
        bg_color = (30, 30, 36, 255)  # Dark background matching app theme
        draw.rounded_rectangle(
            [(2, 2), (size - 3, size - 3)],
            radius=12,
            fill=bg_color,
        )

        # Draw waveform bars (simplified)
        accent = (255, 102, 153, 255)  # #ff6699
        bar_width = 4
        gap = 2
        num_bars = 7
        total_width = num_bars * bar_width + (num_bars - 1) * gap
        start_x = (size - total_width) // 2
        center_y = size // 2

        bar_heights = [10, 18, 26, 30, 26, 18, 10]
        for i, h in enumerate(bar_heights):
            x = start_x + i * (bar_width + gap)
            y1 = center_y - h // 2
            y2 = center_y + h // 2
            draw.rounded_rectangle(
                [(x, y1), (x + bar_width, y2)],
                radius=2,
                fill=accent,
            )

        return img
    except Exception:
        # Fallback: create a minimal icon without Pillow fancy features
        try:
            from PIL import Image, ImageDraw
            size = 64
            img = Image.new("RGBA", (size, size), (30, 30, 36, 255))
            draw = ImageDraw.Draw(img)
            # Simple rectangle
            draw.rectangle([(16, 16), (48, 48)], fill=(255, 102, 153, 255))
            return img
        except Exception:
            return None


class SystemTray:
    """Windows system tray icon with context menu."""

    def __init__(self, on_show_history=None, on_exit=None):
        """
        Initialize the system tray.

        Args:
            on_show_history: Callback when "Show History" is clicked
            on_exit: Callback when "Exit" is clicked
        """
        self.on_show_history = on_show_history
        self.on_exit = on_exit
        self._icon = None
        self._thread = None

    def start(self):
        """Start the system tray icon in a background thread."""
        if not IS_WINDOWS:
            return

        try:
            import pystray
            from pystray import MenuItem, Menu

            icon_image = _create_tray_icon_image()
            if icon_image is None:
                print("[TRAY] Could not create icon image, tray disabled", flush=True)
                return

            def on_history(icon, item):
                if self.on_show_history:
                    self.on_show_history()

            def on_quit(icon, item):
                icon.stop()
                if self.on_exit:
                    self.on_exit()

            menu = Menu(
                MenuItem("VibeToText", None, enabled=False),
                Menu.SEPARATOR,
                MenuItem("Show History", on_history),
                Menu.SEPARATOR,
                MenuItem("Exit", on_quit),
            )

            self._icon = pystray.Icon(
                name="vibetotext",
                icon=icon_image,
                title="VibeToText - Voice to Text",
                menu=menu,
            )

            # Run in background thread so it doesn't block
            self._thread = threading.Thread(target=self._icon.run, daemon=True)
            self._thread.start()
            print("[TRAY] System tray icon started", flush=True)

        except ImportError as e:
            print(f"[TRAY] pystray not installed, system tray disabled: {e}", flush=True)
        except Exception as e:
            print(f"[TRAY] Failed to start system tray: {e}", flush=True)
            import traceback
            traceback.print_exc()

    def stop(self):
        """Stop the system tray icon."""
        if self._icon is not None:
            try:
                self._icon.stop()
            except Exception:
                pass
            self._icon = None

    def update_title(self, title):
        """Update the tray icon tooltip text."""
        if self._icon is not None:
            try:
                self._icon.title = title
            except Exception:
                pass
