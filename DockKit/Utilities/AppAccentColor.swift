/// AppAccentColor.swift
///
/// Sirena: the color of an app, taken from its icon, to tint the glass of the menu bar panel,
/// the ⌘ Tab switcher and the Dock previews. The icon is shrunk to 32×32, its pixels grouped by
/// hue (grays, near-blacks and see-through pixels left out), and the strongest group wins,
/// weighted by how saturated and bright it is. Icons without a clear color (black and white
/// ones) fall back to the system accent color. Worked out once per app.

import AppKit
import SwiftUI

@MainActor
@Observable
public final class AppAccentColor {
    public static let shared = AppAccentColor()

    public static let enabledKey = "appearance.appTint.enabled"
    public static let strengthKey = "appearance.appTint.strength"
    public static let defaultStrength = 0.5

    /// The color of the last app in front other than Sirena itself (Sirena comes forward
    /// while its menu is open; the tint should still be the app you were using).
    public private(set) var current: NSColor?

    @ObservationIgnored private var cache: [String: NSColor?] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        update(with: NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.update(with: app) }
        }
    }

    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// 0…1, how strong the tint is.
    public static var strength: Double {
        let value = UserDefaults.standard.object(forKey: strengthKey) as? Double ?? defaultStrength
        return min(max(value, 0), 1)
    }

    /// The tint for the app you were using, or nil when the feature is off.
    public var tint: NSColor? { Self.isEnabled ? current : nil }

    /// The tint for a given app, or nil when the feature is off.
    public func tint(for app: NSRunningApplication?) -> NSColor? {
        guard Self.isEnabled, let app else { return nil }
        return color(for: app)
    }

    public func tint(forPID pid: pid_t) -> NSColor? {
        tint(for: NSRunningApplication(processIdentifier: pid))
    }

    private func update(with app: NSRunningApplication?) {
        guard let app, app != NSRunningApplication.current else { return }
        current = color(for: app)
    }

    /// The app's color, from its icon (cached).
    public func color(for app: NSRunningApplication) -> NSColor {
        let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "pid-\(app.processIdentifier)"
        if let cached = cache[key] {
            return cached ?? .controlAccentColor
        }
        let icon = app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? app.icon
        let found = icon.flatMap(Self.dominantColor(of:))
        cache[key] = found
        return found ?? .controlAccentColor
    }

    // MARK: - Dominant color

    nonisolated static func dominantColor(of image: NSImage) -> NSColor? {
        let side = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }

        let buckets = 24
        var weight = [Double](repeating: 0, count: buckets)
        var red = [Double](repeating: 0, count: buckets)
        var green = [Double](repeating: 0, count: buckets)
        var blue = [Double](repeating: 0, count: buckets)
        var opaquePixels = 0.0

        for index in 0..<(side * side) {
            let alpha = Double(data[index * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            opaquePixels += 1
            // Premultiplied: undo it before reading the color.
            let r = min(Double(data[index * 4]) / 255 / alpha, 1)
            let g = min(Double(data[index * 4 + 1]) / 255 / alpha, 1)
            let b = min(Double(data[index * 4 + 2]) / 255 / alpha, 1)
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let brightness = maxValue
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
            guard saturation > 0.28, brightness > 0.25 else { continue }
            var hue: Double
            let delta = maxValue - minValue
            if maxValue == r {
                hue = (g - b) / delta
            } else if maxValue == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bucket = min(Int(hue * Double(buckets)), buckets - 1)
            let w = saturation * brightness
            weight[bucket] += w
            red[bucket] += r * w
            green[bucket] += g * w
            blue[bucket] += b * w
        }

        // Neighbouring hues belong together (a gradient icon spreads over several buckets).
        var best = -1
        var bestWeight = 0.0
        for bucket in 0..<buckets {
            let total = weight[bucket] + 0.5 * (weight[(bucket + 1) % buckets] + weight[(bucket + buckets - 1) % buckets])
            if total > bestWeight {
                bestWeight = total
                best = bucket
            }
        }
        // Too little color to call it the icon's color.
        guard best >= 0, opaquePixels > 0, weight[best] / opaquePixels > 0.06 else { return nil }
        let w = weight[best]
        let color = NSColor(srgbRed: red[best] / w, green: green[best] / w, blue: blue[best] / w, alpha: 1)
        // Keep it lively but not glaring.
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: min(max(s, 0.45), 0.9), brightness: min(max(v, 0.55), 0.95), alpha: 1)
    }
}
