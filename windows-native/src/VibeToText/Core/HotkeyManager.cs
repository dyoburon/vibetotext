using System.Diagnostics;
using System.Runtime.InteropServices;

namespace VibeToText.Core;

public enum RecordingMode
{
    Transcribe,
    Greppy,
    Cleanup,
    Plan,
    History
}

public class HotkeyEventArgs : EventArgs
{
    public RecordingMode Mode { get; set; }
}

/// <summary>
/// Global keyboard hook for hold-to-record hotkeys.
/// Uses Win32 SetWindowsHookEx with WH_KEYBOARD_LL.
/// </summary>
public class HotkeyManager : IDisposable
{
    // Hotkey definitions: set of modifier keys -> mode
    private readonly Dictionary<HashSet<ModKey>, RecordingMode> _hotkeys = new()
    {
        [new HashSet<ModKey> { ModKey.Ctrl, ModKey.Shift }] = RecordingMode.Transcribe,
        [new HashSet<ModKey> { ModKey.Alt, ModKey.Shift }] = RecordingMode.Cleanup,
        [new HashSet<ModKey> { ModKey.Ctrl, ModKey.Alt }] = RecordingMode.History,
    };

    private readonly HashSet<ModKey> _pressedKeys = new();
    private bool _isRecording;
    private RecordingMode _activeMode;
    private HashSet<ModKey>? _activeParts;
    private System.Threading.Timer? _timeoutTimer;
    private readonly object _lock = new();
    private readonly int _maxRecordingSeconds = 60;

    private IntPtr _hookId = IntPtr.Zero;
    private LowLevelKeyboardProc? _proc;

    public event EventHandler<HotkeyEventArgs>? HotkeyPressed;
    public event EventHandler<HotkeyEventArgs>? HotkeyReleased;

    public void Start()
    {
        _proc = HookCallback;
        _hookId = SetHook(_proc);
        if (_hookId == IntPtr.Zero)
        {
            int error = Marshal.GetLastWin32Error();
            Console.WriteLine($"[HOTKEY] FAILED to install keyboard hook! Win32 error: {error}");
        }
        else
        {
            Console.WriteLine($"[HOTKEY] Keyboard hook installed (handle: {_hookId}).");
        }
    }

    public void Stop()
    {
        if (_hookId != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
            Console.WriteLine("[HOTKEY] Keyboard hook removed.");
        }
        _timeoutTimer?.Dispose();
    }

    private enum ModKey
    {
        Ctrl,
        Shift,
        Alt,
        Win
    }

    private static ModKey? VkToModKey(int vkCode) => vkCode switch
    {
        0xA0 or 0xA1 or 0x10 => ModKey.Shift,   // VK_LSHIFT, VK_RSHIFT, VK_SHIFT
        0xA2 or 0xA3 or 0x11 => ModKey.Ctrl,     // VK_LCONTROL, VK_RCONTROL, VK_CONTROL
        0xA4 or 0xA5 or 0x12 => ModKey.Alt,       // VK_LMENU, VK_RMENU, VK_MENU
        0x5B or 0x5C => ModKey.Win,                 // VK_LWIN, VK_RWIN
        _ => null
    };

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            var modKey = VkToModKey(vkCode);

            if (modKey.HasValue)
            {
                bool isKeyDown = wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN;
                bool isKeyUp = wParam == (IntPtr)WM_KEYUP || wParam == (IntPtr)WM_SYSKEYUP;

                if (isKeyDown)
                    OnModKeyDown(modKey.Value);
                else if (isKeyUp)
                    OnModKeyUp(modKey.Value);
            }
        }

        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void OnModKeyDown(ModKey key)
    {
        _pressedKeys.Add(key);
        try
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}] [HOTKEY] Key down: {key} | Pressed: {string.Join("+", _pressedKeys)} | Recording: {_isRecording}";
            Console.WriteLine(line);
            var logPath = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".vibetotext", "hotkey.log");
            System.IO.File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch { /* ignore */ }

        if (!_isRecording)
        {
            // Sort by length descending to match most specific first
            foreach (var (parts, mode) in _hotkeys.OrderByDescending(h => h.Key.Count))
            {
                if (parts.IsSubsetOf(_pressedKeys))
                {
                    lock (_lock)
                    {
                        if (_isRecording) return; // Double-check
                        _isRecording = true;
                        _activeMode = mode;
                        _activeParts = parts;
                    }

                    // Start timeout timer
                    _timeoutTimer?.Dispose();
                    _timeoutTimer = new System.Threading.Timer(
                        _ => OnTimeout(),
                        null,
                        _maxRecordingSeconds * 1000,
                        Timeout.Infinite
                    );

                    Console.WriteLine($"[HOTKEY] Started recording: {mode}");
                    HotkeyPressed?.Invoke(this, new HotkeyEventArgs { Mode = mode });
                    break;
                }
            }
        }
    }

    private void OnModKeyUp(ModKey key)
    {
        lock (_lock)
        {
            if (_isRecording && _activeParts != null && _activeParts.Contains(key))
            {
                _timeoutTimer?.Dispose();
                var mode = _activeMode;
                _isRecording = false;
                _activeMode = default;
                _activeParts = null;
                _pressedKeys.Clear();

                Console.WriteLine($"[HOTKEY] Stopped recording: {mode}");
                HotkeyReleased?.Invoke(this, new HotkeyEventArgs { Mode = mode });
            }
            else
            {
                _pressedKeys.Remove(key);
            }
        }
    }

    private void OnTimeout()
    {
        lock (_lock)
        {
            if (_isRecording)
            {
                Console.WriteLine($"[HOTKEY] Recording timed out after {_maxRecordingSeconds}s");
                var mode = _activeMode;
                _isRecording = false;
                _activeMode = default;
                _activeParts = null;
                _pressedKeys.Clear();

                HotkeyReleased?.Invoke(this, new HotkeyEventArgs { Mode = mode });
            }
        }
    }

    public void Dispose()
    {
        Stop();
    }

    // Win32 interop
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    private static IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        // For WH_KEYBOARD_LL, Windows ignores hMod but requires it to be non-null.
        // Using user32.dll handle is reliable across all deployment modes including single-file.
        var hMod = GetModuleHandle("user32");
        if (hMod == IntPtr.Zero)
        {
            // Fallback: null returns the exe's own module handle
            hMod = GetModuleHandle(null!);
        }
        return SetWindowsHookEx(WH_KEYBOARD_LL, proc, hMod, 0);
    }
}
