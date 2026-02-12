import Foundation

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

    static let placeholder = TreeData(
        health: 0.85, streak: 0, streakTier: 0, season: 0.5, growthProgress: 0.0,
        healthLabel: "—", seasonLabel: "—", streakLabel: "—", growthLabel: "—"
    )
}

enum TreeDataCalculator {
    static func calculate(from entries: [TranscriptionEntry]) -> TreeData {
        guard !entries.isEmpty else {
            return TreeData(
                health: 0.3, streak: 0, streakTier: 0, season: 0.0, growthProgress: 0.0,
                healthLabel: "30%", seasonLabel: "Winter", streakLabel: "None", growthLabel: "0%"
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

        return TreeData(
            health: health,
            streak: streak,
            streakTier: streakTier,
            season: season,
            growthProgress: growthProgress,
            healthLabel: healthLabel,
            seasonLabel: seasonLabel,
            streakLabel: streakLabel,
            growthLabel: growthLabel
        )
    }
}
