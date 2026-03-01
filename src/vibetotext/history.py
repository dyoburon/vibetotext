"""Transcription history storage and analytics using SQLite."""

import json
import sqlite3
import threading
from collections import Counter
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

_sentiment_analyzer = SentimentIntensityAnalyzer()


# Common English stopwords to exclude from word frequency
STOPWORDS = {
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
}


class TranscriptionHistory:
    """Manages persistent storage of transcription history using SQLite."""

    def __init__(self, path: Optional[Path] = None):
        """
        Initialize history storage.

        Args:
            path: Path to history database file. Defaults to ~/.vibetotext/history.db
        """
        if path is None:
            path = Path.home() / ".vibetotext" / "history.db"
        self.path = Path(path)
        self._ensure_storage()
        self._migrate_from_json()

    def _ensure_storage(self):
        """Create storage directory and database if they don't exist."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    text TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    word_count INTEGER NOT NULL,
                    duration_seconds REAL,
                    wpm INTEGER,
                    sentiment REAL
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_timestamp ON entries(timestamp DESC)
            """)
            # Add sentiment column if missing (existing databases)
            try:
                conn.execute("ALTER TABLE entries ADD COLUMN sentiment REAL")
            except sqlite3.OperationalError:
                pass  # Column already exists
            conn.commit()
            self._backfill_sentiment(conn)

    def _backfill_sentiment(self, conn):
        """Score any entries missing sentiment with VADER."""
        rows = conn.execute(
            "SELECT id, text FROM entries WHERE sentiment IS NULL"
        ).fetchall()
        if not rows:
            return
        print(f"[HISTORY] Backfilling VADER sentiment for {len(rows)} entries...")
        for row in rows:
            score = _sentiment_analyzer.polarity_scores(row["text"])["compound"]
            conn.execute(
                "UPDATE entries SET sentiment = ? WHERE id = ?",
                (score, row["id"]),
            )
        conn.commit()
        print(f"[HISTORY] Sentiment backfill complete.")

    def _migrate_from_json(self):
        """Migrate existing JSON history to SQLite (one-time operation)."""
        json_path = self.path.with_suffix(".json")
        if not json_path.exists():
            return

        # Check if we already have entries (don't migrate twice)
        with self._get_connection() as conn:
            count = conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
            if count > 0:
                return

        try:
            with open(json_path, "r") as f:
                data = json.load(f)

            entries = data.get("entries", [])
            if not entries:
                return

            print(f"[HISTORY] Migrating {len(entries)} entries from JSON to SQLite...")

            with self._get_connection() as conn:
                for entry in entries:
                    conn.execute("""
                        INSERT INTO entries (text, mode, timestamp, word_count, duration_seconds, wpm)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, (
                        entry.get("text", ""),
                        entry.get("mode", "transcribe"),
                        entry.get("timestamp", datetime.now().isoformat()),
                        entry.get("word_count", len(entry.get("text", "").split())),
                        entry.get("duration_seconds"),
                        entry.get("wpm"),
                    ))
                conn.commit()

            # Rename old JSON file as backup
            backup_path = json_path.with_suffix(".json.migrated")
            json_path.rename(backup_path)
            print(f"[HISTORY] Migration complete. Old file renamed to {backup_path}")

        except Exception as e:
            print(f"[HISTORY] Migration failed: {e}")

    @contextmanager
    def _get_connection(self):
        """Get a database connection with proper settings."""
        conn = sqlite3.connect(
            str(self.path),
            timeout=30.0,  # Wait up to 30 seconds for locks
            isolation_level="IMMEDIATE",  # Acquire lock immediately on write
        )
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def add_entry(
        self,
        text: str,
        mode: str,
        timestamp: Optional[datetime] = None,
        duration_seconds: Optional[float] = None,
    ):
        """
        Add a transcription entry to history (non-blocking).

        Args:
            text: Transcribed text
            mode: Mode used (transcribe, greppy, cleanup, plan)
            timestamp: When transcription occurred (defaults to now)
            duration_seconds: Audio recording duration in seconds
        """
        if timestamp is None:
            timestamp = datetime.now()

        word_count = len(text.split())

        # Calculate WPM if we have duration
        wpm = None
        if duration_seconds and duration_seconds > 0:
            minutes = duration_seconds / 60
            wpm = round(word_count / minutes) if minutes > 0 else None

        # VADER sentiment score (-1 to 1)
        sentiment = _sentiment_analyzer.polarity_scores(text)["compound"]

        # Save in background thread to not block pasting
        def save_async():
            try:
                with self._get_connection() as conn:
                    conn.execute("""
                        INSERT INTO entries (text, mode, timestamp, word_count, duration_seconds, wpm, sentiment)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (text, mode, timestamp.isoformat(), word_count, duration_seconds, wpm, sentiment))
                    conn.commit()

                    count = conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
                    print(f"[HISTORY] Saved entry to {self.path}, total entries: {count}")
            except Exception as e:
                print(f"[HISTORY] Error saving: {e}")

        thread = threading.Thread(target=save_async, daemon=True)
        thread.start()

    def get_entries(self, limit: Optional[int] = None) -> List[dict]:
        """
        Get transcription entries, newest first.

        Args:
            limit: Maximum number of entries to return

        Returns:
            List of entry dicts with text, mode, timestamp, word_count
        """
        with self._get_connection() as conn:
            if limit:
                rows = conn.execute(
                    "SELECT * FROM entries ORDER BY timestamp DESC LIMIT ?",
                    (limit,)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM entries ORDER BY timestamp DESC"
                ).fetchall()

            return [dict(row) for row in rows]

    def get_statistics(self) -> dict:
        """
        Compute statistics from all history.

        Returns:
            Dict with total_words, total_sessions, common_words, avg_wpm, time_saved_minutes
        """
        with self._get_connection() as conn:
            # Get aggregate stats
            stats = conn.execute("""
                SELECT
                    COUNT(*) as total_sessions,
                    COALESCE(SUM(word_count), 0) as total_words,
                    COALESCE(SUM(duration_seconds), 0) as total_duration
                FROM entries
            """).fetchone()

            total_sessions = stats["total_sessions"]
            total_words = stats["total_words"]
            total_duration = stats["total_duration"]

            if total_sessions == 0:
                return {
                    "total_words": 0,
                    "total_sessions": 0,
                    "common_words": [],
                    "longest_words": [],
                    "avg_wpm": 0,
                    "time_saved_minutes": 0,
                    "total_duration_seconds": 0,
                }

            # Calculate average WPM
            wpm_stats = conn.execute("""
                SELECT AVG(wpm) as avg_wpm FROM entries WHERE wpm IS NOT NULL
            """).fetchone()
            avg_wpm = round(wpm_stats["avg_wpm"]) if wpm_stats["avg_wpm"] else 0

            # Time saved calculation
            typing_wpm = 40
            words_with_duration = conn.execute("""
                SELECT COALESCE(SUM(word_count), 0) as words
                FROM entries WHERE duration_seconds IS NOT NULL
            """).fetchone()["words"]

            time_to_type_minutes = words_with_duration / typing_wpm
            time_dictating_minutes = total_duration / 60
            time_saved_minutes = max(0, time_to_type_minutes - time_dictating_minutes)

            # Get all text for word frequency analysis
            rows = conn.execute("SELECT text FROM entries").fetchall()

            all_words = []
            for row in rows:
                words = row["text"].lower().split()
                words = [w.strip(".,!?;:'\"()[]{}") for w in words]
                words = [w for w in words if w and len(w) > 2 and w not in STOPWORDS]
                all_words.extend(words)

            word_counts = Counter(all_words)
            common_words = word_counts.most_common(20)

            # Longest unique words used, sorted by length descending
            unique_words = set(all_words)
            longest_words = sorted(unique_words, key=len, reverse=True)[:20]

            return {
                "total_words": total_words,
                "total_sessions": total_sessions,
                "common_words": common_words,
                "longest_words": longest_words,
                "avg_wpm": avg_wpm,
                "time_saved_minutes": round(time_saved_minutes, 1),
                "total_duration_seconds": round(total_duration, 1),
            }

    def clear(self):
        """Clear all history."""
        with self._get_connection() as conn:
            conn.execute("DELETE FROM entries")
            conn.commit()
