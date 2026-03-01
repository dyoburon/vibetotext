#!/usr/bin/env python3
"""Cross-platform floating waveform indicator using tkinter."""

import json
import os
import sys
import tkinter as tk
from tkinter import Canvas

IPC_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ.get("TEMP", os.environ.get("TMPDIR", "/tmp")),
    "vibetotext_ui_ipc.json"
)


class WaveformWindow:
    """Floating waveform indicator window."""

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("")

        # Window dimensions
        self.width = 140
        self.height = 20

        # Configure window for floating overlay
        self.root.overrideredirect(True)  # Remove window decorations
        self.root.attributes("-topmost", True)  # Always on top
        self.root.attributes("-alpha", 0.95)  # Slightly transparent

        # Try to make window click-through on Windows
        if sys.platform == "win32":
            try:
                self.root.attributes("-transparentcolor", "black")
            except tk.TclError:
                pass

        # Set initial position (bottom center of screen)
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = (screen_w - self.width) // 2
        y = screen_h - self.height - 40
        self.root.geometry(f"{self.width}x{self.height}+{x}+{y}")

        # Dark background
        self.root.configure(bg="#000000")

        # Canvas for drawing waveform
        self.canvas = Canvas(
            self.root,
            width=self.width,
            height=self.height,
            bg="#000000",
            highlightthickness=0
        )
        self.canvas.pack()

        # State
        self.levels = [0.0] * 25
        self.recording = False
        self.last_data = {}

        # Animation state
        self.base_width = 140
        self.base_height = 20
        self.current_scale = 1.0
        self.target_scale = 1.0
        self.scale_velocity = 0.0
        # Position anchors (right edge x, top y for Windows coords)
        self.anchor_right = 0
        self.anchor_top = 0

        # Start update loop
        self.update()

    def update(self):
        """Update waveform from IPC file."""
        try:
            if os.path.exists(IPC_FILE):
                with open(IPC_FILE, "r") as f:
                    data = json.load(f)

                if data.get("stop"):
                    self.root.quit()
                    return

                was_recording = self.recording
                self.recording = data.get("recording", False)

                # Reposition when recording starts
                if self.recording and not was_recording:
                    screen_x = data.get("screen_x", 0)
                    screen_y = data.get("screen_y", 0)
                    screen_w = data.get("screen_w", self.root.winfo_screenwidth())
                    screen_h = data.get("screen_h", self.root.winfo_screenheight())

                    # Reset scale for new recording
                    self.current_scale = 1.0
                    self.target_scale = 1.0
                    self.scale_velocity = 0.0
                    self.width = self.base_width
                    self.height = self.base_height

                    # Position with right edge at 74% of screen width
                    right_edge_x = screen_x + int(screen_w * 0.74)
                    x = right_edge_x - self.width

                    # On Windows, y is from top; position near bottom
                    y = screen_y + screen_h - self.height - 40
                    # On macOS (fallback), y is from bottom
                    if sys.platform == "darwin":
                        y = screen_y + 20

                    # Store anchors for animation
                    self.anchor_right = right_edge_x
                    self.anchor_top = y  # Top edge stays fixed when growing down

                    self.root.geometry(f"{self.width}x{self.height}+{x}+{y}")
                    self.canvas.config(width=self.width, height=self.height)
                    self.root.deiconify()
                    self.root.lift()

                # Update levels with decay
                if "levels" in data and self.recording:
                    new_levels = data["levels"]
                    for i in range(len(self.levels)):
                        if i < len(new_levels):
                            if new_levels[i] > self.levels[i]:
                                self.levels[i] = new_levels[i]
                            else:
                                self.levels[i] = self.levels[i] * 0.86 + new_levels[i] * 0.14
                elif self.recording:
                    self.levels = [l * 0.9 for l in self.levels]
                else:
                    self.levels = [0.0] * 25

                # Animate window size based on recording state (hotkey press/release)
                if self.recording:
                    # Grow when recording (hotkey held)
                    self.target_scale = 3.0
                else:
                    # Shrink when not recording (hotkey released)
                    self.target_scale = 1.0

                # Always animate (even when not recording, to shrink back)
                if True:

                    # Smooth animation with spring-like physics
                    scale_diff = self.target_scale - self.current_scale

                    if abs(scale_diff) > 0.01:
                        # Acceleration towards target with damping
                        spring_strength = 0.15
                        damping = 0.7

                        self.scale_velocity = self.scale_velocity * damping + scale_diff * spring_strength
                        self.current_scale += self.scale_velocity

                        # Clamp to valid range
                        self.current_scale = max(1.0, min(3.0, self.current_scale))

                        # Update window size - grow left and down from anchored right/top
                        self.width = int(self.base_width * self.current_scale)
                        self.height = int(self.base_height * self.current_scale)
                        new_x = self.anchor_right - self.width
                        new_y = self.anchor_top  # Top stays fixed

                        self.root.geometry(f"{self.width}x{self.height}+{new_x}+{new_y}")
                        self.canvas.config(width=self.width, height=self.height)
                    elif abs(scale_diff) <= 0.01 and abs(self.scale_velocity) > 0.001:
                        # Settle at target
                        self.scale_velocity *= 0.5
                        if abs(self.scale_velocity) < 0.001:
                            self.scale_velocity = 0
                            self.current_scale = self.target_scale

                self.draw_waveform()

        except Exception:
            pass

        # Schedule next update (~30fps)
        self.root.after(33, self.update)

    def draw_waveform(self):
        """Draw the waveform bars."""
        self.canvas.delete("all")

        # Draw rounded background
        self.canvas.create_rectangle(
            0, 0, self.width, self.height,
            fill="#000000", outline=""
        )

        num_bars = 25
        # Scale bars to fill ~90% of container width
        padding = self.width * 0.05  # 5% padding on each side
        usable_width = self.width - (padding * 2)
        bar_spacing = usable_width * 0.02  # 2% of usable width for spacing
        total_spacing = bar_spacing * (num_bars - 1)
        bar_width = (usable_width - total_spacing) / num_bars
        start_x = padding
        center_y = self.height / 2

        if self.recording:
            # White color for recording
            color = "#ffffff"
            for i in range(num_bars):
                level = self.levels[i] if i < len(self.levels) else 0.0
                x = start_x + i * (bar_width + bar_spacing)
                # Bar height based on level - scaled to show waveform detail without clipping
                min_height = max(2, self.height * 0.1)
                bar_height = max(min_height, level * self.height * 0.35)
                bar_height = min(bar_height, self.height * 0.85)
                y1 = center_y - bar_height / 2
                y2 = center_y + bar_height / 2
                self.canvas.create_rectangle(
                    x, y1, x + bar_width, y2,
                    fill=color, outline=""
                )
        else:
            # Onyx gray color for idle - flat line
            color = "#3f3f46"
            min_height = max(2, self.height * 0.1)
            for i in range(num_bars):
                x = start_x + i * (bar_width + bar_spacing)
                self.canvas.create_rectangle(
                    x, center_y - min_height / 2, x + bar_width, center_y + min_height / 2,
                    fill=color, outline=""
                )

    def run(self):
        """Start the tkinter main loop."""
        self.root.mainloop()


def main():
    window = WaveformWindow()
    window.run()


if __name__ == "__main__":
    main()
