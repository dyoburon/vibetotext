import SwiftUI

/// Card for a single history entry with hover effects
struct EntryCardView: View {
    let entry: HistoryEntry
    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: time + mode badge
            HStack {
                Text(entry.relativeTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                modeBadge
            }
            .padding(.bottom, 10)

            // Text content
            Text(entry.text)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Stats
            Text(statsString)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isHovered ? Theme.bgTertiary : Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isHovered ? Theme.accent : Theme.border, lineWidth: 1)
        )
        .shadow(color: isHovered ? .black.opacity(0.3) : .clear, radius: 12, y: 4)
        .offset(y: isHovered ? -1 : 0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
    }

    @ViewBuilder
    private var modeBadge: some View {
        Text(entry.mode.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.3)
            .foregroundColor(Theme.modeColor(entry.mode))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.modeSoftColor(entry.mode))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statsString: String {
        var parts: [String] = []
        if let dur = entry.durationSeconds {
            parts.append(String(format: "%.1fs", dur))
        }
        if let wpm = entry.wpm {
            parts.append("\(wpm) WPM")
        }
        parts.append("\(entry.wordCount) words")
        return parts.joined(separator: " \u{00B7} ")
    }
}
