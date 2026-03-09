import SwiftUI

extension Color {
    // Use native macOS system colors for a Finder-like appearance.
    // These adapt automatically to light/dark mode.
    static let windowBg      = Color(nsColor: .windowBackgroundColor)
    static let cardBg        = Color(nsColor: .controlBackgroundColor)
    static let cardBorder    = Color(nsColor: .separatorColor)
    static let accent        = Color.accentColor
    static let recordingRed  = Color.red
    static let onDeviceGreen = Color.green
    static let warningAmber  = Color.orange
}
