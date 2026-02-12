import Foundation
import SQLite3

final class DatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.vibetotext/history.db"
    }

    private func open() -> Bool {
        guard db == nil else { return true }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)
        if result != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db!)))")
            db = nil
            return false
        }
        return true
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    func fetchAllEntries() -> [TranscriptionEntry] {
        guard open() else { return [] }

        let sql = "SELECT id, text, mode, timestamp, word_count, duration_seconds, wpm, sentiment FROM entries ORDER BY timestamp DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("Failed to prepare statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        var entries: [TranscriptionEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let text = String(cString: sqlite3_column_text(stmt, 1))
            let mode = String(cString: sqlite3_column_text(stmt, 2))
            let tsStr = String(cString: sqlite3_column_text(stmt, 3))
            let wordCount = Int(sqlite3_column_int(stmt, 4))

            let durationSeconds: Double? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 5) : nil
            let wpm: Int? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? Int(sqlite3_column_int(stmt, 6)) : nil
            let sentiment: Double? = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                ? sqlite3_column_double(stmt, 7) : nil

            let timestamp = fallbackFormatter.date(from: tsStr) ?? formatter.date(from: tsStr) ?? Date()

            entries.append(TranscriptionEntry(
                id: id, text: text, mode: mode, timestamp: timestamp,
                wordCount: wordCount, durationSeconds: durationSeconds,
                wpm: wpm, sentiment: sentiment
            ))
        }
        return entries
    }

    func fetchEntryCount() -> Int {
        guard open() else { return 0 }
        let sql = "SELECT COUNT(*) FROM entries"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    deinit { close() }
}
