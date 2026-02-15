import Foundation

struct MoodEntry: Identifiable {
    let id = UUID()
    let text: String
    let sentiment: Double
    let hoursAgo: Float
    let weight: Float // how much this entry contributed to mood
}

struct TreeData {
    let health: Float
    let streak: Int
    let streakTier: Int
    let season: Float
    let growthProgress: Float

    let healthLabel: String
    let seasonLabel: String
    let streakLabel: String
    let growthLabel: String

    // Village sentiment data
    let mood: Float          // -1.0 to +1.0
    let moodLabel: String
    let population: Int
    let recentTrend: Float   // -1.0 to +1.0

    // Mood breakdown: top positive and negative contributors
    let moodBreakdown: [MoodEntry]

    static let placeholder = TreeData(
        health: 0.85, streak: 0, streakTier: 0, season: 0.5, growthProgress: 0.0,
        healthLabel: "—", seasonLabel: "—", streakLabel: "—", growthLabel: "—",
        mood: 0.0, moodLabel: "—", population: 0, recentTrend: 0.0,
        moodBreakdown: []
    )
}

enum TreeDataCalculator {
    static func calculate(from entries: [TranscriptionEntry]) -> TreeData {
        guard !entries.isEmpty else {
            return TreeData(
                health: 0.3, streak: 0, streakTier: 0, season: 0.0, growthProgress: 0.0,
                healthLabel: "30%", seasonLabel: "Winter", streakLabel: "None", growthLabel: "0%",
                mood: 0.0, moodLabel: "Neutral", population: 0, recentTrend: 0.0,
                moodBreakdown: []
            )
        }

        let now = Date()
        let calendar = Calendar.current

        // ── Health: decay from last entry ──
        // entries are sorted DESC, so .first is most recent
        let hoursSinceLastEntry = Float(now.timeIntervalSince(entries.first!.timestamp)) / 3600.0
        let health: Float
        if hoursSinceLastEntry < 6 {
            health = 1.0
        } else if hoursSinceLastEntry < 72 {
            // Linear decay from 1.0 → 0.3 over hours 6–72
            health = 1.0 - (hoursSinceLastEntry - 6.0) / 66.0 * 0.7
        } else {
            health = 0.3
        }

        // ── Streak: consecutive days with entries ──
        let entryDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        var checkDate = calendar.startOfDay(for: now)
        var streak = 0

        // Grace: if no entries today, allow starting from yesterday
        if !entryDays.contains(checkDate) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate),
               entryDays.contains(yesterday) {
                checkDate = yesterday
            }
        }

        // Count consecutive days backward
        while entryDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        let streakTier: Int
        if streak >= 30 { streakTier = 4 }
        else if streak >= 14 { streakTier = 3 }
        else if streak >= 7 { streakTier = 2 }
        else if streak >= 3 { streakTier = 1 }
        else { streakTier = 0 }

        // ── Season: rolling 14-day activity ratio ──
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now)!
        let recentActiveDays = Set(
            entries.filter { $0.timestamp >= fourteenDaysAgo }
                .map { calendar.startOfDay(for: $0.timestamp) }
        )
        let season = min(Float(recentActiveDays.count) / 14.0, 1.0)

        // ── Growth: total entries normalized (100 entries = full growth) ──
        let growthProgress = min(Float(entries.count) / 100.0, 1.0)

        // ── Labels ──
        let healthLabel = "\(Int(health * 100))%"

        let seasonLabel: String
        if season > 0.66 { seasonLabel = "Summer" }
        else if season > 0.33 { seasonLabel = "Spring" }
        else if season > 0.15 { seasonLabel = "Autumn" }
        else { seasonLabel = "Winter" }

        let streakLabel = streak == 0 ? "None" : "\(streak) days"
        let growthLabel = "\(Int(growthProgress * 100))%"

        // ── Mood: current day only, with minimum word threshold ──
        let todayStart = calendar.startOfDay(for: now)
        let minWordsForMood = 200
        var todaySentimentSum: Float = 0
        var todaySentimentCount: Int = 0
        var todayWordCount: Int = 0
        for entry in entries {
            guard entry.timestamp >= todayStart else { continue }
            todayWordCount += entry.text.split(separator: " ").count
            guard let s = entry.sentiment else { continue }
            todaySentimentSum += Float(s)
            todaySentimentCount += 1
        }
        let mood: Float
        if todayWordCount < minWordsForMood || todaySentimentCount == 0 {
            mood = 0.0 // neutral until enough words spoken today
        } else {
            mood = max(-1.0, min(1.0, todaySentimentSum / Float(todaySentimentCount)))
        }

        // ── Recent trend: last 24h avg vs previous 24h avg ──
        let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let recentScores = entries.filter { $0.timestamp >= oneDayAgo }.compactMap { $0.sentiment }
        let olderScores = entries.filter { $0.timestamp >= twoDaysAgo && $0.timestamp < oneDayAgo }.compactMap { $0.sentiment }
        let recentAvg = recentScores.isEmpty ? 0.0 : Float(recentScores.reduce(0, +)) / Float(recentScores.count)
        let olderAvg = olderScores.isEmpty ? recentAvg : Float(olderScores.reduce(0, +)) / Float(olderScores.count)
        let recentTrend = max(-1.0, min(1.0, (recentAvg - olderAvg) * 2.0))

        // ── Population: based on entry count scaled by mood ──
        let basePop = min(entries.count / 5, 50)
        let moodMultiplier = 0.3 + 0.7 * Double((mood + 1.0) / 2.0)
        let population = max(1, Int(Double(basePop) * moodMultiplier))

        // ── Mood label ──
        let moodLabel: String
        if mood > 0.5 { moodLabel = "Radiant" }
        else if mood > 0.15 { moodLabel = "Warm" }
        else if mood > -0.15 { moodLabel = "Neutral" }
        else if mood > -0.5 { moodLabel = "Cold" }
        else { moodLabel = "Hostile" }

        // ── Mood breakdown: today's top positive & negative contributors ──
        var moodEntries: [MoodEntry] = []
        for entry in entries {
            guard entry.timestamp >= todayStart else { continue }
            guard let s = entry.sentiment else { continue }
            let hoursAgo = Float(now.timeIntervalSince(entry.timestamp)) / 3600.0
            moodEntries.append(MoodEntry(text: entry.text, sentiment: s, hoursAgo: hoursAgo, weight: 1.0))
        }
        let moodBreakdown = moodEntries
            .filter { abs($0.sentiment) > 0.05 }
            .sorted { abs($0.sentiment) > abs($1.sentiment) }

        return TreeData(
            health: health,
            streak: streak,
            streakTier: streakTier,
            season: season,
            growthProgress: growthProgress,
            healthLabel: healthLabel,
            seasonLabel: seasonLabel,
            streakLabel: streakLabel,
            growthLabel: growthLabel,
            mood: mood,
            moodLabel: moodLabel,
            population: population,
            recentTrend: recentTrend,
            moodBreakdown: moodBreakdown
        )
    }
}
