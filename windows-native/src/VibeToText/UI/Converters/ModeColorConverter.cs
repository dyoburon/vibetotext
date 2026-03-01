using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace VibeToText.UI.Converters;

/// <summary>Converts a mode string to its background and foreground colors.</summary>
public class ModeBackgroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var mode = value as string ?? "transcribe";
        return mode.ToLower() switch
        {
            "transcribe" => Application.Current.FindResource("GreenSoftBrush"),
            "greppy" => Application.Current.FindResource("PurpleSoftBrush"),
            "cleanup" => Application.Current.FindResource("OrangeSoftBrush"),
            "plan" => Application.Current.FindResource("BlueSoftBrush"),
            _ => Application.Current.FindResource("BgTertiaryBrush"),
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

public class ModeForegroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var mode = value as string ?? "transcribe";
        return mode.ToLower() switch
        {
            "transcribe" => Application.Current.FindResource("GreenBrush"),
            "greppy" => Application.Current.FindResource("PurpleBrush"),
            "cleanup" => Application.Current.FindResource("OrangeBrush"),
            "plan" => Application.Current.FindResource("BlueBrush"),
            _ => Application.Current.FindResource("TextSecondaryBrush"),
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => (value is bool b && b) ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is Visibility v && v == Visibility.Visible;
}

public class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is Visibility v && v == Visibility.Collapsed;
}
