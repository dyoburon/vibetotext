import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var entries: [TranscriptionEntry] = []
    @Published var wordFrequencies: [WordFrequency] = []
    @Published var coOccurrence: [String: [(String, Int)]] = [:]
    @Published var isLoading = true
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 32)
    @Published var audioAmplitude: Float = 0

    // Stats
    @Published var totalSessions = 0
    @Published var totalWords = 0
    @Published var averageWPM = 0
    @Published var uniqueWords = 0

    // Tree data
    @Published var treeData = TreeData.placeholder
    @Published var treeWordDataJSON: String = "[]"
    @Published var treeStrataJSON: String = "[]"

    private let db = DatabaseManager()
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var audioTimer: Timer?

    init() {
        reload()
        watchDatabase()
        startAudioIPC()
    }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let entries = self.db.fetchAllEntries()
            let frequencies = WordFrequencyEngine.buildFrequencyMap(from: entries)
            let topWords = Set(frequencies.prefix(8000).map(\.word))
            let coOccurrence = WordFrequencyEngine.buildCoOccurrence(
                from: entries, topWords: topWords
            )

            let totalWords = entries.reduce(0) { $0 + $1.wordCount }
            let wpms = entries.compactMap(\.wpm).filter { $0 > 0 }
            let avgWPM = wpms.isEmpty ? 0 : wpms.reduce(0, +) / wpms.count

            let treeData = TreeDataCalculator.calculate(from: entries)

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            let wordDataArray = frequencies.prefix(500).enumerated().map { i, wf -> [String: Any] in
                ["word": wf.word, "count": wf.count,
                 "firstSeen": formatter.string(from: wf.firstSeen),
                 "firstSeenTS": wf.firstSeen.timeIntervalSince1970,
                 "rank": i + 1]
            }
            let treeWordDataJSON = (try? JSONSerialization.data(withJSONObject: wordDataArray))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            // Compute strata: sort all words by firstSeen, divide into trunk levels
            let sortedByDate = frequencies.sorted { $0.firstSeen < $1.firstSeen }
            let uniqueCount = frequencies.count
            let trunkLevels: Int = {
                if uniqueCount >= 5000 { return 10 }
                if uniqueCount >= 2000 { return 8 }
                if uniqueCount >= 800 { return 6 }
                if uniqueCount >= 200 { return 4 }
                if uniqueCount >= 50 { return 3 }
                return 2
            }()
            let perStratum = max(1, sortedByDate.count / trunkLevels)
            var strataArray: [[String: Any]] = []
            for i in 0..<trunkLevels {
                let start = i * perStratum
                let end = i == trunkLevels - 1 ? sortedByDate.count : min(start + perStratum, sortedByDate.count)
                guard start < sortedByDate.count else { break }
                let slice = sortedByDate[start..<end]
                let totalFreq = slice.reduce(0) { $0 + $1.count }
                strataArray.append(["wordCount": slice.count, "totalFreq": totalFreq])
            }
            let treeStrataJSON = (try? JSONSerialization.data(withJSONObject: strataArray))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            DispatchQueue.main.async {
                self.entries = entries
                self.wordFrequencies = frequencies
                self.coOccurrence = coOccurrence
                self.totalSessions = entries.count
                self.totalWords = totalWords
                self.averageWPM = avgWPM
                self.uniqueWords = frequencies.count
                self.treeData = treeData
                self.treeWordDataJSON = treeWordDataJSON
                self.treeStrataJSON = treeStrataJSON
                self.isLoading = false
            }
        }
    }

    private func startAudioIPC() {
        // Read waveform from vibetotext IPC at ~30fps
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.readAudioIPC()
        }
    }

    private func readAudioIPC() {
        let path = "/tmp/vibetotext_ui_ipc.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let levels = json["levels"] as? [Double] else {
            return
        }
        // Build 32-band array (pad from 25 IPC bands)
        var newLevels = [Float](repeating: 0, count: 32)
        for i in 0..<min(levels.count, 32) {
            newLevels[i] = Float(levels[i])
        }
        let avg = Float(levels.reduce(0, +) / max(Double(levels.count), 1))
        // Smooth per-band: 50% previous, 50% new
        DispatchQueue.main.async {
            for i in 0..<32 {
                self.audioLevels[i] = self.audioLevels[i] * 0.5 + newLevels[i] * 0.5
            }
            self.audioAmplitude = self.audioAmplitude * 0.6 + avg * 0.4
        }
    }

    private func watchDatabase() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.vibetotext/history.db"
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Thread.sleep(forTimeInterval: 0.5)
            self?.reload()
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileMonitor = source
    }
}
