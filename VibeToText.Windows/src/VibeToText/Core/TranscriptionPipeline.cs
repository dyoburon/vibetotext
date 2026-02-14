using System.IO;
using VibeToText.Data;
using VibeToText.UI.Controls;

namespace VibeToText.Core;

/// <summary>
/// Orchestrates the full pipeline: hotkey -> record -> transcribe -> process -> paste.
/// Port of Python __main__.py on_start/on_stop.
/// </summary>
public class TranscriptionPipeline : IDisposable
{
    private readonly AudioRecorder _recorder;
    private readonly WhisperTranscriber _transcriber;
    private readonly HistoryDatabase _database;
    private readonly PasteService _pasteService;
    private readonly GeminiService _geminiService;
    private readonly ConfigStore _config;

    private WaveformOverlay? _overlay;
    private RecordingMode? _currentMode;

    public bool IsRecording => _recorder.IsRecording;

    private static void Log(string msg)
    {
        try
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}] [PIPELINE] {msg}";
            Console.WriteLine(line);
            var logPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".vibetotext", "pipeline.log");
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch { }
    }

    /// <summary>Fired when waveform levels update (for UI binding).</summary>
    public event Action<float[]>? OnWaveformUpdate;

    public TranscriptionPipeline(
        AudioRecorder recorder,
        WhisperTranscriber transcriber,
        HistoryDatabase database,
        PasteService pasteService,
        GeminiService geminiService,
        ConfigStore config)
    {
        _recorder = recorder;
        _transcriber = transcriber;
        _database = database;
        _pasteService = pasteService;
        _geminiService = geminiService;
        _config = config;

        _recorder.OnLevelUpdate += levels =>
        {
            OnWaveformUpdate?.Invoke(levels);
            System.Windows.Application.Current?.Dispatcher.InvokeAsync(() =>
            {
                _overlay?.UpdateLevels(levels);
            });
        };

        // Preload Whisper model in background
        Task.Run(async () =>
        {
            try
            {
                await _transcriber.EnsureModelAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[PIPELINE] Model preload failed: {ex.Message}");
            }
        });
    }

    public void StartRecording(RecordingMode mode)
    {
        try
        {
            Log($"StartRecording called: mode={mode}");

            // History mode: show main window, don't record
            if (mode == RecordingMode.History)
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    var mainWindow = System.Windows.Application.Current.MainWindow;
                    if (mainWindow != null)
                    {
                        mainWindow.Show();
                        mainWindow.Activate();
                    }
                });
                return;
            }

            _currentMode = mode;

            // Reload audio device from config
            _recorder.DeviceIndex = _config.AudioDeviceIndex;

            // Show waveform overlay
            Log("Showing waveform overlay...");
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                if (_overlay == null)
                {
                    _overlay = new WaveformOverlay();
                    Log("WaveformOverlay created.");
                }
                _overlay.Show();
                _overlay.SetRecording(true);
                Log("Overlay shown.");
            });

            Log("Starting audio recorder...");
            _recorder.Start();
            Log($"Recording started: {mode}");
        }
        catch (Exception ex)
        {
            Log($"ERROR starting recording: {ex}");
            _currentMode = null;
        }
    }

    public async Task StopRecordingAndProcess(RecordingMode mode)
    {
        try
        {
            Log($"StopRecordingAndProcess called: mode={mode}");
            if (mode == RecordingMode.History) return;

            var audio = _recorder.Stop();
            Log($"Recorder stopped, audio length: {audio.Length}");

            // Hide waveform overlay
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                _overlay?.SetRecording(false);
                _overlay?.Hide();
            });

            if (audio.Length == 0)
            {
                Log("No audio captured.");
                return;
            }

            var durationSeconds = (double)audio.Length / AudioRecorder.SampleRate;
            Log($"Captured {durationSeconds:F2}s of audio");

            // Transcribe
            Log("Transcribing...");
            var text = await _transcriber.TranscribeAsync(audio);

            if (string.IsNullOrWhiteSpace(text))
            {
                Log("No speech detected.");
                return;
            }

            // Filter noise markers
            var textLower = text.Trim().ToLowerInvariant();
            string[] noiseMarkers =
            {
                "[blank_audio]", "[blank audio]", "[ blank_audio ]", "[ blank audio ]",
                "[silence]", "[ silence ]", "(silence)", "( silence )",
                "[inaudible]", "[ inaudible ]", "(inaudible)", "( inaudible )",
                "[no speech]", "[ no speech ]", "(no speech)", "( no speech )",
            };
            if (noiseMarkers.Contains(textLower))
            {
                Log("Filtered noise marker.");
                return;
            }

            Log($"Transcribed: {text[..Math.Min(text.Length, 100)]}");

            // Mode-specific processing
            string output = text;
            switch (mode)
            {
                case RecordingMode.Cleanup:
                    var refined = await _geminiService.CleanupTextAsync(text);
                    output = refined ?? text;
                    break;
                case RecordingMode.Plan:
                    var plan = await _geminiService.GeneratePlanAsync(text);
                    output = plan ?? text;
                    break;
                case RecordingMode.Transcribe:
                default:
                    break;
            }

            // Save to history
            _database.AddEntry(text, mode.ToString().ToLower(), durationSeconds);
            Log("Saved to history.");

            // Paste at cursor
            await _pasteService.PasteAtCursorAsync(output);
            Log("Pasted at cursor.");

            _currentMode = null;
        }
        catch (Exception ex)
        {
            Log($"ERROR in processing: {ex}");
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                _overlay?.SetRecording(false);
                _overlay?.Hide();
            });
        }
    }

    public void Dispose()
    {
        _recorder.Dispose();
        _transcriber.Dispose();
    }
}
