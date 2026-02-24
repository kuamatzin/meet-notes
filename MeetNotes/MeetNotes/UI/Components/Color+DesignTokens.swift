import SwiftUI

extension Color {
    static let windowBg      = Color(hex: "#13141F")
    static let cardBg        = Color(hex: "#1C1D2E")
    static let cardBorder    = Color(hex: "#2A2B3D")
    static let accent        = Color(hex: "#5B6CF6")
    static let recordingRed  = Color(hex: "#FF3B30")
    static let onDeviceGreen = Color(hex: "#34C759")
    static let warningAmber  = Color(hex: "#FF9F0A")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
