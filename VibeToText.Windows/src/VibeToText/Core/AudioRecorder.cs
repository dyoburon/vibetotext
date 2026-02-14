using System.Numerics;
using NAudio.Wave;

namespace VibeToText.Core;

/// <summary>
/// Records audio from microphone with real-time FFT waveform visualization.
/// Port of Python AudioRecorder using NAudio.
/// </summary>
public class AudioRecorder : IDisposable
{
    public const int NumBars = 25;
    public const int FftSize = 512;
    public const float Smoothing = 0.7f; // 70% previous, 30% new
    public const float SilenceThreshold = 0.08f;
    public const int MinFreqBin = 4; // Skip sub-bass rumble
    public const int SampleRate = 16000;

    private WaveInEvent? _waveIn;
    private readonly List<float> _audioData = new();
    private float[] _prevLevels = new float[NumBars];
    private readonly object _lock = new();

    public bool IsRecording { get; private set; }
    public int? DeviceIndex { get; set; }

    /// <summary>Callback for real-time waveform levels (25 bars, 0-1 range).</summary>
    public event Action<float[]>? OnLevelUpdate;

    public void Start()
    {
        lock (_lock)
        {
            _audioData.Clear();
            _prevLevels = new float[NumBars];
            IsRecording = true;
        }

        _waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(SampleRate, 16, 1), // 16-bit mono
            BufferMilliseconds = 32,
            DeviceNumber = DeviceIndex ?? 0,
        };

        _waveIn.DataAvailable += OnDataAvailable;
        _waveIn.StartRecording();
    }

    public float[] Stop()
    {
        IsRecording = false;

        if (_waveIn != null)
        {
            _waveIn.StopRecording();
            _waveIn.DataAvailable -= OnDataAvailable;
            _waveIn.Dispose();
            _waveIn = null;
        }

        lock (_lock)
        {
            if (_audioData.Count == 0)
                return Array.Empty<float>();

            return _audioData.ToArray();
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (!IsRecording) return;

        // Convert 16-bit PCM to float32 (-1 to 1)
        int sampleCount = e.BytesRecorded / 2;
        var samples = new float[sampleCount];
        for (int i = 0; i < sampleCount; i++)
        {
            short sample = BitConverter.ToInt16(e.Buffer, i * 2);
            samples[i] = sample / 32768f;
        }

        lock (_lock)
        {
            _audioData.AddRange(samples);
        }

        // Calculate waveform visualization using FFT
        CalculateWaveform(samples);
    }

    private void CalculateWaveform(float[] audio)
    {
        // RMS gate
        float rms = 0;
        for (int i = 0; i < audio.Length; i++)
            rms += audio[i] * audio[i];
        rms = MathF.Sqrt(rms / audio.Length);
        float baseLevel = MathF.Min(1.0f, rms * 100);

        if (baseLevel < SilenceThreshold)
        {
            // Smooth decay to zero
            for (int i = 0; i < NumBars; i++)
                _prevLevels[i] *= Smoothing;
            OnLevelUpdate?.Invoke(_prevLevels.ToArray());
            return;
        }

        // Prepare FFT input
        int fftLen = FftSize;
        var fftBuffer = new Complex[fftLen];
        var hanningWindow = new float[fftLen];
        for (int i = 0; i < fftLen; i++)
            hanningWindow[i] = 0.5f * (1 - MathF.Cos(2 * MathF.PI * i / (fftLen - 1)));

        for (int i = 0; i < fftLen; i++)
        {
            float sample = i < audio.Length ? audio[i] * hanningWindow[i] : 0;
            fftBuffer[i] = new Complex(sample, 0);
        }

        // In-place FFT
        Fft(fftBuffer);

        // Compute magnitude spectrum
        int specLen = fftLen / 2 + 1;
        var spectrum = new float[specLen];
        for (int i = 0; i < specLen; i++)
        {
            double mag = fftBuffer[i].Magnitude;
            spectrum[i] = (float)Math.Max(mag, 1e-10);
        }

        // Convert to dB-like scale, normalize
        var spectrumNorm = new float[specLen];
        for (int i = 0; i < specLen; i++)
        {
            float db = 20f * MathF.Log10(spectrum[i]);
            spectrumNorm[i] = Math.Clamp((db + 60f) / 60f, 0f, 1f);
        }

        int usableBins = specLen - MinFreqBin;
        var levels = new float[NumBars];

        // Exponential frequency band mapping
        for (int i = 0; i < NumBars; i++)
        {
            float loFrac = MathF.Pow((float)i / NumBars, 2.5f);
            float hiFrac = MathF.Pow((float)(i + 1) / NumBars, 2.5f);
            int lo = (int)(MinFreqBin + usableBins * loFrac);
            int hi = (int)(MinFreqBin + usableBins * hiFrac);
            hi = Math.Max(hi, lo + 1);
            hi = Math.Min(hi, specLen);

            float avg = 0;
            int count = 0;
            for (int j = lo; j < hi; j++)
            {
                avg += spectrumNorm[j];
                count++;
            }
            avg /= Math.Max(count, 1);

            // Bass reduction for first few bars
            if (i < 4)
                avg *= 0.5f + i * 0.125f;

            levels[i] = avg;
        }

        // Temporal smoothing
        for (int i = 0; i < NumBars; i++)
            levels[i] = _prevLevels[i] * Smoothing + levels[i] * (1 - Smoothing);

        _prevLevels = levels;
        OnLevelUpdate?.Invoke(levels.ToArray());
    }

    /// <summary>Simple Cooley-Tukey radix-2 FFT.</summary>
    private static void Fft(Complex[] buffer)
    {
        int n = buffer.Length;
        if (n <= 1) return;

        // Bit-reversal permutation
        for (int i = 1, j = 0; i < n; i++)
        {
            int bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1)
                j ^= bit;
            j ^= bit;

            if (i < j)
                (buffer[i], buffer[j]) = (buffer[j], buffer[i]);
        }

        // Butterfly computation
        for (int len = 2; len <= n; len <<= 1)
        {
            double angle = -2 * Math.PI / len;
            var wLen = new Complex(Math.Cos(angle), Math.Sin(angle));

            for (int i = 0; i < n; i += len)
            {
                var w = Complex.One;
                for (int j = 0; j < len / 2; j++)
                {
                    var u = buffer[i + j];
                    var v = buffer[i + j + len / 2] * w;
                    buffer[i + j] = u + v;
                    buffer[i + j + len / 2] = u - v;
                    w *= wLen;
                }
            }
        }
    }

    /// <summary>Get available audio input devices.</summary>
    public static List<(int Index, string Name)> GetInputDevices()
    {
        var devices = new List<(int, string)>();
        for (int i = 0; i < WaveInEvent.DeviceCount; i++)
        {
            var caps = WaveInEvent.GetCapabilities(i);
            devices.Add((i, caps.ProductName));
        }
        return devices;
    }

    public void Dispose()
    {
        _waveIn?.Dispose();
    }
}
