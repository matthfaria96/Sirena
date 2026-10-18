/// ColorModel.swift
///
/// Saved colors, palettes and the text formats a color can be copied as.

import AppKit
import SwiftUI

/// A color stored as sRGB components (0...1).
struct SavedColor: Codable, Identifiable, Hashable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
    var name: String?
    var date = Date()

    init(red: Double, green: Double, blue: Double, alpha: Double = 1, name: String? = nil) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha; self.name = name
    }

    init?(nsColor: NSColor) {
        guard let c = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent),
                  blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }

    /// Parses "#RGB", "#RRGGBB" or "#RRGGBBAA".
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        } else {
            self.init(red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                      blue: Double((v >> 8) & 0xFF) / 255, alpha: Double(v & 0xFF) / 255)
        }
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    private var r255: Int { Int((red * 255).rounded()) }
    private var g255: Int { Int((green * 255).rounded()) }
    private var b255: Int { Int((blue * 255).rounded()) }

    var hex: String { String(format: "#%02X%02X%02X", r255, g255, b255) }
    var displayName: String { name?.isEmpty == false ? (name ?? hex) : hex }

    /// Relative luminance, used to pick a readable label color over the swatch.
    var isLight: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6 }

    var hsb: (h: Double, s: Double, b: Double) {
        let mx = max(red, green, blue), mn = min(red, green, blue), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == red { h = ((green - blue) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == green { h = (blue - red) / d + 2 }
            else { h = (red - green) / d + 4 }
            h *= 60; if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(red, green, blue), mn = min(red, green, blue)
        let l = (mx + mn) / 2, d = mx - mn
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return (hsb.h, s, l)
    }

    var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let k = 1 - max(red, green, blue)
        guard k < 1 else { return (0, 0, 0, 1) }
        return ((1 - red - k) / (1 - k), (1 - green - k) / (1 - k), (1 - blue - k) / (1 - k), k)
    }

    func string(_ format: ColorFormat) -> String {
        let f3 = { (v: Double) in String(format: "%.3f", v) }
        switch format {
        case .hex: return hex
        case .hexNoHash: return String(hex.dropFirst())
        case .rgb: return "rgb(\(r255), \(g255), \(b255))"
        case .rgba: return "rgba(\(r255), \(g255), \(b255), \(String(format: "%.2f", alpha)))"
        case .hsl:
            let v = hsl
            return "hsl(\(Int(v.h.rounded())), \(Int((v.s * 100).rounded()))%, \(Int((v.l * 100).rounded()))%)"
        case .hsb:
            let v = hsb
            return "hsb(\(Int(v.h.rounded())), \(Int((v.s * 100).rounded()))%, \(Int((v.b * 100).rounded()))%)"
        case .cmyk:
            let v = cmyk
            return "cmyk(\(Int((v.c * 100).rounded()))%, \(Int((v.m * 100).rounded()))%, \(Int((v.y * 100).rounded()))%, \(Int((v.k * 100).rounded()))%)"
        case .swiftUI: return "Color(red: \(f3(red)), green: \(f3(green)), blue: \(f3(blue)))"
        case .nsColor: return "NSColor(srgbRed: \(f3(red)), green: \(f3(green)), blue: \(f3(blue)), alpha: \(f3(alpha)))"
        case .uiColor: return "UIColor(red: \(f3(red)), green: \(f3(green)), blue: \(f3(blue)), alpha: \(f3(alpha)))"
        case .cssVariable: return "--\(cssName): \(hex);"
        }
    }

    var cssName: String {
        let base = (name?.isEmpty == false ? (name ?? "") : "color-" + String(hex.dropFirst()).lowercased())
        return base.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }
}

enum ColorFormat: String, CaseIterable, Identifiable, Codable {
    case hex, hexNoHash, rgb, rgba, hsl, hsb, cmyk, swiftUI, nsColor, uiColor, cssVariable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hex: "HEX"
        case .hexNoHash: L("HEX without #")
        case .rgb: "RGB"
        case .rgba: "RGBA"
        case .hsl: "HSL"
        case .hsb: "HSB"
        case .cmyk: "CMYK"
        case .swiftUI: "SwiftUI Color"
        case .nsColor: "NSColor"
        case .uiColor: "UIColor"
        case .cssVariable: L("CSS variable")
        }
    }
}

struct ColorPalette: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colors: [SavedColor] = []
    var created = Date()
}

enum PaletteExportFormat: String, CaseIterable, Identifiable {
    case json, css, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .json: "JSON"
        case .css: L("CSS variables")
        case .text: L("Plain text (HEX list)")
        }
    }
    var fileExtension: String {
        switch self {
        case .json: "json"
        case .css: "css"
        case .text: "txt"
        }
    }

    func render(_ palette: ColorPalette) -> String {
        switch self {
        case .json:
            struct Item: Encodable { let name: String; let hex: String; let alpha: Double }
            struct Out: Encodable { let name: String; let colors: [Item] }
            let out = Out(name: palette.name, colors: palette.colors.map { Item(name: $0.displayName, hex: $0.hex, alpha: $0.alpha) })
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? enc.encode(out)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        case .css:
            let lines = palette.colors.map { "  " + $0.string(.cssVariable) }
            return "/* \(palette.name) */\n:root {\n" + lines.joined(separator: "\n") + "\n}\n"
        case .text:
            return palette.colors.map(\.hex).joined(separator: "\n") + "\n"
        }
    }
}
