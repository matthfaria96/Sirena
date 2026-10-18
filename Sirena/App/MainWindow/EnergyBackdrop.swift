/// EnergyBackdrop.swift
///
/// The purple field behind Home's banner, after MacDash's home backdrop (its "smartCare"
/// palette): soft blooms of light over a deep violet, with a fine grain. Here the blooms
/// drift back and forth on out-of-phase cycles, so the banner feels alive.

import AppKit
import SwiftUI

struct EnergyBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MacDash's purple palette.
    private static let primary = Color(red: 0.52, green: 0.12, blue: 0.74)
    private static let secondary = Color(red: 0.33, green: 0.07, blue: 0.58)
    private static let deep = Color(red: 0.10, green: 0.04, blue: 0.32)
    private static let accent = Color(red: 0.96, green: 0.24, blue: 0.83)
    private static let glow = Color(red: 0.62, green: 0.20, blue: 0.95)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            GeometryReader { proxy in
                field(size: proxy.size, time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
        }
        .overlay(Grain().opacity(0.06).blendMode(.overlay))
        .allowsHitTesting(false)
    }

    private func field(size: CGSize, time: TimeInterval) -> some View {
        let span = max(size.width, size.height)
        // Out-of-phase swings: each light wanders on its own slow loop, never in step.
        func swing(_ period: Double, _ phase: Double) -> CGFloat { CGFloat(sin(time * .pi * 2 / period + phase)) }
        func point(_ x: CGFloat, _ y: CGFloat, _ seed: Double, _ reach: CGFloat) -> UnitPoint {
            UnitPoint(x: x + swing(9 + seed * 2.3, seed) * reach, y: y + swing(7 + seed * 1.7, seed * 1.9) * reach * 0.8)
        }
        let pulse = 0.85 + 0.15 * Double(swing(5.5, 0.4))
        return ZStack {
            Self.secondary
            bloom(Self.primary, at: point(0.18, 0.25, 0, 0.18), radius: span * 0.75, opacity: 0.95)
            bloom(Self.glow, at: point(0.62, 0.70, 1, 0.22), radius: span * 0.55, opacity: 0.75 * pulse)
            bloom(Self.accent, at: point(0.88, 0.15, 2, 0.16), radius: span * 0.45, opacity: 0.55 * pulse)
            bloom(Self.accent, at: point(0.35, 0.95, 3, 0.20), radius: span * 0.35, opacity: 0.35)
            bloom(Self.deep, at: point(0.05, 0.95, 4, 0.10), radius: span * 0.55, opacity: 0.85)
            bloom(Self.deep, at: point(0.55, 0.05, 5, 0.12), radius: span * 0.30, opacity: 0.55)
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup()
    }

    private func bloom(_ color: Color, at center: UnitPoint, radius: CGFloat, opacity: Double) -> some View {
        RadialGradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.55), location: 0.35),
            .init(color: color.opacity(0), location: 1)
        ], center: center, startRadius: 0, endRadius: radius)
    }
}

/// Fine film grain, drawn once.
private struct Grain: View {
    private static let tile: NSImage = {
        let side = 128
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite,
                                   bytesPerRow: side, bitsPerPixel: 8)!
        if let data = rep.bitmapData {
            for index in 0..<(side * side) { data[index] = UInt8.random(in: 0...255) }
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }()

    var body: some View {
        Image(nsImage: Self.tile).resizable(resizingMode: .tile)
    }
}
