using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace VibeToText.UI.Controls;

/// <summary>
/// Floating waveform overlay window. Port of Python ui_tkinter.py WaveformWindow.
/// Borderless, transparent, topmost window positioned at bottom-center of screen.
/// </summary>
public partial class WaveformOverlay : Window
{
    private const int NumBars = 25;
    private readonly Rectangle[] _bars = new Rectangle[NumBars];
    private float[] _levels = new float[NumBars];
    private bool _isRecording;

    private static readonly Color PinkColor = (Color)ColorConverter.ConvertFromString("#FF6699");
    private static readonly Color GrayColor = (Color)ColorConverter.ConvertFromString("#595959");

    public WaveformOverlay()
    {
        InitializeComponent();

        // Position at bottom center of primary screen
        var screen = SystemParameters.PrimaryScreenWidth;
        var screenH = SystemParameters.PrimaryScreenHeight;
        Left = (screen - Width) / 2;
        Top = screenH - Height - 40;

        // Create bars
        for (int i = 0; i < NumBars; i++)
        {
            var bar = new Rectangle
            {
                Fill = new SolidColorBrush(GrayColor),
                RadiusX = 2,
                RadiusY = 2,
            };
            _bars[i] = bar;
            WaveformCanvas.Children.Add(bar);
        }

        SizeChanged += (_, _) => DrawBars();
        Loaded += (_, _) => DrawBars();
    }

    public void SetRecording(bool recording)
    {
        _isRecording = recording;
        if (!recording)
        {
            _levels = new float[NumBars];
        }
        DrawBars();
    }

    public void UpdateLevels(float[] levels)
    {
        if (!_isRecording) return;

        // Smooth levels
        for (int i = 0; i < NumBars && i < levels.Length; i++)
        {
            if (levels[i] > _levels[i])
                _levels[i] = levels[i];
            else
                _levels[i] = _levels[i] * 0.86f + levels[i] * 0.14f;
        }

        Dispatcher.InvokeAsync(DrawBars);
    }

    private void DrawBars()
    {
        double canvasW = WaveformCanvas.ActualWidth;
        double canvasH = WaveformCanvas.ActualHeight;
        if (canvasW <= 0 || canvasH <= 0) return;

        double padding = canvasW * 0.05;
        double usableWidth = canvasW - padding * 2;
        double barSpacing = usableWidth * 0.02;
        double totalSpacing = barSpacing * (NumBars - 1);
        double barWidth = (usableWidth - totalSpacing) / NumBars;
        double centerY = canvasH / 2;

        var brush = new SolidColorBrush(_isRecording ? PinkColor : GrayColor);

        for (int i = 0; i < NumBars; i++)
        {
            var bar = _bars[i];
            bar.Fill = brush;
            bar.Width = Math.Max(1, barWidth);

            double level = i < _levels.Length ? _levels[i] : 0;
            double minHeight = Math.Max(2, canvasH * 0.1);
            double barHeight;

            if (_isRecording)
            {
                barHeight = Math.Max(minHeight, level * canvasH * 0.85);
                barHeight = Math.Min(barHeight, canvasH * 0.95);
            }
            else
            {
                barHeight = minHeight;
            }

            bar.Height = barHeight;

            double x = padding + i * (barWidth + barSpacing);
            double y = centerY - barHeight / 2;

            System.Windows.Controls.Canvas.SetLeft(bar, x);
            System.Windows.Controls.Canvas.SetTop(bar, y);
        }
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Don't actually close, just hide
        e.Cancel = true;
        Hide();
    }
}
