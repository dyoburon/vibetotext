# VibeToText

Voice-to-text for developers with AI-powered cleanup and detailed analytics.

![Transcribe View](docs/transcribe.png)

## Features

**Multi-Mode Hotkeys**
- `Ctrl+Shift` — Raw transcription
- `Cmd+Shift` — **Greppy** mode with semantic code search
- `Alt+Shift` — **Cleanup** mode (AI refines rambling into clear prompts)
- `Cmd+Alt` — **Plan** mode (generates structured implementation plans)

**Fast Local Transcription**
- Whisper.cpp for 2-4x faster transcription than Python Whisper
- Technical vocabulary bias for programming terms
- Auto-paste to cursor

## Analytics

![Analytics Dashboard](docs/analytics.png)

Track your voice coding productivity:

| Metric | Description |
|--------|-------------|
| **WPM** | Words per minute across sessions |
| **Time Saved** | Dictation vs typing (40 WPM baseline) |
| **Filler Words** | Track "um", "like", "basically" usage |
| **Vocabulary Diversity** | Unique words / total words richness |
| **Top Words & Phrases** | Frequency analysis per mode |

## Install

```bash
pip install -e .
```

On **Windows**, if you get a warning that `vibetotext.exe` is not on PATH, run:

```bash
python setup_windows_path.py
```

Then open a **new terminal** for the change to take effect.

Requires `GEMINI_API_KEY` in `.env` for cleanup/plan modes.

## Usage

```bash
vibetotext              # Start with default hotkeys
vibetotext --model base # Use specific Whisper model
```
