using System.Text.RegularExpressions;
using VibeToText.Models;

namespace VibeToText.Data;

/// <summary>
/// Port of analytics.js processData() - computes all analytics from history entries.
/// </summary>
public static partial class AnalyticsProcessor
{
    private static readonly string[] FillerWords = { "um", "uh", "like", "basically", "actually", "literally", "honestly", "anyway", "so", "right" };

    private static readonly HashSet<string> PositiveWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "good", "great", "awesome", "excellent", "amazing", "wonderful", "fantastic", "perfect", "love", "best",
        "happy", "nice", "cool", "brilliant", "beautiful", "thanks", "thank", "helpful", "easy", "fast",
        "better", "improved", "success", "successful", "working", "works", "fixed", "solved", "done", "complete"
    };

    private static readonly HashSet<string> NegativeWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "bad", "wrong", "error", "bug", "issue", "problem", "fail", "failed", "broken", "stuck",
        "hard", "difficult", "annoying", "frustrating", "slow", "ugly", "terrible", "awful", "hate", "worst",
        "confused", "confusing", "impossible", "never", "crash", "crashed", "missing", "lost", "stupid", "mess"
    };

    private static readonly HashSet<string> CommonEnglishWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "the","be","to","of","and","a","in","that","have","i","it","for","not","on","with","he","as","you","do","at",
        "this","but","his","by","from","they","we","say","her","she","or","an","will","my","one","all","would","there","their","what",
        "so","up","out","if","about","who","get","which","go","me","when","make","can","like","time","no","just","him","know","take",
        "people","into","year","your","good","some","could","them","see","other","than","then","now","look","only","come","its","over","think","also",
        "back","after","use","two","how","our","work","first","well","way","even","new","want","because","any","these","give","day","most","us",
        "is","are","was","were","been","being","has","had","did","does","done","doing","made","got","went","going","came","coming","took","taking",
        "said","saying","put","thing","things","very","much","more","many","still","such","here","those","own","same","right","too","old","before",
        "last","never","where","why","while","should","must","may","might","let","through","down","off","between","under","long","little","great","need",
        "each","every","both","few","might","shall","part","place","since","around","hand","high","always","sure","something","help","keep","seem",
        "call","point","start","find","show","turn","end","ask","try","tell","feel","become","leave","mean","change","move","play","run","set","big",
        "small","large","another","different","kind","again","home","world","house","life","school","night","city","head","side","water","room","mother",
        "really","actually","probably","maybe","perhaps","okay","yeah","yes","no","oh","well","just","like","know","think","gonna","wanna","gotta",
        "code","function","file","data","type","class","method","value","name","string","array","object","error","test","build","run","create","add",
        "update","delete","check","fix","change","move","copy","save","load","open","close","read","write","send","receive","input","output","return"
    };

    private static readonly HashSet<string> Stopwords = new(StringComparer.OrdinalIgnoreCase)
    {
        "the","a","an","and","or","but","in","on","at","to","for","of","with","i","you","it","is","that","this",
        "by","from","they","we","say","her","she","he","as","do","my","me","no","not","so","up","out","if","about"
    };

    public const int DailyWordGoal = 500;
    public const int WeeklyWordGoal = 2500;

    public static AnalyticsData Process(List<HistoryEntry> entries)
    {
        var data = new AnalyticsData();

        var dailyDataMap = new Dictionary<string, DailyData>();
        var wpmByHour = new (long Sum, int Count)[24];
        var allWords = new List<string>();
        var wordFrequency = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var fillerCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var fw in FillerWords) fillerCounts[fw] = 0;

        var bigrams = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var trigrams = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var daysUsed = new HashSet<string>();
        var sentimentByDay = new Dictionary<string, (int Positive, int Negative, int Total)>();

        foreach (var entry in entries)
        {
            var date = entry.Date;
            var dayOfWeek = (int)date.DayOfWeek;
            var hour = date.Hour;
            var dateKey = date.ToString("yyyy-MM-dd");

            daysUsed.Add(dateKey);

            // Activity matrix
            data.ActivityMatrix[dayOfWeek, hour]++;

            // WPM by hour
            if (entry.Wpm.HasValue)
            {
                wpmByHour[hour].Sum += entry.Wpm.Value;
                wpmByHour[hour].Count++;
                data.MaxWpm = Math.Max(data.MaxWpm, entry.Wpm.Value);
            }

            // Session duration
            if (entry.DurationSeconds.HasValue)
            {
                data.SessionDurations.Add(entry.DurationSeconds.Value);
                data.LongestSession = Math.Max(data.LongestSession, entry.DurationSeconds.Value);
            }

            // Daily data
            if (!dailyDataMap.TryGetValue(dateKey, out var dd))
            {
                dd = new DailyData { Date = dateKey };
                dailyDataMap[dateKey] = dd;
            }
            dd.Words += entry.WordCount;
            dd.Duration += entry.DurationSeconds ?? 0;
            dd.Entries++;
            if (entry.Wpm.HasValue)
            {
                dd.WpmSum += entry.Wpm.Value;
                dd.WpmCount++;
            }

            // Mode counts
            var mode = entry.Mode;
            data.ModeCounts[mode] = data.ModeCounts.GetValueOrDefault(mode) + 1;

            // Text analysis
            var words = TokenizeWords(entry.Text);
            allWords.AddRange(words);

            foreach (var word in words)
            {
                wordFrequency[word] = wordFrequency.GetValueOrDefault(word) + 1;
                if (fillerCounts.ContainsKey(word))
                    fillerCounts[word]++;
            }

            // N-grams
            for (int i = 0; i < words.Count - 1; i++)
            {
                var bg = $"{words[i]} {words[i + 1]}";
                bigrams[bg] = bigrams.GetValueOrDefault(bg) + 1;
            }
            for (int i = 0; i < words.Count - 2; i++)
            {
                var tg = $"{words[i]} {words[i + 1]} {words[i + 2]}";
                trigrams[tg] = trigrams.GetValueOrDefault(tg) + 1;
            }

            // Sentiment
            int positive = words.Count(w => PositiveWords.Contains(w));
            int negative = words.Count(w => NegativeWords.Contains(w));
            if (!sentimentByDay.TryGetValue(dateKey, out var sv))
                sv = (0, 0, 0);
            sentimentByDay[dateKey] = (sv.Positive + positive, sv.Negative + negative, sv.Total + words.Count);
        }

        // Daily array sorted + cumulative time saved
        var dailyArray = dailyDataMap.Values.OrderBy(d => d.Date).ToList();
        double cumulativeTimeSaved = 0;
        foreach (var d in dailyArray)
        {
            double typingTime = d.Words / 40.0;
            double dictatingTime = d.Duration / 60.0;
            d.TimeSavedToday = Math.Max(0, typingTime - dictatingTime);
            cumulativeTimeSaved += d.TimeSavedToday;
            d.CumulativeTimeSaved = cumulativeTimeSaved;
            data.MaxWordsInDay = Math.Max(data.MaxWordsInDay, d.Words);
        }
        data.DailyArray = dailyArray;
        data.DailyDataMap = dailyDataMap;

        // Streaks
        CalculateStreaks(daysUsed, data);

        // WPM by hour
        for (int h = 0; h < 24; h++)
            data.AvgWpmByHour[h] = wpmByHour[h].Count > 0
                ? (int)Math.Round((double)wpmByHour[h].Sum / wpmByHour[h].Count)
                : null;

        // Top n-grams (filter boring ones)
        data.TopBigrams = bigrams
            .Where(kv => kv.Value >= 2 && !kv.Key.Split(' ').All(w => Stopwords.Contains(w)))
            .OrderByDescending(kv => kv.Value)
            .Take(10)
            .Select(kv => (kv.Key, kv.Value))
            .ToList();

        data.TopTrigrams = trigrams
            .Where(kv => kv.Value >= 2 && !kv.Key.Split(' ').All(w => Stopwords.Contains(w)))
            .OrderByDescending(kv => kv.Value)
            .Take(5)
            .Select(kv => (kv.Key, kv.Value))
            .ToList();

        // Vocabulary
        data.UniqueWords = allWords.Where(w => w.Length > 2).Distinct(StringComparer.OrdinalIgnoreCase).Count();
        data.TotalWords = allWords.Count;
        data.WordFrequency = wordFrequency;
        data.FillerCounts = fillerCounts;

        // New words this week
        var now = DateTime.Now;
        var startOfThisWeek = now.AddDays(-(int)now.DayOfWeek).Date;
        var wordsBeforeThisWeek = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var wordsThisWeek = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in entries)
        {
            var entryWords = TokenizeWords(entry.Text).Where(w => w.Length > 2);
            if (entry.Date < startOfThisWeek)
                foreach (var w in entryWords) wordsBeforeThisWeek.Add(w);
            else
                foreach (var w in entryWords) wordsThisWeek.Add(w);
        }
        data.NewWordsThisWeek = wordsThisWeek.Where(w => !wordsBeforeThisWeek.Contains(w)).ToList();

        // Vocabulary growth
        var sortedEntries = entries.OrderBy(e => e.Date).ToList();
        var cumulativeVocab = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var vocabByDay = new Dictionary<string, int>();
        foreach (var entry in sortedEntries)
        {
            var dateKey = entry.Date.ToString("yyyy-MM-dd");
            var entryWords = TokenizeWords(entry.Text).Where(w => w.Length > 2);
            foreach (var w in entryWords) cumulativeVocab.Add(w);
            vocabByDay[dateKey] = cumulativeVocab.Count;
        }
        data.VocabGrowthArray = vocabByDay
            .OrderBy(kv => kv.Key)
            .Select(kv => new VocabGrowthPoint { Date = kv.Key, Count = kv.Value })
            .ToList();

        // Rare words
        var rareWordCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var word in allWords.Where(w => w.Length > 3 && !CommonEnglishWords.Contains(w)))
            rareWordCounts[word] = rareWordCounts.GetValueOrDefault(word) + 1;
        data.RareWords = rareWordCounts
            .Where(kv => kv.Value >= 2)
            .OrderByDescending(kv => kv.Value)
            .Take(20)
            .Select(kv => (kv.Key, kv.Value))
            .ToList();

        // Reading level (Flesch-Kincaid)
        int totalSentences = 0, totalSyllables = 0;
        foreach (var entry in entries)
        {
            totalSentences += Math.Max(1, entry.Text.Split(new[] { '.', '!', '?' }, StringSplitOptions.RemoveEmptyEntries)
                .Count(s => s.Trim().Length > 0));
            var words = TokenizeWords(entry.Text);
            totalSyllables += words.Sum(CountSyllables);
        }
        double avgWordsPerSentence = totalSentences > 0 ? (double)data.TotalWords / totalSentences : 0;
        double avgSyllablesPerWord = data.TotalWords > 0 ? (double)totalSyllables / data.TotalWords : 0;
        data.ReadingLevel = data.TotalWords > 0
            ? Math.Clamp(0.39 * avgWordsPerSentence + 11.8 * avgSyllablesPerWord - 15.59, 1, 18)
            : 0;

        // Word length distribution
        foreach (var word in allWords)
        {
            if (word.Length <= 3) data.WordLengthDist.Short++;
            else if (word.Length <= 6) data.WordLengthDist.Medium++;
            else data.WordLengthDist.Long++;
        }

        // Sentiment array
        data.SentimentArray = sentimentByDay
            .OrderBy(kv => kv.Key)
            .Select(kv => new SentimentPoint
            {
                Date = kv.Key,
                Score = kv.Value.Total > 0 ? (kv.Value.Positive - kv.Value.Negative) / Math.Sqrt(kv.Value.Total) : 0,
                Positive = kv.Value.Positive,
                Negative = kv.Value.Negative,
            })
            .ToList();

        // Week comparison
        var startOfLastWeek = startOfThisWeek.AddDays(-7);
        foreach (var entry in entries)
        {
            if (entry.Date >= startOfThisWeek)
            {
                data.ThisWeekData.Words += entry.WordCount;
                data.ThisWeekData.Sessions++;
                data.ThisWeekData.Duration += entry.DurationSeconds ?? 0;
            }
            else if (entry.Date >= startOfLastWeek && entry.Date < startOfThisWeek)
            {
                data.LastWeekData.Words += entry.WordCount;
                data.LastWeekData.Sessions++;
                data.LastWeekData.Duration += entry.DurationSeconds ?? 0;
            }
        }
        data.ThisWeekWords = data.ThisWeekData.Words;

        // Today's data
        var todayKey = now.ToString("yyyy-MM-dd");
        data.TodayData = dailyDataMap.GetValueOrDefault(todayKey) ?? new DailyData { Date = todayKey };

        return data;
    }

    private static List<string> TokenizeWords(string text)
    {
        return PunctuationRegex().Replace(text.ToLowerInvariant(), "")
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(w => w.Length > 0)
            .ToList();
    }

    private static void CalculateStreaks(HashSet<string> daysUsed, AnalyticsData data)
    {
        var sortedDays = daysUsed.OrderBy(d => d).ToList();
        int longestStreak = 0, tempStreak = 0;

        for (int i = 0; i < sortedDays.Count; i++)
        {
            if (i == 0)
            {
                tempStreak = 1;
            }
            else
            {
                var prev = DateTime.Parse(sortedDays[i - 1]);
                var curr = DateTime.Parse(sortedDays[i]);
                tempStreak = (curr - prev).Days == 1 ? tempStreak + 1 : 1;
            }
            longestStreak = Math.Max(longestStreak, tempStreak);
        }
        data.LongestStreak = longestStreak;

        // Current streak
        var today = DateTime.Now.ToString("yyyy-MM-dd");
        var yesterday = DateTime.Now.AddDays(-1).ToString("yyyy-MM-dd");

        if (daysUsed.Contains(today) || daysUsed.Contains(yesterday))
        {
            data.CurrentStreak = 1;
            var startDay = daysUsed.Contains(today) ? today : yesterday;
            var checkDate = DateTime.Parse(startDay).AddDays(-1);
            while (daysUsed.Contains(checkDate.ToString("yyyy-MM-dd")))
            {
                data.CurrentStreak++;
                checkDate = checkDate.AddDays(-1);
            }
        }
    }

    private static int CountSyllables(string word)
    {
        if (word.Length <= 3) return 1;
        word = SyllableEndRegex().Replace(word, "");
        if (word.StartsWith('y')) word = word[1..];
        var matches = VowelGroupRegex().Matches(word);
        return Math.Max(1, matches.Count);
    }

    [GeneratedRegex(@"[.,!?;:'""\(\)\[\]\{\}]")]
    private static partial Regex PunctuationRegex();

    [GeneratedRegex(@"(?:[^laeiouy]es|ed|[^laeiouy]e)$")]
    private static partial Regex SyllableEndRegex();

    [GeneratedRegex(@"[aeiouy]{1,2}")]
    private static partial Regex VowelGroupRegex();
}
