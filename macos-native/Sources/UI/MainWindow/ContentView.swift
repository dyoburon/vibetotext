import SwiftUI
import Combine
import GRDB

/// Root view: header stats + tab bar + content area
struct ContentView: View {
    @State private var selectedTab: TabMode = .all
    @State private var entries: [HistoryEntry] = []
    @State private var stats = HistoryDatabase.Statistics()
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(stats: stats)
            TabBarView(selectedTab: $selectedTab)
            contentForTab
        }
        .background(Theme.bgPrimary)
        .onAppear { startObserving() }
        .onChange(of: selectedTab) { _, _ in startObserving() }
    }

    @ViewBuilder
    private var contentForTab: some View {
        switch selectedTab {
        case .all, .transcribe, .cleanup, .plan:
            historyContent
        case .greppy:
            greppyContent
        case .analytics:
            AnalyticsDashboardView()
        case .microphone:
            MicrophoneSettingsView()
        case .dictionary:
            DictionarySettingsView()
        }
    }

    @ViewBuilder
    private var greppyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                GreppySettingsView()
                if entries.isEmpty {
                    EmptyStateView()
                } else {
                    VStack(spacing: 0) {
                        CommonWordsView(entries: entries)
                        HistoryListView(entries: entries)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if entries.isEmpty {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                CommonWordsView(entries: entries)
                HistoryListView(entries: entries)
            }
        }
    }

    private func startObserving() {
        cancellables.removeAll()

        let modeFilter: String? = switch selectedTab {
        case .all, .analytics, .microphone, .dictionary: nil
        case .transcribe: "transcribe"
        case .greppy: "greppy"
        case .cleanup: "cleanup"
        case .plan: "plan"
        }

        let statsMode: String? = switch selectedTab {
        case .analytics, .microphone, .dictionary: nil
        default: modeFilter
        }

        HistoryDatabase.shared.observeEntries(mode: modeFilter)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { self.entries = $0 }
            )
            .store(in: &cancellables)

        HistoryDatabase.shared.observeStatistics(mode: statsMode)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { self.stats = $0 }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Tab modes
enum TabMode: String, CaseIterable {
    case all, transcribe, greppy, cleanup, plan, analytics, microphone, dictionary

    var label: String {
        switch self {
        case .all: "All"
        case .transcribe: "Transcribe"
        case .greppy: "Greppy"
        case .cleanup: "Cleanup"
        case .plan: "Plan"
        case .analytics: "Analytics"
        case .microphone: "Microphone"
        case .dictionary: "Dictionary"
        }
    }
}
