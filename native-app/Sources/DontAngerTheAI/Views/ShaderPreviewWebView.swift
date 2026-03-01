import SwiftUI
import MetalKit

struct ShaderPreviewView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = SpherePreviewRenderer(device: device) {
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: SpherePreviewRenderer?
    }
}
