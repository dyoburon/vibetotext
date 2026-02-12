import SwiftUI
import MetalKit

// Custom MTKView that handles zoom (scroll/pinch) and orbit (drag)
final class TreeMTKView: MTKView {
    weak var treeRenderer: TreeRenderer?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard let renderer = treeRenderer else { return }
        let zoomSpeed: Float = 0.3
        renderer.cameraDistance -= Float(event.scrollingDeltaY) * zoomSpeed
        renderer.cameraDistance = max(1.5, min(20.0, renderer.cameraDistance))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let renderer = treeRenderer else { return }
        let rotSpeed: Float = 0.008
        let elevSpeed: Float = 0.02
        renderer.cameraRotation -= Float(event.deltaX) * rotSpeed
        renderer.cameraElevation += Float(event.deltaY) * elevSpeed
        renderer.cameraElevation = max(-2.0, min(8.0, renderer.cameraElevation))
    }

    override func magnify(with event: NSEvent) {
        guard let renderer = treeRenderer else { return }
        renderer.cameraDistance -= Float(event.magnification) * 3.0
        renderer.cameraDistance = max(1.5, min(20.0, renderer.cameraDistance))
    }
}

struct TreeView: NSViewRepresentable {
    func makeNSView(context: Context) -> TreeMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = TreeMTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = TreeRenderer(device: device) {
            mtkView.delegate = renderer
            mtkView.treeRenderer = renderer
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: TreeMTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: TreeRenderer?
    }
}

struct TreeContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Frequency Tree")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(appState.isLoading ? "Loading..." : "\(appState.totalSessions) sessions")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }
                Spacer()
                HStack(spacing: 24) {
                    TreeStatItem(
                        label: "Health",
                        value: appState.treeData.healthLabel,
                        color: healthColor(appState.treeData.health)
                    )
                    TreeStatItem(
                        label: "Season",
                        value: appState.treeData.seasonLabel,
                        color: seasonColor(appState.treeData.season)
                    )
                    TreeStatItem(
                        label: "Streak",
                        value: appState.treeData.streakLabel,
                        color: Color(red: 1.0, green: 0.78, blue: 0.88)
                    )
                    TreeStatItem(
                        label: "Growth",
                        value: appState.treeData.growthLabel,
                        color: Color(red: 0.984, green: 0.749, blue: 0.141)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(white: 0.05))

            TreeWebView(
                health: appState.treeData.health,
                season: appState.treeData.season,
                streakTier: appState.treeData.streakTier,
                growthProgress: appState.treeData.growthProgress,
                wordDataJSON: appState.treeWordDataJSON,
                uniqueWords: appState.uniqueWords,
                totalWords: appState.totalWords,
                strataJSON: appState.treeStrataJSON
            )
        }
        .background(.black)
    }

    private func healthColor(_ health: Float) -> Color {
        if health > 0.7 { return .green }
        if health > 0.4 { return .yellow }
        return .red
    }

    private func seasonColor(_ season: Float) -> Color {
        if season > 0.66 { return Color(red: 0.4, green: 0.78, blue: 0.28) }
        if season > 0.33 { return Color(red: 0.55, green: 0.88, blue: 0.4) }
        if season > 0.15 { return Color(red: 0.9, green: 0.55, blue: 0.15) }
        return Color(red: 0.5, green: 0.42, blue: 0.3)
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
