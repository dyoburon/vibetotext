using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using VibeToText.Models;

namespace VibeToText.UI.Controls;

/// <summary>
/// 7x24 activity heatmap (days x hours). Port of renderActivityHeatmap from analytics.js.
/// </summary>
public class ActivityHeatmapControl : UserControl
{
    private static readonly string[] DayLabels = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

    public ActivityHeatmapControl()
    {
        DataContextChanged += (_, _) => Rebuild();
    }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data) return;

        var canvas = new Canvas { Height = 120, ClipToBounds = true };

        const int cellW = 14, cellH = 11, gap = 2;
        const int marginLeft = 30, marginTop = 5;

        // Find max value
        int maxVal = 1;
        for (int d = 0; d < 7; d++)
            for (int h = 0; h < 24; h++)
                maxVal = Math.Max(maxVal, data.ActivityMatrix[d, h]);

        var bgColor = (Color)ColorConverter.ConvertFromString("#151518");
        var accentColor = (Color)ColorConverter.ConvertFromString("#FBBF24");

        for (int d = 0; d < 7; d++)
        {
            // Day label
            var label = new TextBlock
            {
                Text = DayLabels[d], FontSize = 9,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73"))
            };
            Canvas.SetLeft(label, 0);
            Canvas.SetTop(label, marginTop + d * (cellH + gap));
            canvas.Children.Add(label);

            for (int h = 0; h < 24; h++)
            {
                int value = data.ActivityMatrix[d, h];
                float t = (float)value / maxVal;

                var color = Color.FromRgb(
                    (byte)(bgColor.R + (accentColor.R - bgColor.R) * t),
                    (byte)(bgColor.G + (accentColor.G - bgColor.G) * t),
                    (byte)(bgColor.B + (accentColor.B - bgColor.B) * t)
                );

                var rect = new Rectangle
                {
                    Width = cellW, Height = cellH,
                    Fill = new SolidColorBrush(color),
                    RadiusX = 2, RadiusY = 2,
                    Stroke = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#2A2A32")),
                    StrokeThickness = 0.5,
                    ToolTip = $"{DayLabels[d]} {h}:00 - {value} transcription{(value != 1 ? "s" : "")}"
                };

                Canvas.SetLeft(rect, marginLeft + h * (cellW + gap));
                Canvas.SetTop(rect, marginTop + d * (cellH + gap));
                canvas.Children.Add(rect);
            }
        }

        // Hour labels
        foreach (int h in new[] { 0, 6, 12, 18 })
        {
            var label = new TextBlock
            {
                Text = $"{h}:00", FontSize = 9,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73"))
            };
            Canvas.SetLeft(label, marginLeft + h * (cellW + gap));
            Canvas.SetTop(label, marginTop + 7 * (cellH + gap) + 2);
            canvas.Children.Add(label);
        }

        Content = canvas;
    }
}
