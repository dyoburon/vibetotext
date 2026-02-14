import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject var appState: AppState
    let mode: String?
    @State private var searchText = ""
    @State private var selectedEntry: TranscriptionEntry?

    var filteredEntries: [TranscriptionEntry] {
        var entries = appState.entries
        if let mode {
            entries = entries.filter { $0.mode == mode }
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.text.localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsBar()
            List(filteredEntries, selection: $selectedEntry) { entry in
                EntryRow(entry: entry)
                    .tag(entry)
                    .onTapGesture(count: 2) {
                        selectedEntry = entry
                    }
            }
            .searchable(text: $searchText, prompt: "Search transcriptions...")
        }
        .navigationTitle(mode?.capitalized ?? "All History")
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}

struct EntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ModeBadge(mode: entry.mode)
                Text(entry.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let wpm = entry.wpm {
                    Text("\(wpm) wpm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("\(entry.wordCount)w")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(entry.text)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(Color(white: 0.85))
        }
        .padding(.vertical, 4)
    }
}

struct ModeBadge: View {
    let mode: String

    var color: Color {
        switch mode {
        case "transcribe": return .green
        case "greppy": return .purple
        case "plan": return .blue
        case "cleanup": return .orange
        default: return .gray
        }
    }

    var body: some View {
        Text(mode)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
