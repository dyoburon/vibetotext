import SwiftUI

/// 4 stat boxes: chats, words, avg WPM, time saved
struct HeaderView: View {
    let stats: HistoryDatabase.Statistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRANSCRIPTION HISTORY")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)

            HStack(spacing: 24) {
                statBox(value: "\(stats.totalSessions)", label: "CHATS")
                statBox(value: "\(stats.totalWords)", label: "WORDS")
                statBox(value: stats.avgWpm > 0 ? "\(stats.avgWpm)" : "--", label: "AVG WPM")
                statBox(
                    value: String(format: "%.1f", stats.timeSavedMinutes),
                    label: "MIN SAVED",
                    highlight: true
                )
            }
        }
        .padding(.top, 38) // Space for hidden titlebar traffic lights
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Theme.bgSecondary, Theme.bgPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Divider().background(Theme.border)
        }
    }

    @ViewBuilder
    private func statBox(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(highlight ? Theme.green : Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(highlight ? Theme.green : Theme.textMuted)
                .tracking(0.5)
        }
    }
}
