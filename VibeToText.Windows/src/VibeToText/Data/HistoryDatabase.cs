using System.Collections.Concurrent;
using System.IO;
using Microsoft.Data.Sqlite;
using VibeToText.Models;

namespace VibeToText.Data;

/// <summary>
/// SQLite database for transcription history. Compatible schema with Python/Swift apps.
/// </summary>
public class HistoryDatabase
{
    private static readonly string DbPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".vibetotext", "history.db"
    );

    private static readonly HashSet<string> Stopwords = new(StringComparer.OrdinalIgnoreCase)
    {
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "need",
        "dare", "ought", "used", "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them", "my", "your", "his", "its", "our",
        "their", "this", "that", "these", "those", "what", "which", "who",
        "whom", "whose", "where", "when", "why", "how", "all", "each", "every",
        "both", "few", "more", "most", "other", "some", "such", "no", "nor",
        "not", "only", "own", "same", "so", "than", "too", "very", "just",
        "also", "now", "here", "there", "then", "once", "if", "because",
        "until", "while", "about", "into", "through", "during", "before",
        "after", "above", "below", "between", "under", "again", "further",
        "any", "up", "down", "out", "off", "over", "under", "again", "once",
        "going", "gonna", "like", "okay", "ok", "yeah", "yes", "no", "um",
        "uh", "ah", "oh", "well", "right", "actually", "basically", "really",
        "just", "thing", "things", "something", "anything", "everything",
    };

    /// <summary>Fired when entries change (for reactive UI updates).</summary>
    public event Action? EntriesChanged;

    public HistoryDatabase()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(DbPath)!);
        EnsureSchema();
    }

    private SqliteConnection CreateConnection()
    {
        var conn = new SqliteConnection($"Data Source={DbPath}");
        conn.Open();
        return conn;
    }

    private void EnsureSchema()
    {
        using var conn = CreateConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                mode TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                word_count INTEGER NOT NULL,
                duration_seconds REAL,
                wpm INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON entries(timestamp DESC);
            """;
        cmd.ExecuteNonQuery();
    }

    public void AddEntry(string text, string mode, double? durationSeconds = null)
    {
        var wordCount = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        int? wpm = null;
        if (durationSeconds.HasValue && durationSeconds > 0)
        {
            var minutes = durationSeconds.Value / 60.0;
            wpm = minutes > 0 ? (int)Math.Round(wordCount / minutes) : null;
        }

        // Save asynchronously to not block pasting
        Task.Run(() =>
        {
            try
            {
                using var conn = CreateConnection();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = """
                    INSERT INTO entries (text, mode, timestamp, word_count, duration_seconds, wpm)
                    VALUES (@text, @mode, @timestamp, @wordCount, @duration, @wpm)
                    """;
                cmd.Parameters.AddWithValue("@text", text);
                cmd.Parameters.AddWithValue("@mode", mode);
                cmd.Parameters.AddWithValue("@timestamp", DateTime.Now.ToString("o"));
                cmd.Parameters.AddWithValue("@wordCount", wordCount);
                cmd.Parameters.AddWithValue("@duration", (object?)durationSeconds ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@wpm", (object?)wpm ?? DBNull.Value);
                cmd.ExecuteNonQuery();

                Console.WriteLine($"[HISTORY] Saved entry, mode={mode}, words={wordCount}");
                EntriesChanged?.Invoke();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HISTORY] Error saving: {ex.Message}");
            }
        });
    }

    public List<HistoryEntry> GetEntries(int? limit = null, string? mode = null)
    {
        using var conn = CreateConnection();
        using var cmd = conn.CreateCommand();

        var sql = "SELECT * FROM entries";
        var conditions = new List<string>();

        if (mode != null && mode != "all")
        {
            conditions.Add("mode = @mode");
            cmd.Parameters.AddWithValue("@mode", mode);
        }

        if (conditions.Count > 0)
            sql += " WHERE " + string.Join(" AND ", conditions);

        sql += " ORDER BY timestamp DESC";

        if (limit.HasValue)
        {
            sql += " LIMIT @limit";
            cmd.Parameters.AddWithValue("@limit", limit.Value);
        }

        cmd.CommandText = sql;

        var entries = new List<HistoryEntry>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            entries.Add(new HistoryEntry
            {
                Id = reader.GetInt64(0),
                Text = reader.GetString(1),
                Mode = reader.GetString(2),
                Timestamp = reader.GetString(3),
                WordCount = reader.GetInt32(4),
                DurationSeconds = reader.IsDBNull(5) ? null : reader.GetDouble(5),
                Wpm = reader.IsDBNull(6) ? null : reader.GetInt32(6),
            });
        }

        return entries;
    }

    public (int TotalSessions, int TotalWords, int AvgWpm, double TimeSavedMinutes) GetStatistics(string? mode = null)
    {
        using var conn = CreateConnection();

        var whereClause = mode != null && mode != "all" ? "WHERE mode = @mode" : "";

        using var cmd = conn.CreateCommand();
        cmd.CommandText = $"""
            SELECT
                COUNT(*) as total_sessions,
                COALESCE(SUM(word_count), 0) as total_words,
                COALESCE(SUM(duration_seconds), 0) as total_duration
            FROM entries {whereClause}
            """;
        if (mode != null && mode != "all")
            cmd.Parameters.AddWithValue("@mode", mode);

        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return (0, 0, 0, 0);

        int totalSessions = reader.GetInt32(0);
        int totalWords = (int)reader.GetInt64(1);
        double totalDuration = reader.GetDouble(2);

        if (totalSessions == 0) return (0, 0, 0, 0);

        // Average WPM
        using var wpmCmd = conn.CreateCommand();
        wpmCmd.CommandText = $"SELECT AVG(wpm) FROM entries WHERE wpm IS NOT NULL {(whereClause.Length > 0 ? "AND mode = @mode" : "")}";
        if (mode != null && mode != "all")
            wpmCmd.Parameters.AddWithValue("@mode", mode);

        var avgWpmObj = wpmCmd.ExecuteScalar();
        int avgWpm = avgWpmObj is double d ? (int)Math.Round(d) : 0;

        // Time saved
        double typingWpm = 40;
        double timeToType = totalWords / typingWpm;
        double timeDictating = totalDuration / 60.0;
        double timeSaved = Math.Max(0, timeToType - timeDictating);

        return (totalSessions, totalWords, avgWpm, Math.Round(timeSaved, 1));
    }

    public List<(string Word, int Count)> GetCommonWords(string? mode = null, int top = 10)
    {
        var entries = GetEntries(mode: mode);
        var wordCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in entries)
        {
            var words = entry.Text.ToLowerInvariant()
                .Split(new[] { ' ', '.', ',', '!', '?', ';', ':', '\'', '"', '(', ')', '[', ']', '{', '}' },
                    StringSplitOptions.RemoveEmptyEntries)
                .Where(w => w.Length > 2 && !Stopwords.Contains(w));

            foreach (var word in words)
            {
                wordCounts[word] = wordCounts.GetValueOrDefault(word) + 1;
            }
        }

        return wordCounts
            .OrderByDescending(kv => kv.Value)
            .Take(top)
            .Select(kv => (kv.Key, kv.Value))
            .ToList();
    }
}
