# Changelog

## Unreleased

### Added
- **JARVIS-style TTS status reports** — Neural voice (edge-tts, en-GB-RyanNeural) speaks concise status after each action ("Got it. 12 words captured", "Located 4 files, sir")
- **TTS HTTP API server** — `POST http://127.0.0.1:7865/api/speak` endpoint lets any external tool (Claude Code, scripts, etc.) trigger spoken feedback
- **Feedback hotkey mode** (`Cmd+Shift+F`) — Pastes transcription with TTS endpoint instructions so the receiving LLM can speak back
- **Chunked TTS playback** — Long text splits into rolling chunks of 2-3 sentences; first chunk plays immediately while the rest generate in the background
- **Cross-platform TTS** — edge-tts with ffplay/afplay for headless playback on Windows, macOS, and Linux; SAPI/AVSpeechSynthesizer/espeak-ng fallback when offline
- **TTS config keys** — `tts_enabled`, `tts_voice`, `tts_edge_rate`, `tts_edge_pitch`, `tts_rate`, `tts_volume` in `~/.vibetotext/config.json`
- **Gemini LLM integration** — New `llm.py` module that uses Google Gemini to clean up rambling voice transcriptions into clear prompts and generate structured implementation plans
- **Window state persistence** — History app now remembers its position and size between sessions
- **Startup/stop scripts** — `start-all.sh` and `stop-all.sh` to launch and kill both services in one command
- `google-generativeai` and `python-dotenv` as project dependencies

### Changed
- History app now uses `history.db` instead of `history.json`
- Startup scripts use relative paths derived from script location instead of hardcoded paths
- Increased header top padding in history app to accommodate macOS traffic light buttons

### Removed
- Window no longer repositions to cursor on toggle — it stays where you last placed it
