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
                    MoodStatItem(
                        value: appState.treeData.moodLabel,
                        color: moodColor(appState.treeData.mood),
                        mood: appState.treeData.mood,
                        breakdown: appState.treeData.moodBreakdown
                    )
                    TreeStatItem(
                        label: "Pop.",
                        value: "\(appState.treeData.population)",
                        color: .white
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
                strataJSON: appState.treeStrataJSON,
                mood: appState.treeData.mood,
                population: appState.treeData.population,
                recentTrend: appState.treeData.recentTrend
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

    private func moodColor(_ mood: Float) -> Color {
        if mood > 0.3 { return .green }
        if mood > 0.0 { return Color(red: 0.5, green: 0.85, blue: 0.4) }
        if mood > -0.3 { return .yellow }
        return .red
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

private struct MoodStatItem: View {
    let value: String
    let color: Color
    let mood: Float
    let breakdown: [MoodEntry]
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text("Mood")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.5))
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            MoodBreakdownPopover(mood: mood, breakdown: breakdown)
        }
    }
}

private struct MoodBreakdownPopover: View {
    let mood: Float
    let breakdown: [MoodEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Mood: \(moodEmoji)")
                    .font(.system(size: 14, weight: .bold))
                Text(String(format: "%.0f%%", (mood + 1) / 2 * 100))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(moodColor)
            }

            if breakdown.isEmpty {
                Text("No sentiment data yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                let negatives = breakdown.filter { $0.sentiment < 0 }
                let positives = breakdown.filter { $0.sentiment > 0 }

                if !positives.isEmpty {
                    Text("Made me happy:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                    ForEach(positives) { entry in
                        sentimentRow(entry)
                    }
                }

                if !negatives.isEmpty {
                    Text("Made me upset:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.top, positives.isEmpty ? 0 : 4)
                    ForEach(negatives) { entry in
                        sentimentRow(entry)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func sentimentRow(_ entry: MoodEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.sentiment > 0 ? "+" : "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(entry.sentiment > 0 ? .green : .red)
            + Text(String(format: "%.0f%%", entry.sentiment * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(entry.sentiment > 0 ? .green : .red)

            Text(entry.text)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            Text(timeAgo(entry.hoursAgo))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func timeAgo(_ hours: Float) -> String {
        if hours < 1 { return "now" }
        if hours < 24 { return "\(Int(hours))h" }
        return "\(Int(hours / 24))d"
    }

    private var moodEmoji: String {
        if mood > 0.5 { return "radiant" }
        if mood > 0.15 { return "warm" }
        if mood > -0.15 { return "neutral" }
        if mood > -0.5 { return "cold" }
        return "hostile"
    }

    private var moodColor: Color {
        if mood > 0.3 { return .green }
        if mood > 0.0 { return Color(red: 0.5, green: 0.85, blue: 0.4) }
        if mood > -0.3 { return .yellow }
        return .red
    }
}
