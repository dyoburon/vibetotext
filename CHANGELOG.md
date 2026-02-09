# Changelog

## Unreleased

### Added
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
