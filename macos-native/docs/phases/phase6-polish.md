# Phase 6: Polish

## Goal
Final visual polish, animations, error handling, and packaging to match the Electron app's look and feel precisely.

## Tasks

### 1. Entry Card Animations
**Reference**: `styles.css` `@keyframes fadeIn`
```css
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
.entry { animation: fadeIn 0.2s ease; }
```

**SwiftUI implementation:**
Add `.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))` to entry cards, or use `.onAppear` with an animation:

```swift
// In EntryCardView:
@State private var appeared = false

var body: some View {
    cardContent
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                appeared = true
            }
        }
}
```

### 2. Custom Scrollbar Styling
**Reference**: `styles.css`
```css
::-webkit-scrollbar { width: 8px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; border: 2px solid transparent; }
::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }
```

**SwiftUI**: Limited scrollbar customization in SwiftUI. Options:
1. Accept system scrollbar (simplest)
2. Use `NSScrollView` customization via `NSViewRepresentable` introspection
3. Use `.scrollIndicators(.hidden)` and implement custom scroll indicator

Recommendation: Accept system scrollbar with `.scrollIndicators(.automatic)` — the dark theme makes it blend well enough.

### 3. Window State Persistence
**Already partially implemented** in `MainWindowController.swift` → `WindowStatePersistence` enum.

**Reference**: `history-app/main.js`
```javascript
// Save on move/resize:
mainWindow.on('move', () => { saveWindowState(); });
mainWindow.on('resize', () => { saveWindowState(); });

// State file: ~/.vibetotext/window-state.json
// Format: { x, y, width, height }
```

**Work needed:**
- Add `NSWindow` delegate methods for `windowDidMove` and `windowDidResize`
- Save state with debounce (don't save on every pixel of movement)
- Load state on window creation, fall back to default 450×600 centered

### 4. Error Handling & Resilience

**Areas to harden:**
- `HistoryDatabase`: Handle corrupt DB gracefully (recreate if needed)
- `ConfigStore`: Handle malformed JSON (use defaults)
- `AudioRecorder`: Handle mic disconnection mid-recording
- `WhisperTranscriber`: Handle model file corruption or missing
- `GeminiService`: Handle network errors, rate limits, invalid API key
- `PasteService`: Handle paste failure gracefully (text is still on clipboard)
- `HotkeyManager`: Handle CGEvent tap failure (no accessibility permission)

**Pattern:**
```swift
// Don't crash — log and show user-friendly status
do {
    try someOperation()
} catch {
    print("[Component] Error: \(error)")
    // Show status in menu bar or notification
}
```

### 5. Menu Bar Icon & App Icon

**Menu bar icon (NSStatusItem):**
- Current: SF Symbol "waveform" + " VTT" text
- Could be refined to a custom 16×16 template image for better appearance
- Template images automatically adapt to light/dark menu bars

**App icon:**
- Create `Assets.xcassets` with `AppIcon` image set
- Sizes needed: 16, 32, 64, 128, 256, 512, 1024 (all @1x and @2x)
- Design suggestion: Waveform/microphone icon in the app's pink/amber color scheme
- Place in `Sources/Resources/Assets.xcassets`

**To add Assets.xcassets:**
1. Create the directory structure:
```
Sources/Resources/Assets.xcassets/
  AppIcon.appiconset/
    Contents.json
    icon_512x512@2x.png   (1024×1024)
    icon_512x512.png       (512×512)
    icon_256x256@2x.png    (512×512)
    icon_256x256.png       (256×256)
    icon_128x128@2x.png    (256×256)
    icon_128x128.png       (128×128)
    icon_32x32@2x.png      (64×64)
    icon_32x32.png         (32×32)
    icon_16x16@2x.png      (32×32)
    icon_16x16.png         (16×16)
```
2. The `.process("Resources")` in Package.swift will pick it up automatically

### 6. First-Launch Onboarding

On first launch, the app needs:
1. **Microphone permission** — prompted by AVAudioEngine automatically
2. **Accessibility permission** — prompted by `AXIsProcessTrustedWithOptions`
3. **Whisper model download** — check if model exists, offer to download if not

**Simple approach (no separate window):**
```swift
// In AppDelegate.applicationDidFinishLaunching:
if !AXIsProcessTrusted() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

// Model check:
if !FileManager.default.fileExists(atPath: modelPath) {
    // Show alert: "Whisper model not found. Download ggml-base.bin?"
    // Or print instructions to console
}
```

### 7. Activation Policy
**Current**: `.accessory` (no dock icon, menu bar only)
**Behavior**: Window shows/hides via menu bar click. No Cmd+Tab entry.

This matches the Electron app's behavior (tray-only app).

When the main window is shown, temporarily set `.regular` so the app appears in Cmd+Tab:
```swift
func showWindow() {
    NSApp.setActivationPolicy(.regular)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

func hideWindow() {
    window?.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
}
```

### 8. Waveform Overlay Spring Animation
**Reference**: The Python overlay simply appears/disappears. Consider adding a subtle spring animation for the Swift version:
```swift
// In show():
panel?.alphaValue = 0
panel?.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.15
    panel?.animator().alphaValue = 1
}

// In hide() — optional gentle fade:
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.15
    panel?.animator().alphaValue = 0.5  // Fade to idle, not fully hidden
}
```

## Testing Checklist
- [ ] Entry cards fade in with 0.2s animation
- [ ] Window position/size persists across launches
- [ ] App handles corrupt/missing history.db gracefully
- [ ] App handles missing config.json gracefully
- [ ] App handles missing Whisper model with helpful message
- [ ] App handles no Gemini API key with helpful message
- [ ] App handles mic disconnection without crashing
- [ ] Menu bar icon looks correct in both light and dark mode
- [ ] App icon appears in About dialog and Finder
- [ ] First launch prompts for Accessibility permission
- [ ] Cmd+Tab shows app when window is open, hides when closed
- [ ] Waveform overlay has smooth appear/disappear transition
- [ ] No console errors or warnings during normal operation

## Build & Run
```bash
cd VibeToText
swift build && swift run
```

## Release Packaging (Future)
```bash
swift build -c release
# Binary at: .build/release/VibeToText
# For distribution: wrap in .app bundle with Info.plist, entitlements
```
