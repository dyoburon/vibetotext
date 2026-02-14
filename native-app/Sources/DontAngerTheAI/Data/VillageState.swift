import Foundation

// MARK: - Position

struct VillagePosition: Codable {
    var x: Double
    var z: Double
}

// MARK: - Villager

struct VillagerState: Codable, Identifiable {
    let id: Int
    var name: String
    var role: VillagerRole
    var bornAt: Date
    var alive: Bool
    var diedAt: Date?
    var position: VillagePosition
    var homeBuilding: Int
}

enum VillagerRole: String, Codable, CaseIterable {
    case mayor
    case guard_
    case farmer
    case builder
    case blacksmith
    case scholar

    var displayName: String {
        switch self {
        case .mayor: return "Mayor"
        case .guard_: return "Guard"
        case .farmer: return "Farmer"
        case .builder: return "Builder"
        case .blacksmith: return "Blacksmith"
        case .scholar: return "Scholar"
        }
    }

    /// Lower = dies first. Mayor dies last.
    var deathPriority: Int {
        switch self {
        case .farmer: return 1
        case .builder: return 2
        case .blacksmith: return 3
        case .scholar: return 4
        case .guard_: return 5
        case .mayor: return 6
        }
    }

    /// Minimum mood required to be at risk of death
    var deathMoodThreshold: Float {
        switch self {
        case .farmer, .builder, .blacksmith, .scholar: return -0.3
        case .guard_: return -0.5
        case .mayor: return -0.6
        }
    }

    // Encoding fix for guard_ → "guard" in JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "guard": self = .guard_
        default:
            guard let role = VillagerRole(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown role: \(raw)")
            }
            self = role
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .guard_: try container.encode("guard")
        default: try container.encode(rawValue)
        }
    }
}

// MARK: - Building

struct BuildingState: Codable, Identifiable {
    let id: Int
    var type: BuildingType
    var owner: Int? // villager ID
    var position: VillagePosition
    var burned: Bool
    var size: Double
}

enum BuildingType: String, Codable {
    case townhall
    case cottage
    case farm
    case workshop
    case barracks
}

// MARK: - Graveyard

struct GraveyardEntry: Codable, Identifiable {
    var id: Int { villagerId }
    let villagerId: Int
    let name: String
    let role: String
    let diedAt: Date
    var position: VillagePosition
}

// MARK: - Village State

struct VillageState: Codable {
    var version: Int = 1
    var createdAt: Date
    var totalWordsAtLastBirth: Int
    var nextVillagerId: Int
    var villagers: [VillagerState]
    var buildings: [BuildingState]
    var graveyard: [GraveyardEntry]
}

// MARK: - Name Generator

enum VillageNameGenerator {
    private static let names = [
        "Alaric", "Brenna", "Calder", "Dorin", "Elena", "Faron", "Greta",
        "Halden", "Isolde", "Jareth", "Kira", "Lewin", "Maren", "Norin",
        "Orla", "Perrin", "Rowan", "Seren", "Theron", "Vanya", "Wren",
        "Zara", "Aldric", "Belen", "Cyra", "Dain", "Elara", "Finn",
        "Galen", "Hera", "Idris", "Joran", "Kael", "Liora", "Mira",
        "Niven", "Orin", "Petra", "Rune", "Sylva", "Tarn", "Una",
        "Voss", "Wylan", "Xera", "Yara", "Zephyr", "Ashwin", "Brigid",
        "Coren", "Dagny", "Eamon", "Flora", "Gareth", "Haven", "Iona",
        "Kellan", "Lark", "Maeve", "Niall", "Ondra", "Quinn", "Rhea",
        "Stellan", "Torin", "Vesper", "Wynn", "Astra", "Bram", "Calla"
    ]

    static func name(forId id: Int) -> String {
        // Deterministic: same ID always gives same name
        var seed = UInt64(id &* 2654435761)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let idx = Int((seed >> 33) & 0x7FFFFFFF) % names.count
        return names[idx]
    }
}

// MARK: - Village State Manager

enum VillageStateManager {
    private static var villageFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".vibetotext/village.json")
    }

    static func load() -> VillageState? {
        let url = villageFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VillageState.self, from: data)
    }

    static func save(_ state: VillageState) {
        let url = villageFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func toJSON(_ state: VillageState) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Create initial village for first launch
    static func createInitial(totalWords: Int) -> VillageState {
        let now = Date()
        let baseRadius = 12 + sqrt(Double(max(5, 5 + log2(Double(max(1, totalWords / 50))) * 4))) * 2

        var villagers: [VillagerState] = []
        var buildings: [BuildingState] = []

        // Scale villager count with total words: 1 per 2500, min 5, max 5000
        let count = max(5, min(5000, totalWords / 2500))

        // First 5 get special roles
        let specialRoles: [VillagerRole] = [.mayor, .guard_, .farmer, .builder, .blacksmith]
        let specialBuildings: [BuildingType] = [.townhall, .barracks, .farm, .workshop, .cottage]

        for i in 0..<count {
            let angle = Double(i) * 2.399 // golden angle for even spread
            let radius = baseRadius + Double(i % 5) * 3.0
            let bx = cos(angle) * radius
            let bz = sin(angle) * radius

            let role: VillagerRole
            let buildingType: BuildingType
            if i < 5 {
                role = specialRoles[i]
                buildingType = specialBuildings[i]
            } else {
                role = nextRole(existingVillagers: villagers)
                switch role {
                case .farmer: buildingType = .farm
                case .guard_: buildingType = .barracks
                case .builder, .blacksmith: buildingType = .workshop
                case .scholar, .mayor: buildingType = .cottage
                }
            }

            let building = BuildingState(
                id: i,
                type: buildingType,
                owner: i + 1,
                position: VillagePosition(x: bx, z: bz),
                burned: false,
                size: i == 0 ? 1.4 : 0.8 + Double(i % 4) * 0.3
            )
            buildings.append(building)

            let villager = VillagerState(
                id: i + 1,
                name: VillageNameGenerator.name(forId: i + 1),
                role: role,
                bornAt: now,
                alive: true,
                diedAt: nil,
                position: VillagePosition(x: bx + 2, z: bz + 2),
                homeBuilding: i
            )
            villagers.append(villager)
        }

        return VillageState(
            version: 1,
            createdAt: now,
            totalWordsAtLastBirth: totalWords,
            nextVillagerId: count + 1,
            villagers: villagers,
            buildings: buildings,
            graveyard: []
        )
    }

    /// Assign a role for a new villager based on round-robin
    static func nextRole(existingVillagers: [VillagerState]) -> VillagerRole {
        let cycleRoles: [VillagerRole] = [.farmer, .builder, .blacksmith, .scholar]
        let aliveCount = existingVillagers.filter(\.alive).count
        // First villager = Mayor (already created), second = Guard (already created)
        // After that, cycle through farmer/builder/blacksmith/scholar
        let idx = max(0, aliveCount - 2) % cycleRoles.count
        return cycleRoles[idx]
    }
}
