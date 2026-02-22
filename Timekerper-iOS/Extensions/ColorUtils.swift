import SwiftUI

enum ColorUtils {

    struct RGB {
        let r: Double
        let g: Double
        let b: Double
    }

    /// Parse a hex string to RGB components (0-255 scale).
    static func hexToRgb(_ hex: String) -> RGB {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgb) else {
            return RGB(r: 148, g: 163, b: 184) // fallback: #94a3b8
        }
        return RGB(
            r: Double((rgb >> 16) & 0xFF),
            g: Double((rgb >> 8) & 0xFF),
            b: Double(rgb & 0xFF)
        )
    }

    /// Blend a hex color with the surface background at a given alpha.
    /// Returns a SwiftUI Color.
    static func blendWithSurface(hex: String, alpha: Double, isDarkMode: Bool) -> Color {
        let c = hexToRgb(hex)
        let bg = isDarkMode ? RGB(r: 30, g: 41, b: 59) : RGB(r: 250, g: 249, b: 245)
        let r = c.r * alpha + bg.r * (1 - alpha)
        let g = c.g * alpha + bg.g * (1 - alpha)
        let b = c.b * alpha + bg.b * (1 - alpha)
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    /// Determine whether text on a block should be dark or light.
    /// blockOpacity is the alpha used for the block background.
    static func textColor(hex: String, blockOpacity: Double, isDarkMode: Bool) -> Color {
        let c = hexToRgb(hex)
        let bg = isDarkMode ? RGB(r: 30, g: 41, b: 59) : RGB(r: 250, g: 249, b: 245)
        let effR = c.r * blockOpacity + bg.r * (1 - blockOpacity)
        let effG = c.g * blockOpacity + bg.g * (1 - blockOpacity)
        let effB = c.b * blockOpacity + bg.b * (1 - blockOpacity)
        let brightness = (effR * 299 + effG * 587 + effB * 114) / 1000
        return brightness > 150 ? Color(hex: "#1a1a1a") : .white
    }

    /// Get the effective color for a block based on its type.
    /// Task blocks: blended at 10% opacity. Event blocks: full color.
    static func blockBackground(hex: String, type: BlockType, isDarkMode: Bool) -> Color {
        switch type {
        case .task:
            return blendWithSurface(hex: hex, alpha: 0.25, isDarkMode: isDarkMode)
        case .event:
            return Color(hex: hex)
        case .pause:
            return Color.orange.opacity(0.3)
        }
    }

    /// Get text color for a block.
    static func blockTextColor(hex: String, type: BlockType, isDarkMode: Bool) -> Color {
        switch type {
        case .task:
            return textColor(hex: hex, blockOpacity: 0.25, isDarkMode: isDarkMode)
        case .event:
            return textColor(hex: hex, blockOpacity: 1.0, isDarkMode: isDarkMode)
        case .pause:
            return Color(hex: "#92400e")
        }
    }
}
