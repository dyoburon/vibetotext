# VibeToText Swift Port — Phase Guide

Phase 1 is complete. Phases 2-6 each have a dedicated doc in `docs/phases/`.

| Phase | Doc | Status | Summary |
|-------|-----|--------|---------|
| 1 | (complete) | DONE | SPM project, design tokens, data layer, app shell — builds clean |
| 2 | [phase2-dashboard-ui.md](docs/phases/phase2-dashboard-ui.md) | Pending | Visual polish, tab switching, real data rendering |
| 3 | [phase3-audio-transcription.md](docs/phases/phase3-audio-transcription.md) | Pending | AVAudioEngine, FFT, Whisper, waveform overlay |
| 4 | [phase4-pipeline.md](docs/phases/phase4-pipeline.md) | Pending | CGEvent hotkeys, Gemini API, paste-at-cursor, orchestrator |
| 5 | [phase5-analytics.md](docs/phases/phase5-analytics.md) | Pending | Swift Charts for 10+ placeholder views, Canvas heatmaps |
| 6 | [phase6-polish.md](docs/phases/phase6-polish.md) | Pending | Animations, scrollbar, window state, error handling, icons |

## Quick Start

```bash
cd VibeToText
swift build        # Should compile clean after Phase 1
swift run          # Launches the app (menu bar icon appears)
```

## Project Structure

```
VibeToText/
  Package.swift
  Sources/
    App/            VibeToTextApp.swift, AppDelegate.swift
    Core/           HotkeyManager, AudioRecorder, WhisperTranscriber, GeminiService, PasteService, TranscriptionPipeline
    Data/           HistoryDatabase, HistoryEntry, ConfigStore, AnalyticsProcessor
    UI/Theme/       DesignTokens.swift
    UI/MainWindow/  MainWindowController, ContentView, HeaderView, TabBarView
    UI/History/     HistoryListView, EntryCardView, CommonWordsView, EmptyStateView
    UI/Analytics/   AnalyticsDashboardView (contains 20+ sub-views)
    UI/Settings/    MicrophoneSettingsView, DictionarySettingsView
    UI/Overlay/     WaveformOverlayController, WaveformNSView
    Resources/      placeholder.txt (for Assets.xcassets later)
```
