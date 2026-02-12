import SwiftUI

enum NavDestination: Hashable {
    case galaxy
    case history(mode: String?)
    case entryDetail(TranscriptionEntry)
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: NavDestination? = .galaxy

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .galaxy:
                GalaxyContainerView()
            case .history(let mode):
                HistoryListView(mode: mode)
            case .entryDetail(let entry):
                EntryDetailView(entry: entry)
            case nil:
                GalaxyContainerView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct GalaxyContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredWord: String?
    @State private var hoveredCount: Int?
    @State private var hoveredPosition: CGPoint?
    @State private var searchText: String = ""
    @State private var colorMode: Int = 0  // 0 = frequency, 1 = age
    @State private var timeRange: Date? = nil
    @State private var timeSliderValue: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: stats + controls
            HStack(spacing: 16) {
                StatsBar()
                Spacer()
                // Color mode picker
                Picker("", selection: $colorMode) {
                    Text("Frequency").tag(0)
                    Text("Age").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search word...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 140)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(white: 0.12))
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(white: 0.05))

            // Galaxy
            if appState.isLoading {
                Spacer()
                ProgressView("Loading transcription history...")
                Spacer()
            } else {
                ZStack {
                    GalaxyView(
                        wordFrequencies: filteredFrequencies,
                        coOccurrence: appState.coOccurrence,
                        entries: appState.entries,
                        audioLevels: appState.audioLevels,
                        audioAmplitude: appState.audioAmplitude,
                        hoveredWord: $hoveredWord,
                        hoveredCount: $hoveredCount,
                        hoveredPosition: $hoveredPosition,
                        searchText: $searchText,
                        colorMode: $colorMode,
                        timeRange: $timeRange
                    )

                    // Hover tooltip
                    if let word = hoveredWord, let count = hoveredCount, let pos = hoveredPosition {
                        WordTooltip(word: word, count: count)
                            .position(x: pos.x + 40, y: pos.y - 20)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Time scrubber
            if !appState.isLoading {
                TimeScrubber(value: $timeSliderValue, appState: appState)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.05))
            }
        }
        .background(.black)
        .onChange(of: timeSliderValue) { _, newValue in
            updateTimeRange(newValue)
        }
    }

    var filteredFrequencies: [WordFrequency] {
        if let endDate = timeRange {
            return WordFrequencyEngine.buildFrequencyMap(from: appState.entries, upTo: endDate)
        }
        return appState.wordFrequencies
    }

    func updateTimeRange(_ fraction: Double) {
        if fraction >= 0.99 {
            timeRange = nil
            return
        }
        let sorted = appState.entries.map(\.timestamp).sorted()
        guard let first = sorted.first, let last = sorted.last else { return }
        let span = last.timeIntervalSince(first)
        timeRange = first.addingTimeInterval(span * fraction)
    }
}

struct WordTooltip: View {
    let word: String
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(word)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text("\(count) uses")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.15).opacity(0.95))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.5), radius: 4)
    }
}

struct TimeScrubber: View {
    @Binding var value: Double
    let appState: AppState

    var dateLabel: String {
        if value >= 0.99 { return "All time" }
        let sorted = appState.entries.map(\.timestamp).sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        let span = last.timeIntervalSince(first)
        let date = first.addingTimeInterval(span * value)
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    var wordCount: Int {
        if value >= 0.99 { return appState.uniqueWords }
        let sorted = appState.entries.map(\.timestamp).sorted()
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        let span = last.timeIntervalSince(first)
        let endDate = first.addingTimeInterval(span * value)
        let filtered = appState.entries.filter { $0.timestamp <= endDate }
        return Set(filtered.flatMap { WordFrequencyEngine.tokenize($0.text) }).count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            Slider(value: $value, in: 0.01...1.0)
                .tint(Color(red: 0.984, green: 0.749, blue: 0.141))

            Text(dateLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(red: 0.984, green: 0.749, blue: 0.141))
                .frame(width: 70, alignment: .trailing)

            Text("\(wordCount) words")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }
}

struct StatsBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 32) {
            StatItem(label: "Sessions", value: "\(appState.totalSessions)")
            StatItem(label: "Total Words", value: formatNumber(appState.totalWords))
            StatItem(label: "Avg WPM", value: "\(appState.averageWPM)")
            StatItem(label: "Unique Words", value: formatNumber(appState.uniqueWords))
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.984, green: 0.749, blue: 0.141))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.5))
        }
    }
}
