using System.Diagnostics;
using System.IO;
using System.Speech.Synthesis;
using VibeToText.Data;

namespace VibeToText.Core;

/// <summary>
/// Fire-and-forget text-to-speech for status reports.
/// Primary: edge-tts (neural voice) + ffplay for playback.
/// Fallback: System.Speech.Synthesis (built-in SAPI).
/// </summary>
public class TtsService : IDisposable
{
    private SpeechSynthesizer? _synth;
    private readonly ConfigStore _config;
    private readonly object _lock = new();
    private Process? _ffplayProcess;
    private static readonly string TempMp3Path = Path.Combine(Path.GetTempPath(), "vibetotext_tts.mp3");

    // edge-tts defaults
    private const string DefaultVoice = "en-GB-RyanNeural";

    public TtsService(ConfigStore config)
    {
        _config = config;
        try
        {
            _synth = new SpeechSynthesizer();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[TTS] Failed to initialize SAPI fallback: {ex.Message}");
        }
    }

    /// <summary>
    /// Speak text using edge-tts (neural) with SAPI fallback. Fire-and-forget.
    /// </summary>
    public void Speak(string text)
    {
        if (!_config.TtsEnabled || string.IsNullOrWhiteSpace(text))
            return;

        // Cancel any previous speech
        StopPlayback();

        // Run everything in background so we don't block
        Task.Run(() =>
        {
            try
            {
                SpeakEdgeTts(text);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[TTS] edge-tts failed, falling back to SAPI: {ex.Message}");
                try
                {
                    SpeakSapiFallback(text);
                }
                catch (Exception ex2)
                {
                    Console.WriteLine($"[TTS] SAPI fallback also failed: {ex2.Message}");
                }
            }
        });
    }

    /// <summary>
    /// Stop current playback (kill ffplay or cancel SAPI).
    /// </summary>
    public void StopPlayback()
    {
        lock (_lock)
        {
            // Kill ffplay if running
            if (_ffplayProcess != null)
            {
                try
                {
                    if (!_ffplayProcess.HasExited)
                        _ffplayProcess.Kill();
                    _ffplayProcess.Dispose();
                }
                catch { }
                _ffplayProcess = null;
            }

            // Cancel SAPI if running
            try { _synth?.SpeakAsyncCancelAll(); }
            catch { }
        }
    }

    private void SpeakEdgeTts(string text)
    {
        var voice = _config.TtsVoice;
        if (string.IsNullOrEmpty(voice))
            voice = DefaultVoice;
        var rate = _config.TtsEdgeRate;
        var pitch = _config.TtsEdgePitch;

        // Step 1: Generate mp3 with edge-tts CLI
        var edgeProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "edge-tts",
                Arguments = $"--voice \"{voice}\" --rate \"{rate}\" --pitch \"{pitch}\" --text \"{EscapeArg(text)}\" --write-media \"{TempMp3Path}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            }
        };

        edgeProcess.Start();
        // Consume stdout/stderr to prevent deadlock
        edgeProcess.StandardOutput.ReadToEnd();
        edgeProcess.StandardError.ReadToEnd();

        if (!edgeProcess.WaitForExit(15_000)) // 15 second timeout
        {
            try { edgeProcess.Kill(); } catch { }
            throw new TimeoutException("edge-tts timed out after 15 seconds");
        }

        if (edgeProcess.ExitCode != 0)
            throw new InvalidOperationException($"edge-tts exited with code {edgeProcess.ExitCode}");

        if (!File.Exists(TempMp3Path) || new FileInfo(TempMp3Path).Length == 0)
            throw new FileNotFoundException("edge-tts did not produce an output file");

        // Step 2: Play with ffplay
        var ffplay = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "ffplay",
                Arguments = $"-nodisp -autoexit -loglevel quiet \"{TempMp3Path}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
            }
        };

        lock (_lock)
        {
            ffplay.Start();
            _ffplayProcess = ffplay;
        }

        // Wait for playback to complete (don't leave zombie processes)
        ffplay.WaitForExit();
    }

    private void SpeakSapiFallback(string text)
    {
        if (_synth == null)
            throw new InvalidOperationException("SAPI SpeechSynthesizer not available");

        // Apply settings
        // SAPI rate: -10 to 10, WPM 185 ~ -1 (slightly slower for Jarvis feel)
        _synth.Rate = Math.Clamp((_config.TtsRate - 200) / 20, -10, 10);
        _synth.Volume = Math.Clamp(_config.TtsVolume, 0, 100);

        var voice = _config.TtsVoice;
        if (string.IsNullOrEmpty(voice))
            voice = "Microsoft David Desktop"; // Deep male - Jarvis vibe
        try { _synth.SelectVoice(voice); }
        catch { /* voice not found, use default */ }

        _synth.SpeakAsync(text);
    }

    /// <summary>Escape double quotes in text for CLI argument.</summary>
    private static string EscapeArg(string text)
    {
        return text
            .Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("\r", " ")
            .Replace("\n", " ");
    }

    public static string GenerateStatusMessage(RecordingMode mode, string text, string output)
    {
        return mode switch
        {
            RecordingMode.Greppy => "Files located, sir",
            RecordingMode.Cleanup => $"All tidied up. {CountParagraphs(output)} paragraphs ready",
            RecordingMode.Plan => $"Plan's ready. {CountSteps(output)} steps laid out",
            RecordingMode.Feedback => "Feedback spoken, sir",
            _ => $"Got it. {CountWords(text)} words captured",
        };
    }

    private static int CountWords(string text) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    private static int CountParagraphs(string text) =>
        text.Split("\n\n", StringSplitOptions.RemoveEmptyEntries)
            .Count(p => !string.IsNullOrWhiteSpace(p));

    private static int CountSteps(string text) =>
        text.Split('\n')
            .Count(line =>
            {
                var trimmed = line.TrimStart();
                return System.Text.RegularExpressions.Regex.IsMatch(trimmed, @"^(\d+[\.\):]|[-*])\s");
            });

    public void Dispose()
    {
        StopPlayback();
        try
        {
            _synth?.Dispose();
        }
        catch { }
        _synth = null;

        // Clean up temp file
        try
        {
            if (File.Exists(TempMp3Path))
                File.Delete(TempMp3Path);
        }
        catch { }
    }
}
