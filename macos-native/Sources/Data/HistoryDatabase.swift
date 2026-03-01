import Foundation
import GRDB
import Combine

/// GRDB-based database layer matching the existing ~/.vibetotext/history.db schema.
/// Uses ValueObservation for reactive SwiftUI updates.
final class HistoryDatabase: ObservableObject, Sendable {
    static let shared = HistoryDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibetotext")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent("history.db").path
        do {
            var config = Configuration()
            config.busyMode = .timeout(30)
            dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }

    // MARK: - Schema migration (idempotent)
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createEntries") { db in
            // Only create if not exists — preserves data from Python app
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    text TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    word_count INTEGER NOT NULL,
                    duration_seconds REAL,
                    wpm INTEGER
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_timestamp ON entries(timestamp DESC)
            """)
        }
        return migrator
    }

    // MARK: - Write

    func addEntry(_ entry: HistoryEntry) async throws {
        try await dbQueue.write { db in
            var e = entry
            try e.insert(db)
        }
    }

    func addEntry(text: String, mode: String, durationSeconds: Double? = nil) async throws {
        let entry = HistoryEntry.create(text: text, mode: mode, durationSeconds: durationSeconds)
        try await addEntry(entry)
    }

    func clearAll() async throws {
        try await dbQueue.write { db in
            try HistoryEntry.deleteAll(db)
        }
    }

    // MARK: - Read

    func entries(limit: Int? = nil, mode: String? = nil) throws -> [HistoryEntry] {
        try dbQueue.read { db in
            var request = HistoryEntry.order(Column("timestamp").desc)
            if let mode {
                request = request.filter(Column("mode") == mode)
            }
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    func entryCount() throws -> Int {
        try dbQueue.read { db in
            try HistoryEntry.fetchCount(db)
        }
    }

    // MARK: - Statistics

    struct Statistics {
        var totalSessions: Int = 0
        var totalWords: Int = 0
        var avgWpm: Int = 0
        var timeSavedMinutes: Double = 0
        var totalDurationSeconds: Double = 0
    }

    func statistics(mode: String? = nil) throws -> Statistics {
        try dbQueue.read { db in
            var filter = ""
            if let mode {
                filter = " WHERE mode = '\(mode)'"
            }
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) as total_sessions,
                    COALESCE(SUM(word_count), 0) as total_words,
                    COALESCE(SUM(duration_seconds), 0) as total_duration
                FROM entries\(filter)
            """)!

            let totalSessions = row["total_sessions"] as Int
            let totalWords = row["total_words"] as Int
            let totalDuration = row["total_duration"] as Double

            // Average WPM
            let wpmRow = try Row.fetchOne(db, sql: """
                SELECT AVG(wpm) as avg_wpm FROM entries WHERE wpm IS NOT NULL\(filter.isEmpty ? "" : " AND mode = '\(mode!)'")
            """)!
            let avgWpm = (wpmRow["avg_wpm"] as Double?).map { Int(round($0)) } ?? 0

            // Time saved
            let wordsRow = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(word_count), 0) as words
                FROM entries WHERE duration_seconds IS NOT NULL\(filter.isEmpty ? "" : " AND mode = '\(mode!)'")
            """)!
            let wordsWithDuration = wordsRow["words"] as Int
            let typingWpm = 100.0 // same as renderer.js
            let timeToType = Double(wordsWithDuration) / typingWpm
            let timeDictating = totalDuration / 60.0
            let timeSaved = max(0, timeToType - timeDictating)

            return Statistics(
                totalSessions: totalSessions,
                totalWords: totalWords,
                avgWpm: avgWpm,
                timeSavedMinutes: timeSaved,
                totalDurationSeconds: totalDuration
            )
        }
    }

    // MARK: - Reactive observation (replaces chokidar polling)

    /// Publisher that emits the full entry list whenever the DB changes.
    func observeEntries(mode: String? = nil) -> DatabasePublishers.Value<[HistoryEntry]> {
        ValueObservation.tracking { db in
            var request = HistoryEntry.order(Column("timestamp").desc)
            if let mode {
                request = request.filter(Column("mode") == mode)
            }
            return try request.fetchAll(db)
        }
        .publisher(in: dbQueue, scheduling: .immediate)
    }

    /// Publisher that emits statistics whenever the DB changes.
    func observeStatistics(mode: String? = nil) -> DatabasePublishers.Value<Statistics> {
        ValueObservation.tracking { [self] db in
            // Can't call `self.statistics()` inside tracking because it opens a new read.
            // Re-inline the query here.
            let filter = mode.map { " WHERE mode = '\($0)'" } ?? ""
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as total_sessions,
                       COALESCE(SUM(word_count), 0) as total_words,
                       COALESCE(SUM(duration_seconds), 0) as total_duration
                FROM entries\(filter)
            """)!
            let totalSessions = row["total_sessions"] as Int
            let totalWords = row["total_words"] as Int
            let totalDuration = row["total_duration"] as Double

            let wpmFilter = filter.isEmpty ? "" : " AND mode = '\(mode!)'"
            let wpmRow = try Row.fetchOne(db, sql: """
                SELECT AVG(wpm) as avg_wpm FROM entries WHERE wpm IS NOT NULL\(wpmFilter)
            """)!
            let avgWpm = (wpmRow["avg_wpm"] as Double?).map { Int(round($0)) } ?? 0

            let wordsRow = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(word_count), 0) as words
                FROM entries WHERE duration_seconds IS NOT NULL\(wpmFilter)
            """)!
            let wordsWithDuration = wordsRow["words"] as Int
            let timeToType = Double(wordsWithDuration) / 100.0
            let timeDictating = totalDuration / 60.0
            let timeSaved = max(0, timeToType - timeDictating)

            return Statistics(
                totalSessions: totalSessions,
                totalWords: totalWords,
                avgWpm: avgWpm,
                timeSavedMinutes: timeSaved,
                totalDurationSeconds: totalDuration
            )
        }
        .publisher(in: dbQueue, scheduling: .immediate)
    }
}
