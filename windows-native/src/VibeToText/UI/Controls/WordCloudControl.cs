using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using VibeToText.Models;

namespace VibeToText.UI.Controls;

/// <summary>
/// Word cloud with sized text. Port of renderWordCloud from analytics.js.
/// </summary>
public class WordCloudControl : UserControl
{
    private static readonly HashSet<string> StopWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "the","a","an","and","or","but","in","on","at","to","for","of","with","by","from",
        "as","is","was","are","were","been","be","have","has","had","do","does","did","will",
        "would","could","should","may","might","must","shall","can","need","i","you","he","she",
        "it","we","they","me","him","her","my","your","his","its","our","their","this","that",
        "these","what","which","who","where","when","why","how","all","each","some","no","not",
        "only","so","than","too","very","just","also","now","here","there","then","if","because",
        "about","any","up","down","out","off","over","going","gonna","like","okay","ok","yeah",
        "yes","um","uh","ah","oh","well","right","actually","basically","really","thing","things",
        "something","know","think","want","get","got","make","way","see","go","one","two"
    };

    public WordCloudControl()
    {
        DataContextChanged += (_, _) => Rebuild();
    }

    private void Rebuild()
    {
        if (DataContext is not AnalyticsData data || data.WordFrequency.Count == 0)
        {
            Content = null;
            return;
        }

        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = "WORD CLOUD", FontSize = 10, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
            Margin = new Thickness(0, 0, 0, 8)
        });

        var words = data.WordFrequency
            .Where(kv => kv.Key.Length > 2 && !StopWords.Contains(kv.Key) && kv.Value >= 2)
            .OrderByDescending(kv => kv.Value)
            .Take(40)
            .ToList();

        if (words.Count == 0)
        {
            sp.Children.Add(new TextBlock
            {
                Text = "No data yet", FontSize = 12,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#6E6E73")),
                HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 20, 0, 0)
            });
            Content = sp;
            return;
        }

        int maxCount = words.First().Value;
        int minCount = words.Last().Value;

        var wrap = new WrapPanel
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 8, 0, 0)
        };

        foreach (var (word, count) in words)
        {
            double size = 12 + (double)(count - minCount) / Math.Max(maxCount - minCount, 1) * 24;
            var tb = new TextBlock
            {
                Text = word,
                FontSize = size,
                FontWeight = size > 20 ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#A1A1A6")),
                Margin = new Thickness(4),
                Cursor = System.Windows.Input.Cursors.Arrow,
                ToolTip = $"{word}: {count}"
            };
            wrap.Children.Add(tb);
        }

        sp.Children.Add(wrap);
        Content = sp;
    }
}
