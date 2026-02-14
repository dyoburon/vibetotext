import Foundation

struct TranscriptionEntry: Identifiable, Hashable {
    let id: Int
    let text: String
    let mode: String
    let timestamp: Date
    let wordCount: Int
    let durationSeconds: Double?
    let wpm: Int?
    let sentiment: Double?

    var modeColor: String {
        switch mode {
        case "transcribe": return "green"
        case "greppy": return "purple"
        case "plan": return "blue"
        case "cleanup": return "orange"
        default: return "gray"
        }
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
