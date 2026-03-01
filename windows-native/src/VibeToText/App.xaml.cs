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

    private static string? _iconPath;

    private void CreateTrayIcon()
    {
        try
        {
            // Generate separate icons for tray (small) and window/taskbar (large)
            var appDataDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".vibetotext");
            var trayIcoPath = Path.Combine(appDataDir, "tray.ico");
            _iconPath = Path.Combine(appDataDir, "vibetotext.ico");
            GenerateIcoFile(trayIcoPath, trayOnly: true);
            GenerateIcoFile(_iconPath, trayOnly: false);
            Log($"Icon files saved.");

            var icon = new System.Drawing.Icon(trayIcoPath);

            _trayIcon = new TaskbarIcon
            {
                ToolTipText = "VibeToText - Voice to Text",
                Icon = icon,
                ContextMenu = CreateTrayContextMenu(),
            };
            _trayIcon.ForceCreate(false);

            _trayIcon.TrayMouseDoubleClick += (_, _) => ToggleMainWindow();
            Log("Tray icon created and forced visible.");
        }
        catch (Exception ex)
        {
            Log($"Tray icon failed: {ex.Message}\n{ex.StackTrace}");
        }
    }

    /// <summary>
    /// Returns a BitmapImage for the window icon (WPF uses ImageSource, not System.Drawing.Icon).
    /// </summary>
    public static ImageSource? GetWindowIcon()
    {
        try
        {
            if (_iconPath != null && File.Exists(_iconPath))
            {
                var bi = new BitmapImage();
                bi.BeginInit();
                bi.UriSource = new Uri(_iconPath);
                bi.CacheOption = BitmapCacheOption.OnLoad;
                bi.EndInit();
                bi.Freeze();
                return bi;
            }
        }
        catch { }
        return null;
    }

    private static void GenerateIcoFile(string path, bool trayOnly)
    {
        // Tray: small sizes with original compact text. Taskbar: large sizes with big text.
        var sizes = trayOnly ? new[] { 16, 32 } : new[] { 16, 32, 48, 64, 256 };
        var pngDataList = new List<byte[]>();
        foreach (var size in sizes)
            pngDataList.Add(RenderVttPng(size, trayOnly));

        using var fs = File.Create(path);
        using var w = new BinaryWriter(fs);

        // ICO header
        w.Write((short)0);              // Reserved
        w.Write((short)1);              // Type: ICO
        w.Write((short)sizes.Length);   // Image count

        // Directory entries
        int dataOffset = 6 + sizes.Length * 16;
        for (int i = 0; i < sizes.Length; i++)
        {
            w.Write((byte)(sizes[i] < 256 ? sizes[i] : 0));
            w.Write((byte)(sizes[i] < 256 ? sizes[i] : 0));
            w.Write((byte)0);           // Colors (0 = no palette)
            w.Write((byte)0);           // Reserved
            w.Write((short)1);          // Color planes
            w.Write((short)32);         // Bits per pixel
            w.Write(pngDataList[i].Length);
            w.Write(dataOffset);
            dataOffset += pngDataList[i].Length;
        }

        // Image data (PNG format is valid inside ICO)
        foreach (var png in pngDataList)
            w.Write(png);
    }

    private static byte[] RenderVttPng(int size, bool trayStyle = false)
    {
        using var bmp = new System.Drawing.Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = System.Drawing.Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        if (trayStyle)
        {
            // Tray icon: dark bg, pink border, white text (original look)
            g.Clear(System.Drawing.Color.FromArgb(255, 30, 30, 34));
            var accent = System.Drawing.Color.FromArgb(255, 255, 102, 153);
            using var pen = new System.Drawing.Pen(accent, 1f);
            g.DrawRectangle(pen, 0.5f, 0.5f, size - 1f, size - 1f);

            float fontSize = size >= 32 ? 11f : 6.5f;
            using var font = new System.Drawing.Font("Segoe UI", fontSize, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Pixel);
            using var brush = new System.Drawing.SolidBrush(System.Drawing.Color.White);
            var sf = new System.Drawing.StringFormat { Alignment = System.Drawing.StringAlignment.Center, LineAlignment = System.Drawing.StringAlignment.Center };
            g.DrawString("VTT", font, brush, new System.Drawing.RectangleF(0, 0, size, size), sf);
        }
        else
        {
            // Taskbar icon: same dark style as tray, but a single large "V" that fills the space
            g.Clear(System.Drawing.Color.FromArgb(255, 30, 30, 34));
            var accent = System.Drawing.Color.FromArgb(255, 255, 102, 153);
            float bw = size >= 64 ? 2f : 1f;
            using var pen = new System.Drawing.Pen(accent, bw);
            g.DrawRectangle(pen, bw / 2, bw / 2, size - bw, size - bw);

            float fontSize = size switch { >= 256 => 200f, >= 64 => 48f, >= 48 => 36f, >= 32 => 24f, _ => 12f };
            using var font = new System.Drawing.Font("Segoe UI", fontSize, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Pixel);
            using var brush = new System.Drawing.SolidBrush(System.Drawing.Color.White);
            var sf = new System.Drawing.StringFormat { Alignment = System.Drawing.StringAlignment.Center, LineAlignment = System.Drawing.StringAlignment.Center };
            g.DrawString("V", font, brush, new System.Drawing.RectangleF(0, 0, size, size), sf);
        }

        using var ms = new MemoryStream();
        bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
        return ms.ToArray();
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
