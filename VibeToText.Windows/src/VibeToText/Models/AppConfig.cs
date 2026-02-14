using System.Text.Json.Serialization;

namespace VibeToText.Models;

public class AppConfig
{
    [JsonPropertyName("audio_device_index")]
    public int? AudioDeviceIndex { get; set; }

    [JsonPropertyName("audio_device_name")]
    public string? AudioDeviceName { get; set; }

    [JsonPropertyName("codebase_path")]
    public string? CodebasePath { get; set; }

    [JsonPropertyName("custom_dictionary")]
    public List<string> CustomDictionary { get; set; } = new();

    [JsonExtensionData]
    public Dictionary<string, object>? ExtensionData { get; set; }
}
