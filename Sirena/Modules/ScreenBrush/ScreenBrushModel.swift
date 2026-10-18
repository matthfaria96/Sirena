/// ScreenBrushModel.swift
///
/// Tools, strokes and the drawing document of Desenho Livre. Written from scratch for
/// Sirena: ScreenBrush is closed source, only its public feature list was used.

import AppKit

enum BrushTool: String, CaseIterable, Identifiable {
    case pen, highlighter, laser, line, arrow, rectangle, ellipse, text, eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return L("Pen")
        case .highlighter: return L("Highlighter")
        case .laser: return L("Laser Pen")
        case .line: return L("Line")
        case .arrow: return L("Arrow")
        case .rectangle: return L("Rectangle")
        case .ellipse: return L("Ellipse")
        case .text: return L("Text")
        case .eraser: return L("Eraser")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .laser: return "wand.and.rays"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }

    /// Letter that selects the tool while drawing (numbers 1–9 follow the list order).
    var key: Character {
        switch self {
        case .pen: return "p"
        case .highlighter: return "h"
        case .laser: return "k"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .text: return "t"
        case .eraser: return "e"
        }
    }

    /// The tools offered (the laser pen and the plain line were left out on request).
    static let available: [BrushTool] = [.pen, .highlighter, .arrow, .rectangle, .ellipse, .text, .eraser]

    var isShape: Bool { [.line, .arrow, .rectangle, .ellipse].contains(self) }
}

enum BrushPalette {
    static let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                    .systemBlue, .systemPurple, .white, .black]
    static func color(_ index: Int) -> NSColor { colors[min(max(index, 0), colors.count - 1)] }
}

enum BrushBackground: Int, CaseIterable {
    case none, dim, whiteboard, blackboard
}

struct BrushStroke: Identifiable {
    let id = UUID()
    var tool: BrushTool
    var color: NSColor
    var width: CGFloat
    /// Global screen coordinates (Cocoa, bottom-left origin).
    var points: [CGPoint]
    var text: String = ""
    var created = Date()
    var filled = false

    var fontSize: CGFloat { 12 + width * 3 }
}

/// What changed in the document, so the overlays repaint only what they must.
enum BrushChange {
    /// Committed strokes or background: rebuild the cached layer.
    case strokes
    /// Live stroke or lasers, in global coordinates.
    case area(CGRect)
    case spotlight
}

/// Everything drawn, shared by the overlay of every screen.
@MainActor
@Observable
final class BrushDocument {
    /// Committed strokes (never lasers): what undo and redo snapshot.
    private(set) var strokes: [BrushStroke] = [] { didSet { onChange(.strokes) } }
    /// Laser strokes fade on their own and stay out of the history.
    private(set) var lasers: [BrushStroke] = []
    /// Stroke being drawn (live preview).
    var current: BrushStroke? {
        didSet { onChange(.area(BrushRenderer.dirtyRect(old: oldValue, new: current))) }
    }
    var background: BrushBackground = .none { didSet { onChange(.strokes) } }
    var spotlight = false { didSet { onChange(.spotlight) } }
    var clickThrough = false
    /// Last mouse location, for the spotlight.
    @ObservationIgnored var cursor: CGPoint = .zero { didSet { if spotlight { onChange(.spotlight) } } }

    private(set) var undoStack: [[BrushStroke]] = []
    private(set) var redoStack: [[BrushStroke]] = []
    @ObservationIgnored private var eraseCheckpointPending = false
    @ObservationIgnored private var outlineCache: [UUID: (radius: CGFloat, bounds: CGRect, outline: CGPath)] = [:]

    @ObservationIgnored var onChange: (BrushChange) -> Void = { _ in }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { strokes.isEmpty }

    private func checkpoint() {
        undoStack.append(strokes)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func commit(_ stroke: BrushStroke) {
        if stroke.tool == .laser {
            lasers.append(stroke)
            onChange(.area(BrushRenderer.bounds(stroke)))
            return
        }
        checkpoint()
        strokes.append(stroke)
    }

    /// Start of an eraser gesture: the whole drag becomes one undo step.
    func beginErase() { eraseCheckpointPending = true }

    func erase(at point: CGPoint, radius: CGFloat) {
        let hits = strokes.indices.filter { hit(strokes[$0], point, radius: radius) }
        guard !hits.isEmpty else { return }
        if eraseCheckpointPending { checkpoint(); eraseCheckpointPending = false }
        hits.forEach { outlineCache[strokes[$0].id] = nil }
        strokes.remove(atOffsets: IndexSet(hits))
    }

    private func hit(_ s: BrushStroke, _ point: CGPoint, radius: CGFloat) -> Bool {
        if s.tool == .text { return BrushRenderer.textRect(s).insetBy(dx: -radius, dy: -radius).contains(point) }
        if let cached = outlineCache[s.id], cached.radius == radius {
            return cached.bounds.contains(point) && cached.outline.contains(point)
        }
        let width = max(s.width * (s.tool == .highlighter ? 4 : 1), 2) + radius * 2
        let path = BrushRenderer.path(for: s).cgPath
        let bounds = path.boundingBoxOfPath.insetBy(dx: -width, dy: -width)
        let outline = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        outlineCache[s.id] = (radius, bounds, outline)
        return bounds.contains(point) && outline.contains(point)
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        checkpoint()
        strokes.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    func reset() {
        strokes.removeAll()
        lasers.removeAll()
        outlineCache.removeAll()
        current = nil
        undoStack.removeAll()
        redoStack.removeAll()
        background = .none
        spotlight = false
        clickThrough = false
    }

    /// Repaints fading lasers and drops finished ones. Returns true while any is visible.
    func tickLasers(delay: TimeInterval) -> Bool {
        let now = Date()
        let limit = delay + BrushRenderer.fadeDuration
        let area = (lasers + [current].compactMap { $0 }.filter { $0.tool == .laser })
            .map(BrushRenderer.bounds).reduce(CGRect.null) { $0.union($1) }
        lasers.removeAll { now.timeIntervalSince($0.created) > limit }
        if !area.isNull { onChange(.area(area)) }
        return !lasers.isEmpty || current?.tool == .laser
    }
}

/// Turns strokes into paths and paints them.
enum BrushRenderer {
    static let fadeDuration: TimeInterval = 0.6

    /// Smooth path through the points: quadratic curves between the midpoints.
    static func smoothPath(_ pts: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { path.line(to: $0) }
            if pts.count == 1 { path.line(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            return path
        }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.curve(to: mid, controlPoint: pts[i])
        }
        if let last = pts.last { path.line(to: last) }
        return path
    }

    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func path(for s: BrushStroke) -> NSBezierPath {
        guard let a = s.points.first, let b = s.points.last else { return NSBezierPath() }
        switch s.tool {
        case .pen, .highlighter, .laser, .eraser:
            return smoothPath(s.points)
        case .line:
            let p = NSBezierPath(); p.move(to: a); p.line(to: b); return p
        case .arrow:
            let p = NSBezierPath(); p.move(to: a); p.line(to: b)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(14, s.width * 4)
            for side in [CGFloat.pi * 0.83, -CGFloat.pi * 0.83] {
                p.move(to: b)
                p.line(to: CGPoint(x: b.x + head * cos(angle + side), y: b.y + head * sin(angle + side)))
            }
            return p
        case .rectangle:
            return NSBezierPath(roundedRect: rect(a, b), xRadius: 4, yRadius: 4)
        case .ellipse:
            return NSBezierPath(ovalIn: rect(a, b))
        case .text:
            return NSBezierPath(rect: textRect(s))
        }
    }

    static func textAttributes(_ s: BrushStroke, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: s.fontSize, weight: .semibold),
         .foregroundColor: s.color.withAlphaComponent(alpha)]
    }

    static func textRect(_ s: BrushStroke) -> CGRect {
        let origin = s.points.first ?? .zero
        let size = (s.text as NSString).size(withAttributes: textAttributes(s))
        return CGRect(origin: CGPoint(x: origin.x, y: origin.y - size.height), size: size)
    }

    /// Area a stroke paints, glow and arrow head included.
    static func bounds(_ s: BrushStroke) -> CGRect {
        if s.tool == .text { return textRect(s).insetBy(dx: -8, dy: -8) }
        let pad = s.width * 4 + 24
        return path(for: s).bounds.insetBy(dx: -pad, dy: -pad)
    }

    /// What to repaint when the live stroke changes: only its newest piece for freehand.
    static func dirtyRect(old: BrushStroke?, new: BrushStroke?) -> CGRect {
        guard let new else { return old.map(bounds) ?? .null }
        guard let old, old.id == new.id, !new.tool.isShape else {
            return bounds(new).union(old.map(bounds) ?? .null)
        }
        let tail = new.points.suffix(4)
        var r = CGRect.null
        for p in tail { r = r.union(CGRect(origin: p, size: .zero)) }
        let pad = new.width * 4 + 24
        return r.insetBy(dx: -pad, dy: -pad)
    }

    /// Paints one stroke. `offset` converts global coordinates into the view's.
    static func draw(_ s: BrushStroke, offset: CGPoint, laserDelay: TimeInterval) {
        var alpha: CGFloat = 1
        if s.tool == .laser {
            let age = Date().timeIntervalSince(s.created)
            if age > laserDelay { alpha = max(0, 1 - CGFloat((age - laserDelay) / fadeDuration)) }
            if alpha <= 0 { return }
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(translationByX: -offset.x, byY: -offset.y)

        if s.tool == .text {
            guard let p = s.points.first else { return }
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            let r = textRect(s)
            (s.text as NSString).draw(at: CGPoint(x: p.x - offset.x, y: r.minY - offset.y), withAttributes: textAttributes(s))
            return
        }

        let path = self.path(for: s)
        path.transform(using: transform)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch s.tool {
        case .highlighter:
            path.lineWidth = s.width * 4
            path.lineCapStyle = .square
            s.color.withAlphaComponent(0.35).setStroke()
        case .laser:
            let glow = NSShadow()
            glow.shadowBlurRadius = s.width * 2
            glow.shadowColor = s.color.withAlphaComponent(alpha)
            glow.set()
            path.lineWidth = s.width
            s.color.withAlphaComponent(alpha).setStroke()
        default:
            path.lineWidth = s.width
            s.color.setStroke()
            if s.filled, s.tool == .rectangle || s.tool == .ellipse {
                s.color.withAlphaComponent(0.25).setFill()
                path.fill()
            }
        }
        path.stroke()
    }
}
