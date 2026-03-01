import SwiftUI
import AppKit

// MARK: - Colors (from styles.css :root variables)
enum Theme {

    // Background hierarchy
    static let bgPrimary   = Color(hex: 0x0D0D0F)
    static let bgSecondary = Color(hex: 0x151518)
    static let bgTertiary  = Color(hex: 0x1C1C21)
    static let bgHover     = Color(hex: 0x232329)

    // Border
    static let border = Color(hex: 0x2A2A32)

    // Text hierarchy
    static let textPrimary   = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0xA1A1A6)
    static let textMuted     = Color(hex: 0x6E6E73)

    // Accent
    static let accent     = Color(hex: 0x6366F1)
    static let accentSoft = Color(hex: 0x6366F1).opacity(0.15)

    // Mode colors
    static let green      = Color(hex: 0x34D399)
    static let greenSoft  = Color(hex: 0x34D399).opacity(0.15)
    static let purple     = Color(hex: 0xA78BFA)
    static let purpleSoft = Color(hex: 0xA78BFA).opacity(0.15)
    static let orange     = Color(hex: 0xFB923C)
    static let orangeSoft = Color(hex: 0xFB923C).opacity(0.15)
    static let blue       = Color(hex: 0x60A5FA)
    static let blueSoft   = Color(hex: 0x60A5FA).opacity(0.15)

    // Chart accent (amber)
    static let chartAccent = Color(hex: 0xFBBF24)

    // Analytics tab highlight
    static let analyticsColor = Color(hex: 0xFBBF24)

    // Microphone tab
    static let microphoneColor = Color(hex: 0xEC4899)
    static let microphoneSoft  = Color(hex: 0xEC4899).opacity(0.15)

    // Dictionary tab
    static let dictionaryColor = Color(hex: 0x22D3EE)
    static let dictionarySoft  = Color(hex: 0x22D3EE).opacity(0.15)

    // NSColor equivalents for AppKit
    static let nsBgPrimary   = NSColor(hex: 0x0D0D0F)
    static let nsBgSecondary = NSColor(hex: 0x151518)
    static let nsBorder      = NSColor(hex: 0x2A2A32)

    // Mode color mapping
    static func modeColor(_ mode: String) -> Color {
        switch mode {
        case "transcribe": return green
        case "greppy":     return purple
        case "cleanup":    return orange
        case "plan":       return blue
        default:           return green
        }
    }

    static func modeSoftColor(_ mode: String) -> Color {
        switch mode {
        case "transcribe": return greenSoft
        case "greppy":     return purpleSoft
        case "cleanup":    return orangeSoft
        case "plan":       return blueSoft
        default:           return greenSoft
        }
    }

    // MARK: - Typography
    static let bodyFont    = Font.system(size: 13)
    static let smallFont   = Font.system(size: 11)
    static let tinyFont    = Font.system(size: 10)
    static let headerFont  = Font.system(size: 28, weight: .bold)
    static let sectionFont = Font.system(size: 12, weight: .semibold)
    static let monoFont    = Font.system(size: 13, design: .monospaced)

    // MARK: - Spacing & Radii
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 6
    static let pillRadius: CGFloat = 5
    static let borderWidth: CGFloat = 1
    static let cardPadding: CGFloat = 14
}

// MARK: - Color hex initializers

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
