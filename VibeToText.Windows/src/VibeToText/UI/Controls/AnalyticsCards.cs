using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;
using LiveChartsCore;
using LiveChartsCore.SkiaSharpView;
using LiveChartsCore.SkiaSharpView.Painting;
using LiveChartsCore.SkiaSharpView.WPF;
using SkiaSharp;
using VibeToText.Data;
using VibeToText.Models;

namespace VibeToText.UI.Controls;

/// <summary>Goal progress bars card.</summary>
public class GoalProgressCard : UserControl
{
    public GoalProgressCard()
    {
        DataContextChanged += (_, _) => Rebuild();
    }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) return;

        var sp = new StackPanel();

        // Title
        sp.Children.Add(CreateLabel("DAILY GOAL PROGRESS"));

        // Daily goal
        var dailyPct = Math.Min(100, (double)data.TodayData.Words / AnalyticsProcessor.DailyWordGoal * 100);
        sp.Children.Add(CreateGoalBar("Daily Words",
            $"{data.TodayData.Words:N0} / {AnalyticsProcessor.DailyWordGoal:N0}",
            dailyPct, dailyPct >= 100 ? "#34D399" : "#FBBF24"));

        // Weekly goal
        var weeklyPct = Math.Min(100, (double)data.ThisWeekWords / AnalyticsProcessor.WeeklyWordGoal * 100);
        sp.Children.Add(CreateGoalBar("Weekly Words",
            $"{data.ThisWeekWords:N0} / {AnalyticsProcessor.WeeklyWordGoal:N0}",
            weeklyPct, weeklyPct >= 100 ? "#34D399" : "#60A5FA"));

        Content = sp;
    }

    private static UIElement CreateGoalBar(string label, string value, double pct, string color)
    {
        var sp = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        var header = new DockPanel();
        header.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = Brush("#A1A1A6") });
        var val = new TextBlock { Text = value, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brush("#F5F5F7") };
        DockPanel.SetDock(val, Dock.Right);
        header.Children.Add(val);
        sp.Children.Add(header);

        var track = new Border
        {
            Height = 6, Background = Brush("#1C1C21"), CornerRadius = new CornerRadius(3),
            Margin = new Thickness(0, 4, 0, 0)
        };
        var fill = new Border
        {
            Height = 6, Background = Brush(color), CornerRadius = new CornerRadius(3),
            HorizontalAlignment = HorizontalAlignment.Left,
            Width = 0 // Set after layout
        };
        track.Child = fill;
        track.Loaded += (_, _) => fill.Width = track.ActualWidth * pct / 100;
        sp.Children.Add(track);
        return sp;
    }

    private static TextBlock CreateLabel(string text) => new()
    {
        Text = text, FontSize = 10, FontWeight = FontWeights.SemiBold,
        Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 4)
    };

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Sessions today radial gauge.</summary>
public class SessionsGaugeCard : UserControl
{
    public SessionsGaugeCard()
    {
        DataContextChanged += (_, _) => Rebuild();
    }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) return;

        var sessions = data.TodayData.Entries;
        var duration = data.TodayData.Duration;
        var minutes = (int)(duration / 60);

        var sp = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        sp.Children.Add(CreateLabel("SESSIONS TODAY"));
        sp.Children.Add(new TextBlock
        {
            Text = sessions.ToString(),
            FontSize = 36, FontWeight = FontWeights.SemiBold,
            Foreground = Brush("#FBBF24"), HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 10, 0, 0)
        });
        sp.Children.Add(new TextBlock
        {
            Text = "sessions", FontSize = 10,
            Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center
        });
        sp.Children.Add(new TextBlock
        {
            Text = $"{minutes}m recorded", FontSize = 9,
            Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 8, 0, 0)
        });

        Content = sp;
    }

    private static TextBlock CreateLabel(string text) => new()
    {
        Text = text, FontSize = 10, FontWeight = FontWeights.SemiBold,
        Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center
    };

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Words over time area chart using LiveCharts2.</summary>
public class WordsChartCard : UserControl
{
    public WordsChartCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.DailyArray.Count == 0)
        {
            Content = EmptyState("WORDS OVER TIME");
            return;
        }

        var chart = ChartHelper.CreateAreaChart(
            data.DailyArray.Select(d => (double)d.Words).ToArray(),
            data.DailyArray.Select(d => d.Date).ToArray(),
            "#FBBF24", "WORDS OVER TIME");
        Content = chart;
    }

    private static StackPanel EmptyState(string title)
    {
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = title, FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")) });
        sp.Children.Add(new TextBlock { Text = "No data yet", FontSize = 12, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 30, 0, 0) });
        return sp;
    }
}

/// <summary>Time saved cumulative chart.</summary>
public class TimeSavedChartCard : UserControl
{
    public TimeSavedChartCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.DailyArray.Count == 0) { Content = null; return; }
        Content = ChartHelper.CreateAreaChart(
            data.DailyArray.Select(d => d.CumulativeTimeSaved).ToArray(),
            data.DailyArray.Select(d => d.Date).ToArray(),
            "#34D399", "TIME SAVED");
    }
}

/// <summary>WPM trends line chart.</summary>
public class WpmChartCard : UserControl
{
    public WpmChartCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }
        var wpmData = data.DailyArray.Where(d => d.AvgWpm.HasValue).ToList();
        if (wpmData.Count == 0) { Content = null; return; }
        Content = ChartHelper.CreateLineChart(
            wpmData.Select(d => (double)d.AvgWpm!.Value).ToArray(),
            wpmData.Select(d => d.Date).ToArray(),
            "#FBBF24", "SPEAKING SPEED (WPM)");
    }
}

/// <summary>Mode distribution donut chart.</summary>
public class ModeDonutCard : UserControl
{
    public ModeDonutCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = "USAGE BY MODE", FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
            Margin = new Thickness(0, 0, 0, 8)
        });

        var colors = new Dictionary<string, string>
        {
            ["transcribe"] = "#34D399",
            ["greppy"] = "#A78BFA",
            ["cleanup"] = "#FB923C",
            ["plan"] = "#60A5FA"
        };

        var series = data.ModeCounts
            .Where(kv => kv.Value > 0)
            .Select(kv => new PieSeries<int>
            {
                Values = new[] { kv.Value },
                Name = kv.Key,
                Fill = new SolidColorPaint(SKColor.Parse(colors.GetValueOrDefault(kv.Key, "#6E6E73"))),
                InnerRadius = 40,
            })
            .ToArray();

        var chart = new PieChart
        {
            Series = series,
            Height = 150,
            LegendPosition = LiveChartsCore.Measure.LegendPosition.Bottom,
        };
        sp.Children.Add(chart);
        Content = sp;
    }
}

/// <summary>Period comparison (this week vs last week).</summary>
public class PeriodComparisonCard : UserControl
{
    public PeriodComparisonCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = "THIS WEEK VS LAST WEEK", FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8)
        });

        var grid = new UniformGrid { Columns = 2 };

        // This week
        var tw = CreateWeekColumn("This Week",
            $"{data.ThisWeekData.Words:N0}", $"{data.ThisWeekData.Sessions}",
            $"{data.ThisWeekData.Duration / 60:F1}m");
        grid.Children.Add(tw);

        // Last week
        var lw = CreateWeekColumn("Last Week",
            $"{data.LastWeekData.Words:N0}", $"{data.LastWeekData.Sessions}",
            $"{data.LastWeekData.Duration / 60:F1}m");
        grid.Children.Add(lw);

        sp.Children.Add(grid);
        Content = sp;
    }

    private static StackPanel CreateWeekColumn(string label, string words, string sessions, string duration)
    {
        var sp = new StackPanel { Margin = new Thickness(0, 0, 8, 0) };
        sp.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 8) });

        foreach (var (lbl, val) in new[] { ("Words", words), ("Sessions", sessions), ("Duration", duration) })
        {
            var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
            row.Children.Add(new TextBlock { Text = lbl, FontSize = 12, Foreground = Brush("#A1A1A6") });
            var v = new TextBlock { Text = val, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Brush("#F5F5F7") };
            DockPanel.SetDock(v, Dock.Right);
            row.Children.Add(v);
            var border = new Border { Background = Brush("#1C1C21"), CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 6, 8, 6), Child = row };
            sp.Children.Add(border);
        }
        return sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Filler words horizontal bars.</summary>
public class FillerWordsCard : UserControl
{
    public FillerWordsCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = "FILLER WORDS", FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8)
        });

        var sorted = data.FillerCounts.Where(kv => kv.Value > 0).OrderByDescending(kv => kv.Value).Take(6).ToList();
        if (sorted.Count == 0)
        {
            sp.Children.Add(new TextBlock { Text = "No filler words detected", FontSize = 12, Foreground = Brush("#6E6E73") });
            Content = sp;
            return;
        }

        int max = sorted.First().Value;
        foreach (var (word, count) in sorted)
        {
            var row = new DockPanel { Margin = new Thickness(0, 4, 0, 0) };
            row.Children.Add(new TextBlock { Text = $"\"{word}\"", Width = 70, FontSize = 13, Foreground = Brush("#A1A1A6"), FontFamily = new FontFamily("Consolas") });
            var countText = new TextBlock { Text = count.ToString(), Width = 40, FontSize = 11, Foreground = Brush("#6E6E73"), TextAlignment = TextAlignment.Right };
            DockPanel.SetDock(countText, Dock.Right);
            row.Children.Add(countText);

            var track = new Border { Height = 6, Background = Brush("#1C1C21"), CornerRadius = new CornerRadius(3), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            var fill = new Border { Height = 6, Background = Brush("#FB923C"), CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left };
            track.Child = fill;
            track.Loaded += (s, _) => fill.Width = ((Border)s!).ActualWidth * count / max;
            row.Children.Add(track);
            sp.Children.Add(row);
        }

        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Common phrases as chips.</summary>
public class CommonPhrasesCard : UserControl
{
    public CommonPhrasesCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = "COMMON PHRASES", FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8)
        });

        var phrases = data.TopTrigrams.Concat(data.TopBigrams.Select(b => b)).Take(12).ToList();
        if (phrases.Count == 0)
        {
            sp.Children.Add(new TextBlock { Text = "No phrases yet", FontSize = 12, Foreground = Brush("#6E6E73") });
            Content = sp;
            return;
        }

        var wrap = new WrapPanel();
        foreach (var (phrase, count) in phrases)
        {
            var border = new Border
            {
                Background = Brush("#1C1C21"), BorderBrush = Brush("#2A2A32"),
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16),
                Padding = new Thickness(12, 6, 12, 6), Margin = new Thickness(0, 0, 8, 8)
            };
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock { Text = phrase, FontSize = 12, Foreground = Brush("#A1A1A6") });
            row.Children.Add(new TextBlock { Text = count.ToString(), FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Brush("#A78BFA"), Margin = new Thickness(6, 0, 0, 0) });
            border.Child = row;
            wrap.Children.Add(border);
        }
        sp.Children.Add(wrap);
        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>New words this week display.</summary>
public class NewWordsCard : UserControl
{
    public NewWordsCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        sp.Children.Add(new TextBlock { Text = "NEW WORDS THIS WEEK", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center });
        sp.Children.Add(new TextBlock { Text = data.NewWordsThisWeek.Count.ToString(), FontSize = 42, FontWeight = FontWeights.Bold, Foreground = Brush("#FBBF24"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 4) });
        sp.Children.Add(new TextBlock { Text = "new words this week", FontSize = 12, Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center });

        if (data.NewWordsThisWeek.Count > 0)
        {
            var wrap = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 0) };
            foreach (var word in data.NewWordsThisWeek.Take(8))
            {
                wrap.Children.Add(new Border
                {
                    Background = Brush("#1C1C21"), CornerRadius = new CornerRadius(12),
                    Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(3),
                    Child = new TextBlock { Text = word, FontSize = 11, Foreground = Brush("#A1A1A6") }
                });
            }
            if (data.NewWordsThisWeek.Count > 8)
                wrap.Children.Add(new TextBlock { Text = $"+{data.NewWordsThisWeek.Count - 8} more", FontSize = 11, Foreground = Brush("#6E6E73"), Margin = new Thickness(4) });
            sp.Children.Add(wrap);
        }
        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Reading level gauge.</summary>
public class ReadingLevelCard : UserControl
{
    public ReadingLevelCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var grade = (int)Math.Round(data.ReadingLevel);
        var labels = new Dictionary<int, string>
        {
            [1] = "1st", [2] = "2nd", [3] = "3rd", [4] = "4th", [5] = "5th", [6] = "6th",
            [7] = "7th", [8] = "8th", [9] = "9th", [10] = "10th", [11] = "11th", [12] = "12th",
            [13] = "College", [14] = "College", [15] = "College+", [16] = "Graduate"
        };
        var gradeLabel = labels.GetValueOrDefault(grade, $"{grade}th");

        var sp = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        sp.Children.Add(new TextBlock { Text = "READING LEVEL", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center });
        sp.Children.Add(new TextBlock { Text = gradeLabel, FontSize = 36, FontWeight = FontWeights.Bold, Foreground = Brush("#FBBF24"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 2) });
        sp.Children.Add(new TextBlock { Text = "grade level", FontSize = 12, Foreground = Brush("#6E6E73"), HorizontalAlignment = HorizontalAlignment.Center });

        // Scale bar
        var position = Math.Min(100, data.ReadingLevel / 16.0 * 100);
        var track = new Border { Height = 6, Margin = new Thickness(20, 12, 20, 4), CornerRadius = new CornerRadius(3), Opacity = 0.3 };
        track.Background = new LinearGradientBrush(
            (Color)ColorConverter.ConvertFromString("#34D399"),
            (Color)ColorConverter.ConvertFromString("#FB923C"),
            0);
        sp.Children.Add(track);

        var labelRow = new DockPanel { Margin = new Thickness(20, 0, 20, 0) };
        labelRow.Children.Add(new TextBlock { Text = "Simple", FontSize = 10, Foreground = Brush("#6E6E73") });
        var complex = new TextBlock { Text = "Complex", FontSize = 10, Foreground = Brush("#6E6E73") };
        DockPanel.SetDock(complex, Dock.Right);
        labelRow.Children.Add(complex);
        sp.Children.Add(labelRow);

        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Vocabulary growth area chart.</summary>
public class VocabGrowthCard : UserControl
{
    public VocabGrowthCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.VocabGrowthArray.Count == 0) { Content = null; return; }
        Content = ChartHelper.CreateAreaChart(
            data.VocabGrowthArray.Select(v => (double)v.Count).ToArray(),
            data.VocabGrowthArray.Select(v => v.Date).ToArray(),
            "#FBBF24", "VOCABULARY GROWTH");
    }
}

/// <summary>Word length distribution stacked bar.</summary>
public class WordLengthCard : UserControl
{
    public WordLengthCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var total = data.WordLengthDist.Short + data.WordLengthDist.Medium + data.WordLengthDist.Long;
        if (total == 0) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = "WORD LENGTH", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8) });

        // Stacked bar
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Height = 24 };
        var items = new[]
        {
            ("1-3 chars", data.WordLengthDist.Short, "#34D399"),
            ("4-6 chars", data.WordLengthDist.Medium, "#FBBF24"),
            ("7+ chars", data.WordLengthDist.Long, "#A78BFA"),
        };

        foreach (var (label, value, color) in items)
        {
            if (value <= 0) continue;
            bar.Children.Add(new Border
            {
                Background = Brush(color),
                Width = 180.0 * value / total, // Approximate width
                Height = 24,
            });
        }
        sp.Children.Add(bar);

        // Legend
        foreach (var (label, value, color) in items)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
            row.Children.Add(new Border { Background = Brush(color), Width = 10, Height = 10, CornerRadius = new CornerRadius(2), Margin = new Thickness(0, 0, 8, 0) });
            row.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = Brush("#A1A1A6"), Width = 80 });
            row.Children.Add(new TextBlock { Text = $"{value * 100 / total}%", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brush("#F5F5F7") });
            sp.Children.Add(row);
        }

        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Rare words as tags.</summary>
public class RareWordsCard : UserControl
{
    public RareWordsCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = "YOUR RARE WORDS", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8) });

        if (data.RareWords.Count == 0)
        {
            sp.Children.Add(new TextBlock { Text = "Keep talking to discover your rare words!", FontSize = 12, Foreground = Brush("#6E6E73") });
            Content = sp;
            return;
        }

        var wrap = new WrapPanel();
        foreach (var (word, count) in data.RareWords)
        {
            var border = new Border
            {
                Background = Brush("#1C1C21"), BorderBrush = Brush("#2A2A32"),
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16),
                Padding = new Thickness(12, 6, 12, 6), Margin = new Thickness(0, 0, 8, 8)
            };
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock { Text = word, FontSize = 12, Foreground = Brush("#F5F5F7") });
            row.Children.Add(new Border
            {
                Background = Brush("#0D0D0F"), CornerRadius = new CornerRadius(8),
                Padding = new Thickness(6, 2, 6, 2), Margin = new Thickness(6, 0, 0, 0),
                Child = new TextBlock { Text = count.ToString(), FontSize = 10, Foreground = Brush("#6E6E73") }
            });
            border.Child = row;
            wrap.Children.Add(border);
        }
        sp.Children.Add(wrap);
        Content = sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>WPM by hour bar chart.</summary>
public class WpmByHourCard : UserControl
{
    public WpmByHourCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) { Content = null; return; }

        var values = data.AvgWpmByHour.Select(v => v.HasValue ? (double)v.Value : 0).ToArray();
        if (values.All(v => v == 0)) { Content = null; return; }

        Content = ChartHelper.CreateBarChart(values, Enumerable.Range(0, 24).Select(h => $"{h}:00").ToArray(),
            "#FBBF24", "WPM BY HOUR OF DAY");
    }
}

/// <summary>Session length histogram.</summary>
public class SessionHistogramCard : UserControl
{
    public SessionHistogramCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.SessionDurations.Count == 0) { Content = null; return; }

        // Create histogram bins
        double maxDur = Math.Min(data.SessionDurations.Max(), 60);
        int binCount = 12;
        double binWidth = maxDur / binCount;
        var bins = new int[binCount];

        foreach (var dur in data.SessionDurations.Where(d => d <= maxDur))
        {
            int bin = Math.Min((int)(dur / binWidth), binCount - 1);
            bins[bin]++;
        }

        var labels = Enumerable.Range(0, binCount).Select(i => $"{(int)(i * binWidth)}s").ToArray();
        Content = ChartHelper.CreateBarChart(bins.Select(b => (double)b).ToArray(), labels,
            "#A78BFA", "SESSION LENGTH DISTRIBUTION");
    }
}

/// <summary>Sentiment over time dual area chart.</summary>
public class SentimentChartCard : UserControl
{
    public SentimentChartCard() { DataContextChanged += (_, _) => Rebuild(); }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.SentimentArray.Count == 0) { Content = null; return; }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = "SENTIMENT OVER TIME", FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Brush("#6E6E73"), Margin = new Thickness(0, 0, 0, 8) });

        var positive = data.SentimentArray.Select(s => Math.Max(0, s.Score)).ToArray();
        var negative = data.SentimentArray.Select(s => Math.Min(0, s.Score)).ToArray();

        var series = new ISeries[]
        {
            new LineSeries<double>
            {
                Values = positive,
                Fill = new SolidColorPaint(SKColor.Parse("#34D399").WithAlpha(80)),
                Stroke = new SolidColorPaint(SKColor.Parse("#34D399"), 2),
                GeometrySize = 0,
                LineSmoothness = 0.7,
            },
            new LineSeries<double>
            {
                Values = negative,
                Fill = new SolidColorPaint(SKColor.Parse("#FB923C").WithAlpha(80)),
                Stroke = new SolidColorPaint(SKColor.Parse("#FB923C"), 2),
                GeometrySize = 0,
                LineSmoothness = 0.7,
            }
        };

        var chart = new CartesianChart
        {
            Series = series,
            Height = 130,
            XAxes = new[] { new Axis { IsVisible = false } },
            YAxes = new[] { new Axis { LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")), SeparatorsPaint = new SolidColorPaint(SKColor.Parse("#2A2A32")) } },
        };
        sp.Children.Add(chart);

        // Legend
        var legend = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        legend.Children.Add(CreateLegendItem("#34D399", "Positive"));
        legend.Children.Add(CreateLegendItem("#FB923C", "Negative"));
        sp.Children.Add(legend);

        Content = sp;
    }

    private static StackPanel CreateLegendItem(string color, string label)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 10, 0) };
        sp.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = Brush(color), Margin = new Thickness(0, 0, 6, 0) });
        sp.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = Brush("#6E6E73") });
        return sp;
    }

    private static SolidColorBrush Brush(string hex) =>
        new((Color)ColorConverter.ConvertFromString(hex));
}

/// <summary>Helper to create common LiveCharts2 chart types.</summary>
internal static class ChartHelper
{
    public static StackPanel CreateAreaChart(double[] values, string[] labels, string color, string title)
    {
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = title, FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
            Margin = new Thickness(0, 0, 0, 8)
        });

        var skColor = SKColor.Parse(color);
        var series = new ISeries[]
        {
            new LineSeries<double>
            {
                Values = values,
                Fill = new SolidColorPaint(skColor.WithAlpha(50)),
                Stroke = new SolidColorPaint(skColor, 2),
                GeometrySize = 6,
                GeometryFill = new SolidColorPaint(skColor),
                GeometryStroke = new SolidColorPaint(skColor, 2),
                LineSmoothness = 0.7,
            }
        };

        var chart = new CartesianChart
        {
            Series = series,
            Height = 140,
            XAxes = new[] { new Axis
            {
                Labels = labels.Length <= 10 ? labels : labels.Where((_, i) => i % (labels.Length / 5 + 1) == 0).ToArray(),
                LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")),
                TextSize = 9,
            }},
            YAxes = new[] { new Axis
            {
                LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")),
                SeparatorsPaint = new SolidColorPaint(SKColor.Parse("#2A2A32")),
                TextSize = 9,
            }},
        };

        sp.Children.Add(chart);
        return sp;
    }

    public static StackPanel CreateLineChart(double[] values, string[] labels, string color, string title)
    {
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = title, FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
            Margin = new Thickness(0, 0, 0, 8)
        });

        var skColor = SKColor.Parse(color);
        var series = new ISeries[]
        {
            new LineSeries<double>
            {
                Values = values,
                Stroke = new SolidColorPaint(skColor, 2),
                GeometrySize = 8,
                GeometryFill = new SolidColorPaint(skColor),
                GeometryStroke = new SolidColorPaint(skColor, 2),
                LineSmoothness = 0.7,
                Fill = null,
            }
        };

        var chart = new CartesianChart
        {
            Series = series,
            Height = 140,
            XAxes = new[] { new Axis { IsVisible = false } },
            YAxes = new[] { new Axis
            {
                LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")),
                SeparatorsPaint = new SolidColorPaint(SKColor.Parse("#2A2A32")),
                TextSize = 9,
            }},
        };

        sp.Children.Add(chart);
        return sp;
    }

    public static StackPanel CreateBarChart(double[] values, string[] labels, string color, string title)
    {
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = title, FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
            Margin = new Thickness(0, 0, 0, 8)
        });

        var skColor = SKColor.Parse(color);
        var series = new ISeries[]
        {
            new ColumnSeries<double>
            {
                Values = values,
                Fill = new SolidColorPaint(skColor),
                Rx = 2, Ry = 2,
            }
        };

        var chart = new CartesianChart
        {
            Series = series,
            Height = 120,
            XAxes = new[] { new Axis
            {
                Labels = labels.Length <= 12 ? labels : labels.Where((_, i) => i % (labels.Length / 6 + 1) == 0).ToArray(),
                LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")),
                TextSize = 9,
            }},
            YAxes = new[] { new Axis
            {
                LabelsPaint = new SolidColorPaint(SKColor.Parse("#6E6E73")),
                SeparatorsPaint = new SolidColorPaint(SKColor.Parse("#2A2A32")),
                TextSize = 9,
            }},
        };

        sp.Children.Add(chart);
        return sp;
    }
}
