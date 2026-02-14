#!/usr/bin/env python3
"""Cross-platform history viewer using tkinter - works on Windows, macOS, and Linux."""

import json
import os
import sqlite3
import sys
import tkinter as tk
from tkinter import ttk
from collections import Counter
from datetime import datetime
from pathlib import Path


# Paths
HISTORY_DB = Path.home() / ".vibetotext" / "history.db"
CONFIG_FILE = Path.home() / ".vibetotext" / "config.json"

# IPC file path passed as argument or default
IPC_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ.get("TEMP", os.environ.get("TMPDIR", "/tmp")),
    "vibetotext_history_ipc.json"
)

# Common English stopwords to exclude from word frequency
STOPWORDS = {
    "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
    "be", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "must", "shall", "can", "need",
    "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
    "my", "your", "his", "its", "our", "their", "this", "that", "these",
    "what", "which", "who", "where", "when", "why", "how", "all", "each",
    "some", "no", "not", "only", "so", "than", "too", "very", "just",
    "also", "now", "here", "there", "then", "if", "because", "about",
    "any", "up", "down", "out", "off", "over", "going", "gonna", "like",
    "okay", "ok", "yeah", "yes", "um", "uh", "ah", "oh", "well", "right",
    "actually", "basically", "really", "thing", "things", "something",
}

# Dark theme colors
BG_COLOR = "#1e1e24"
BG_DARKER = "#14141a"
TEXT_COLOR = "#e0e0e0"
TEXT_MUTED = "#888888"
ACCENT_COLOR = "#ff6699"
BORDER_COLOR = "#2a2a35"
CARD_BG = "#252530"
HEADER_BG = "#1a1a22"


def load_config():
    """Load config from disk."""
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def save_config(config):
    """Save config to disk."""
    try:
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(config, f, indent=2)
    except Exception:
        pass


def get_audio_devices():
    """Get list of input audio devices."""
    try:
        import sounddevice as sd
        devices = sd.query_devices()
        input_devices = []
        default_idx = sd.default.device[0]
        for i, dev in enumerate(devices):
            if dev['max_input_channels'] > 0:
                is_default = (i == default_idx)
                input_devices.append({
                    'index': i,
                    'name': dev['name'],
                    'is_default': is_default,
                })
        return input_devices
    except Exception:
        return []


def get_entries_from_db(limit=50):
    """Load history entries from SQLite database."""
    if not HISTORY_DB.exists():
        return []

    try:
        conn = sqlite3.connect(str(HISTORY_DB), timeout=5.0)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT * FROM entries ORDER BY timestamp DESC LIMIT ?",
            (limit,)
        ).fetchall()
        entries = [dict(row) for row in rows]
        conn.close()
        return entries
    except Exception:
        return []


def get_statistics_from_db():
    """Compute statistics from SQLite database."""
    if not HISTORY_DB.exists():
        return {
            "total_words": 0,
            "total_sessions": 0,
            "common_words": [],
            "avg_wpm": 0,
            "time_saved_minutes": 0,
        }

    try:
        conn = sqlite3.connect(str(HISTORY_DB), timeout=5.0)
        conn.row_factory = sqlite3.Row

        # Aggregate stats
        stats = conn.execute("""
            SELECT
                COUNT(*) as total_sessions,
                COALESCE(SUM(word_count), 0) as total_words,
                COALESCE(SUM(duration_seconds), 0) as total_duration
            FROM entries
        """).fetchone()

        total_sessions = stats["total_sessions"]
        total_words = stats["total_words"]
        total_duration = stats["total_duration"]

        # Average WPM
        wpm_row = conn.execute(
            "SELECT AVG(wpm) as avg_wpm FROM entries WHERE wpm IS NOT NULL"
        ).fetchone()
        avg_wpm = round(wpm_row["avg_wpm"]) if wpm_row["avg_wpm"] else 0

        # Time saved
        typing_wpm = 40
        words_with_dur = conn.execute(
            "SELECT COALESCE(SUM(word_count), 0) as words FROM entries WHERE duration_seconds IS NOT NULL"
        ).fetchone()["words"]
        time_to_type = words_with_dur / typing_wpm if typing_wpm else 0
        time_dictating = total_duration / 60
        time_saved = max(0, time_to_type - time_dictating)

        # Word frequency
        rows = conn.execute("SELECT text FROM entries").fetchall()
        all_words = []
        for row in rows:
            words = row["text"].lower().split()
            words = [w.strip(".,!?;:'\"()[]{}") for w in words]
            words = [w for w in words if w and len(w) > 2 and w not in STOPWORDS]
            all_words.extend(words)

        word_counts = Counter(all_words)
        common_words = word_counts.most_common(10)

        conn.close()

        return {
            "total_words": total_words,
            "total_sessions": total_sessions,
            "common_words": common_words,
            "avg_wpm": avg_wpm,
            "time_saved_minutes": round(time_saved, 1),
        }
    except Exception:
        return {
            "total_words": 0,
            "total_sessions": 0,
            "common_words": [],
            "avg_wpm": 0,
            "time_saved_minutes": 0,
        }


class HistoryWindow:
    """Tkinter-based transcription history viewer with dark theme."""

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("VibeToText - Transcription History")
        self.root.geometry("500x650")
        self.root.minsize(400, 500)
        self.root.configure(bg=BG_COLOR)

        # Try to set dark title bar on Windows 10/11
        self._set_dark_title_bar()

        # Style configuration
        self.style = ttk.Style()
        self.style.theme_use("clam")
        self._configure_styles()

        # Build the UI
        self._build_ui()

        # Load initial content
        self.refresh_content()

        # Start IPC polling
        self._check_ipc()

    def _set_dark_title_bar(self):
        """Set dark title bar on Windows 10/11."""
        if sys.platform != "win32":
            return
        try:
            import ctypes
            hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
            DWMWA_USE_IMMERSIVE_DARK_MODE = 20
            value = ctypes.c_int(1)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                ctypes.byref(value), ctypes.sizeof(value)
            )
        except Exception:
            pass

    def _configure_styles(self):
        """Configure ttk styles for dark theme."""
        self.style.configure("Dark.TFrame", background=BG_COLOR)
        self.style.configure("Card.TFrame", background=CARD_BG)
        self.style.configure("Header.TFrame", background=HEADER_BG)

        self.style.configure(
            "Dark.TLabel",
            background=BG_COLOR,
            foreground=TEXT_COLOR,
            font=("Segoe UI", 10),
        )
        self.style.configure(
            "Header.TLabel",
            background=HEADER_BG,
            foreground=TEXT_COLOR,
            font=("Segoe UI", 11, "bold"),
        )
        self.style.configure(
            "Stat.TLabel",
            background=CARD_BG,
            foreground=TEXT_COLOR,
            font=("Segoe UI", 10),
        )
        self.style.configure(
            "StatValue.TLabel",
            background=CARD_BG,
            foreground=ACCENT_COLOR,
            font=("Segoe UI", 14, "bold"),
        )
        self.style.configure(
            "Muted.TLabel",
            background=BG_COLOR,
            foreground=TEXT_MUTED,
            font=("Segoe UI", 9),
        )
        self.style.configure(
            "Mode.TLabel",
            background=BG_COLOR,
            foreground=ACCENT_COLOR,
            font=("Segoe UI", 9, "bold"),
        )

        # Combobox style
        self.style.configure(
            "Dark.TCombobox",
            fieldbackground=CARD_BG,
            background=CARD_BG,
            foreground=TEXT_COLOR,
            selectbackground=ACCENT_COLOR,
            selectforeground="white",
        )
        self.style.map("Dark.TCombobox",
            fieldbackground=[("readonly", CARD_BG)],
            foreground=[("readonly", TEXT_COLOR)],
        )

    def _build_ui(self):
        """Build the main UI layout."""
        # Main container
        main_frame = ttk.Frame(self.root, style="Dark.TFrame")
        main_frame.pack(fill=tk.BOTH, expand=True, padx=0, pady=0)

        # --- Header: Microphone selector ---
        header_frame = ttk.Frame(main_frame, style="Header.TFrame")
        header_frame.pack(fill=tk.X, padx=0, pady=0)

        header_inner = ttk.Frame(header_frame, style="Header.TFrame")
        header_inner.pack(fill=tk.X, padx=15, pady=10)

        ttk.Label(header_inner, text="Microphone:", style="Header.TLabel").pack(side=tk.LEFT)

        self.audio_devices = get_audio_devices()
        device_names = []
        selected_idx = 0
        config = load_config()
        saved_device = config.get("audio_device_index")

        for i, dev in enumerate(self.audio_devices):
            name = dev['name']
            if dev['is_default']:
                name += " (Default)"
            device_names.append(name)
            if saved_device is not None and dev['index'] == saved_device:
                selected_idx = i

        self.mic_var = tk.StringVar()
        self.mic_combo = ttk.Combobox(
            header_inner,
            textvariable=self.mic_var,
            values=device_names,
            state="readonly",
            style="Dark.TCombobox",
            width=40,
        )
        self.mic_combo.pack(side=tk.LEFT, padx=(10, 0), fill=tk.X, expand=True)
        if device_names:
            self.mic_combo.current(selected_idx)
        self.mic_combo.bind("<<ComboboxSelected>>", self._on_mic_changed)

        # --- Stats bar ---
        stats_frame = ttk.Frame(main_frame, style="Card.TFrame")
        stats_frame.pack(fill=tk.X, padx=15, pady=(10, 5))

        self.stats_labels = {}
        stat_items = [
            ("sessions", "Sessions"),
            ("words", "Words"),
            ("wpm", "Avg WPM"),
            ("saved", "Min Saved"),
        ]
        for col, (key, label) in enumerate(stat_items):
            cell = ttk.Frame(stats_frame, style="Card.TFrame")
            cell.grid(row=0, column=col, padx=10, pady=8, sticky="nsew")
            stats_frame.columnconfigure(col, weight=1)

            val_label = ttk.Label(cell, text="0", style="StatValue.TLabel")
            val_label.pack()
            ttk.Label(cell, text=label, style="Stat.TLabel").pack()
            self.stats_labels[key] = val_label

        # --- Common words ---
        words_frame = ttk.Frame(main_frame, style="Dark.TFrame")
        words_frame.pack(fill=tk.X, padx=15, pady=(5, 5))

        ttk.Label(words_frame, text="Common Words:", style="Dark.TLabel").pack(anchor=tk.W)
        self.common_words_label = ttk.Label(words_frame, text="", style="Muted.TLabel", wraplength=460)
        self.common_words_label.pack(anchor=tk.W, pady=(2, 0))

        # --- Separator ---
        sep = tk.Frame(main_frame, height=1, bg=BORDER_COLOR)
        sep.pack(fill=tk.X, padx=15, pady=5)

        # --- Transcription list header ---
        list_header = ttk.Frame(main_frame, style="Dark.TFrame")
        list_header.pack(fill=tk.X, padx=15, pady=(5, 2))
        ttk.Label(list_header, text="Recent Transcriptions", style="Dark.TLabel").pack(anchor=tk.W)

        # --- Scrollable transcription list ---
        list_container = tk.Frame(main_frame, bg=BG_COLOR)
        list_container.pack(fill=tk.BOTH, expand=True, padx=15, pady=(0, 10))

        self.canvas = tk.Canvas(list_container, bg=BG_COLOR, highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient=tk.VERTICAL, command=self.canvas.yview)
        self.scroll_frame = tk.Frame(self.canvas, bg=BG_COLOR)

        self.scroll_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )

        self.canvas_window = self.canvas.create_window((0, 0), window=self.scroll_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=scrollbar.set)

        # Make the inner frame fill the canvas width
        self.canvas.bind("<Configure>", self._on_canvas_configure)

        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Mouse wheel scrolling
        self.canvas.bind_all("<MouseWheel>", self._on_mousewheel)

    def _on_canvas_configure(self, event):
        """Resize the inner frame to match canvas width."""
        self.canvas.itemconfig(self.canvas_window, width=event.width)

    def _on_mousewheel(self, event):
        """Handle mouse wheel scrolling."""
        self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

    def _on_mic_changed(self, event):
        """Handle microphone selection change."""
        idx = self.mic_combo.current()
        if 0 <= idx < len(self.audio_devices):
            device = self.audio_devices[idx]
            config = load_config()
            config["audio_device_index"] = device['index']
            config["audio_device_name"] = device['name']
            save_config(config)

    def refresh_content(self):
        """Refresh statistics and transcription list."""
        # Update stats
        stats = get_statistics_from_db()
        self.stats_labels["sessions"].configure(text=str(stats["total_sessions"]))
        self.stats_labels["words"].configure(text=str(stats["total_words"]))
        self.stats_labels["wpm"].configure(text=str(stats["avg_wpm"]))
        self.stats_labels["saved"].configure(text=str(stats["time_saved_minutes"]))

        # Update common words
        if stats["common_words"]:
            words_text = ", ".join(f"{w} ({c})" for w, c in stats["common_words"][:10])
            self.common_words_label.configure(text=words_text)
        else:
            self.common_words_label.configure(text="No data yet")

        # Clear existing entries
        for widget in self.scroll_frame.winfo_children():
            widget.destroy()

        # Load and display entries
        entries = get_entries_from_db(limit=50)

        if not entries:
            empty_label = tk.Label(
                self.scroll_frame,
                text="No transcriptions yet.\nUse Ctrl+Shift to start recording!",
                bg=BG_COLOR,
                fg=TEXT_MUTED,
                font=("Segoe UI", 11),
                justify=tk.CENTER,
                pady=40,
            )
            empty_label.pack(fill=tk.X)
            return

        for entry in entries:
            self._create_entry_card(entry)

    def _create_entry_card(self, entry):
        """Create a card widget for a transcription entry."""
        card = tk.Frame(self.scroll_frame, bg=CARD_BG, padx=12, pady=10)
        card.pack(fill=tk.X, pady=3)

        # Header row: timestamp, mode, word count
        header = tk.Frame(card, bg=CARD_BG)
        header.pack(fill=tk.X)

        # Timestamp
        timestamp = entry.get("timestamp", "")
        try:
            dt = datetime.fromisoformat(timestamp)
            time_str = dt.strftime("%b %d, %I:%M %p")
        except Exception:
            time_str = timestamp[:16] if timestamp else "Unknown"

        tk.Label(
            header, text=time_str,
            bg=CARD_BG, fg=TEXT_MUTED, font=("Segoe UI", 9),
        ).pack(side=tk.LEFT)

        # Mode badge
        mode = entry.get("mode", "transcribe").upper()
        mode_colors = {
            "TRANSCRIBE": ACCENT_COLOR,
            "GREPPY": "#66ccff",
            "CLEANUP": "#66ff99",
            "PLAN": "#ffcc66",
        }
        mode_color = mode_colors.get(mode, ACCENT_COLOR)
        tk.Label(
            header, text=f"  {mode}  ",
            bg=CARD_BG, fg=mode_color, font=("Segoe UI", 8, "bold"),
        ).pack(side=tk.LEFT, padx=(8, 0))

        # Word count + WPM
        word_count = entry.get("word_count", 0)
        wpm = entry.get("wpm")
        meta_text = f"{word_count} words"
        if wpm:
            meta_text += f" | {wpm} WPM"
        tk.Label(
            header, text=meta_text,
            bg=CARD_BG, fg=TEXT_MUTED, font=("Segoe UI", 9),
        ).pack(side=tk.RIGHT)

        # Text content
        text = entry.get("text", "")
        preview = text[:300] + "..." if len(text) > 300 else text
        text_label = tk.Label(
            card, text=preview,
            bg=CARD_BG, fg=TEXT_COLOR, font=("Segoe UI", 10),
            wraplength=440, justify=tk.LEFT, anchor="w",
        )
        text_label.pack(fill=tk.X, pady=(6, 0))

    def _check_ipc(self):
        """Poll IPC file for commands from the main process."""
        try:
            if os.path.exists(IPC_FILE):
                with open(IPC_FILE, "r") as f:
                    data = json.load(f)

                if data.get("stop"):
                    self.root.quit()
                    return

                if data.get("refresh"):
                    self.refresh_content()
                    # Clear refresh flag
                    data["refresh"] = False
                    with open(IPC_FILE, "w") as f:
                        json.dump(data, f)

                should_show = data.get("show", False)
                if should_show:
                    self.root.deiconify()
                    self.root.lift()
                    self.root.focus_force()
                elif not should_show and data.get("show") is not None:
                    self.root.withdraw()
        except Exception:
            pass

        # Poll every 200ms
        self.root.after(200, self._check_ipc)

    def run(self):
        """Start the tkinter main loop."""
        self.root.mainloop()


def main():
    window = HistoryWindow()
    window.run()


if __name__ == "__main__":
    main()
