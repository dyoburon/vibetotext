import AppKit

/// Custom NSView that draws the 25-bar frequency waveform.
/// Port of ui_standalone.py's WaveformView.
final class WaveformNSView: NSView {
    var levels: [Float] = [Float](repeating: 0, count: AudioRecorder.numBars)
    var isRecording = false

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds

        // Rounded dark background
        NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 0.95).set()
        let cornerRadius = min(4, rect.height / 5)
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        bgPath.fill()

        let width = rect.width
        let height = rect.height
        let numBars = AudioRecorder.numBars
        let padding = width * 0.05
        let usableWidth = width - padding * 2
        let barSpacing = usableWidth * 0.02
        let totalSpacing = barSpacing * CGFloat(numBars - 1)
        let barWidth = (usableWidth - totalSpacing) / CGFloat(numBars)
        let startX = padding
        let centerY = height / 2

        if isRecording {
            // Pink bars for recording
            NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.6, alpha: 1.0).set()
            for i in 0..<numBars {
                let level = CGFloat(i < levels.count ? levels[i] : 0)
                let x = startX + CGFloat(i) * (barWidth + barSpacing)
                let minHeight = max(2, height * 0.1)
                var barHeight = max(minHeight, level * height * 0.35)
                barHeight = min(barHeight, height * 0.85)
                let y = centerY - barHeight / 2
                let barPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight), xRadius: 1, yRadius: 1)
                barPath.fill()
            }
        } else {
            // Gray flat line for idle
            NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.35, alpha: 1.0).set()
            let minHeight = max(2, height * 0.1)
            for i in 0..<numBars {
                let x = startX + CGFloat(i) * (barWidth + barSpacing)
                let barPath = NSBezierPath(roundedRect: NSRect(x: x, y: centerY - minHeight / 2, width: barWidth, height: minHeight), xRadius: 1, yRadius: 1)
                barPath.fill()
            }
        }
    }
}
