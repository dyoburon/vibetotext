using System.IO;
using System.Runtime.InteropServices;
using System.Windows;

namespace VibeToText.Core;

/// <summary>
/// Copies text to clipboard and simulates Ctrl+V to paste at cursor.
/// Uses Win32 SendInput directly for maximum compatibility.
/// </summary>
public class PasteService
{
    private static void Log(string msg)
    {
        try
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}] [PASTE] {msg}";
            Console.WriteLine(line);
            var logPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".vibetotext", "paste.log");
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch { }
    }

    public async Task PasteAtCursorAsync(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        Log($"Pasting {text.Length} chars...");

        // Copy to clipboard (must run on STA thread)
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            Clipboard.SetText(text);
        });

        Log("Clipboard set.");

        // First, release ALL modifier keys to ensure clean state
        ReleaseAllModifiers();

        // Wait for modifiers to fully release
        await Task.Delay(250);

        // Simulate Ctrl+V using SendInput
        try
        {
            Log($"INPUT struct size: {Marshal.SizeOf<INPUT>()}");
            var result = SimulateCtrlV();
            Log($"SendInput returned {result} (expected 4). GetLastError={Marshal.GetLastWin32Error()}");
        }
        catch (Exception ex)
        {
            Log($"Auto-paste failed: {ex.Message}");
            PlayNotificationSound();
        }
    }

    private static void ReleaseAllModifiers()
    {
        var releases = new INPUT[]
        {
            MakeKeyInput(VK_LSHIFT, true),
            MakeKeyInput(VK_RSHIFT, true),
            MakeKeyInput(VK_LCONTROL, true),
            MakeKeyInput(VK_RCONTROL, true),
            MakeKeyInput(VK_LMENU, true),
            MakeKeyInput(VK_RMENU, true),
        };

        var result = SendInput((uint)releases.Length, releases, Marshal.SizeOf<INPUT>());
        Log($"Released modifiers: SendInput returned {result}");
    }

    private static uint SimulateCtrlV()
    {
        var inputs = new INPUT[]
        {
            MakeKeyInput(VK_LCONTROL, false),
            MakeKeyInput(VK_V, false),
            MakeKeyInput(VK_V, true),
            MakeKeyInput(VK_LCONTROL, true),
        };

        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT MakeKeyInput(ushort vk, bool keyUp)
    {
        var input = new INPUT { type = INPUT_KEYBOARD };
        input.u.ki.wVk = vk;
        input.u.ki.wScan = (ushort)MapVirtualKey(vk, MAPVK_VK_TO_VSC);
        input.u.ki.dwFlags = keyUp ? KEYEVENTF_KEYUP : 0;
        input.u.ki.time = 0;
        input.u.ki.dwExtraInfo = IntPtr.Zero;
        return input;
    }

    private static void PlayNotificationSound()
    {
        try { System.Media.SystemSounds.Beep.Play(); } catch { }
    }

    // Win32 constants
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint MAPVK_VK_TO_VSC = 0;

    private const ushort VK_LCONTROL = 0xA2;
    private const ushort VK_RCONTROL = 0xA3;
    private const ushort VK_LSHIFT = 0xA0;
    private const ushort VK_RSHIFT = 0xA1;
    private const ushort VK_LMENU = 0xA4;
    private const ushort VK_RMENU = 0xA5;
    private const ushort VK_V = 0x56;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    // Correct Win32 INPUT struct layout for x64.
    // The union must be the size of the LARGEST member (MOUSEINPUT = 32 bytes on x64).
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion u;
    }
}
