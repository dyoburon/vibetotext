import SwiftUI
import Combine
import Charts

/// Analytics dashboard — 2-column grid of chart cards.
struct AnalyticsDashboardView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var analyticsData: AnalyticsData?
    @State private var cancellable: AnyCancellable?

    var body: some View {
        ScrollView {
            if let data = analyticsData, !entries.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    // Streaks & Records
                    chartCard("Streaks") { StreaksCardView(current: data.currentStreak, longest: data.longestStreak) }
                    chartCard("Personal Records") { RecordsCardView(maxWpm: data.maxWpm, maxWords: data.maxWordsInDay, longestSession: data.longestSession) }

                    // Goals
                    chartCard("Daily Goal Progress") { GoalsCardView(todayWords: data.todayWords, weekWords: data.thisWeekWords) }
                    chartCard("Sessions Today") { SessionsGaugeView(sessions: data.todaySessions, duration: data.todayDuration) }

                    // Activity (full width)
                    chartCard("Activity", fullWidth: true) { ActivityHeatmapView(matrix: data.activityMatrix) }
                    chartCard("Peak Hours") { PeakHoursView(matrix: data.activityMatrix) }

                    // Time charts
                    chartCard("Words Over Time") { WordsOverTimeView(daily: data.dailyArray) }
                    chartCard("Time Saved") { TimeSavedChartView(daily: data.dailyArray) }
                    chartCard("Speaking Speed (WPM)") { WpmTrendsView(daily: data.dailyArray) }
                    chartCard("Usage by Mode") { ModeDonutView(counts: data.modeCounts) }

                    // Period comparison (full width)
                    chartCard("This Week vs Last Week", fullWidth: true) {
                        PeriodComparisonView(thisWeek: data.thisWeekData, lastWeek: data.lastWeekData)
                    }

                    // Speech patterns
                    chartCard("Filler Words") { FillerWordsView(counts: data.fillerCounts) }
                    chartCard("Common Phrases") { CommonPhrasesView(bigrams: data.topBigrams, trigrams: data.topTrigrams) }

                    // Vocabulary
                    chartCard("New Words This Week") { NewWordsView(words: data.newWordsThisWeek) }
                    chartCard("Reading Level") { ReadingLevelView(level: data.readingLevel) }
                    chartCard("Vocabulary Growth") { VocabGrowthView(growth: data.vocabGrowth) }
                    chartCard("Word Length") { WordLengthDistView(dist: data.wordLengthDist) }
                    chartCard("Your Rare Words", fullWidth: true) { RareWordsView(words: data.rareWords) }

                    // WPM by hour (full width)
                    chartCard("WPM by Hour of Day", fullWidth: true) { WpmByHourView(avgByHour: data.avgWpmByHour) }

                    // Session histogram (full width)
                    chartCard("Session Length Distribution", fullWidth: true) { SessionHistogramView(durations: data.sessionDurations) }

                    // Word cloud (full width)
                    chartCard("Word Cloud", fullWidth: true) { WordCloudView(frequency: data.wordFrequency) }

                    // Sentiment (full width)
                    chartCard("Sentiment Over Time", fullWidth: true) { SentimentChartView(data: data.sentimentArray) }
                }
                .padding(12)
            } else {
                VStack {
                    Spacer(minLength: 60)
                    Text("No transcriptions yet")
                        .foregroundColor(Theme.textMuted)
                        .font(.system(size: 12))
                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { startObserving() }
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, fullWidth: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.5)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .if(fullWidth) { view in
            view.gridCellColumns(2)
        }
    }

    private func startObserving() {
        cancellable = HistoryDatabase.shared.observeEntries()
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { entries -> (entries: [HistoryEntry], data: AnalyticsData) in
                (entries, AnalyticsProcessor.process(entries))
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { result in
                    self.entries = result.entries
                    self.analyticsData = result.data
                }
            )
    }
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Chart views

struct StreaksCardView: View {
    let current: Int, longest: Int
    var body: some View {
        HStack(spacing: 8) {
            statItem(value: "\(current)", label: "CURRENT STREAK", highlight: true)
            statItem(value: "\(longest)", label: "LONGEST STREAK")
        }
    }
    private func statItem(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(highlight ? Theme.chartAccent : Theme.textPrimary)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.textMuted).tracking(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(highlight ? Theme.chartAccent.opacity(0.1) : Theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct RecordsCardView: View {
    let maxWpm: Int, maxWords: Int, longestSession: Double
    var body: some View {
        HStack(spacing: 8) {
            miniStat(value: maxWpm > 0 ? "\(maxWpm)" : "--", label: "BEST WPM")
            miniStat(value: "\(maxWords)", label: "MOST WORDS/DAY")
            miniStat(value: longestSession > 0 ? "\(Int(longestSession))s" : "--", label: "LONGEST SESSION")
        }
    }
    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.textPrimary)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.textMuted).tracking(0.4)
        }
        .frame(maxWidth: .infinity).padding(8).background(Theme.bgTertiary).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct GoalsCardView: View {
    let todayWords: Int, weekWords: Int
    var body: some View {
        VStack(spacing: 12) {
            goalBar(label: "Daily Words", current: todayWords, target: AnalyticsProcessor.dailyWordGoal, color: Theme.chartAccent)
            goalBar(label: "Weekly Words", current: weekWords, target: AnalyticsProcessor.weeklyWordGoal, color: Theme.blue)
        }
    }
    private func goalBar(label: String, current: Int, target: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack { Text(label).font(.system(size: 11)).foregroundColor(Theme.textSecondary); Spacer(); Text("\(current) / \(target)").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textPrimary) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.bgTertiary).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(current >= target ? Theme.green : color).frame(width: min(geo.size.width, geo.size.width * CGFloat(current) / CGFloat(max(1, target))), height: 6)
                }
            }.frame(height: 6)
        }
    }
}

struct SessionsGaugeView: View {
    let sessions: Int, duration: Double
    var body: some View {
        VStack(spacing: 4) {
            Text("\(sessions)").font(.system(size: 26, weight: .semibold)).foregroundColor(Theme.chartAccent)
            Text("sessions").font(.system(size: 10)).foregroundColor(Theme.textMuted)
            Text("\(Int(duration / 60))m recorded").font(.system(size: 9)).foregroundColor(Theme.textMuted)
        }.frame(maxWidth: .infinity)
    }
}

struct ActivityHeatmapView: View {
    let matrix: [[Int]]
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var body: some View {
        let maxVal = max(1, matrix.flatMap { $0 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 2) {
            // Hour labels
            HStack(spacing: 0) {
                Text("").frame(width: 30)
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(h == 0 ? "12a" : h == 6 ? "6a" : h == 12 ? "12p" : "6p")
                        .font(.system(size: 8)).foregroundColor(Theme.textMuted)
                        .frame(width: 15 * 6, alignment: .leading)
                }
            }
            // Grid
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 2) {
                    Text(dayLabels[day]).font(.system(size: 8)).foregroundColor(Theme.textMuted).frame(width: 28, alignment: .trailing)
                    ForEach(0..<24, id: \.self) { hour in
                        let val = matrix[day][hour]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.chartAccent.opacity(val == 0 ? 0.05 : 0.15 + 0.85 * Double(val) / Double(maxVal)))
                            .frame(width: 13, height: 10)
                    }
                }
            }
        }
    }
}

struct PeakHoursView: View {
    let matrix: [[Int]]
    var body: some View {
        let hourly = (0..<24).map { h in (hour: h, total: matrix.reduce(0) { $0 + $1[h] }) }
        let maxVal = max(1, hourly.map(\.total).max() ?? 1)
        Chart(hourly, id: \.hour) { item in
            BarMark(x: .value("Hour", item.hour), y: .value("Sessions", item.total))
                .foregroundStyle(Theme.chartAccent.opacity(item.total == 0 ? 0.1 : 0.3 + 0.7 * Double(item.total) / Double(maxVal)))
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { val in
                AxisValueLabel {
                    if let h = val.as(Int.self) {
                        Text(h == 0 ? "12am" : h == 6 ? "6am" : h == 12 ? "12pm" : "6pm")
                            .font(.system(size: 9)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
        }
        .frame(minHeight: 80)
    }
}

struct WordsOverTimeView: View {
    let daily: [AnalyticsData.DailyAggregate]
    var body: some View {
        Chart(daily, id: \.date) { day in
            AreaMark(x: .value("Date", day.dateObj), y: .value("Words", day.words))
                .foregroundStyle(.linearGradient(colors: [Theme.chartAccent.opacity(0.5), Theme.chartAccent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", day.dateObj), y: .value("Words", day.words))
                .foregroundStyle(Theme.chartAccent).lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
        }
        .frame(minHeight: 100)
    }
}

struct TimeSavedChartView: View {
    let daily: [AnalyticsData.DailyAggregate]
    var body: some View {
        Chart(daily, id: \.date) { day in
            AreaMark(x: .value("Date", day.dateObj), y: .value("Minutes", day.cumulativeTimeSaved))
                .foregroundStyle(.linearGradient(colors: [Theme.green.opacity(0.5), Theme.green.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", day.dateObj), y: .value("Minutes", day.cumulativeTimeSaved))
                .foregroundStyle(Theme.green).lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
        }
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
        }
        .frame(minHeight: 100)
    }
}

struct WpmTrendsView: View {
    let daily: [AnalyticsData.DailyAggregate]
    var body: some View {
        let filtered = daily.compactMap { d -> (date: Date, wpm: Int)? in
            guard let w = d.avgWpm else { return nil }
            return (d.dateObj, w)
        }
        if filtered.isEmpty {
            Text("Not enough data yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 100)
        } else {
            Chart(filtered, id: \.date) { item in
                LineMark(x: .value("Date", item.date), y: .value("WPM", item.wpm))
                    .foregroundStyle(Theme.chartAccent).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Date", item.date), y: .value("WPM", item.wpm))
                    .foregroundStyle(Theme.chartAccent).symbolSize(20)
            }
            .chartYScale(domain: {
                let vals = filtered.map(\.wpm)
                let lo = (vals.min() ?? 0)
                let hi = (vals.max() ?? 100)
                return (Double(lo) * 0.9)...(Double(hi) * 1.1)
            }())
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
            }
            .frame(minHeight: 100)
        }
    }
}

struct ModeDonutView: View {
    let counts: [String: Int]
    private let modeOrder = ["transcribe", "cleanup", "plan", "greppy"]
    var body: some View {
        let data = modeOrder.compactMap { mode -> (mode: String, count: Int)? in
            guard let c = counts[mode], c > 0 else { return nil }
            return (mode, c)
        }
        if data.isEmpty {
            Text("No data yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 100)
        } else {
            VStack(spacing: 12) {
                Chart(data, id: \.mode) { item in
                    SectorMark(angle: .value("Count", item.count), innerRadius: .ratio(0.5), angularInset: 2)
                        .foregroundStyle(Theme.modeColor(item.mode))
                }
                .frame(height: 100)
                // Legend
                HStack(spacing: 12) {
                    ForEach(data, id: \.mode) { item in
                        HStack(spacing: 4) {
                            Circle().fill(Theme.modeColor(item.mode)).frame(width: 8, height: 8)
                            Text(item.mode.capitalized).font(.system(size: 10)).foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

struct PeriodComparisonView: View {
    let thisWeek: AnalyticsData.PeriodData, lastWeek: AnalyticsData.PeriodData
    var body: some View {
        HStack(spacing: 20) {
            periodColumn("THIS WEEK", data: thisWeek)
            periodColumn("LAST WEEK", data: lastWeek)
        }
    }
    private func periodColumn(_ label: String, data: AnalyticsData.PeriodData) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.textMuted)
            compStat("Words", "\(data.words)")
            compStat("Sessions", "\(data.sessions)")
            compStat("Duration", String(format: "%.1fm", data.duration / 60))
        }.frame(maxWidth: .infinity)
    }
    private func compStat(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.system(size: 12)).foregroundColor(Theme.textSecondary); Spacer(); Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textPrimary) }
        .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.bgTertiary).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct FillerWordsView: View {
    let counts: [String: Int]
    var body: some View {
        let sorted = counts.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(6)
        let maxCount = sorted.first?.value ?? 1
        VStack(spacing: 8) {
            ForEach(Array(sorted), id: \.key) { word, count in
                HStack(spacing: 10) {
                    Text("\"\(word)\"").font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.textSecondary).frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.bgTertiary).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.orange).frame(width: geo.size.width * CGFloat(count) / CGFloat(maxCount), height: 6)
                        }
                    }.frame(height: 6)
                    Text("\(count)").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

struct CommonPhrasesView: View {
    let bigrams: [(phrase: String, count: Int)], trigrams: [(phrase: String, count: Int)]
    var body: some View {
        let all = (trigrams + bigrams).prefix(12)
        FlowLayout(spacing: 8) {
            ForEach(Array(all.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(item.phrase).font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                    Text("\(item.count)").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.purple)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.bgTertiary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
        }
    }
}

struct NewWordsView: View {
    let words: [String]
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(words.count)").font(.system(size: 42, weight: .bold)).foregroundColor(Theme.chartAccent)
                Text("new words this week").font(.system(size: 12)).foregroundColor(Theme.textMuted)
            }
            if !words.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(words.prefix(8), id: \.self) { word in
                        Text(word).font(.system(size: 11)).foregroundColor(Theme.textSecondary).padding(.horizontal, 10).padding(.vertical, 4).background(Theme.bgTertiary).clipShape(Capsule())
                    }
                    if words.count > 8 { Text("+\(words.count - 8) more").font(.system(size: 11)).foregroundColor(Theme.textMuted) }
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

struct ReadingLevelView: View {
    let level: Double
    var body: some View {
        let grade = Int(round(level))
        let labels: [Int: String] = [1: "1st", 2: "2nd", 3: "3rd", 13: "College", 14: "College", 15: "College+", 16: "Graduate"]
        let gradeLabel = labels[grade] ?? "\(grade)th"
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(gradeLabel).font(.system(size: 36, weight: .bold)).foregroundColor(Theme.chartAccent)
                Text("grade level").font(.system(size: 12)).foregroundColor(Theme.textMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [Theme.green, Theme.chartAccent, Theme.orange], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 6).clipShape(RoundedRectangle(cornerRadius: 3)).opacity(0.3)
                    Circle().fill(Theme.chartAccent).frame(width: 12, height: 12)
                        .offset(x: min(geo.size.width - 12, geo.size.width * CGFloat(level / 16)))
                }
            }.frame(height: 12).padding(.horizontal, 20)
            HStack { Text("Simple").font(.system(size: 10)).foregroundColor(Theme.textMuted); Spacer(); Text("Complex").font(.system(size: 10)).foregroundColor(Theme.textMuted) }.padding(.horizontal, 20)
        }.frame(maxWidth: .infinity)
    }
}

struct VocabGrowthView: View {
    let growth: [(date: String, count: Int)]
    var body: some View {
        if growth.isEmpty {
            Text("Not enough data yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 100)
        } else {
            let df = DateFormatter(); let _ = df.dateFormat = "yyyy-MM-dd"
            let data = growth.compactMap { item -> (date: Date, count: Int)? in
                guard let d = df.date(from: item.date) else { return nil }
                return (d, item.count)
            }
            Chart(data, id: \.date) { item in
                AreaMark(x: .value("Date", item.date), y: .value("Words", item.count))
                    .foregroundStyle(.linearGradient(colors: [Theme.purple.opacity(0.5), Theme.purple.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", item.date), y: .value("Words", item.count))
                    .foregroundStyle(Theme.purple).lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
            }
            .frame(minHeight: 100)
        }
    }
}

struct WordLengthDistView: View {
    let dist: (short: Int, medium: Int, long: Int)
    var body: some View {
        let total = max(1, dist.short + dist.medium + dist.long)
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.green).frame(width: geo.size.width * CGFloat(dist.short) / CGFloat(total))
                    Rectangle().fill(Theme.chartAccent).frame(width: geo.size.width * CGFloat(dist.medium) / CGFloat(total))
                    Rectangle().fill(Theme.purple).frame(width: geo.size.width * CGFloat(dist.long) / CGFloat(total))
                }.clipShape(RoundedRectangle(cornerRadius: 6))
            }.frame(height: 24)
            VStack(spacing: 6) {
                lengthRow("1-3 chars", pct: dist.short * 100 / total, color: Theme.green)
                lengthRow("4-6 chars", pct: dist.medium * 100 / total, color: Theme.chartAccent)
                lengthRow("7+ chars", pct: dist.long * 100 / total, color: Theme.purple)
            }
        }
    }
    private func lengthRow(_ label: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text("\(pct)%").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textPrimary)
        }
    }
}

struct RareWordsView: View {
    let words: [(word: String, count: Int)]
    var body: some View {
        if words.isEmpty {
            Text("Keep talking to discover your rare words!").font(.system(size: 12)).foregroundColor(Theme.textMuted)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.word).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                        Text("\(item.count)").font(.system(size: 10)).foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.bgPrimary).clipShape(Capsule())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.bgTertiary).clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
            }
        }
    }
}

struct WpmByHourView: View {
    let avgByHour: [Int?]
    var body: some View {
        let data = avgByHour.enumerated().compactMap { h, wpm -> (hour: Int, wpm: Int)? in
            guard let w = wpm else { return nil }
            return (h, w)
        }
        if data.isEmpty {
            Text("Not enough data yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart(data, id: \.hour) { item in
                BarMark(x: .value("Hour", item.hour), y: .value("WPM", item.wpm))
                    .foregroundStyle(Theme.blue).cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { val in
                    AxisValueLabel {
                        if let h = val.as(Int.self) {
                            Text(h == 0 ? "12am" : h == 6 ? "6am" : h == 12 ? "12pm" : "6pm")
                                .font(.system(size: 9)).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
            }
            .frame(minHeight: 80)
        }
    }
}

struct SessionHistogramView: View {
    let durations: [Double]
    var body: some View {
        if durations.isEmpty {
            Text("No sessions yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let capped = durations.map { min($0, 60) }
            let binSize = 5.0
            let bins = (0..<12).map { i -> (range: String, count: Int) in
                let lo = Double(i) * binSize
                let hi = lo + binSize
                let count = capped.filter { $0 >= lo && $0 < hi }.count
                return ("\(Int(lo))-\(Int(hi))s", count)
            }
            Chart(bins, id: \.range) { bin in
                BarMark(x: .value("Duration", bin.range), y: .value("Count", bin.count))
                    .foregroundStyle(Theme.chartAccent).cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 8)).foregroundStyle(Theme.textMuted) }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
            }
            .frame(minHeight: 80)
        }
    }
}

struct WordCloudView: View {
    let frequency: [String: Int]
    var body: some View {
        let filtered = frequency.filter { $0.key.count > 2 && !stopwords.contains($0.key) && $0.value >= 2 }
            .sorted { $0.value > $1.value }.prefix(40)
        let maxCount = filtered.first?.value ?? 1
        let minCount = filtered.last?.value ?? 1
        FlowLayout(spacing: 8) {
            ForEach(Array(filtered.enumerated()), id: \.offset) { _, item in
                let size = 12.0 + Double(item.value - minCount) / Double(max(1, maxCount - minCount)) * 24.0
                Text(item.key)
                    .font(.system(size: CGFloat(size), weight: size > 20 ? .semibold : .regular))
                    .foregroundColor(Theme.textSecondary)
            }
        }.padding(20)
    }
}

struct SentimentChartView: View {
    let data: [(date: String, score: Double, positive: Int, negative: Int)]
    var body: some View {
        if data.isEmpty {
            Text("Not enough data yet").font(.system(size: 11)).foregroundColor(Theme.textMuted).frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let df = DateFormatter(); let _ = df.dateFormat = "yyyy-MM-dd"
            let points = data.compactMap { item -> (date: Date, score: Double)? in
                guard let d = df.date(from: item.date) else { return nil }
                return (d, item.score)
            }
            Chart {
                ForEach(points, id: \.date) { item in
                    AreaMark(x: .value("Date", item.date), y: .value("Score", item.score))
                        .foregroundStyle(.linearGradient(
                            colors: [item.score >= 0 ? Theme.green.opacity(0.4) : Theme.orange.opacity(0.4),
                                     item.score >= 0 ? Theme.green.opacity(0.05) : Theme.orange.opacity(0.05)],
                            startPoint: item.score >= 0 ? .top : .bottom,
                            endPoint: item.score >= 0 ? .bottom : .top
                        ))
                    LineMark(x: .value("Date", item.date), y: .value("Score", item.score))
                        .foregroundStyle(item.score >= 0 ? Theme.green : Theme.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.border)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textMuted); AxisGridLine().foregroundStyle(Theme.border.opacity(0.3)) }
            }
            .frame(minHeight: 80)
        }
    }
}
