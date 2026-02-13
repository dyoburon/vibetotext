import Foundation
import GRDB

/// Matches the existing `entries` table in ~/.vibetotext/history.db
struct HistoryEntry: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "entries"

    var id: Int64?
    var text: String
    var mode: String
    var timestamp: String          // ISO-8601
    var wordCount: Int
    var durationSeconds: Double?
    var wpm: Int?

    // MARK: - Column mapping (snake_case DB ↔ camelCase Swift)
    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case text
        case mode
        case timestamp
        case wordCount     = "word_count"
        case durationSeconds = "duration_seconds"
        case wpm
    }

    // MARK: - Auto-increment
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Computed properties

    var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: timestamp) { return d }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: timestamp) { return d }
        // Last resort: DateFormatter for Python's isoformat() which may lack timezone
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df.date(from: timestamp) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: timestamp) ?? Date()
    }

    var relativeTime: String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)

        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days < 7 { return "\(days)d ago" }

        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return df.string(from: date)
    }

    // MARK: - Factory

    static func create(
        text: String,
        mode: String,
        durationSeconds: Double? = nil
    ) -> HistoryEntry {
        let wordCount = text.split(separator: " ").count
        var wpm: Int? = nil
        if let dur = durationSeconds, dur > 0 {
            wpm = Int(round(Double(wordCount) / (dur / 60)))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return HistoryEntry(
            id: nil,
            text: text,
            mode: mode,
            timestamp: formatter.string(from: Date()),
            wordCount: wordCount,
            durationSeconds: durationSeconds,
            wpm: wpm
        )
    }
}

// MARK: - Ordering
extension HistoryEntry {
    static let byTimestampDesc = Column("timestamp").desc
}
