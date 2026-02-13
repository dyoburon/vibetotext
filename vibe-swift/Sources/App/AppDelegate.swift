import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindowController: MainWindowController?
    private var pipeline: TranscriptionPipeline?
    private lazy var appIcon: NSImage = Self.makeAppIcon()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu-bar-only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        requestAccessibilityIfNeeded()
        showMainWindow()
        startPipeline()
    }

    /// Generate a dock icon with "VTT" text on a dark rounded-rect background.
    private static func makeAppIcon() -> NSImage {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Dark background matching app theme (bgPrimary: 0x0D0D0F)
        let bg = NSColor(srgbRed: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x0F / 255.0, alpha: 1.0)
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
        bg.setFill()
        path.fill()

        // Subtle border
        let borderColor = NSColor(srgbRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x32 / 255.0, alpha: 1.0)
        borderColor.setStroke()
        path.lineWidth = 4
        path.stroke()

        // "VTT" text in white, bold, centered
        let textColor = NSColor(srgbRed: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0)
        let font = NSFont.systemFont(ofSize: size * 0.30, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let text = "VTT" as NSString
        let textSize = text.size(withAttributes: attrs)
        let textOrigin = NSPoint(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2
        )
        text.draw(at: textOrigin, withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    private func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // SF Symbol microphone icon (template adapts to light/dark)
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VibeToText")
            image?.isTemplate = true
            button.image = image
            button.title = " VTT"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show", action: #selector(showMainWindowAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click works again
        statusItem.menu = nil
    }

    @objc private func showMainWindowAction() {
        showMainWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Main window

    private func toggleMainWindow() {
        if let wc = mainWindowController, wc.window?.isVisible == true {
            wc.window?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = appIcon
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Pipeline

    private func startPipeline() {
        pipeline = TranscriptionPipeline.shared
        pipeline?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pipeline?.stop()
        return .terminateNow
    }
}
