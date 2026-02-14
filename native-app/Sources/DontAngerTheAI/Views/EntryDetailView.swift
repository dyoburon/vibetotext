import SwiftUI

struct EntryDetailView: View {
    let entry: TranscriptionEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ModeBadge(mode: entry.mode)
                Text(entry.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            HStack(spacing: 24) {
                DetailStat(label: "Words", value: "\(entry.wordCount)")
                if let wpm = entry.wpm {
                    DetailStat(label: "WPM", value: "\(wpm)")
                }
                if let dur = entry.durationSeconds {
                    DetailStat(label: "Duration", value: String(format: "%.1fs", dur))
                }
                if let sentiment = entry.sentiment {
                    DetailStat(
                        label: "Sentiment",
                        value: String(format: "%.2f", sentiment),
                        color: sentimentColor(sentiment)
                    )
                }
            }

            Divider()

            ScrollView {
                Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(Color(white: 0.08))
    }

    private func sentimentColor(_ value: Double) -> Color {
        if value > 0.2 { return .green }
        if value < -0.2 { return .red }
        return .secondary
    }
}

struct DetailStat: View {
    let label: String
    let value: String
    var color: Color = Color(red: 0.984, green: 0.749, blue: 0.141)

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
