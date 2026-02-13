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

    // Village persistent state
    @Published var villageState: VillageState?
    @Published var villageStateJSON: String = "{}"

    private let db = DatabaseManager()
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var audioTimer: Timer?

    init() {
        // Load or create village state
        if let saved = VillageStateManager.load() {
            villageState = saved
            villageStateJSON = VillageStateManager.toJSON(saved)
        }
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

            // ── Village state mutation ──
            // DEBUG: Force negative mood for testing destruction
            let debugMood: Float = -0.7

            let updatedVillageState = self.mutateVillageState(
                totalWords: totalWords,
                mood: debugMood,
                entryCount: entries.count
            )
            let villageJSON = VillageStateManager.toJSON(updatedVillageState)

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
                self.villageState = updatedVillageState
                self.villageStateJSON = villageJSON
                self.isLoading = false
            }
        }
    }

    // MARK: - Village State Mutation

    private func mutateVillageState(totalWords: Int, mood: Float, entryCount: Int) -> VillageState {
        var state: VillageState
        if let existing = VillageStateManager.load() {
            state = existing
        } else {
            state = VillageStateManager.createInitial(totalWords: totalWords)
            VillageStateManager.save(state)
            return state
        }

        let now = Date()
        var changed = false

        // ── Birth logic: 1 new villager per 1000 new words ──
        let newWords = totalWords - state.totalWordsAtLastBirth
        if newWords >= 1000 {
            let births = newWords / 1000
            let buildingCount = state.buildings.count
            let baseRadius = 12.0 + sqrt(Double(buildingCount)) * 2.0

            for _ in 0..<births {
                let vid = state.nextVillagerId
                let role = VillageStateManager.nextRole(existingVillagers: state.villagers)
                let angle = Double(vid) * 2.399 // golden angle
                let radius = baseRadius + Double(vid % 5) * 3.0
                let bx = cos(angle) * radius
                let bz = sin(angle) * radius

                // Create a building for the new villager
                let buildingId = state.buildings.count
                let buildingType: BuildingType = {
                    switch role {
                    case .farmer: return .farm
                    case .guard_: return .barracks
                    case .builder, .blacksmith: return .workshop
                    case .scholar, .mayor: return .cottage
                    }
                }()
                let building = BuildingState(
                    id: buildingId,
                    type: buildingType,
                    owner: vid,
                    position: VillagePosition(x: bx, z: bz),
                    burned: false,
                    size: 0.8 + Double(vid % 4) * 0.3
                )
                state.buildings.append(building)

                let villager = VillagerState(
                    id: vid,
                    name: VillageNameGenerator.name(forId: vid),
                    role: role,
                    bornAt: now,
                    alive: true,
                    diedAt: nil,
                    position: VillagePosition(x: bx + 2, z: bz + 2),
                    homeBuilding: buildingId
                )
                state.villagers.append(villager)
                state.nextVillagerId = vid + 1
            }
            state.totalWordsAtLastBirth = totalWords
            changed = true
        }

        // ── Death logic: mood below threshold kills villagers by priority ──
        if mood < -0.3 {
            // How many should die: fraction of alive villagers
            let aliveVillagers = state.villagers.filter(\.alive)
            let killFraction = Double((-mood - 0.3) / 0.7) // 0 at -0.3, 1 at -1.0
            // DEBUG: Kill more aggressively for testing (was * 0.5)
            let targetDeaths = max(2, Int(Double(aliveVillagers.count) * killFraction))

            // Sort by death priority (lowest dies first)
            let candidates = aliveVillagers
                .filter { mood <= $0.role.deathMoodThreshold }
                .sorted { $0.role.deathPriority < $1.role.deathPriority }

            let toKill = min(targetDeaths, candidates.count)
            for i in 0..<toKill {
                let victim = candidates[i]
                guard let idx = state.villagers.firstIndex(where: { $0.id == victim.id }) else { continue }
                // Only create pending death if not already pending
                let alreadyPending = state.pendingDeaths.contains { $0.villagerId == victim.id }
                let alreadyDead = state.graveyard.contains { $0.villagerId == victim.id }
                if alreadyPending || alreadyDead { continue }

                state.villagers[idx].alive = false
                state.villagers[idx].diedAt = now

                let death = PendingDeath(
                    villagerId: victim.id,
                    name: victim.name,
                    role: victim.role.displayName,
                    diedAt: now,
                    position: victim.position
                )
                state.pendingDeaths.append(death)
                changed = true
            }
        }

        // ── Building burn state ──
        let burnFraction = mood < -0.3 ? Double((-mood - 0.3) / 0.7) : 0.0
        let burnCount = Int(Double(state.buildings.count) * burnFraction)
        for i in 0..<state.buildings.count {
            let shouldBurn = i < burnCount
            if state.buildings[i].burned != shouldBurn {
                state.buildings[i].burned = shouldBurn
                changed = true
            }
        }

        if changed {
            VillageStateManager.save(state)
        }
        return state
    }

    func clearPendingDeaths() {
        guard var state = VillageStateManager.load() else { return }
        // Move pending deaths to graveyard
        for death in state.pendingDeaths {
            let entry = GraveyardEntry(
                villagerId: death.villagerId,
                name: death.name,
                role: death.role,
                diedAt: death.diedAt,
                position: death.position
            )
            state.graveyard.append(entry)
        }
        state.pendingDeaths.removeAll()
        VillageStateManager.save(state)
        DispatchQueue.main.async {
            self.villageState = state
            self.villageStateJSON = VillageStateManager.toJSON(state)
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
