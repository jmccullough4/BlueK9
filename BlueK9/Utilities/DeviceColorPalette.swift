import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

enum DeviceColorPalette {
    private static func rgbComponents(for id: UUID) -> (red: Double, green: Double, blue: Double) {
        let uuidString = id.uuidString
        var hasher = Hasher()
        hasher.combine(uuidString)
        let hashValue = hasher.finalize()
        let normalized = Double(abs(hashValue % 360)) / 360.0
        let saturation: Double = 0.65
        let brightness: Double = 0.85
        return hsbToRgb(hue: normalized, saturation: saturation, brightness: brightness)
    }

    private static func hsbToRgb(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        let h = hue * 6.0
        let c = brightness * saturation
        let x = c * (1 - abs(fmod(h, 2) - 1))
        let m = brightness - c

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<1:
            (r1, g1, b1) = (c, x, 0)
        case ..<2:
            (r1, g1, b1) = (x, c, 0)
        case ..<3:
            (r1, g1, b1) = (0, c, x)
        case ..<4:
            (r1, g1, b1) = (0, x, c)
        case ..<5:
            (r1, g1, b1) = (x, 0, c)
        default:
            (r1, g1, b1) = (c, 0, x)
        }

        return (r1 + m, g1 + m, b1 + m)
    }

    static func hexString(for id: UUID) -> String {
        let components = rgbComponents(for: id)
        let r = Int(round(components.red * 255))
        let g = Int(round(components.green * 255))
        let b = Int(round(components.blue * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    #if canImport(SwiftUI)
    static func color(for id: UUID) -> Color {
        let components = rgbComponents(for: id)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
    #endif
}
