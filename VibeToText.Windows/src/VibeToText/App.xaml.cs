using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using H.NotifyIcon;
using VibeToText.Core;
using VibeToText.Data;
using VibeToText.UI;
using VibeToText.ViewModels;

namespace VibeToText;

public partial class App : Application
{
    private TaskbarIcon? _trayIcon;
    private MainWindow? _mainWindow;
    private TranscriptionPipeline? _pipeline;
    private HotkeyManager? _hotkeyManager;
    private Mutex? _singleInstanceMutex;

    // Shared services
    public static ConfigStore Config { get; private set; } = null!;
    public static HistoryDatabase Database { get; private set; } = null!;
    public static TranscriptionPipeline Pipeline { get; private set; } = null!;
    public static GeminiService Gemini { get; private set; } = null!;

    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".vibetotext", "vibetotext.log");

    private static void Log(string message)
    {
        try
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}] {message}";
            Console.WriteLine(line);
            File.AppendAllText(LogPath, line + Environment.NewLine);
        }
        catch { /* ignore log failures */ }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Ensure log directory exists
        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
        File.WriteAllText(LogPath, $"=== VibeToText starting {DateTime.Now} ==={Environment.NewLine}");

        // Global exception handlers
        DispatcherUnhandledException += (_, args) =>
        {
            Log($"[FATAL] Unhandled UI exception: {args.Exception}");
            args.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            Log($"[FATAL] Unhandled exception: {args.ExceptionObject}");
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Log($"[FATAL] Unobserved task exception: {args.Exception}");
            args.SetObserved();
        };

        try
        {
            // Single instance check
            _singleInstanceMutex = new Mutex(true, "VibeToText_SingleInstance", out bool isNew);
            if (!isNew)
            {
                Log("Another instance already running. Exiting.");
                Shutdown();
                return;
            }

            Log("Initializing services...");

            // Initialize services
            Config = new ConfigStore();
            Database = new HistoryDatabase();

            var recorder = new AudioRecorder();
            var transcriber = new WhisperTranscriber();
            var pasteService = new PasteService();
            Gemini = new GeminiService();

            _pipeline = new TranscriptionPipeline(recorder, transcriber, Database, pasteService, Gemini, Config);
            Pipeline = _pipeline;

            Log("Services initialized.");

            // Set up hotkey manager
            _hotkeyManager = new HotkeyManager();
            _hotkeyManager.HotkeyPressed += OnHotkeyPressed;
            _hotkeyManager.HotkeyReleased += OnHotkeyReleased;
            _hotkeyManager.Start();

            Log("Creating tray icon...");

            // Create system tray icon
            CreateTrayIcon();

            Log("Creating main window...");

            // Create main window
            _mainWindow = new MainWindow();
            Log("MainWindow created. Calling Show()...");
            _mainWindow.Show();

            Log("Startup complete. Window shown.");
        }
        catch (Exception ex)
        {
            Log($"[FATAL] Startup failed: {ex}");
            Shutdown();
        }
    }

    private void CreateTrayIcon()
    {
        try
        {
            _trayIcon = new TaskbarIcon
            {
                ToolTipText = "VibeToText - Voice to Text",
                Icon = CreateTrayIconImage(),
                ContextMenu = CreateTrayContextMenu(),
            };

            _trayIcon.TrayLeftMouseDown += (_, _) => ToggleMainWindow();
            Console.WriteLine("[APP] Tray icon created.");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[APP] Tray icon failed: {ex.Message}");
            // Continue without tray icon
        }
    }

    private static System.Drawing.Icon CreateTrayIconImage()
    {
        // Create a simple 16x16 icon programmatically
        using var bmp = new System.Drawing.Bitmap(16, 16);
        using var g = System.Drawing.Graphics.FromImage(bmp);
        g.Clear(System.Drawing.Color.FromArgb(13, 13, 15));

        var pink = System.Drawing.Color.FromArgb(255, 102, 153);
        using var pen = new System.Drawing.Pen(pink, 1);

        // Draw simple waveform bars
        int[] heights = { 3, 6, 10, 8, 12, 7, 5, 9, 11, 6, 4, 8 };
        for (int i = 0; i < heights.Length; i++)
        {
            int x = i + 2;
            int h = heights[i];
            int y1 = 8 - h / 2;
            int y2 = 8 + h / 2;
            g.DrawLine(pen, x, y1, x, y2);
        }

        var hIcon = bmp.GetHicon();
        return System.Drawing.Icon.FromHandle(hIcon);
    }

    private System.Windows.Controls.ContextMenu CreateTrayContextMenu()
    {
        var menu = new System.Windows.Controls.ContextMenu();

        var header = new System.Windows.Controls.MenuItem { Header = "VibeToText", IsEnabled = false };
        menu.Items.Add(header);

        menu.Items.Add(new System.Windows.Controls.Separator());

        var showItem = new System.Windows.Controls.MenuItem { Header = "Show History" };
        showItem.Click += (_, _) => ShowMainWindow();
        menu.Items.Add(showItem);

        var exitItem = new System.Windows.Controls.MenuItem { Header = "Exit" };
        exitItem.Click += (_, _) => ExitApplication();
        menu.Items.Add(exitItem);

        return menu;
    }

    private void ToggleMainWindow()
    {
        if (_mainWindow == null)
        {
            _mainWindow = new MainWindow();
            _mainWindow.Show();
            return;
        }

        if (_mainWindow.IsVisible)
        {
            _mainWindow.Hide();
        }
        else
        {
            _mainWindow.Show();
            _mainWindow.Activate();
        }
    }

    private void ShowMainWindow()
    {
        if (_mainWindow == null)
        {
            _mainWindow = new MainWindow();
        }
        _mainWindow.Show();
        _mainWindow.Activate();
    }

    private void OnHotkeyPressed(object? sender, HotkeyEventArgs e)
    {
        Dispatcher.Invoke(() => _pipeline?.StartRecording(e.Mode));
    }

    private void OnHotkeyReleased(object? sender, HotkeyEventArgs e)
    {
        Task.Run(() => _pipeline?.StopRecordingAndProcess(e.Mode));
    }

    private void ExitApplication()
    {
        _hotkeyManager?.Stop();
        _pipeline?.Dispose();
        _trayIcon?.Dispose();
        _singleInstanceMutex?.ReleaseMutex();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Stop();
        _pipeline?.Dispose();
        _trayIcon?.Dispose();
        _singleInstanceMutex?.ReleaseMutex();
        base.OnExit(e);
    }
}
