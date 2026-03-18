# VibeToText

Voice-to-text for developers featuring AI-powered cleanup and detailed analytics.

## Components

| Component | Directory | Stack |
|-----------|-----------|-------|
| **Python CLI** | `src/vibetotext/` | Python 3.9+, Whisper.cpp, sounddevice, pynput |
| **Windows native app** | `windows-native/` | C# .NET 9, WPF, NAudio, Whisper.net |
| **macOS native app** | `macos-native/` | Swift 5.9, Metal, macOS 14+ |
| **Electron history app** | `history-app/` | Electron 28, better-sqlite3, D3.js |

All implementations share the same SQLite database at `~/.vibetotext/history.db`.

## Features

**Multi-Mode Hotkeys**
- `Ctrl+Shift` — Raw transcription
- `Cmd+Shift` — **Greppy** mode with semantic code search
- `Alt+Shift` — **Cleanup** mode (AI refines rambling into clear prompts)
- `Cmd+Alt` — **Plan** mode (generates structured implementation plans)
- `Cmd+Shift+F` — **Feedback** mode (pastes transcription with TTS endpoint instructions so any LLM can speak back)

**Fast Local Transcription**
- Whisper.cpp for 2-4x faster transcription than Python Whisper
- Technical vocabulary bias for programming terms
- Auto-paste to cursor

**JARVIS-style TTS Status Reports**
- Neural voice (edge-tts, en-GB-RyanNeural) speaks status after each action
- Chunked playback for long text — first sentence plays immediately while rest generates in background
- HTTP API server at `http://127.0.0.1:7865` enables any external tool to speak via `POST /api/speak`
- Configurable voice, rate, pitch, and volume in `~/.vibetotext/config.json`
- Falls back to platform TTS (SAPI/say/espeak-ng) when offline

## Analytics & Settings

![Analytics Dashboard](docs/analytics.png)

Press `Cmd+Comma` (macOS) or `Ctrl+Comma` (Windows) to open the **History & Settings** window.

- **Streaks & Personal Records** — Track your current streak, best WPM, most words/day, and longest session.
- **Topic Speed & Mood** — See how fast and positive you are across topics like Testing, Planning, Documentation, and more. Bar colors shift from negative to positive sentiment.
- **Daily Goal Progress** — Set daily and weekly word targets and track completion.
- **Activity Heatmap** — GitHub-style hourly/yearly view of when you dictate most.
- **Peak Hours & Words Over Time** — Visualize your productivity patterns and dictation volume trends.
- **Filler Words & Vocabulary Diversity** — Monitor filler word usage and track your unique word count and richness score.
- **Recent History** — Review and copy previous transcriptions.
- **Microphone Selection** — Switch audio input devices directly from the UI.

## Cosmic Visualization (macOS only)

![Cosmic Visualization](docs/cosmic.png)

A living 3D world that reacts to your voice in real time. As you dictate, a procedural planet grows with villagers, buildings, crops, and a tree whose leaves are your most-used words. A cosmic entity watches from a black hole in the sky — and if your sentiment turns negative, it attacks.

**Hotkeys**
- `Cmd+Ctrl+G` — Open the Word Galaxy visualization

**How it works**
- **Sentiment-driven behavior** — Your words are analyzed in real time. Positive speech keeps the world peaceful; negative sentiment triggers the cosmic entity to charge and fire lasers at your village.
- **Procedural planet** — Villagers (farmers, scholars, builders, guards) and buildings populate a 3D planet that grows as you talk.
- **Word tree** — Your top 500 words are assigned to leaves on a procedural tree that grows during the intro sequence.
- **Word nebula** — Recent transcriptions float as text in a nebula cloud. Common words migrate from the nebula to the tree.
- **Seasons & day/night** — A 15-second day/night cycle with shifting sky colors, dynamic lighting, and fireflies at night.
- **GLB export** — Export generated 3D entities for use in external tools.

> Requires macOS 14+ (Sonoma). The cosmic visualization is part of the native macOS app in `macos-native/`, built with Swift and Metal. Not available on Windows or Linux.

## Install

### Python CLI

```bash
pip install -e .
pip install -e ".[gemini,dev]"   # with Gemini + dev dependencies
```

Optionally set `GEMINI_API_KEY` in a `.env` file to enable cleanup/plan modes. You can copy the `.env.example` file and then add your key.

### Windows Native App

```bash
cd windows-native
build.bat                        # or: dotnet build src/VibeToText/VibeToText.csproj
```

### macOS Native App

```bash
cd macos-native
swift build
```

Requires macOS 14+ (Sonoma) and Swift 5.9+.

### Platform Builds (Python app)

These scripts package the Python CLI into standalone executables via PyInstaller:

```bash
# Windows (from project root) → dist/vibetotext-engine.exe, dist/vibetotext-ui.exe
build_windows.bat

# macOS
bash packaging/macos/build_macos.sh

# Linux
bash packaging/linux/build_linux.sh
```

Executables will be in the `dist/` folder. See `packaging/` for platform-specific configs.

## Usage

```bash
vibetotext              # Start with default hotkeys
vibetotext --model base # Use specific Whisper model
```

## Start/Stop with History Application

```bash
start-all.sh
```

```bash
stop-all.sh
```
