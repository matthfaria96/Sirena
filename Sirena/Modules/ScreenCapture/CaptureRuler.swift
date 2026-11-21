/// CaptureRuler.swift
///
/// The capture's ruler, for checking a layout: always straight (across, down or at 45°),
/// its ends on pixel centers, drawn one device pixel thin in a color of its own (magenta, like
/// a design tool's guides, whatever the marks' color) with a tick every 10 screen pixels. A
/// dashed guide carries it on across the whole selection, so what should line up with it shows
/// at a glance, and a small label gives its length in the screen's pixels.

import AppKit

enum CaptureRuler {
    /// Its own color, apart from the palette: a measure never reads as a mark.
    static let color = NSColor(srgbRed: 1, green: 0.17, blue: 0.75, alpha: 1)

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
    /// the context's; `selection` (global) is where its label must stay; `scale` is the
    /// display's pixels per point, for the ticks and the length.
    static func draw(_ s: BrushStroke, offset: CGPoint, selection: CGRect, scale: CGFloat) {
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
        // A tick every 10 pixels, a longer one every 50 (on the ruler's own axis: a diagonal
        // counts the pixels it crosses across, as its label does).
        let step = 10 / max(scale, 1) * (abs(u.x) > 0.01 && abs(u.y) > 0.01 ? 2.squareRoot() : 1)
        var index = 1
        while CGFloat(index) * step < length - 0.25 {
            let t = CGFloat(index) * step
            ruler.move(to: at(t))
            ruler.line(to: at(t, index % 5 == 0 ? 5 : 3))
            index += 1
        }
        ruler.lineWidth = hairline
        ruler.lineCapStyle = .butt
        s.color.setStroke()
        ruler.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawLabel(text(for: ga, gb, length: length, scale: scale), middle: at(length / 2), normal: n,
                  within: selection.offsetBy(dx: -offset.x, dy: -offset.y))
    }

    /// "240 px" across or down, "170 × 170 px" at 45°: the screen's own pixels (the ends sit
    /// on pixel centers, so these are whole numbers).
    private static func text(for a: CGPoint, _ b: CGPoint, length: CGFloat, scale: CGFloat) -> String {
        let dx = abs(b.x - a.x) * scale, dy = abs(b.y - a.y) * scale
        if dx < 0.01 || dy < 0.01 { return "\(Int((length * scale).rounded())) px" }
        return "\(Int(dx.rounded())) × \(Int(dy.rounded())) px"
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
