import SwiftUI

/// Horizontal chip list of top words
struct CommonWordsView: View {
    let entries: [HistoryEntry]

    private var topWords: [(String, Int)] {
        computeTopWords(from: entries, limit: 10)
    }

    var body: some View {
        if !topWords.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("TOP WORDS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .tracking(0.8)

                FlowLayout(spacing: 6) {
                    ForEach(topWords, id: \.0) { word, count in
                        wordChip(word: word, count: count)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Theme.bgSecondary)
            .overlay(alignment: .bottom) {
                Divider().background(Theme.border)
            }
        }
    }

    @ViewBuilder
    private func wordChip(word: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(word)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.chipRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Word frequency computation

let stopwords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
    "be", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "must", "shall", "can", "need",
    "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
    "my", "your", "his", "its", "our", "their", "this", "that", "these",
    "what", "which", "who", "where", "when", "why", "how", "all", "each",
    "some", "no", "not", "only", "so", "than", "too", "very", "just",
    "also", "now", "here", "there", "then", "if", "because", "about",
    "any", "up", "down", "out", "off", "over", "going", "gonna", "like",
    "okay", "ok", "yeah", "yes", "um", "uh", "ah", "oh", "well", "right",
    "actually", "basically", "really", "thing", "things", "something",
    "know", "think", "want", "get", "got", "make", "way", "see", "go",
]

func computeTopWords(from entries: [HistoryEntry], limit: Int) -> [(String, Int)] {
    var counts: [String: Int] = [:]
    let punctuation = CharacterSet.punctuationCharacters
    for entry in entries {
        let words = entry.text.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: punctuation) }
            .filter { $0.count > 2 && !stopwords.contains($0) }
        for w in words {
            counts[w, default: 0] += 1
        }
    }
    return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
}

// MARK: - FlowLayout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), offsets)
    }
}
