using System.Windows;
using VibeToText.ViewModels;

namespace VibeToText.UI;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();

        // Set window/taskbar icon
        var icon = App.GetWindowIcon();
        if (icon != null)
            Icon = icon;
    }

    protected override void OnStateChanged(EventArgs e)
    {
        // Minimize to tray instead of taskbar
        if (WindowState == WindowState.Minimized)
            Hide();
        base.OnStateChanged(e);
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Hide to tray instead of closing
        e.Cancel = true;
        Hide();
    }
}
