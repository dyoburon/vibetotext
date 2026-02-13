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
                recentTrend: appState.treeData.recentTrend,
                villageStateJSON: appState.villageStateJSON,
                onVillagerKilled: { [weak appState] id, name, role in appState?.recordVillagerDeath(villagerId: id, name: name, role: role) }
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
    @State private var showingDetail = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text("Mood")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.5))
        }
        .onTapGesture {
            showingDetail = true
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .sheet(isPresented: $showingDetail) {
            MoodDetailView(mood: mood, breakdown: breakdown)
        }
    }
}

private struct MoodDetailView: View {
    let mood: Float
    let breakdown: [MoodEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Mood Analysis")
                        .font(.system(size: 20, weight: .bold))
                    HStack(spacing: 8) {
                        Text(moodLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(moodColor)
                        Text(String(format: "%.0f%%", (mood + 1) / 2 * 100))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(moodColor)
                        moodBar
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(Color(white: 0.12))

            Divider()

            if breakdown.isEmpty {
                Spacer()
                Text("No sentiment data yet")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let negatives = breakdown.filter { $0.sentiment < 0 }
                            .sorted { abs($0.sentiment) * Double($0.weight) > abs($1.sentiment) * Double($1.weight) }
                        let positives = breakdown.filter { $0.sentiment > 0 }
                            .sorted { abs($0.sentiment) * Double($0.weight) > abs($1.sentiment) * Double($1.weight) }

                        if !negatives.isEmpty {
                            sectionView(
                                title: "Made me upset (\(negatives.count))",
                                titleColor: .red,
                                entries: negatives
                            )
                        }

                        if !positives.isEmpty {
                            sectionView(
                                title: "Made me happy (\(positives.count))",
                                titleColor: .green,
                                entries: positives
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 600, height: 500)
        .preferredColorScheme(.dark)
    }

    private func sectionView(title: String, titleColor: Color, entries: [MoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(titleColor)
                .padding(.bottom, 2)

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    // Sentiment bar
                    let barWidth = CGFloat(min(abs(entry.sentiment), 1.0)) * 40
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.sentiment > 0 ? Color.green : Color.red)
                        .frame(width: max(barWidth, 4), height: 14)
                        .padding(.top, 3)

                    // Score
                    Text(String(format: "%+.0f%%", entry.sentiment * 100))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(entry.sentiment > 0 ? .green : .red)
                        .frame(width: 50, alignment: .trailing)

                    // Full text
                    Text(entry.text)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // Time
                    Text(timeAgo(entry.hoursAgo))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.15))
                )
            }
        }
    }

    private var moodBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(moodColor)
                    .frame(width: geo.size.width * CGFloat((mood + 1) / 2))
            }
        }
        .frame(width: 80, height: 8)
    }

    private func timeAgo(_ hours: Float) -> String {
        if hours < 1 { return "now" }
        if hours < 24 { return "\(Int(hours))h" }
        return "\(Int(hours / 24))d"
    }

    private var moodLabel: String {
        if mood > 0.5 { return "Radiant" }
        if mood > 0.15 { return "Warm" }
        if mood > -0.15 { return "Neutral" }
        if mood > -0.5 { return "Cold" }
        return "Hostile"
    }

    private var moodColor: Color {
        if mood > 0.3 { return .green }
        if mood > 0.0 { return Color(red: 0.5, green: 0.85, blue: 0.4) }
        if mood > -0.3 { return .yellow }
        return .red
    }
}
