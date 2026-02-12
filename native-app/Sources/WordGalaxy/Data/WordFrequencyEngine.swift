import Foundation

struct WordFrequency {
    let word: String
    let count: Int
    let normalizedFrequency: Float  // 0.0 (rarest) to 1.0 (most common), log-scaled
    let firstSeen: Date             // when this word first appeared
    let ageFraction: Float          // 0.0 (oldest word) to 1.0 (newest word)
}

final class WordFrequencyEngine {
    /// Build frequency map with birth dates from entries within an optional date range.
    static func buildFrequencyMap(
        from entries: [TranscriptionEntry],
        upTo endDate: Date? = nil
    ) -> [WordFrequency] {
        // Sort entries chronologically for birth date tracking
        let chronological = entries.sorted { $0.timestamp < $1.timestamp }

        var counts: [String: Int] = [:]
        var firstSeen: [String: Date] = [:]

        for entry in chronological {
            if let endDate, entry.timestamp > endDate { continue }

            let words = tokenize(entry.text)
            for word in words {
                counts[word, default: 0] += 1
                if firstSeen[word] == nil {
                    firstSeen[word] = entry.timestamp
                }
            }
        }

        let sorted = counts.sorted { $0.value > $1.value }
        guard let maxCount = sorted.first?.value, maxCount > 0 else { return [] }

        let logMax = log(Float(maxCount))

        // Compute age fractions (oldest = 0, newest = 1)
        let allDates = sorted.compactMap { firstSeen[$0.key] }
        let minDate = allDates.min() ?? Date()
        let maxDate = allDates.max() ?? Date()
        let dateSpan = max(maxDate.timeIntervalSince(minDate), 1.0)

        return sorted.map { word, count in
            let normalizedFreq: Float = logMax > 0
                ? log(Float(count)) / logMax
                : 0.0
            let wordDate = firstSeen[word] ?? minDate
            let ageFrac = Float(wordDate.timeIntervalSince(minDate) / dateSpan)

            return WordFrequency(
                word: word,
                count: count,
                normalizedFrequency: normalizedFreq,
                firstSeen: wordDate,
                ageFraction: ageFrac
            )
        }
    }

    /// Build co-occurrence map: for each word, which other words appear in the same entries.
    static func buildCoOccurrence(
        from entries: [TranscriptionEntry],
        topWords: Set<String>,
        maxPerWord: Int = 8
    ) -> [String: [(String, Int)]] {
        var coOccur: [String: [String: Int]] = [:]

        for entry in entries {
            let words = Set(tokenize(entry.text)).intersection(topWords)
            for word in words {
                for other in words where other != word {
                    coOccur[word, default: [:]][other, default: 0] += 1
                }
            }
        }

        // Return top co-occurring words per word
        return coOccur.mapValues { counts in
            counts.sorted { $0.value > $1.value }.prefix(maxPerWord).map { ($0.key, $0.value) }
        }
    }

    /// Label-propagation clustering on co-occurrence graph.
    /// Returns word → clusterID mapping.
    static func buildClusters(
        coOccurrence: [String: [(String, Int)]],
        words: [String]
    ) -> [String: Int] {
        // Each word starts as its own cluster
        var labels: [String: Int] = [:]
        for (i, w) in words.enumerated() {
            labels[w] = i
        }

        // Iterate label propagation
        for _ in 0..<8 {
            var changed = false
            for word in words {
                guard let neighbors = coOccurrence[word], !neighbors.isEmpty else { continue }
                // Count weighted votes for each label
                var votes: [Int: Int] = [:]
                for (neighbor, weight) in neighbors {
                    guard let lbl = labels[neighbor] else { continue }
                    votes[lbl, default: 0] += weight
                }
                if let best = votes.max(by: { $0.value < $1.value })?.key,
                   best != labels[word] {
                    labels[word] = best
                    changed = true
                }
            }
            if !changed { break }
        }

        // Merge tiny clusters (<3 members) into nearest neighbor's cluster
        var clusterSizes: [Int: Int] = [:]
        for (_, lbl) in labels { clusterSizes[lbl, default: 0] += 1 }

        for word in words {
            guard let lbl = labels[word], (clusterSizes[lbl] ?? 0) < 3 else { continue }
            if let neighbors = coOccurrence[word],
               let best = neighbors.first(where: {
                   if let nl = labels[$0.0] { return (clusterSizes[nl] ?? 0) >= 3 }
                   return false
               }) {
                labels[word] = labels[best.0]
            }
        }

        // Renumber clusters to be contiguous 0..N
        var uniqueLabels: [Int: Int] = [:]
        var nextID = 0
        for word in words {
            guard let lbl = labels[word] else { continue }
            if uniqueLabels[lbl] == nil {
                uniqueLabels[lbl] = nextID
                nextID += 1
            }
            labels[word] = uniqueLabels[lbl]
        }

        return labels
    }

    static func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        var words: [String] = []
        var current = ""

        for char in lower {
            if char.isLetter || char == "'" {
                current.append(char)
            } else {
                if current.count > 2 && !stopWords.contains(current) {
                    words.append(current)
                }
                current = ""
            }
        }
        if current.count > 2 && !stopWords.contains(current) {
            words.append(current)
        }
        return words
    }
}
