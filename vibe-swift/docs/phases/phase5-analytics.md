# Phase 5: Analytics — Charts and Visualizations

## Goal
Implement all 20+ chart and visualization views in the Analytics dashboard. After this phase, clicking the "Analytics" tab should show a fully populated 2-column grid of charts matching the Electron/D3.js reference.

## What Already Exists

### Fully Implemented (no work needed)
These views in `AnalyticsDashboardView.swift` are complete:

| View | Lines | Description |
|------|-------|-------------|
| `StreaksCardView` | ~20 | Current streak + longest streak display |
| `RecordsCardView` | ~25 | Personal bests: max WPM, max words/day, longest session |
| `GoalsCardView` | ~30 | Daily (500 words) + weekly (2500 words) progress bars |
| `SessionsGaugeView` | ~35 | Radial gauge showing sessions today (target: 10) |
| `FillerWordsView` | ~25 | Horizontal bar chart of top filler words |
| `CommonPhrasesView` | ~30 | N-gram chips (bigrams + trigrams) with count badges |
| `NewWordsView` | ~15 | "X new words this week" stat |
| `ReadingLevelView` | ~30 | Flesch-Kincaid gauge with grade labels |
| `WordLengthDistView` | ~35 | Stacked bar (1-3, 4-6, 7+ chars) with percentages |
| `RareWordsView` | ~20 | Flow layout of rare word chips |
| `WordCloudView` | ~20 | Scaled text flow (12-36px by frequency) |
| `PeriodComparisonView` | ~25 | This week vs last week: words, sessions, duration |

### Placeholder Stubs (need Swift Charts implementation)
These views currently show placeholder text:

| View | Chart Type | Reference Function in `analytics.js` |
|------|-----------|--------------------------------------|
| `WordsOverTimeView` | Area chart | `renderWordsChart()` |
| `TimeSavedChartView` | Area chart | `renderTimeSavedChart()` |
| `WpmTrendsView` | Line chart + dots | `renderWpmChart()` |
| `ModeDonutView` | Donut/pie chart | `renderModeDonut()` |
| `PeakHoursView` | Bar chart (24 bars) | `renderPeakHours()` |
| `VocabGrowthView` | Area chart | `renderVocabGrowth()` |
| `WpmByHourView` | Bar chart (24 bars) | `renderWpmByHour()` |
| `SessionHistogramView` | Histogram | `renderSessionHistogram()` |
| `SentimentChartView` | Dual area chart | `renderSentimentChart()` |

### Canvas-Drawn (need custom implementation)
| View | Chart Type | Reference Function |
|------|-----------|-------------------|
| `ActivityHeatmapView` | 24×7 grid | `renderActivityHeatmap()` |
| (new) `YearlyHeatmapView` | GitHub-style 365-day grid | `renderYearlyHeatmap()` |

## Data Source: AnalyticsProcessor

`Sources/Data/AnalyticsProcessor.swift` is **fully implemented**. It ports all of `analytics.js processData()` and returns an `AnalyticsData` struct with all computed fields:

```swift
struct AnalyticsData {
    let totalEntries: Int
    let totalWords: Int
    let averageWpm: Double
    let totalTimeSavedMinutes: Double

    // Activity
    let activityMatrix: [[Int]]     // [7][24] - day of week × hour
    let wpmByHour: [Double?]        // [24] - avg WPM per hour

    // Daily
    let dailyData: [DailyStats]     // Sorted by date

    // Modes
    let modeCounts: [String: Int]   // {transcribe: N, cleanup: N, ...}

    // Streaks
    let currentStreak: Int
    let longestStreak: Int

    // Records
    let maxWpm: Int
    let maxWordsInDay: Int
    let longestSessionSeconds: Double

    // Goals
    let todayWords: Int
    let todaySessions: Int
    let thisWeekWords: Int

    // Vocabulary
    let uniqueWords: Int
    let vocabGrowth: [(date: String, count: Int)]
    let newWordsThisWeek: Int

    // Language
    let fillerCounts: [(word: String, count: Int)]
    let topBigrams: [(phrase: String, count: Int)]
    let topTrigrams: [(phrase: String, count: Int)]
    let rareWords: [(word: String, count: Int)]
    let sentimentData: [(date: String, score: Double, positive: Int, negative: Int)]
    let readingLevel: Double
    let wordLengthDist: (short: Int, medium: Int, long: Int)

    // Comparison
    let thisWeekData: PeriodData
    let lastWeekData: PeriodData

    // Raw
    let wordFrequency: [String: Int]
    let sessionDurations: [Double]
}
```

## Chart Implementation Guide

### Framework: Swift Charts (macOS 14+)
All charts use `import Charts` with the Swift Charts framework.

### Common Pattern
```swift
struct MyChartView: View {
    let data: [DataPoint]

    var body: some View {
        Chart(data) { point in
            // Mark type here
        }
        .chartXAxis { ... }
        .chartYAxis { ... }
        .chartPlotStyle { plot in
            plot.background(Theme.bgTertiary.opacity(0.3))
        }
        .frame(minHeight: 120)
    }
}
```

### Chart Colors (from `analytics.js CHART_COLORS`)
- Accent/primary: `Theme.chartAccent` (#fbbf24 amber)
- Green: `Theme.green` (#34d399)
- Purple: `Theme.purple` (#a78bfa)
- Orange: `Theme.orange` (#fb923c)
- Blue: `Theme.blue` (#60a5fa)
- Muted: `Theme.textMuted` (#6e6e73)
- Background: `Theme.bgSecondary` (#151518)
- Border: `Theme.border` (#2a2a32)

---

### 1. WordsOverTimeView (Area Chart)
**D3 reference**: `renderWordsChart()` — area with monotone curve, 150px height

```swift
struct WordsOverTimeView: View {
    let dailyData: [AnalyticsProcessor.DailyStats]

    var body: some View {
        Chart(dailyData, id: \.date) { day in
            AreaMark(
                x: .value("Date", day.dateObj),    // Parse day.date to Date
                y: .value("Words", day.words)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Theme.chartAccent.opacity(0.6), Theme.chartAccent.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Date", day.dateObj),
                y: .value("Words", day.words)
            )
            .foregroundStyle(Theme.chartAccent)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(Theme.textMuted)
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.3))
            }
        }
        .frame(minHeight: 120)
    }
}
```

### 2. TimeSavedChartView (Area Chart)
**D3 reference**: `renderTimeSavedChart()` — cumulative time saved, green color

Same structure as WordsOverTimeView but:
- Y-axis: cumulative `timeSavedMinutes`
- Color: `Theme.green` instead of `Theme.chartAccent`
- Y-axis label: "minutes"

### 3. WpmTrendsView (Line Chart + Dots)
**D3 reference**: `renderWpmChart()` — line with dots, filtered to days with WPM data

```swift
Chart(filteredData, id: \.date) { day in
    LineMark(x: .value("Date", day.dateObj), y: .value("WPM", day.avgWpm))
        .foregroundStyle(Theme.chartAccent)
    PointMark(x: .value("Date", day.dateObj), y: .value("WPM", day.avgWpm))
        .foregroundStyle(Theme.chartAccent)
        .symbolSize(20)
}
```
- Filter `dailyData` to only entries where `avgWpm > 0`
- Y domain: `min * 0.9 ... max * 1.1`

### 4. ModeDonutView (Donut Chart)
**D3 reference**: `renderModeDonut()` — donut with `innerRadius = radius * 0.5`

```swift
Chart(modeData, id: \.mode) { item in
    SectorMark(
        angle: .value("Count", item.count),
        innerRadius: .ratio(0.5),
        angularInset: 2
    )
    .foregroundStyle(by: .value("Mode", item.mode))
}
.chartForegroundStyleScale([
    "transcribe": Theme.green,
    "cleanup": Theme.orange,
    "plan": Theme.blue,
    "greppy": Theme.purple
])
```
**Note**: `SectorMark` requires macOS 14+ (Sonoma).

### 5. PeakHoursView (Bar Chart, 24 bars)
**D3 reference**: `renderPeakHours()` — 24 bars for hourly activity totals

```swift
// Sum activityMatrix columns to get hourly totals
let hourlyTotals = (0..<24).map { hour in
    (hour: hour, total: activityMatrix.reduce(0) { $0 + $1[hour] })
}
Chart(hourlyTotals, id: \.hour) { item in
    BarMark(x: .value("Hour", item.hour), y: .value("Sessions", item.total))
        .foregroundStyle(Theme.chartAccent.opacity(0.3 + 0.7 * Double(item.total) / Double(maxTotal)))
}
```
- X-axis: 0-23 hours, labels every 6h ("12am", "6am", "12pm", "6pm")
- Opacity scales with value: `0.3 + (value/max) * 0.7`

### 6. VocabGrowthView (Area Chart)
**D3 reference**: `renderVocabGrowth()` — cumulative unique word count

Same area chart pattern as WordsOverTimeView:
- Data: `vocabGrowth: [(date, count)]`
- Color: `Theme.purple`
- Y-axis: cumulative unique words

### 7. WpmByHourView (Bar Chart, 24 bars)
**D3 reference**: `renderWpmByHour()` — average WPM per hour

```swift
let hourData = wpmByHour.enumerated().compactMap { hour, wpm -> (Int, Double)? in
    guard let wpm = wpm else { return nil }
    return (hour, wpm)
}
Chart(hourData, id: \.0) { item in
    BarMark(x: .value("Hour", item.0), y: .value("WPM", item.1))
        .foregroundStyle(Theme.blue)
}
```

### 8. SessionHistogramView (Histogram)
**D3 reference**: `renderSessionHistogram()` — histogram of session durations

```swift
// Bin durations into 12 bins, capped at 60s
let capped = sessionDurations.map { min($0, 60) }
// Create histogram bins manually or use BarMark with binned data
```
- 12 bins from 0 to 60 seconds
- Color: `Theme.chartAccent`
- X-axis: "0s" to "60s"

### 9. SentimentChartView (Dual Area)
**D3 reference**: `renderSentimentChart()` — positive above 0, negative below

```swift
Chart(sentimentData, id: \.date) { day in
    AreaMark(
        x: .value("Date", day.dateObj),
        y: .value("Score", day.score)
    )
    .foregroundStyle(day.score >= 0 ? Theme.green.opacity(0.3) : Theme.orange.opacity(0.3))
}
// Add zero line with RuleMark
RuleMark(y: .value("Zero", 0))
    .foregroundStyle(Theme.border)
```

### 10. ActivityHeatmapView (Canvas, 24×7 grid)
**D3 reference**: `renderActivityHeatmap()` — cell size 15×12, 2px gaps

This needs **Canvas** (not Swift Charts) since Charts doesn't support heatmaps:
```swift
Canvas { context, size in
    let cellW: CGFloat = 15, cellH: CGFloat = 12, gap: CGFloat = 2
    for day in 0..<7 {
        for hour in 0..<24 {
            let x = CGFloat(hour) * (cellW + gap)
            let y = CGFloat(day) * (cellH + gap)
            let value = activityMatrix[day][hour]
            let opacity = Double(value) / Double(maxValue)
            let color = Theme.chartAccent.opacity(opacity)
            context.fill(
                Path(roundedRect: CGRect(x: x, y: y, width: cellW, height: cellH), cornerRadius: 2),
                with: .color(color)
            )
        }
    }
}
```
- Row labels: Mon, Tue, ..., Sun
- Column labels: Hours (every 6h)
- Color: Amber (chartAccent) with opacity scaled by value

### 11. YearlyHeatmapView (Canvas, GitHub-style)
**D3 reference**: `renderYearlyHeatmap()` — 365 cells, 10px with 2px gaps

Similar Canvas approach but for last 365 days:
- Cell size: 10×10, 2px gap
- 7 rows (Sun-Sat) × ~52 columns (weeks)
- Color scale: bg → chartAccent

## Dashboard Layout

The `AnalyticsDashboardView` uses a 2-column `LazyVGrid`:
```swift
let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
]
LazyVGrid(columns: columns, spacing: 12) {
    chartCard("Words Over Time", fullWidth: true) { WordsOverTimeView(dailyData: data.dailyData) }
    chartCard("Time Saved", fullWidth: true) { TimeSavedChartView(dailyData: data.dailyData) }
    chartCard("Mode Distribution") { ModeDonutView(modeCounts: data.modeCounts) }
    chartCard("WPM Trends") { WpmTrendsView(dailyData: data.dailyData) }
    // ... etc
}
```

Full-width cards: Words Over Time, Time Saved, Activity Heatmap, Yearly Heatmap, Word Cloud
Single-column cards: Everything else

## `chartCard` Helper
Already exists in AnalyticsDashboardView.swift. Provides consistent card styling:
- Background: `Theme.bgSecondary`
- Border: `Theme.border`, 1px
- Corner radius: 10
- Padding: 16
- Title: 12px semibold, `Theme.textSecondary`

## Testing Checklist
- [ ] Analytics tab renders all 20+ chart/visualization views
- [ ] Charts display real data from history.db
- [ ] Area charts show smooth gradients
- [ ] Donut chart shows mode distribution with correct colors
- [ ] Bar charts show 24-hour data correctly
- [ ] Heatmaps render with correct color scaling
- [ ] Word cloud renders with proper size scaling
- [ ] Empty state handled when no entries
- [ ] Scrolling through dashboard is smooth
- [ ] Charts resize correctly if window is resized

## Build & Run
```bash
cd VibeToText
swift build && swift run
```
Navigate to the Analytics tab. With existing history data from the Python app, all charts should populate.
