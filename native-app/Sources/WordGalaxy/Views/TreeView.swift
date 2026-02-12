import SwiftUI
import MetalKit

struct TreeView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = TreeRenderer(device: device) {
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: TreeRenderer?
    }
}

struct TreeContainerView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Frequency Tree")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Sample Data — Prototype")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }
                Spacer()
                HStack(spacing: 24) {
                    TreeStatItem(label: "Health", value: "85%", color: .green)
                    TreeStatItem(label: "Season", value: "Summer", color: Color(red: 0.4, green: 0.78, blue: 0.28))
                    TreeStatItem(label: "Streak", value: "7 days", color: Color(red: 1.0, green: 0.78, blue: 0.88))
                    TreeStatItem(label: "Growth", value: "100%", color: Color(red: 0.984, green: 0.749, blue: 0.141))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(white: 0.05))

            TreeView()
        }
        .background(.black)
    }
}

private struct TreeStatItem: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.5))
        }
    }
}
