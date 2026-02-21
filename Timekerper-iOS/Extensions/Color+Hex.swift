import SwiftUI

extension Color {
    /// Initialize a Color from a hex string like "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Convert a Color to a hex string "#RRGGBB".
    /// Falls back to "#94a3b8" if conversion fails.
    func toHex() -> String {
        guard let components = cgColor?.components, components.count >= 3 else {
            return "#94a3b8"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
