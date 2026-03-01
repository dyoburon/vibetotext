import AppKit
import CoreGraphics

/// Copies text to clipboard and simulates Cmd+V via CGEventPost.
/// Port of output.py's paste_at_cursor().
enum PasteService {

    static func pasteAtCursor(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        print("[Paste] Copied \(trimmed.count) chars to clipboard")

        // 2. Wait for modifier keys to be released
        Thread.sleep(forTimeInterval: 0.1)

        // 3. Simulate Cmd+V
        simulatePaste()
    }

    private static func simulatePaste() {
        let vKeyCode: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else {
            print("[Paste] Failed to create keyboard events")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("[Paste] Cmd+V simulated")
    }
}
