import AppKit
import CoreGraphics

/// NSPanel-based floating waveform overlay.
/// Borderless, transparent, maximum window level — appears during recording.
/// Port of ui_standalone.py's NSPanel + WaveformView.
final class WaveformOverlayController {
    private var panel: NSPanel?
    private var waveformView: WaveformNSView?
    private let panelWidth: CGFloat = 140
    private let panelHeight: CGFloat = 20

    func show() {
        if panel == nil {
            createPanel()
        }
        positionPanel()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        waveformView?.isRecording = true
        waveformView?.needsDisplay = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        waveformView?.isRecording = false
        waveformView?.levels = [Float](repeating: 0, count: AudioRecorder.numBars)
        waveformView?.needsDisplay = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 0.6
        }
    }

    func updateLevels(_ levels: [Float]) {
        waveformView?.levels = levels
        waveformView?.needsDisplay = true
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear

        let view = WaveformNSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        p.contentView = view

        panel = p
        waveformView = view
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        // Position at 2/3 width, 20px from bottom (matches Python)
        let centerX = screenFrame.origin.x + screenFrame.width * 0.66
        let x = centerX - panelWidth / 2
        let y = screenFrame.origin.y + 20

        panel?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
