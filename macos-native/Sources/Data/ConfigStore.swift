import Foundation

/// Manages ~/.vibetotext/config.json — shared with the Python app.
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    private let configURL: URL
    private let envURL: URL

    @Published var audioDeviceIndex: Int?
    @Published var audioDeviceName: String?
    @Published var codebasePath: String?
    @Published var customDictionary: [String]
    @Published var ttsEnabled: Bool = true
    @Published var ttsRate: Int = 200
    @Published var ttsVolume: Int = 80
    @Published var ttsVoice: String?
    @Published var ttsEdgeRate: String?
    @Published var ttsEdgePitch: String?

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibetotext")
        configURL = dir.appendingPathComponent("config.json")
        envURL = dir.appendingPathComponent(".env")
        customDictionary = []
        load()
    }

    // MARK: - Load

    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            let data = try Data(contentsOf: configURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            audioDeviceIndex = json["audio_device_index"] as? Int
            audioDeviceName = json["audio_device_name"] as? String
            codebasePath = json["codebase_path"] as? String
            customDictionary = json["custom_dictionary"] as? [String] ?? []
            ttsEnabled = json["tts_enabled"] as? Bool ?? true
            ttsRate = json["tts_rate"] as? Int ?? 200
            ttsVolume = json["tts_volume"] as? Int ?? 80
            ttsVoice = json["tts_voice"] as? String
            ttsEdgeRate = json["tts_edge_rate"] as? String
            ttsEdgePitch = json["tts_edge_pitch"] as? String
        } catch {
            print("[ConfigStore] Failed to load config: \(error)")
        }
    }

    // MARK: - Save

    func save() {
        do {
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var json: [String: Any] = [:]
            // Preserve existing keys we don't manage
            if FileManager.default.fileExists(atPath: configURL.path),
               let data = try? Data(contentsOf: configURL),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            }

            if let idx = audioDeviceIndex {
                json["audio_device_index"] = idx
            } else {
                json.removeValue(forKey: "audio_device_index")
            }
            if let name = audioDeviceName {
                json["audio_device_name"] = name
            } else {
                json.removeValue(forKey: "audio_device_name")
            }
            if let path = codebasePath {
                json["codebase_path"] = path
            } else {
                json.removeValue(forKey: "codebase_path")
            }
            json["custom_dictionary"] = customDictionary
            json["tts_enabled"] = ttsEnabled
            json["tts_rate"] = ttsRate
            json["tts_volume"] = ttsVolume
            if let voice = ttsVoice {
                json["tts_voice"] = voice
            } else {
                json.removeValue(forKey: "tts_voice")
            }
            if let edgeRate = ttsEdgeRate {
                json["tts_edge_rate"] = edgeRate
            } else {
                json.removeValue(forKey: "tts_edge_rate")
            }
            if let edgePitch = ttsEdgePitch {
                json["tts_edge_pitch"] = edgePitch
            } else {
                json.removeValue(forKey: "tts_edge_pitch")
            }

            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[ConfigStore] Failed to save config: \(error)")
        }
    }

    // MARK: - Dictionary helpers

    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customDictionary.contains(trimmed) else { return }
        customDictionary.append(trimmed)
        save()
    }

    func removeWord(_ word: String) {
        customDictionary.removeAll { $0 == word }
        save()
    }

    // MARK: - Gemini API key

    var geminiAPIKey: String? {
        // Check environment first
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !key.isEmpty {
            return key
        }
        // Check .env file
        if let key = readEnvKey("GEMINI_API_KEY") { return key }
        if let key = readEnvKey("GOOGLE_API_KEY") { return key }

        // Also check project-level .env
        let projectEnv = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev/vibetotext/.env")
        if let key = readEnvKey("GEMINI_API_KEY", from: projectEnv) { return key }
        if let key = readEnvKey("GOOGLE_API_KEY", from: projectEnv) { return key }

        return nil
    }

    private func readEnvKey(_ key: String, from url: URL? = nil) -> String? {
        let fileURL = url ?? envURL
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(key + "=") {
                let value = String(trimmed.dropFirst(key.count + 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
