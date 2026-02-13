import Foundation

/// Ports analytics.js processData() — crunches history entries into chart-ready data.
/// Phase 5 will add all the computed properties. This is the data model stub.
struct AnalyticsData {
    // Activity
    var activityMatrix: [[Int]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var dailyArray: [DailyAggregate] = []

    // Mode counts
    var modeCounts: [String: Int] = ["transcribe": 0, "greppy": 0, "cleanup": 0, "plan": 0]

    // Streaks
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    // Records
    var maxWpm: Int = 0
    var maxWordsInDay: Int = 0
    var longestSession: Double = 0

    // Goals
    var todayWords: Int = 0
    var todaySessions: Int = 0
    var todayDuration: Double = 0
    var thisWeekWords: Int = 0

    // WPM by hour
    var avgWpmByHour: [Int?] = Array(repeating: nil, count: 24)

    // Session durations
    var sessionDurations: [Double] = []

    // Filler words
    var fillerCounts: [String: Int] = [:]

    // Vocabulary
    var uniqueWordCount: Int = 0
    var totalWordCount: Int = 0
    var newWordsThisWeek: [String] = []
    var vocabGrowth: [(date: String, count: Int)] = []
    var rareWords: [(word: String, count: Int)] = []
    var readingLevel: Double = 0
    var wordLengthDist: (short: Int, medium: Int, long: Int) = (0, 0, 0)

    // Phrases
    var topBigrams: [(phrase: String, count: Int)] = []
    var topTrigrams: [(phrase: String, count: Int)] = []

    // Word cloud
    var wordFrequency: [String: Int] = [:]

    // Sentiment
    var sentimentArray: [(date: String, score: Double, positive: Int, negative: Int)] = []

    // Period comparison
    var thisWeekData: PeriodData = PeriodData()
    var lastWeekData: PeriodData = PeriodData()

    struct DailyAggregate {
        var date: String
        var words: Int = 0
        var duration: Double = 0
        var wpmSum: Int = 0
        var wpmCount: Int = 0
        var entries: Int = 0
        var timeSavedToday: Double = 0
        var cumulativeTimeSaved: Double = 0
        var avgWpm: Int? { wpmCount > 0 ? wpmSum / wpmCount : nil }
        var dateObj: Date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: date) ?? Date()
        }
    }

    struct PeriodData {
        var words: Int = 0
        var sessions: Int = 0
        var duration: Double = 0
    }
}

// MARK: - Processor

enum AnalyticsProcessor {

    static let fillerWords = ["um", "uh", "like", "basically", "actually", "literally", "honestly", "anyway", "so", "right"]

    static let positiveWords: Set<String> = [
        "good", "great", "awesome", "excellent", "amazing", "wonderful", "fantastic", "perfect", "love", "best",
        "happy", "nice", "cool", "brilliant", "beautiful", "thanks", "thank", "helpful", "easy", "fast",
        "better", "improved", "success", "successful", "working", "works", "fixed", "solved", "done", "complete",
    ]

    static let negativeWords: Set<String> = [
        "bad", "wrong", "error", "bug", "issue", "problem", "fail", "failed", "broken", "stuck",
        "hard", "difficult", "annoying", "frustrating", "slow", "ugly", "terrible", "awful", "hate", "worst",
        "confused", "confusing", "impossible", "never", "crash", "crashed", "missing", "lost", "stupid", "mess",
    ]

    static let commonWords: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with",
        "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if",
        "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time", "no", "just", "him",
        "know", "take", "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
        "than", "then", "now", "look", "only", "come", "its", "over", "think", "also", "back", "after", "use",
        "two", "how", "our", "work", "first", "well", "way", "even", "new", "want", "because", "any", "these",
        "give", "day", "most", "us", "is", "are", "was", "were", "been", "being", "has", "had", "did", "does",
        "done", "doing", "made", "got", "went", "going", "came", "coming", "took", "taking", "said", "saying",
        "put", "thing", "things", "very", "much", "more", "many", "still", "such", "here", "those", "own",
        "same", "right", "too", "old", "before", "last", "never", "where", "why", "while", "should", "must",
        "may", "might", "let", "through", "down", "off", "between", "under", "long", "little", "great", "need",
        "code", "function", "file", "data", "type", "class", "method", "value", "name", "string", "array",
        "object", "error", "test", "build", "run", "create", "add", "update", "delete", "check", "fix",
        "change", "move", "copy", "save", "load", "open", "close", "read", "write", "send", "receive",
        "input", "output", "return", "really", "actually", "probably", "maybe", "perhaps", "okay", "yeah",
        "yes", "oh", "gonna", "wanna", "gotta",
    ]

    static let dailyWordGoal = 500
    static let weeklyWordGoal = 2500

    /// Process entries into chart-ready AnalyticsData.
    /// This is the Swift port of analytics.js processData().
    static func process(_ entries: [HistoryEntry]) -> AnalyticsData {
        var data = AnalyticsData()
        guard !entries.isEmpty else { return data }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayKey = dateKey(today)

        // Week boundaries
        let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek)!

        var dailyData: [String: AnalyticsData.DailyAggregate] = [:]
        var daysUsed: Set<String> = []
        var allWords: [String] = []
        var wordFrequency: [String: Int] = [:]
        var fillerCounts: [String: Int] = [:]
        fillerWords.forEach { fillerCounts[$0] = 0 }
        var bigrams: [String: Int] = [:]
        var trigrams: [String: Int] = [:]
        var sentimentByDay: [String: (positive: Int, negative: Int, total: Int)] = [:]
        var wordsBeforeThisWeek: Set<String> = []
        var wordsThisWeek: Set<String> = []
        var cumulativeVocab: Set<String> = []
        var vocabGrowthByDay: [String: Int] = [:]
        var wpmByHour: [(sum: Int, count: Int)] = Array(repeating: (0, 0), count: 24)

        // Sort for vocab growth computation
        let sortedEntries = entries.sorted { $0.date < $1.date }

        for entry in entries {
            let date = entry.date
            let dayOfWeek = calendar.component(.weekday, from: date) - 1 // 0=Sun
            let hour = calendar.component(.hour, from: date)
            let dk = dateKey(date)

            daysUsed.insert(dk)
            data.activityMatrix[dayOfWeek][hour] += 1

            // WPM by hour
            if let wpm = entry.wpm {
                wpmByHour[hour].sum += wpm
                wpmByHour[hour].count += 1
                data.maxWpm = max(data.maxWpm, wpm)
            }

            // Session duration
            if let dur = entry.durationSeconds {
                data.sessionDurations.append(dur)
                data.longestSession = max(data.longestSession, dur)
            }

            // Daily aggregate
            if dailyData[dk] == nil {
                dailyData[dk] = AnalyticsData.DailyAggregate(date: dk)
            }
            dailyData[dk]!.words += entry.wordCount
            dailyData[dk]!.duration += entry.durationSeconds ?? 0
            dailyData[dk]!.entries += 1
            if let wpm = entry.wpm {
                dailyData[dk]!.wpmSum += wpm
                dailyData[dk]!.wpmCount += 1
            }

            // Mode counts
            data.modeCounts[entry.mode, default: 0] += 1

            // Text analysis
            let words = entry.text.lowercased()
                .replacingOccurrences(of: "[.,!?;:'\"()\\[\\]{}]", with: "", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }

            allWords.append(contentsOf: words)
            for w in words {
                wordFrequency[w, default: 0] += 1
                if fillerCounts.keys.contains(w) {
                    fillerCounts[w, default: 0] += 1
                }
            }

            // N-grams
            for i in 0..<max(0, words.count - 1) {
                let bi = "\(words[i]) \(words[i + 1])"
                bigrams[bi, default: 0] += 1
            }
            for i in 0..<max(0, words.count - 2) {
                let tri = "\(words[i]) \(words[i + 1]) \(words[i + 2])"
                trigrams[tri, default: 0] += 1
            }

            // Sentiment
            var pos = 0, neg = 0
            for w in words {
                if positiveWords.contains(w) { pos += 1 }
                if negativeWords.contains(w) { neg += 1 }
            }
            var s = sentimentByDay[dk] ?? (0, 0, 0)
            s.positive += pos
            s.negative += neg
            s.total += words.count
            sentimentByDay[dk] = s

            // New words tracking
            let longWords = words.filter { $0.count > 2 }
            if date < startOfThisWeek {
                longWords.forEach { wordsBeforeThisWeek.insert($0) }
            } else {
                longWords.forEach { wordsThisWeek.insert($0) }
            }

            // Period comparison
            if date >= startOfThisWeek {
                data.thisWeekData.words += entry.wordCount
                data.thisWeekData.sessions += 1
                data.thisWeekData.duration += entry.durationSeconds ?? 0
            } else if date >= startOfLastWeek {
                data.lastWeekData.words += entry.wordCount
                data.lastWeekData.sessions += 1
                data.lastWeekData.duration += entry.durationSeconds ?? 0
            }
        }

        // Vocab growth (must iterate sorted)
        for entry in sortedEntries {
            let dk = dateKey(entry.date)
            let words = entry.text.lowercased()
                .replacingOccurrences(of: "[.,!?;:'\"()\\[\\]{}]", with: "", options: .regularExpression)
                .split(separator: " ")
                .filter { $0.count > 2 }
                .map(String.init)
            words.forEach { cumulativeVocab.insert($0) }
            vocabGrowthByDay[dk] = cumulativeVocab.count
        }

        // Build daily array
        var dailyArray = dailyData.values.sorted { $0.date < $1.date }
        var cumTimeSaved: Double = 0
        for i in 0..<dailyArray.count {
            let typingTime = Double(dailyArray[i].words) / 40.0
            let dictTime = dailyArray[i].duration / 60.0
            dailyArray[i].timeSavedToday = max(0, typingTime - dictTime)
            cumTimeSaved += dailyArray[i].timeSavedToday
            dailyArray[i].cumulativeTimeSaved = cumTimeSaved
            data.maxWordsInDay = max(data.maxWordsInDay, dailyArray[i].words)
        }
        data.dailyArray = dailyArray

        // Streaks
        let sortedDays = daysUsed.sorted()
        var tempStreak = 0
        for i in 0..<sortedDays.count {
            if i == 0 {
                tempStreak = 1
            } else {
                let prev = dateFromKey(sortedDays[i - 1])
                let curr = dateFromKey(sortedDays[i])
                if let prev, let curr, calendar.dateComponents([.day], from: prev, to: curr).day == 1 {
                    tempStreak += 1
                } else {
                    tempStreak = 1
                }
            }
            data.longestStreak = max(data.longestStreak, tempStreak)
        }

        let yesterdayKey = dateKey(calendar.date(byAdding: .day, value: -1, to: Date())!)
        if daysUsed.contains(todayKey) || daysUsed.contains(yesterdayKey) {
            data.currentStreak = 1
            let startDay = daysUsed.contains(todayKey) ? todayKey : yesterdayKey
            var checkDate = calendar.date(byAdding: .day, value: -1, to: dateFromKey(startDay)!)!
            while daysUsed.contains(dateKey(checkDate)) {
                data.currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            }
        }

        // Today stats
        let todayAgg = dailyData[todayKey]
        data.todayWords = todayAgg?.words ?? 0
        data.todaySessions = todayAgg?.entries ?? 0
        data.todayDuration = todayAgg?.duration ?? 0
        data.thisWeekWords = data.thisWeekData.words

        // WPM by hour
        data.avgWpmByHour = wpmByHour.map { $0.count > 0 ? $0.sum / $0.count : nil }

        // Filler counts
        data.fillerCounts = fillerCounts

        // Vocabulary
        data.uniqueWordCount = Set(allWords.filter { $0.count > 2 }).count
        data.totalWordCount = allWords.count
        data.newWordsThisWeek = wordsThisWeek.filter { !wordsBeforeThisWeek.contains($0) }.sorted()
        data.vocabGrowth = vocabGrowthByDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

        // Rare words
        var rareWordCounts: [String: Int] = [:]
        for w in allWords where w.count > 3 && !commonWords.contains(w) {
            rareWordCounts[w, default: 0] += 1
        }
        data.rareWords = rareWordCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { ($0.key, $0.value) }

        // Word length distribution
        var short = 0, medium = 0, long = 0
        for w in allWords {
            if w.count <= 3 { short += 1 }
            else if w.count <= 6 { medium += 1 }
            else { long += 1 }
        }
        data.wordLengthDist = (short, medium, long)

        // Top n-grams
        let stopNGram: Set<String> = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "i", "you", "it", "is", "that", "this"]
        data.topBigrams = bigrams
            .filter { entry in entry.value >= 2 && !entry.key.split(separator: " ").allSatisfy { stopNGram.contains(String($0)) } }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }
        data.topTrigrams = trigrams
            .filter { entry in entry.value >= 2 && !entry.key.split(separator: " ").allSatisfy { stopNGram.contains(String($0)) } }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        // Word frequency
        data.wordFrequency = wordFrequency

        // Reading level (Flesch-Kincaid)
        var totalSentences = 0
        var totalSyllables = 0
        for entry in entries {
            let sentences = max(1, entry.text.split(omittingEmptySubsequences: true, whereSeparator: { ".!?".contains($0) }).count)
            totalSentences += sentences
            let words = entry.text.lowercased()
                .replacingOccurrences(of: "[.,!?;:'\"()\\[\\]{}]", with: "", options: .regularExpression)
                .split(separator: " ")
                .filter { !$0.isEmpty }
            for w in words {
                totalSyllables += countSyllables(String(w))
            }
        }
        let avgWordsPerSentence = totalSentences > 0 ? Double(allWords.count) / Double(totalSentences) : 0
        let avgSyllablesPerWord = allWords.count > 0 ? Double(totalSyllables) / Double(allWords.count) : 0
        data.readingLevel = allWords.count > 0
            ? max(1, min(18, 0.39 * avgWordsPerSentence + 11.8 * avgSyllablesPerWord - 15.59))
            : 0

        // Sentiment array
        data.sentimentArray = sentimentByDay
            .map { (date: $0.key,
                     score: $0.value.total > 0 ? Double($0.value.positive - $0.value.negative) / sqrt(Double($0.value.total)) : 0,
                     positive: $0.value.positive,
                     negative: $0.value.negative) }
            .sorted { $0.date < $1.date }

        return data
    }

    // MARK: - Helpers

    private static func dateKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private static func dateFromKey(_ key: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: key)
    }

    private static func countSyllables(_ word: String) -> Int {
        var w = word.lowercased()
        if w.count <= 3 { return 1 }
        // Remove silent endings
        if w.hasSuffix("es") || w.hasSuffix("ed") {
            w = String(w.dropLast(2))
        } else if w.hasSuffix("e") && !w.hasSuffix("le") {
            w = String(w.dropLast())
        }
        if w.hasPrefix("y") { w = String(w.dropFirst()) }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevWasVowel = false
        for ch in w {
            let isVowel = vowels.contains(ch)
            if isVowel && !prevWasVowel { count += 1 }
            prevWasVowel = isVowel
        }
        return max(1, count)
    }
}
