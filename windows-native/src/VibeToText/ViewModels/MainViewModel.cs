using System.Collections.ObjectModel;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using VibeToText.Data;
using VibeToText.Models;

namespace VibeToText.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly HistoryDatabase _database;
    private readonly ConfigStore _config;
    private readonly DispatcherTimer _refreshTimer;

    [ObservableProperty] private string _currentTab = "all";
    [ObservableProperty] private int _totalSessions;
    [ObservableProperty] private int _totalWords;
    [ObservableProperty] private int _avgWpm;
    [ObservableProperty] private double _timeSavedMinutes;

    [ObservableProperty] private ObservableCollection<HistoryEntry> _entries = new();
    [ObservableProperty] private ObservableCollection<WordChip> _commonWords = new();
    [ObservableProperty] private AnalyticsData? _analyticsData;

    [ObservableProperty] private bool _hasEntries;
    [ObservableProperty] private bool _showEntries = true;
    [ObservableProperty] private bool _showAnalytics;
    [ObservableProperty] private bool _showMicrophone;
    [ObservableProperty] private bool _showDictionary;
    [ObservableProperty] private bool _showSettings;

    // Microphone settings
    [ObservableProperty] private ObservableCollection<AudioDeviceItem> _audioDevices = new();
    [ObservableProperty] private int _selectedDeviceIndex;
    [ObservableProperty] private string _micStatusText = "";

    // Dictionary settings
    [ObservableProperty] private ObservableCollection<string> _dictionaryWords = new();
    [ObservableProperty] private string _newDictionaryWord = "";
    [ObservableProperty] private string _dictStatusText = "";

    // Settings
    [ObservableProperty] private string _geminiApiKey = "";
    [ObservableProperty] private string _settingsStatusText = "";
    [ObservableProperty] private bool _geminiKeyConfigured;

    // Whisper model
    [ObservableProperty] private string _selectedWhisperModel = "base";
    [ObservableProperty] private string _modelStatusText = "";
    [ObservableProperty] private bool _isModelChanging;
    public string[] AvailableWhisperModels => Core.WhisperTranscriber.AvailableModels;

    public MainViewModel()
    {
        _database = App.Database;
        _config = App.Config;

        _database.EntriesChanged += () =>
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(Refresh);
        };

        // Auto-refresh timer for timestamps
        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _refreshTimer.Tick += (_, _) => RefreshTimestamps();
        _refreshTimer.Start();

        // Load dictionary words
        DictionaryWords = new ObservableCollection<string>(_config.CustomDictionary);

        // Load Gemini API key (masked display)
        GeminiApiKey = _config.GeminiApiKey ?? "";
        GeminiKeyConfigured = App.Gemini.HasApiKey;

        // Load whisper model
        SelectedWhisperModel = _config.WhisperModel;

        Refresh();
    }

    [RelayCommand]
    private void SwitchTab(string tab)
    {
        CurrentTab = tab;
        ShowEntries = tab is "all" or "transcribe" or "greppy" or "cleanup" or "plan";
        ShowAnalytics = tab == "analytics";
        ShowMicrophone = tab == "microphone";
        ShowDictionary = tab == "dictionary";
        ShowSettings = tab == "settings";

        if (ShowMicrophone)
            LoadAudioDevices();

        Refresh();
    }

    public void Refresh()
    {
        var mode = CurrentTab is "analytics" or "microphone" or "dictionary" ? "all" : CurrentTab;

        // Update stats
        var (sessions, words, wpm, saved) = _database.GetStatistics(mode);
        TotalSessions = sessions;
        TotalWords = words;
        AvgWpm = wpm;
        TimeSavedMinutes = saved;

        if (ShowEntries)
        {
            // Update entries
            var dbEntries = _database.GetEntries(100, mode == "all" ? null : mode);
            Entries = new ObservableCollection<HistoryEntry>(dbEntries);
            HasEntries = Entries.Count > 0;

            // Update common words
            var words2 = _database.GetCommonWords(mode == "all" ? null : mode);
            CommonWords = new ObservableCollection<WordChip>(
                words2.Select(w => new WordChip { Word = w.Word, Count = w.Count })
            );
        }

        if (ShowAnalytics)
        {
            var allEntries = _database.GetEntries();
            AnalyticsData = AnalyticsProcessor.Process(allEntries);
        }
    }

    private void RefreshTimestamps()
    {
        // Just trigger property change to update relative times
        OnPropertyChanged(nameof(Entries));
    }

    private void LoadAudioDevices()
    {
        var devices = Core.AudioRecorder.GetInputDevices();
        AudioDevices = new ObservableCollection<AudioDeviceItem>(
            devices.Select(d => new AudioDeviceItem { Index = d.Index, Name = d.Name })
        );

        if (_config.AudioDeviceIndex.HasValue)
            SelectedDeviceIndex = _config.AudioDeviceIndex.Value;
    }

    [RelayCommand]
    private void SelectDevice(AudioDeviceItem? device)
    {
        if (device == null) return;
        _config.AudioDeviceIndex = device.Index;
        _config.AudioDeviceName = device.Name;
        MicStatusText = $"Saved: {device.Name}";
    }

    [RelayCommand]
    private void AddDictionaryWord()
    {
        var word = NewDictionaryWord?.Trim();
        if (string.IsNullOrEmpty(word)) return;

        if (DictionaryWords.Contains(word))
        {
            DictStatusText = $"\"{word}\" is already in your dictionary";
            return;
        }

        _config.AddDictionaryWord(word);
        DictionaryWords.Add(word);
        NewDictionaryWord = "";
        DictStatusText = $"Added \"{word}\"";
    }

    [RelayCommand]
    private void RemoveDictionaryWord(string word)
    {
        _config.RemoveDictionaryWord(word);
        DictionaryWords.Remove(word);
        DictStatusText = $"Removed \"{word}\"";
    }

    [RelayCommand]
    private void SaveGeminiKey()
    {
        var key = GeminiApiKey?.Trim();
        if (string.IsNullOrEmpty(key))
        {
            SettingsStatusText = "Please enter an API key";
            return;
        }

        _config.GeminiApiKey = key;
        App.Gemini.LoadApiKey();
        GeminiKeyConfigured = App.Gemini.HasApiKey;
        SettingsStatusText = "Gemini API key saved";
    }

    [RelayCommand]
    private async Task ChangeWhisperModel(string? model)
    {
        if (string.IsNullOrEmpty(model) || model == _config.WhisperModel) return;

        IsModelChanging = true;
        ModelStatusText = $"Switching to {model}...";

        try
        {
            _config.WhisperModel = model;
            await App.Pipeline.Transcriber.ChangeModelAsync(model);
            ModelStatusText = $"Model set to {model}";
        }
        catch (Exception ex)
        {
            ModelStatusText = $"Error: {ex.Message}";
        }
        finally
        {
            IsModelChanging = false;
        }
    }

    [RelayCommand]
    private void ClearGeminiKey()
    {
        GeminiApiKey = "";
        _config.GeminiApiKey = null;
        App.Gemini.LoadApiKey();
        GeminiKeyConfigured = App.Gemini.HasApiKey;
        SettingsStatusText = "Gemini API key removed";
    }
}

public class WordChip
{
    public string Word { get; set; } = "";
    public int Count { get; set; }
}

public class AudioDeviceItem
{
    public int Index { get; set; }
    public string Name { get; set; } = "";
    public override string ToString() => Name;
}
