import SwiftUI
import MetalKit

struct GalaxyView: NSViewRepresentable {
    let wordFrequencies: [WordFrequency]
    let coOccurrence: [String: [(String, Int)]]
    let entries: [TranscriptionEntry]
    var audioLevels: [Float]
    var audioAmplitude: Float
    @Binding var hoveredWord: String?
    @Binding var hoveredCount: Int?
    @Binding var hoveredPosition: CGPoint?
    @Binding var searchText: String
    @Binding var colorMode: Int
    @Binding var timeRange: Date?

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = GalaxyMTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = GalaxyRenderer(device: device) {
            renderer.loadParticles(
                wordFrequencies: wordFrequencies,
                coOccurrence: coOccurrence,
                entries: entries
            )
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
            mtkView.coordinator = context.coordinator
        }

        let magnification = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        mtkView.addGestureRecognizer(magnification)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update search highlight
        if let renderer = context.coordinator.renderer,
           let ps = renderer.particleSystem {
            if searchText.isEmpty {
                renderer.highlightIndex = -1
                renderer.dimFactor = 1.0
            } else {
                let lower = searchText.lowercased()
                if let idx = ps.wordIndices[lower] {
                    renderer.highlightIndex = Int32(idx)
                    renderer.dimFactor = 0.12
                } else {
                    renderer.highlightIndex = -1
                    renderer.dimFactor = 0.12
                }
            }
            renderer.colorMode = Int32(colorMode)
            renderer.audioLevels = audioLevels
            renderer.audioAmplitude = audioAmplitude
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var renderer: GalaxyRenderer?
        let parent: GalaxyView

        init(parent: GalaxyView) {
            self.parent = parent
        }

        @objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            guard let renderer else { return }
            let delta = Float(gesture.magnification) * 0.5
            renderer.zoom = max(0.3, min(5.0, renderer.zoom + delta))
            if gesture.state == .ended {
                gesture.magnification = 0
            }
        }

        func handleMouseMoved(at point: NSPoint, in view: NSView) {
            guard let renderer, let ps = renderer.particleSystem else {
                DispatchQueue.main.async { [self] in
                    parent.hoveredWord = nil
                }
                return
            }

            let scale = view.window?.backingScaleFactor ?? 2.0
            let screenPt = SIMD2<Float>(Float(point.x * scale), Float((view.bounds.height - point.y) * scale))

            if let idx = ps.hitTest(screenPoint: screenPt, uniforms: renderer.uniforms, threshold: 25) {
                DispatchQueue.main.async { [self] in
                    parent.hoveredWord = ps.words[idx]
                    parent.hoveredCount = ps.wordCounts[idx]
                    parent.hoveredPosition = CGPoint(x: point.x, y: point.y)
                }
                renderer.highlightIndex = parent.searchText.isEmpty ? Int32(idx) : renderer.highlightIndex
            } else {
                DispatchQueue.main.async { [self] in
                    parent.hoveredWord = nil
                }
                if parent.searchText.isEmpty {
                    renderer.highlightIndex = -1
                }
            }
        }
    }
}

// Custom MTKView subclass for mouse tracking
class GalaxyMTKView: MTKView {
    weak var coordinator: GalaxyView.Coordinator?
    var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        coordinator?.handleMouseMoved(at: pt, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let renderer = coordinator?.renderer else { return }
        let delta = Float(event.scrollingDeltaY) * 0.02
        renderer.zoom = max(0.3, min(5.0, renderer.zoom + delta))
    }
}
