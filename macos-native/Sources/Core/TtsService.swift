import AVFoundation

/// Fire-and-forget text-to-speech — neural TTS via edge-tts CLI, with
/// AVSpeechSynthesizer as fallback when edge-tts is unavailable.
final class TtsService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TtsService()

    private let synthesizer = AVSpeechSynthesizer()

    /// Active afplay process for single-slot cancellation.
    private var activeProcess: Process?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public

    func speak(_ text: String) {
        let config = ConfigStore.shared
        guard config.ttsEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Cancel any previous speech
        stop()

        Task.detached { [weak self] in
            let tmpPath = NSTemporaryDirectory() + "vibetotext_tts.mp3"
            let voice = config.ttsVoice ?? "en-GB-RyanNeural"
            let rate = config.ttsEdgeRate ?? "+12%"
            let pitch = config.ttsEdgePitch ?? "+1Hz"

            // 1. Generate mp3 via edge-tts CLI
            let genProcess = Process()
            genProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            genProcess.arguments = [
                "edge-tts",
                "--voice", voice,
                "--rate", rate,
                "--pitch", pitch,
                "--text", text,
                "--write-media", tmpPath,
            ]
            genProcess.standardOutput = FileHandle.nullDevice
            genProcess.standardError = FileHandle.nullDevice

            do {
                try genProcess.run()
                genProcess.waitUntilExit()

                guard genProcess.terminationStatus == 0 else {
                    print("[TTS] edge-tts exited with status \(genProcess.terminationStatus), falling back")
                    self?.speakFallback(text)
                    return
                }

                // 2. Play with afplay
                let playProcess = Process()
                playProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                playProcess.arguments = [tmpPath]
                try playProcess.run()
                self?.activeProcess = playProcess
            } catch {
                print("[TTS] edge-tts failed: \(error), falling back")
                self?.speakFallback(text)
            }
        }
    }

    func stop() {
        // Kill active afplay process
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
        }
        activeProcess = nil

        // Also stop AVSpeechSynthesizer fallback
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Fallback (AVSpeechSynthesizer)

    private func speakFallback(_ text: String) {
        let config = ConfigStore.shared

        // Cancel any previous fallback speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Convert WPM (default 200) to AVSpeechUtterance rate (0.0 - 1.0)
        let wpm = Float(config.ttsRate)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                            min(AVSpeechUtteranceMaximumSpeechRate,
                                (wpm / 200.0) * AVSpeechUtteranceDefaultSpeechRate))

        // Volume: 0-100 -> 0.0-1.0
        utterance.volume = Float(config.ttsVolume) / 100.0

        let voiceId = (config.ttsVoice?.isEmpty == false) ? config.ttsVoice : nil
        if let id = voiceId {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
                ?? AVSpeechSynthesisVoice(language: id)
        } else {
            // Default: Daniel (British male) for Jarvis feel
            utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-GB.Daniel")
                ?? AVSpeechSynthesisVoice(language: "en-GB")
        }

        synthesizer.speak(utterance)
    }

    // MARK: - Status messages

    static func generateStatusMessage(mode: String, text: String, output: String, fileCount: Int = 0) -> String {
        switch mode {
        case "greppy":
            return fileCount == 1 ? "Located one file, sir" : "Located \(fileCount) files, sir"
        case "cleanup":
            let n = output.components(separatedBy: "\n\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
            return "All tidied up. \(n) paragraphs ready"
        case "plan":
            let n = output.components(separatedBy: "\n")
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.range(of: #"^(\d+[\.\):]|[-*])\s"#, options: .regularExpression) != nil
                }
                .count
            return "Plan's ready. \(n) steps laid out"
        case "feedback":
            return "Feedback spoken, sir"
        default:
            let n = text.split(separator: " ").count
            return "Got it. \(n) words captured"
        }
    }
}
