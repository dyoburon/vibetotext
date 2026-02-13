# Phase 3: Audio + Transcription

## Goal
Get audio recording, FFT waveform visualization, and Whisper transcription working end-to-end. After this phase, you should be able to call `AudioRecorder.start()`, speak into the mic, call `AudioRecorder.stop()` to get audio, and pass it to `WhisperTranscriber.transcribe()` to get text back.

## What Already Exists
Core files are created and compile. The algorithms are ported but need **real-world testing and debugging**.

### Files to Modify

| File | Status | Work Needed |
|------|--------|-------------|
| `Sources/Core/AudioRecorder.swift` | Fully implemented | Test with real mic, verify FFT output matches Python |
| `Sources/Core/WhisperTranscriber.swift` | Fully implemented | Test model loading, verify transcription quality |
| `Sources/UI/Overlay/WaveformOverlayController.swift` | Fully implemented | Test panel visibility, positioning |
| `Sources/UI/Overlay/WaveformNSView.swift` | Fully implemented | Test drawing, verify visual match to Python |

## AudioRecorder — Reference Implementation

### Python Source: `src/vibetotext/recorder.py` → `AudioRecorder`

**Swift equivalent**: `Sources/Core/AudioRecorder.swift`

**Audio capture parameters (must match exactly):**
- Sample rate: 16000 Hz (required by Whisper)
- Channels: 1 (mono)
- Format: Float32
- Buffer size: not explicitly set (system default is fine)

**FFT visualization parameters:**
```
NUM_BARS = 25
FFT_SIZE = 512
SMOOTHING = 0.7
SILENCE_THRESHOLD = 0.08
MIN_FREQ_BIN = 4  (skips sub-bass ~125Hz at 16kHz)
```

**FFT Algorithm (step by step):**
1. Get audio chunk from tap buffer
2. Compute RMS: `sqrt(mean(samples^2))`
3. `base_level = min(1.0, rms * 100)`
4. If `rms < 0.08` (silence): smooth decay `prev_levels *= 0.7`, skip FFT
5. Zero-pad to 512 samples if shorter
6. Apply Hanning window: `samples * hanning(len)`
7. Real FFT: `abs(rfft(windowed))`
8. Convert to dB: `20 * log10(spectrum)` (clip min to -60dB)
9. Normalize: `(dB + 60) / 60` → range [0, 1]
10. **Exponential frequency mapping** (25 bars):
    - `usable_bins = spectrum_length - MIN_FREQ_BIN`
    - For bar `i` (0..24):
      - `lo = MIN_FREQ_BIN + usable_bins * ((i / 25) ^ 2.5)`
      - `hi = MIN_FREQ_BIN + usable_bins * (((i+1) / 25) ^ 2.5)`
      - `levels[i] = mean(spectrum[lo..hi])`
11. **Bass reduction**: First 4 bars × [0.5, 0.625, 0.75, 0.875]
12. **Temporal smoothing**: `levels = prev * 0.7 + new * 0.3`
13. Call `onLevels?(levels)` on main thread

**Swift implementation notes:**
- Uses `AVAudioEngine` with `installTap(onBus:bufferSize:format:block:)`
- Uses `Accelerate` framework: `vDSP_hann_window`, `vDSP_DFT_zrop_CreateSetup`, `vDSP_DFT_Execute`
- The tap callback runs on the audio thread — keep it fast, dispatch UI updates to main
- Audio data accumulates in `audioBuffer: [Float]` for later transcription

**Key gotcha**: AVAudioEngine's tap format may not match 16kHz mono. You may need to install a format converter or request the format explicitly. The current code requests 16kHz mono — verify this works on real hardware.

## WhisperTranscriber — Reference Implementation

### Python Source: `src/vibetotext/transcriber.py` → `Transcriber`

**Swift equivalent**: `Sources/Core/WhisperTranscriber.swift`

**Model loading:**
- Model file: `ggml-base.bin` (or other size)
- Search paths (in order):
  1. `~/.vibetotext/models/ggml-{model}.bin`
  2. `~/Library/Application Support/whisper/ggml-{model}.bin`
  3. App bundle resource
- Uses `whisper_init_from_file_with_params(path, params)`
- Model is lazy-loaded on first transcription

**Transcription API:**
```c
// whisper.h API calls used:
whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
whisper_full(ctx, params, audio_ptr, audio_count)
whisper_full_n_segments(ctx)
whisper_full_get_segment_text(ctx, segment_index)
```

**Parameters:**
- `params.language = "en"`
- `params.print_progress = false`
- `params.print_timestamps = false`
- `params.single_segment = false`
- `params.initial_prompt` = TECH_PROMPT + custom dictionary words

**TECH_PROMPT** (already in WhisperTranscriber.swift):
200+ technical terms for vocabulary biasing. Includes databases, APIs, languages, frameworks, cloud services, Git, AI/ML terms, etc.

**Custom dictionary:**
- Loaded from `ConfigStore.shared.customDictionary`
- Appended to prompt: "IMPORTANT: The speaker uses these specific terms that must be transcribed exactly as spelled: [words]"
- Hot-reloaded each transcription (no restart needed)

**Artifact filtering:**
- Regex: `\[(?:end|blank_audio|silence|music|applause)\]` (case-insensitive)
- Collapse whitespace: `\s+` → single space
- Trim

**Testing the transcriber:**
You'll need a Whisper model file. Download one:
```bash
mkdir -p ~/.vibetotext/models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" -o ~/.vibetotext/models/ggml-base.bin
```

## Waveform Overlay — Reference Implementation

### Python Source: `src/vibetotext/ui_standalone.py`

**Swift equivalent**: `Sources/UI/Overlay/WaveformOverlayController.swift` + `WaveformNSView.swift`

**Panel setup:**
- Size: 140×20 px
- Position: `(screen.width * 0.66 - 70, 20)` — 2/3 across, 20px from bottom
- Window level: `CGWindowLevelForKey(.maximumWindow)` — above everything
- Style: borderless, non-activating, transparent background
- Collection behavior: `canJoinAllSpaces`, `stationary`
- `hidesOnDeactivate = false`

**Drawing (WaveformNSView):**
- Background: `(0.1, 0.1, 0.1, 0.95)` with rounded corners
- Recording bars: Pink `(1.0, 0.4, 0.6, 1.0)`, height = `level * height * 0.35` (min 10%, max 85%)
- Idle bars: Gray `(0.35, 0.35, 0.35, 1.0)`, fixed at 10% height
- Bars are centered vertically, with 1px corner radius
- Padding: 5% each side, 2% spacing between bars

**Behavior:**
- `show()`: Creates panel if needed, positions it, orders front, sets isRecording=true
- `hide()`: Sets isRecording=false, resets levels to zero, keeps panel visible (idle flat line)
- `updateLevels()`: Sets new levels array, triggers redraw
- Panel stays visible after first show (matches Python — always shows idle line)

## Integration Test Plan

1. **Mic capture test**: Start recording, speak for 5 seconds, stop. Verify:
   - `stop()` returns a non-empty `[Float]` array
   - Duration matches (~5 seconds = ~80,000 samples at 16kHz)
   - Audio is audible if saved to file

2. **FFT test**: During recording, verify:
   - `onLevels` callback fires regularly
   - Levels array has 25 elements
   - Values are in [0, 1] range
   - Silence → levels near 0, speech → levels vary

3. **Waveform test**: During recording, verify:
   - Panel appears at correct screen position
   - Bars animate with audio levels
   - Bars are pink during recording
   - After stop, bars go flat and gray

4. **Transcription test**: Record a phrase, transcribe. Verify:
   - Model loads from disk
   - `transcribe()` returns non-nil text
   - Text is reasonable match to spoken words
   - Artifacts like `[BLANK_AUDIO]` are filtered

## Build & Run
```bash
cd VibeToText
swift build && swift run
```

**Important**: The app needs **microphone permission**. On first run, macOS will prompt. Grant it.

For testing without the full pipeline, you can add temporary test code in `AppDelegate.applicationDidFinishLaunching()` to exercise the audio/transcription APIs directly.
