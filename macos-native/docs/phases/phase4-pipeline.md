# Phase 4: Pipeline — Hotkeys, Gemini, Paste, Orchestrator

## Goal
Wire up the complete recording pipeline: global hotkeys trigger recording, audio is transcribed, optionally processed by Gemini, saved to history, and pasted at the cursor. After this phase, the app is **fully functional** for all 3 modes.

## What Already Exists
All files are created and compile. The logic is ported but needs **integration testing and permission handling**.

### Files to Modify

| File | Status | Work Needed |
|------|--------|-------------|
| `Sources/Core/HotkeyManager.swift` | Fully implemented | Test CGEvent tap, verify hotkey detection, permissions |
| `Sources/Core/GeminiService.swift` | Fully implemented | Test API calls, verify prompts produce good output |
| `Sources/Core/PasteService.swift` | Fully implemented | Test CGEvent paste, verify accessibility permission |
| `Sources/Core/TranscriptionPipeline.swift` | Fully implemented | Integration test: full record→transcribe→process→paste flow |
| `Sources/App/AppDelegate.swift` | May need changes | Add permission prompts, pipeline lifecycle |

## HotkeyManager — Reference Implementation

### Python Source: `src/vibetotext/recorder.py` → `HotkeyListener`

**Swift equivalent**: `Sources/Core/HotkeyManager.swift`

**3 Hotkey Combos:**
| Hotkey | Mode | Action |
|--------|------|--------|
| `ctrl+shift` | transcribe | Raw transcription, paste at cursor |
| `alt+shift` | cleanup | Transcribe → Gemini cleanup → paste refined text |
| `cmd+alt+p` | plan | Transcribe → Gemini plan generation → paste plan |

**How it works (CGEvent tap):**
1. Create `CGEvent.tapCreate()` with `.cgSessionEventTap` location
2. Listen for `.flagsChanged` and `.keyDown`/`.keyUp` events
3. Track modifier state from flags
4. Detect when a hotkey combo is **held** (all modifiers active)
5. On hold → call `onRecordingStart?(mode)`
6. On release (any key in combo released) → call `onRecordingStop?(mode)`
7. 60-second auto-cutoff timer

**Key detection logic:**
- `ctrl+shift`: Both `.control` and `.shift` flags set, no `.command` or `.option`
- `alt+shift`: Both `.option` and `.shift` flags set, no `.command`
- `cmd+alt+p`: `.command` and `.option` flags + keyCode 35 (P) pressed

**CGEvent tap specifics:**
```swift
let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
                              (1 << CGEventType.keyDown.rawValue) |
                              (1 << CGEventType.keyUp.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,      // Don't consume events
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: pointer
)
```

**Permission**: CGEvent tap requires **Accessibility permission**. The app must prompt for this on first launch. Use `AXIsProcessTrusted()` to check, `AXIsProcessTrustedWithOptions()` with prompt option to request.

**Threading**: The event tap runs on a `CFRunLoop`. The current implementation creates a background thread with its own run loop. Callbacks (`onRecordingStart`/`onRecordingStop`) should dispatch to main thread.

## GeminiService — Reference Implementation

### Python Source: `src/vibetotext/llm.py`

**Swift equivalent**: `Sources/Core/GeminiService.swift`

**API Configuration:**
- Model: `gemini-3-flash-preview`
- Base URL: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}`
- API key from: `GEMINI_API_KEY` env → `GOOGLE_API_KEY` env → `~/.vibetotext/.env` → project `.env`

**Two endpoints:**

### 1. Cleanup (`temperature: 0.3, maxOutputTokens: 2048`)
Prompt (from `llm.py` `CLEANUP_PROMPT`):
```
You are a world-class prompt engineer and technical communicator.

Your task: Transform this rambling voice-to-text transcription into a clear,
focused, and well-structured prompt or message.

Key objectives:
1. Extract the core intent — what does the speaker actually want?
2. Resolve contradictions — if they changed their mind mid-sentence, use the latest intent
3. Apply expert knowledge — use precise technical terms, correct any obvious speech-to-text errors
4. Optimize for LLM consumption — structure the output so an AI assistant can act on it immediately
5. Be concise but complete — remove filler words, repetition, and tangents

Rules:
- Output ONLY the refined prompt/message. No meta-commentary, no "Here's the refined version:"
- Preserve the speaker's voice and intent — don't add requirements they didn't mention
- Use markdown formatting if it helps clarity
- If the speaker is asking for code, include specific technical requirements

Raw transcription:
{text}
```

### 2. Plan (`temperature: 0.4, maxOutputTokens: 4096`)
Prompt (from `llm.py` `IMPLEMENTATION_PLAN_PROMPT`):
```
You are a senior software architect creating an implementation plan.

Transform this voice description into a structured, actionable implementation plan.

Output EXACTLY this format (no deviation):

# [Feature Name]

## Problem
[1-2 sentences describing the problem or feature request]

## Solution
[2-3 sentences describing the high-level approach]

---

## Implementation

### Step 1: [Name]
**Files:** `path/to/file.py`
```python
# Key code snippet showing the approach
```

### Step 2: [Name]
...

---

## Files Changed
- `new/file.py` - [purpose]
- `existing/file.py` - [what changes]

Rules:
- Be concise. No fluff, no explanations of basic concepts
- 2-4 implementation steps (not more)
- Show KEY code only (interfaces, function signatures, critical logic) — not full implementations
- No time estimates
- Use real file paths based on common project structures

Voice transcription:
{text}
```

**Request format (JSON):**
```json
{
  "contents": [{"parts": [{"text": "prompt here"}]}],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 2048
  }
}
```

**Response parsing:**
- Extract `response.candidates[0].content.parts[0].text`
- Return trimmed text

## PasteService — Reference Implementation

### Python Source: `src/vibetotext/output.py`

**Swift equivalent**: `Sources/Core/PasteService.swift`

**How it works:**
1. Copy text to `NSPasteboard.general`
2. Wait 0.1 seconds (for hotkey modifiers to release)
3. Simulate Cmd+V via CGEvent:
```swift
let vKeyCode: CGKeyCode = 9  // 'v' key
let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)!
keyDown.flags = .maskCommand
let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)!
keyUp.flags = .maskCommand
keyDown.post(tap: .cgSessionEventTap)
keyUp.post(tap: .cgSessionEventTap)
```

**Permission**: Same as hotkeys — requires Accessibility permission.

**Important timing**: The 0.1s delay is critical. Without it, the paste event fires while the hotkey modifiers are still held, resulting in Cmd+Ctrl+Shift+V instead of Cmd+V.

## TranscriptionPipeline — Orchestrator

### Python Source: `src/vibetotext/cli.py` → `on_start()` / `on_stop()`

**Swift equivalent**: `Sources/Core/TranscriptionPipeline.swift`

**Flow:**
```
HotkeyManager.onRecordingStart(mode)
  → ConfigStore.load()           // Hot-reload mic config
  → WaveformOverlay.show()
  → AudioRecorder.start()
  → Set up onLevels callback → WaveformOverlay.updateLevels()

HotkeyManager.onRecordingStop(mode)
  → AudioRecorder.stop() → [Float] audio
  → WaveformOverlay.hide()
  → WhisperTranscriber.transcribe(audio) → String text
  → Mode processing:
      "transcribe" → use raw text
      "cleanup"    → GeminiService.cleanup(text) → refined text
      "plan"       → GeminiService.generatePlan(text) → plan text
  → HistoryDatabase.addEntry(text, mode, duration)
  → PasteService.pasteAtCursor(output)
```

**Error handling:**
- If no audio captured → log and return
- If no speech detected → log and return
- If Gemini fails → fall back to raw transcription text
- If paste fails → text is still on clipboard, user can Cmd+V manually
- All errors should be logged, not crash the app

**60-second auto-cutoff:**
- HotkeyManager has a Timer that fires after 60 seconds
- Automatically calls `onRecordingStop` if still recording
- Prevents accidental infinite recordings

## Permission Handling

The app needs these permissions:
1. **Microphone** — prompted automatically by AVAudioEngine on first use
2. **Accessibility** — needed for CGEvent tap (hotkeys) and CGEvent post (paste)

### Accessibility Permission Flow:
```swift
import ApplicationServices

func checkAccessibility() -> Bool {
    return AXIsProcessTrusted()
}

func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
```

Call `requestAccessibility()` on first launch in `AppDelegate.applicationDidFinishLaunching()`. The system will show a dialog asking the user to grant permission in System Preferences > Privacy & Security > Accessibility.

## Testing Checklist
- [ ] `ctrl+shift` hold starts recording, release stops
- [ ] `alt+shift` hold starts recording in cleanup mode
- [ ] `cmd+alt+p` hold starts recording in plan mode
- [ ] Waveform overlay appears during recording, hides on stop
- [ ] Audio is transcribed correctly after recording
- [ ] Cleanup mode: Gemini refines the text
- [ ] Plan mode: Gemini generates structured plan
- [ ] Transcribed/processed text is pasted at cursor in external apps
- [ ] History entry is saved to `~/.vibetotext/history.db`
- [ ] 60-second auto-cutoff stops recording
- [ ] Multiple record/stop cycles work without issues
- [ ] App prompts for Accessibility permission on first launch
- [ ] App prompts for Microphone permission on first use

## Environment Setup
```bash
# Gemini API key (one of these):
export GEMINI_API_KEY="your-key-here"
# OR add to ~/.vibetotext/.env:
echo "GEMINI_API_KEY=your-key-here" >> ~/.vibetotext/.env

# Whisper model:
mkdir -p ~/.vibetotext/models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
  -o ~/.vibetotext/models/ggml-base.bin
```

## Build & Run
```bash
cd VibeToText
swift build && swift run
```
