namespace VibeToText.Models;

public class HistoryEntry
{
    public long Id { get; set; }
    public string Text { get; set; } = string.Empty;
    public string Mode { get; set; } = "transcribe";
    public string Timestamp { get; set; } = string.Empty;
    public int WordCount { get; set; }
    public double? DurationSeconds { get; set; }
    public int? Wpm { get; set; }

    public DateTime Date => DateTime.TryParse(Timestamp, out var dt) ? dt : DateTime.MinValue;

    public string RelativeTime
    {
        get
        {
            var now = DateTime.Now;
            var diff = now - Date;

            if (diff.TotalMinutes < 1) return "Just now";
            if (diff.TotalMinutes < 60) return $"{(int)diff.TotalMinutes}m ago";
            if (diff.TotalHours < 24) return $"{(int)diff.TotalHours}h ago";
            if (diff.TotalDays < 7) return $"{(int)diff.TotalDays}d ago";

            return Date.ToString("MMM d, h:mm tt");
        }
    }

    public string StatsText
    {
        get
        {
            var parts = new List<string>();
            if (DurationSeconds.HasValue)
                parts.Add($"{DurationSeconds.Value:F1}s");
            if (Wpm.HasValue)
                parts.Add($"{Wpm.Value} WPM");
            parts.Add($"{WordCount} words");
            return string.Join(" \u00B7 ", parts);
        }
    }
}
