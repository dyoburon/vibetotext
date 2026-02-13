import AppKit
import SwiftUI

/// NSWindowController that hosts the main SwiftUI ContentView.
/// 450x600 default, hidden titlebar with inset traffic lights, dark chrome.
final class MainWindowController: NSWindowController {
    convenience init() {
        let savedState = WindowStatePersistence.load()
        let frame = savedState ?? NSRect(x: 200, y: 200, width: 450, height: 600)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 350, height: 400)
        window.backgroundColor = Theme.nsBgPrimary
        window.title = "VibeToText"

        // Restore saved position
        if savedState != nil {
            window.setFrame(frame, display: true)
        } else {
            window.center()
        }

        let contentView = ContentView()
        window.contentView = NSHostingView(rootView: contentView)

        self.init(window: window)

        // Save window state on move/resize
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveOrResize),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveOrResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc private func windowDidMoveOrResize(_ notification: Notification) {
        guard let window else { return }
        WindowStatePersistence.save(window.frame)
    }
}

// MARK: - Window state persistence (matches Electron's window-state.json)

enum WindowStatePersistence {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vibetotext/window-state.json")

    static func load() -> NSRect? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let x = json["x"] as? Double,
              let y = json["y"] as? Double,
              let w = json["width"] as? Double,
              let h = json["height"] as? Double
        else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    static func save(_ frame: NSRect) {
        let json: [String: Any] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
