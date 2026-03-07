using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using CommunityToolkit.Mvvm.ComponentModel;

namespace VibeToText.Data;

/// <summary>
/// Manages ~/.vibetotext/config.json with observable properties.
/// Preserves unknown keys for compatibility with the Python app.
/// </summary>
public partial class ConfigStore : ObservableObject
{
    private static readonly string ConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".vibetotext"
    );
    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.json");

    private int? _audioDeviceIndex;
    private string? _audioDeviceName;
    private string? _codebasePath;
    private string? _geminiApiKey;
    private string _whisperModel = "base";
    private List<string> _customDictionary = new();
    private JsonObject? _rawJson; // Preserve unknown keys

    public int? AudioDeviceIndex
    {
        get => _audioDeviceIndex;
        set { SetProperty(ref _audioDeviceIndex, value); Save(); }
    }

    public string? AudioDeviceName
    {
        get => _audioDeviceName;
        set { SetProperty(ref _audioDeviceName, value); Save(); }
    }

    public string? CodebasePath
    {
        get => _codebasePath;
        set { SetProperty(ref _codebasePath, value); Save(); }
    }

    public string? GeminiApiKey
    {
        get => _geminiApiKey;
        set { SetProperty(ref _geminiApiKey, value); Save(); }
    }

    public string WhisperModel
    {
        get => _whisperModel;
        set { SetProperty(ref _whisperModel, value); Save(); }
    }

    public List<string> CustomDictionary
    {
        get => _customDictionary;
        set { SetProperty(ref _customDictionary, value); Save(); }
    }

    public ConfigStore()
    {
        Directory.CreateDirectory(ConfigDir);
        Load();
    }

    public void Load()
    {
        try
        {
            if (!File.Exists(ConfigPath)) return;

            var json = File.ReadAllText(ConfigPath);
            _rawJson = JsonNode.Parse(json)?.AsObject();
            if (_rawJson == null) return;

            _audioDeviceIndex = _rawJson["audio_device_index"]?.GetValue<int>();
            _audioDeviceName = _rawJson["audio_device_name"]?.GetValue<string>();
            _codebasePath = _rawJson["codebase_path"]?.GetValue<string>();
            _geminiApiKey = _rawJson["gemini_api_key"]?.GetValue<string>();
            _whisperModel = _rawJson["whisper_model"]?.GetValue<string>() ?? "base";

            var dictArray = _rawJson["custom_dictionary"]?.AsArray();
            if (dictArray != null)
            {
                _customDictionary = dictArray
                    .Select(n => n?.GetValue<string>() ?? "")
                    .Where(s => !string.IsNullOrEmpty(s))
                    .ToList();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[CONFIG] Error loading config: {ex.Message}");
        }
    }

    public void Save()
    {
        try
        {
            _rawJson ??= new JsonObject();

            // Update known fields
            if (_audioDeviceIndex.HasValue)
                _rawJson["audio_device_index"] = _audioDeviceIndex.Value;
            else
                _rawJson.Remove("audio_device_index");

            if (_audioDeviceName != null)
                _rawJson["audio_device_name"] = _audioDeviceName;
            else
                _rawJson.Remove("audio_device_name");

            if (_codebasePath != null)
                _rawJson["codebase_path"] = _codebasePath;
            else
                _rawJson.Remove("codebase_path");

            if (_geminiApiKey != null)
                _rawJson["gemini_api_key"] = _geminiApiKey;
            else
                _rawJson.Remove("gemini_api_key");

            _rawJson["whisper_model"] = _whisperModel;

            var dictArray = new JsonArray();
            foreach (var word in _customDictionary)
                dictArray.Add(word);
            _rawJson["custom_dictionary"] = dictArray;

            var options = new JsonSerializerOptions { WriteIndented = true };
            var json = _rawJson.ToJsonString(options);
            File.WriteAllText(ConfigPath, json);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[CONFIG] Error saving config: {ex.Message}");
        }
    }

    public void AddDictionaryWord(string word)
    {
        if (string.IsNullOrWhiteSpace(word)) return;
        if (_customDictionary.Contains(word)) return;

        _customDictionary.Add(word);
        OnPropertyChanged(nameof(CustomDictionary));
        Save();
    }

    public void RemoveDictionaryWord(string word)
    {
        if (_customDictionary.Remove(word))
        {
            OnPropertyChanged(nameof(CustomDictionary));
            Save();
        }
    }
}
