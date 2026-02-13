# Phase 2: Dashboard UI

## Goal
Get the history dashboard visually correct and functional with real data from `~/.vibetotext/history.db`. All tabs should work, entries should display, stats should compute, and the settings panels should be interactive.

## What Already Exists
All view files are created and compile. The structure is in place but needs **visual verification and functional testing** against the Electron reference.

### Files to Modify

| File | Status | Work Needed |
|------|--------|-------------|
| `Sources/UI/MainWindow/ContentView.swift` | Implemented | Test tab switching, verify GRDB observation works |
| `Sources/UI/MainWindow/HeaderView.swift` | Implemented | Verify 4 stat boxes match Electron (chats, words, WPM, time saved) |
| `Sources/UI/MainWindow/TabBarView.swift` | Implemented | Verify 8 colored pill tabs, active state colors |
| `Sources/UI/History/HistoryListView.swift` | Implemented | Test with real entries, verify scroll performance |
| `Sources/UI/History/EntryCardView.swift` | Implemented | Verify hover effects, mode badge colors, relative time |
| `Sources/UI/History/CommonWordsView.swift` | Implemented | Verify FlowLayout, stopwords filtering |
| `Sources/UI/History/EmptyStateView.swift` | Implemented | Verify appearance when no entries |
| `Sources/UI/Settings/MicrophoneSettingsView.swift` | Implemented | Test AVCaptureDevice enumeration, device selection persistence |
| `Sources/UI/Settings/DictionarySettingsView.swift` | Implemented | Test add/remove words, FlowLayout of chips |
| `Sources/UI/MainWindow/MainWindowController.swift` | Implemented | Verify 450x600 window, hidden titlebar, NSHostingView |
| `Sources/App/AppDelegate.swift` | Implemented | Verify NSStatusItem, left-click toggle, right-click menu |

## Reference Implementation

### Header Stats (from `renderer.js` `updateHeaderStats()`)
```
Total sessions  |  Total words  |  Avg WPM  |  Time saved
```
- **Time saved formula**: `(totalWords / 100) - (totalDuration / 60)` minutes
  - 100 WPM = assumed typing speed
  - Python uses 40 WPM for typing speed in analytics.js — check which is correct for the header
- **WPM**: Average of entries that have `wpm` field set
- Filter by current mode tab (or "all")

### Tab Colors (from `styles.css`)
| Tab | Color |
|-----|-------|
| All | `#6366f1` (accent/indigo) |
| Transcribe | `#34d399` (green) |
| Greppy | `#a78bfa` (purple) |
| Cleanup | `#fb923c` (orange) |
| Plan | `#60a5fa` (blue) |
| Analytics | `#fbbf24` (amber/chartAccent) |
| Microphone | `#ec4899` (pink) |
| Dictionary | `#22d3ee` (cyan) |

### Entry Card (from `renderer.js` `render()`)
Each entry card shows:
- **Mode badge**: Colored pill with mode name (e.g., "transcribe" in green)
- **Relative time**: "Just now", "5m ago", "2h ago", "3d ago", or "Jan 15, 3:45 PM"
- **Text**: Full transcription text (truncated in card, or shown fully — match Electron)
- **Stats line**: duration (if available), WPM (if available), word count
- **Hover**: translateY(-1px), border accent color, shadow `0 4px 12px rgba(0,0,0,0.3)`

### Common Words Section
- Shows top 10 non-stopword words as chips
- Words must be > 2 chars and not in stopwords set
- Appears above the history list
- Each chip: word + count badge

### Empty State
- SF Symbol: `mic.slash` or `waveform` icon (large, muted)
- Text: "No transcriptions yet"
- Subtext: "Hold ctrl+shift to record"

### Settings Panels
- **Microphone tab**: `AVCaptureDevice.DiscoverySession` to enumerate audio inputs, Picker dropdown, saves `audio_device_index` and `audio_device_name` to ConfigStore
- **Dictionary tab**: TextField + "Add" button, word chips with X remove, saves to `config.custom_dictionary`, 3-second status messages

## Key Design Tokens (from `DesignTokens.swift`)
Already defined. Key values for reference:
- Card background: `Theme.bgSecondary` (#151518)
- Card border: `Theme.border` (#2a2a32)
- Card radius: `Theme.cardRadius` (12)
- Text primary: `Theme.textPrimary` (#f5f5f7)
- Text secondary: `Theme.textSecondary` (#a1a1a6)
- Text muted: `Theme.textMuted` (#6e6e73)

## Testing Checklist
- [ ] App launches with menu bar icon (waveform + " VTT")
- [ ] Left-click menu bar icon toggles 450x600 window
- [ ] Right-click shows "Show VibeToText" / "Quit" menu
- [ ] Window has dark background, hidden titlebar
- [ ] Header shows 4 stat boxes with correct values from DB
- [ ] All 8 tabs render with correct colors
- [ ] "All" tab shows all entries from history.db
- [ ] Mode tabs filter entries correctly
- [ ] Entry cards show mode badge, relative time, text, stats
- [ ] Entry card hover lifts and shows accent border
- [ ] Common words chips appear above history list
- [ ] Empty state shows when no entries match current filter
- [ ] Analytics tab switches to analytics panel (placeholder OK for now)
- [ ] Microphone tab shows device picker, saves selection
- [ ] Dictionary tab allows add/remove words, persists to config.json
- [ ] Scrolling is smooth with 100+ entries
- [ ] GRDB ValueObservation updates UI when DB changes externally

## Build & Run
```bash
cd VibeToText
swift build && swift run
```
The app should load `~/.vibetotext/history.db` if it exists (shared with the Python app).
