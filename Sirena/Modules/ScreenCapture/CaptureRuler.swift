/// CaptureRuler.swift
///
/// The capture's ruler, for checking a layout: always straight (across, down or at 45°),
/// its ends on pixel centers, drawn one device pixel thin with a tick every 10 pt. A dashed
/// guide carries it on across the whole selection, so what should line up with it shows at a
/// glance, and a small label gives its length in points.

import AppKit

enum CaptureRuler {
    /// The end of a ruler started at `a` (already on a pixel center) with the pointer at `b`:
    /// the nearest of the eight straight directions, a whole number of pixels long.
    static func end(from a: CGPoint, toward b: CGPoint, scale: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        func pixels(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        switch (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 4 {
        case 0: return CGPoint(x: a.x + pixels(dx), y: a.y)
        case 2: return CGPoint(x: a.x, y: a.y + pixels(dy))
        default:
            let d = pixels((abs(dx) + abs(dy)) / 2)
            return CGPoint(x: a.x + (dx < 0 ? -d : d), y: a.y + (dy < 0 ? -d : d))
        }
    }

    /// The center of the pixel under a point, so a one-pixel line covers exactly one row or column.
    static func pixelCenter(_ p: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: ((p.x * scale).rounded(.down) + 0.5) / scale, y: ((p.y * scale).rounded(.down) + 0.5) / scale)
    }

    /// Paints a ruler into the current graphics context. `offset` turns global points into
    /// the context's; `selection` (global) is where its label must stay.
    static func draw(_ s: BrushStroke, offset: CGPoint, selection: CGRect) {
        guard let ga = s.points.first, let gb = s.points.last else { return }
        let a = CGPoint(x: ga.x - offset.x, y: ga.y - offset.y)
        let b = CGPoint(x: gb.x - offset.x, y: gb.y - offset.y)
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return }
        let u = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        // Ticks on the upper side (left for a vertical ruler), whichever way it was drawn.
        var n = CGPoint(x: -u.y, y: u.x)
        if n.y < 0 || (n.y == 0 && n.x > 0) { n = CGPoint(x: -n.x, y: -n.y) }
        func at(_ t: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: a.x + u.x * t + n.x * side, y: a.y + u.y * t + n.y * side)
        }

        let hairline = devicePixel
        let guide = NSBezierPath()
        guide.move(to: at(-BrushRenderer.rulerReach))
        guide.line(to: at(length + BrushRenderer.rulerReach))
        guide.lineWidth = hairline
        // The reach is a multiple of the dash pattern: a dash starts right at the ruler's end.
        guide.setLineDash([6, 4], count: 2, phase: 0)
        s.color.withAlphaComponent(0.85).setStroke()
        guide.stroke()

        NSGraphicsContext.saveGraphicsState()
        // A faint dark rim keeps the ruler readable on a background of its own color.
        let rim = NSShadow()
        rim.shadowBlurRadius = 1
        rim.shadowOffset = .zero
        rim.shadowColor = NSColor.black.withAlphaComponent(0.3)
        rim.set()
        let ruler = NSBezierPath()
        ruler.move(to: a)
        ruler.line(to: b)
        for end in [0, length] {
            ruler.move(to: at(end, -6))
            ruler.line(to: at(end, 6))
        }
        var t: CGFloat = 10
        while t < length - 0.5 {
            let major = Int((t / 10).rounded()) % 5 == 0
            ruler.move(to: at(t))
            ruler.line(to: at(t, major ? 5 : 3))
            t += 10
        }
        ruler.lineWidth = hairline
        ruler.lineCapStyle = .butt
        s.color.setStroke()
        ruler.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawLabel(text(for: ga, gb, length: length), middle: at(length / 2), normal: n,
                  within: selection.offsetBy(dx: -offset.x, dy: -offset.y))
    }

    /// "240 pt" across or down, "170 × 170 pt" at 45°.
    private static func text(for a: CGPoint, _ b: CGPoint, length: CGFloat) -> String {
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        if dx < 0.01 || dy < 0.01 { return "\(number(length)) pt" }
        return "\(number(dx)) × \(number(dy)) pt"
    }

    private static func number(_ v: CGFloat) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", Double(rounded))
    }

    /// A small dark capsule beside the ruler's middle, on the ticks' side (the other side, or
    /// pushed inside, when the selection's edge is too close).
    private static func drawLabel(_ text: String, middle: CGPoint, normal n: CGPoint, within bounds: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let w = ceil(size.width) + 12, h = ceil(size.height) + 4
        let distance = 9 + abs(n.x) * w / 2 + abs(n.y) * h / 2
        func pill(_ side: CGFloat) -> CGRect {
            CGRect(x: middle.x + n.x * distance * side - w / 2, y: middle.y + n.y * distance * side - h / 2, width: w, height: h)
        }
        var rect = pill(1)
        if !bounds.contains(rect), bounds.contains(pill(-1)) { rect = pill(-1) }
        if rect.width <= bounds.width - 4, rect.height <= bounds.height - 4 {
            rect.origin.x = min(max(rect.minX, bounds.minX + 2), bounds.maxX - 2 - w)
            rect.origin.y = min(max(rect.minY, bounds.minY + 2), bounds.maxY - 2 - h)
        }
        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + (h - size.height) / 2), withAttributes: attributes)
    }

    /// One pixel of the device being drawn into (half a point on Retina, one pixel of a
    /// full-resolution copy).
    private static var devicePixel: CGFloat {
        guard let t = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform else { return 0.5 }
        return 1 / max(hypot(t.a, t.b), 1)
    }
}
