/// AppScreenPlacement.swift
///
/// Where a window goes when its app is set to open on another display (Ajustes › Monitores).
/// Pure geometry, no AppKit or AX: tested by scripts/test-app-screen-placement.sh.
/// All rectangles are in global top-left coordinates (the ones AX uses).

import CoreGraphics

enum AppScreenPlacementMode: String, Codable, CaseIterable {
    /// Same size (shrunk only if it doesn't fit), same relative spot.
    case keep
    /// The whole usable area of the display.
    case fill
    /// Same size (shrunk only if it doesn't fit), centred.
    case center
}

enum AppScreenPlacement {
    /// The display (index into `screens`, their full frames) holding most of `window`; nil when
    /// it touches none. Ties go to the one holding the window's centre.
    static func screenIndex(of window: CGRect, in screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(window)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (index, area) }
        }
        if let best { return best.index }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.firstIndex { $0.contains(center) }
    }

    /// The frame for `window`, now on a display whose usable area is `from`, on the display
    /// whose usable area is `to`.
    static func frame(for window: CGRect, from: CGRect, to: CGRect, mode: AppScreenPlacementMode) -> CGRect {
        if mode == .fill { return to.integral }
        let size = CGSize(width: min(window.width, to.width), height: min(window.height, to.height))
        let origin: CGPoint
        switch mode {
        case .center, .fill:
            origin = CGPoint(x: to.midX - size.width / 2, y: to.midY - size.height / 2)
        case .keep:
            // Where the window sat in the room it had to move in, from 0 (left/top) to 1.
            let roomX = from.width - window.width
            let roomY = from.height - window.height
            let relX = roomX > 0 ? clamp((window.minX - from.minX) / roomX) : 0.5
            let relY = roomY > 0 ? clamp((window.minY - from.minY) / roomY) : 0.5
            origin = CGPoint(x: to.minX + (to.width - size.width) * relX,
                             y: to.minY + (to.height - size.height) * relY)
        }
        // Round the origin, not the rect: `integral` would grow the size by a point.
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
}
