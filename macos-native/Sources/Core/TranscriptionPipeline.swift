import Foundation

/// Orchestrator: hotkeys → record → transcribe → process → paste
final class TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private var hotkeyManager: HotkeyManager?
    private var recorder: AudioRecorder?
    private var transcriber: WhisperTranscriber?
    private var geminiService: GeminiService?
    private var greppyService: GreppyService?
    private var waveformController: WaveformOverlayController?
    private var apiServer: ApiServer?

    private var isRecording = false
    private var currentMode: String?
    private var recordingStart: Date?

    func start() {
        hotkeyManager = HotkeyManager()
        recorder = AudioRecorder()
        transcriber = WhisperTranscriber()
        geminiService = GeminiService()
        greppyService = GreppyService()
        waveformController = WaveformOverlayController()

        // Register hotkey callbacks
        hotkeyManager?.onRecordingStart = { [weak self] mode in
            self?.startRecording(mode: mode)
        }
        hotkeyManager?.onRecordingStop = { [weak self] mode in
            self?.stopRecording(mode: mode)
        }

        hotkeyManager?.start()

        apiServer = ApiServer()
        apiServer?.start()

        print("[Pipeline] Started — hold hotkey to record")
    }

    func stop() {
        hotkeyManager?.stop()
        if isRecording {
            _ = recorder?.stop()
        }
        waveformController?.hide()
        TtsService.shared.stop()
        apiServer?.stop()
    }

    private func startRecording(mode: String) {
        guard !isRecording else { return }
        isRecording = true
        currentMode = mode
        recordingStart = Date()

        // Reload mic config
        ConfigStore.shared.load()

        // Set up waveform callback
        recorder?.onLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.waveformController?.updateLevels(levels)
            }
        }

        waveformController?.show()
        recorder?.start()
        print("[Pipeline] Recording (\(mode))...")
    }

    private func stopRecording(mode: String) {
        guard isRecording else { return }
        isRecording = false

        let audio = recorder?.stop() ?? []
        let duration = recordingStart.map { Date().timeIntervalSince($0) }
        waveformController?.hide()
        print("[Pipeline] Recording stopped.")

        guard !audio.isEmpty else {
            print("[Pipeline] No audio captured.")
            return
        }

        // Process in background
        Task {
            do {
                // 1. Transcribe
                guard let text = try await transcriber?.transcribe(audio: audio), !text.isEmpty else {
                    print("[Pipeline] No speech detected.")
                    return
                }
                print("[Pipeline] Transcribed: \(text.prefix(80))...")

                // 2. Process based on mode
                var output = text
                var fileCount = 0
                switch mode {
                case "cleanup":
                    if let refined = try await geminiService?.cleanup(text: text) {
                        output = refined
                    }
                case "plan":
                    if let plan = try await geminiService?.generatePlan(text: text) {
                        output = plan
                    }
                case "greppy":
                    let context = await greppyService?.search(query: text) ?? ""
                    if !context.isEmpty {
                        output = text + "\n\n" + context
                        fileCount = context.components(separatedBy: "### ").count - 1
                    }
                case "feedback":
                    if let feedback = try await geminiService?.feedback(text: text) {
                        TtsService.shared.speak(feedback)
                    } else {
                        TtsService.shared.speak("I couldn't generate feedback, sir")
                    }
                    // output stays as original text for paste
                default:
                    break // transcribe mode: use raw text
                }

                // 3. Save to history
                try await HistoryDatabase.shared.addEntry(
                    text: text,
                    mode: mode,
                    durationSeconds: duration
                )

                // 4. Paste at cursor
                PasteService.pasteAtCursor(output)
                print("[Pipeline] Pasted at cursor.")

                // 5. Speak status report
                let status = TtsService.generateStatusMessage(
                    mode: mode, text: text, output: output, fileCount: fileCount)
                TtsService.shared.speak(status)

            } catch {
                print("[Pipeline] Error: \(error)")
                TtsService.shared.speak("Processing failed")
            }
        }
    }
}
