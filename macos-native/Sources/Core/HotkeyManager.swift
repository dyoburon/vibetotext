import Foundation
import CoreGraphics

/// CGEvent tap for global hotkey listening.
/// 4 modes: cmd+alt+p → plan, cmd+alt+shift → greppy, alt+shift → cleanup, ctrl+shift → transcribe
/// Hold-to-record, release-to-stop. 60-second auto-cutoff.
///
/// Phase 4 implementation — this is a functional stub.
final class HotkeyManager {
    var onRecordingStart: ((String) -> Void)?
    var onRecordingStop: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var activeMode: String?
    private var timeoutTimer: Timer?
    private let maxRecordingSeconds: TimeInterval = 60

    // Track modifier state
    private var pressedModifiers: CGEventFlags = []

    // Hotkey definitions: (modifiers, key) → mode
    // cmd+alt+p → plan
    // alt+shift → cleanup
    // ctrl+shift → transcribe
    private struct HotkeyDef {
        let modifiers: CGEventFlags
        let keyCode: UInt16? // nil = modifiers-only combo
        let mode: String
    }

    private let hotkeys: [HotkeyDef] = [
        // cmd+alt+p (key code 35 = 'p')
        HotkeyDef(modifiers: [.maskCommand, .maskAlternate], keyCode: 35, mode: "plan"),
        // cmd+shift+f (key code 3 = 'f')
        HotkeyDef(modifiers: [.maskCommand, .maskShift], keyCode: 3, mode: "feedback"),
        // cmd+alt+shift (modifiers only) — must be before alt+shift (more specific)
        HotkeyDef(modifiers: [.maskCommand, .maskAlternate, .maskShift], keyCode: nil, mode: "greppy"),
        // alt+shift (modifiers only)
        HotkeyDef(modifiers: [.maskAlternate, .maskShift], keyCode: nil, mode: "cleanup"),
        // ctrl+shift (modifiers only)
        HotkeyDef(modifiers: [.maskControl, .maskShift], keyCode: nil, mode: "transcribe"),
    ]

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handleEvent(type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("[HotkeyManager] Failed to create event tap. Grant Accessibility permission.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyManager] Listening for hotkeys:")
        print("  [ctrl+shift]    = transcribe")
        print("  [alt+shift]     = cleanup")
        print("  [cmd+alt+shift] = greppy")
        print("  [cmd+alt+p]     = plan")
        print("  [cmd+shift+f]   = feedback")
    }

    func stop() {
        timeoutTimer?.invalidate()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            pressedModifiers = flags
            checkHotkeys(keyCode: nil, isKeyDown: false, flags: flags)

        case .keyDown:
            checkHotkeys(keyCode: keyCode, isKeyDown: true, flags: flags)

        case .keyUp:
            // If recording and key released, check if we should stop
            if isRecording {
                // For key-based combos (like cmd+alt+p), stop on 'p' release
                if let mode = activeMode,
                   let def = hotkeys.first(where: { $0.mode == mode }),
                   def.keyCode == keyCode {
                    stopRecordingForMode(mode)
                }
            }

        default:
            break
        }

        // For modifier-only combos, detect release
        if isRecording, let mode = activeMode,
           let def = hotkeys.first(where: { $0.mode == mode }),
           def.keyCode == nil {
            // Check if required modifiers are no longer all held
            if !flags.contains(def.modifiers) {
                stopRecordingForMode(mode)
            }
        }
    }

    private func checkHotkeys(keyCode: UInt16?, isKeyDown: Bool, flags: CGEventFlags) {
        guard !isRecording else { return }

        // Check longest combos first (most specific match)
        let sorted = hotkeys.sorted { a, b in
            a.modifiers.rawValue.nonzeroBitCount > b.modifiers.rawValue.nonzeroBitCount
        }

        for def in sorted {
            let modsMatch = flags.contains(def.modifiers)
            let keyMatch = def.keyCode == nil || (isKeyDown && keyCode == def.keyCode)

            if modsMatch && keyMatch {
                startRecordingForMode(def.mode)
                return
            }
        }
    }

    private func startRecordingForMode(_ mode: String) {
        isRecording = true
        activeMode = mode

        // Auto-cutoff timer
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingSeconds, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            print("[HotkeyManager] Recording timeout (\(Int(self.maxRecordingSeconds))s), auto-stopping...")
            self.stopRecordingForMode(mode)
        }

        onRecordingStart?(mode)
    }

    private func stopRecordingForMode(_ mode: String) {
        guard isRecording else { return }
        isRecording = false
        activeMode = nil
        timeoutTimer?.invalidate()

        onRecordingStop?(mode)
    }
}
