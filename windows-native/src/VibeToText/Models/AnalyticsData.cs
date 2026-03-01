namespace VibeToText.Models;

public class AnalyticsData
{
    // Activity
    public int[,] ActivityMatrix { get; set; } = new int[7, 24]; // [dayOfWeek, hour]

    // Daily aggregates
    public List<DailyData> DailyArray { get; set; } = new();
    public Dictionary<string, DailyData> DailyDataMap { get; set; } = new();

    // Mode counts
    public Dictionary<string, int> ModeCounts { get; set; } = new()
    {
        ["transcribe"] = 0,
        ["greppy"] = 0,
        ["cleanup"] = 0,
        ["plan"] = 0
    };

    // Streaks & Records
    public int CurrentStreak { get; set; }
    public int LongestStreak { get; set; }
    public int MaxWpm { get; set; }
    public int MaxWordsInDay { get; set; }
    public double LongestSession { get; set; }

    // Speech patterns
    public Dictionary<string, int> FillerCounts { get; set; } = new();
    public List<(string Phrase, int Count)> TopBigrams { get; set; } = new();
    public List<(string Phrase, int Count)> TopTrigrams { get; set; } = new();

    // Vocabulary
    public int UniqueWords { get; set; }
    public int TotalWords { get; set; }
    public Dictionary<string, int> WordFrequency { get; set; } = new();
    public List<string> NewWordsThisWeek { get; set; } = new();
    public List<VocabGrowthPoint> VocabGrowthArray { get; set; } = new();
    public List<(string Word, int Count)> RareWords { get; set; } = new();
    public double ReadingLevel { get; set; }
    public WordLengthDist WordLengthDist { get; set; } = new();

    // WPM
    public int?[] AvgWpmByHour { get; set; } = new int?[24];
    public List<double> SessionDurations { get; set; } = new();

    // Sentiment
    public List<SentimentPoint> SentimentArray { get; set; } = new();

    // Week comparison
    public WeekData ThisWeekData { get; set; } = new();
    public WeekData LastWeekData { get; set; } = new();

    // Today
    public DailyData TodayData { get; set; } = new();
    public int ThisWeekWords { get; set; }
}

public class DailyData
{
    public string Date { get; set; } = string.Empty;
    public int Words { get; set; }
    public double Duration { get; set; }
    public int WpmSum { get; set; }
    public int WpmCount { get; set; }
    public int Entries { get; set; }
    public double TimeSavedToday { get; set; }
    public double CumulativeTimeSaved { get; set; }
    public int? AvgWpm => WpmCount > 0 ? (int)Math.Round((double)WpmSum / WpmCount) : null;
}

public class VocabGrowthPoint
{
    public string Date { get; set; } = string.Empty;
    public int Count { get; set; }
}

public class SentimentPoint
{
    public string Date { get; set; } = string.Empty;
    public double Score { get; set; }
    public int Positive { get; set; }
    public int Negative { get; set; }
}

public class WeekData
{
    public int Words { get; set; }
    public int Sessions { get; set; }
    public double Duration { get; set; }
}

public class WordLengthDist
{
    public int Short { get; set; } // 1-3 chars
    public int Medium { get; set; } // 4-6 chars
    public int Long { get; set; } // 7+ chars
}
