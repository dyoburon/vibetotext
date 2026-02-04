"""History viewer UI using tkinter."""

import json
import os
import subprocess
import sys
import tempfile

# Path for IPC
_history_ipc_file = os.path.join(tempfile.gettempdir(), "vibetotext_history_ipc.json")
_history_ui_process = None

# The History UI script that runs in its own process
HISTORY_UI_SCRIPT_TKINTER = '''
import json
import os
import sys
import sqlite3
import tkinter as tk
from tkinter import ttk, scrolledtext
from datetime import datetime
from pathlib import Path
from collections import Counter

IPC_FILE = sys.argv[1]
HISTORY_DB = Path.home() / ".vibetotext" / "history.db"
CONFIG_FILE = Path.home() / ".vibetotext" / "config.json"

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


def get_audio_devices():
    """Get list of input audio devices."""
    try:
        import sounddevice as sd
        devices = sd.query_devices()
        input_devices = []
        default_idx = sd.default.device[0]
        for i, dev in enumerate(devices):
            if dev["max_input_channels"] > 0:
                is_default = (i == default_idx)
                input_devices.append({
                    "index": i,
                    "name": dev["name"],
                    "is_default": is_default,
                })
        return input_devices
    except Exception:
        return []


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


def load_history_from_db():
    """Load history entries from SQLite database."""
    entries = []
    try:
        if not HISTORY_DB.exists():
            return entries
        conn = sqlite3.connect(str(HISTORY_DB))
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT * FROM entries ORDER BY timestamp DESC LIMIT 50"
        ).fetchall()
        for row in rows:
            entries.append({
                "text": row["text"],
                "mode": row["mode"],
                "timestamp": row["timestamp"],
                "word_count": row["word_count"],
                "duration_seconds": row["duration_seconds"],
                "wpm": row["wpm"],
            })
        conn.close()
    except Exception:
        pass
    return entries


def get_all_entries_for_stats():
    """Load all entries for computing statistics."""
    entries = []
    try:
        if not HISTORY_DB.exists():
            return entries
        conn = sqlite3.connect(str(HISTORY_DB))
        conn.row_factory = sqlite3.Row
        rows = conn.execute("SELECT text, mode, timestamp, word_count FROM entries").fetchall()
        for row in rows:
            entries.append({
                "text": row["text"],
                "mode": row["mode"],
                "timestamp": row["timestamp"],
                "word_count": row["word_count"],
            })
        conn.close()
    except Exception:
        pass
    return entries


def get_statistics(entries):
    """Compute statistics from entries."""
    if not entries:
        return {"total_words": 0, "total_sessions": 0, "common_words": []}

    total_words = sum(e.get("word_count", len(e["text"].split())) for e in entries)
    total_sessions = len(entries)

    all_words = []
    for entry in entries:
        words = entry["text"].lower().split()
        words = [w.strip(".,!?;:\\\\\\'\\\\\\"\\"\\\'()[]{}") for w in words]
        words = [w for w in words if w and len(w) > 2 and w not in STOPWORDS]
        all_words.extend(words)

    word_counts = Counter(all_words)
    common_words = word_counts.most_common(10)

    return {
        "total_words": total_words,
        "total_sessions": total_sessions,
        "common_words": common_words,
    }


def get_monospace_font():
    """Return monospace font name for Linux."""
    return "monospace"


class HistoryApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Transcription History")
        self.root.geometry("450x550")
        self.root.configure(bg="#1a1a1a")
        self.root.minsize(350, 400)
        self.visible = False

        # Style
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Dark.TFrame", background="#1a1a1a")
        style.configure("Dark.TLabel", background="#1a1a1a", foreground="#cccccc",
                         font=("sans-serif", 10))
        style.configure("Dark.TCombobox", fieldbackground="#2a2a2a", foreground="#cccccc")

        # Top frame for mic dropdown
        top_frame = ttk.Frame(self.root, style="Dark.TFrame", padding=(10, 8))
        top_frame.pack(fill=tk.X)

        mic_label = ttk.Label(top_frame, text="Microphone:", style="Dark.TLabel")
        mic_label.pack(side=tk.LEFT, padx=(0, 5))

        self.audio_devices = get_audio_devices()
        device_names = []
        config = load_config()
        saved_device = config.get("audio_device_index")
        selected_idx = 0
        for i, dev in enumerate(self.audio_devices):
            name = dev["name"]
            if dev["is_default"]:
                name += " (System Default)"
            device_names.append(name)
            if saved_device is not None and dev["index"] == saved_device:
                selected_idx = i

        self.mic_var = tk.StringVar()
        self.mic_dropdown = ttk.Combobox(top_frame, textvariable=self.mic_var,
                                          values=device_names, state="readonly")
        if device_names:
            self.mic_dropdown.current(selected_idx)
        self.mic_dropdown.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.mic_dropdown.bind("<<ComboboxSelected>>", self._on_mic_changed)

        # Text area
        font_name = get_monospace_font()
        self.text_area = scrolledtext.ScrolledText(
            self.root,
            wrap=tk.WORD,
            bg="#14141a",
            fg="#e6e6e6",
            insertbackground="#e6e6e6",
            selectbackground="#3a3a5a",
            font=(font_name, 12),
            borderwidth=1,
            relief=tk.SUNKEN,
            padx=8,
            pady=8,
        )
        self.text_area.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))
        self.text_area.configure(state=tk.DISABLED)

        # Handle window close
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self.refresh_content()
        self.check_ipc()

    def _on_mic_changed(self, event=None):
        """Called when microphone dropdown selection changes."""
        idx = self.mic_dropdown.current()
        if 0 <= idx < len(self.audio_devices):
            device = self.audio_devices[idx]
            config = load_config()
            config["audio_device_index"] = device["index"]
            config["audio_device_name"] = device["name"]
            save_config(config)

    def _on_close(self):
        """Called when window is closed via X button."""
        self.visible = False
        try:
            with open(IPC_FILE, "w") as f:
                json.dump({"visible": False}, f)
        except Exception:
            pass
        self.root.withdraw()

    def refresh_content(self):
        """Refresh display with latest history."""
        recent_entries = load_history_from_db()
        all_entries = get_all_entries_for_stats()
        stats = get_statistics(all_entries)

        content = []
        content.append("=" * 50)
        content.append("                    STATISTICS")
        content.append("=" * 50)
        content.append("")
        content.append(f"  Total Chats:     {stats['total_sessions']}")
        content.append(f"  Total Words:     {stats['total_words']}")
        content.append("")

        if stats["common_words"]:
            content.append("  Most Common Words:")
            for word, count in stats["common_words"][:10]:
                content.append(f"    {word}: {count}")

        content.append("")
        content.append("=" * 50)
        content.append("                 RECENT TRANSCRIPTIONS")
        content.append("=" * 50)
        content.append("")

        for entry in recent_entries:
            timestamp = entry.get("timestamp", "")
            try:
                dt = datetime.fromisoformat(timestamp)
                time_str = dt.strftime("%b %d, %I:%M %p")
            except Exception:
                time_str = timestamp[:16] if timestamp else "Unknown"

            mode = entry.get("mode", "transcribe").upper()
            word_count = entry.get("word_count", len(entry.get("text", "").split()))
            text = entry.get("text", "")
            preview = text[:200] + "..." if len(text) > 200 else text

            content.append(f"[{time_str}] [{mode}] ({word_count} words)")
            content.append(f"  {preview}")
            content.append("")

        if not recent_entries:
            content.append("  No transcriptions yet.")
            content.append("  Use ctrl+shift to start recording!")
            content.append("")

        full_text = "\\n".join(content)

        self.text_area.configure(state=tk.NORMAL)
        self.text_area.delete("1.0", tk.END)
        self.text_area.insert("1.0", full_text)
        self.text_area.configure(state=tk.DISABLED)

    def check_ipc(self):
        """Check IPC file for commands."""
        try:
            if os.path.exists(IPC_FILE):
                with open(IPC_FILE, "r") as f:
                    data = json.load(f)

                if data.get("stop"):
                    self.root.destroy()
                    return

                should_show = data.get("show", False)
                should_refresh = data.get("refresh", False)

                if should_show and not self.visible:
                    self.refresh_content()
                    self.root.deiconify()
                    self.root.lift()
                    self.root.focus_force()
                    self.visible = True
                elif not should_show and self.visible:
                    self.root.withdraw()
                    self.visible = False
                elif should_refresh and self.visible:
                    self.refresh_content()
                    data["refresh"] = False
                    with open(IPC_FILE, "w") as f:
                        json.dump(data, f)
        except Exception:
            pass

        self.root.after(100, self.check_ipc)

    def run(self):
        self.root.withdraw()
        self.root.mainloop()


if __name__ == "__main__":
    app = HistoryApp()
    app.run()
'''


def _write_history_ipc(data):
    """Write data to history IPC file."""
    try:
        tmp_file = _history_ipc_file + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(data, f)
        os.replace(tmp_file, _history_ipc_file)
    except Exception:
        pass


def _ensure_history_ui_process():
    """Start the history UI process if not running."""
    global _history_ui_process

    if _history_ui_process is not None and _history_ui_process.poll() is None:
        return

    script_content = HISTORY_UI_SCRIPT_TKINTER

    # Write the UI script to a temp file
    script_file = os.path.join(tempfile.gettempdir(), "vibetotext_history_ui.py")
    with open(script_file, "w") as f:
        f.write(script_content)

    # Clear any old IPC file
    if os.path.exists(_history_ipc_file):
        os.remove(_history_ipc_file)

    # Start the UI process
    error_log = os.path.join(tempfile.gettempdir(), "vibetotext_history_ui_error.log")
    with open(error_log, "w") as err_file:
        _history_ui_process = subprocess.Popen(
            [sys.executable, script_file, _history_ipc_file],
            stdout=subprocess.PIPE,
            stderr=err_file,
        )


# Track visibility state
_history_visible = False


def toggle_history():
    """Toggle the history window visibility."""
    global _history_visible
    _ensure_history_ui_process()
    _history_visible = not _history_visible
    _write_history_ipc({"show": _history_visible})


def show_history():
    """Show the history window."""
    global _history_visible
    _ensure_history_ui_process()
    _history_visible = True
    _write_history_ipc({"show": True})


def hide_history():
    """Hide the history window."""
    global _history_visible
    _history_visible = False
    _write_history_ipc({"show": False})


def refresh_history():
    """Refresh the history display (call after adding new entry)."""
    if _history_visible:
        _write_history_ipc({"show": True, "refresh": True})


def stop_history_ui():
    """Stop the history UI process."""
    global _history_ui_process
    _write_history_ipc({"stop": True})
    if _history_ui_process is not None:
        try:
            _history_ui_process.terminate()
            _history_ui_process.wait(timeout=1)
        except Exception:
            pass
        _history_ui_process = None
