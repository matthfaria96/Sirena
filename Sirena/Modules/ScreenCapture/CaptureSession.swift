/// CaptureSession.swift
///
/// One screen capture, from the key press to copy, save, record or cancel: the frozen
/// displays (one overlay each), the selection (dragged, or a window or the whole display
/// picked with a click), the marks drawn on it and the two toolbars around it.
/// Everything is in Cocoa global coordinates (bottom-left origin), in points.

import AppKit
import Carbon.HIToolbox

@MainActor
@Observable
final class CaptureSession {
    enum Outcome {
        case cancel, copy, save, copyAndSave, record
    }

    /// The selection's eight handles.
    enum Handle: CaseIterable {
        case bottomLeft, bottomRight, topRight, topLeft, bottom, right, top, left
    }

    enum Drag: Equatable {
        /// Pressed with nothing selected yet: a click picks what is under it, a drag selects.
        case pressing(CGPoint)
        case selecting(anchor: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, original: CGRect)
        case drawing
    }

    /// What the controller gets back when the capture ends with something to do.
    struct Result {
        let outcome: Outcome
        /// The selection with its marks (nil for a recording).
        let image: CGImage?
        let selection: CGRect
        let displayID: CGDirectDisplayID
        /// The window picked with a click and left as it was: a recording follows it.
        let window: CaptureWindow?
    }

    /// Stroke widths offered by the thickness button.
    static let widths: [Double] = [2, 4, 8]

    @ObservationIgnored let frames: [CaptureFrame]
    @ObservationIgnored let windows: [CaptureWindow]
    @ObservationIgnored let document = BrushDocument()
    /// Called once; nil when cancelled.
    @ObservationIgnored var onFinish: (Result?) -> Void = { _ in }

    private(set) var selection: CGRect?
    private(set) var pickedWindow: CaptureWindow?
    /// Under the pointer while nothing is selected: a window, or the whole display.
    private(set) var hover: CGRect?
    private(set) var hoverWindow: CaptureWindow?
    private(set) var drag: Drag?
    private(set) var tool: BrushTool?
    var showsPalette = false { didSet { refresh() } }
    /// The name of the toolbar button under the pointer.
    private(set) var hint: String?

    @ObservationIgnored private(set) var cursor: CGPoint = NSEvent.mouseLocation
    @ObservationIgnored private var overlays: [CaptureOverlayWindow] = []
    @ObservationIgnored private var pixelCache: [UUID: (rect: CGRect, image: CGImage)] = [:]
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var finished = false

    private var settings: ScreenCaptureController { .shared }

    init(frames: [CaptureFrame], windows: [CaptureWindow], previousApp: NSRunningApplication?) {
        self.frames = frames
        self.windows = windows
        self.previousApp = previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : previousApp
    }

    var color: NSColor { BrushPalette.color(settings.colorIndex) }

    /// The toolbars hide while the selection is being dragged or resized.
    var showsToolbars: Bool {
        guard selection != nil else { return false }
        switch drag {
        case nil, .drawing?: return true
        default: return false
        }
    }

    /// Selecting or resizing: the loupe helps aim.
    var showsLoupe: Bool {
        guard settings.showsLoupe else { return false }
        switch drag {
        case .selecting?, .resizing?: return true
        default: return false
        }
    }

    // MARK: Showing and closing

    func show() {
        document.onChange = { [weak self] change in
            self?.overlays.forEach { $0.overlay.marksChanged(change) }
        }
        overlays = frames.map { CaptureOverlayWindow(capture: $0, session: self) }
        // Veil and labels in place before anything shows.
        updateHover(at: cursor)
        refresh()
        overlays.forEach { $0.orderFrontRegardless() }
        SirenaActivation.activateForTool()
        focusOverlayUnderMouse()
        updateCursor()

        // The keyboard may stay with another app (macOS can refuse to bring Sirena forward):
        // Esc and Return still work from there.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = Int(event.keyCode)
            Task { @MainActor in self?.globalKey(code) }
        }) { monitors.append(monitor) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.cancel) }
        })
        // Another app came forward (⌘Tab, a click through): the frozen screen is stale.
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.cancel) }
        })
    }

    private func focusOverlayUnderMouse() {
        let window = overlays.first { $0.frame.contains(cursor) } ?? overlays.first
        window?.makeKeyAndOrderFront(nil)
        window.map { $0.makeFirstResponder($0.overlay) }
    }

    private func globalKey(_ code: Int) {
        switch code {
        case kVK_Escape: finish(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter: if selection != nil { finish(settings.primaryAction.outcome) }
        default: break
        }
    }

    /// Ends the capture. Copy, save and record need a selection.
    func finish(_ outcome: Outcome) {
        guard !finished else { return }
        // A text still being typed belongs to the capture.
        overlays.forEach { $0.overlay.commitText() }
        if outcome != .cancel, selection == nil {
            NSSound.beep()
            return
        }
        finished = true
        var result: Result?
        if outcome != .cancel, let selection, let frame = frame(of: selection) {
            result = Result(outcome: outcome,
                            image: outcome == .record ? nil : render(selection, in: frame),
                            selection: selection, displayID: frame.displayID, window: pickedWindow)
        }
        close()
        onFinish(result)
    }

    private func close() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        document.onChange = { _ in }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        pixelCache.removeAll()
        NSCursor.arrow.set()
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Geometry

    func frame(containing p: CGPoint) -> CaptureFrame? {
        frames.first { $0.frame.contains(p) }
            ?? frames.min { distance(p, $0.frame) < distance(p, $1.frame) }
    }

    func frame(of rect: CGRect) -> CaptureFrame? {
        frame(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    /// Whole points on every edge.
    private func snapped(_ r: CGRect) -> CGRect {
        let x0 = r.minX.rounded(), y0 = r.minY.rounded(), x1 = r.maxX.rounded(), y1 = r.maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func handlePoints(_ r: CGRect) -> [(Handle, CGPoint)] {
        [(.bottomLeft, CGPoint(x: r.minX, y: r.minY)), (.bottomRight, CGPoint(x: r.maxX, y: r.minY)),
         (.topRight, CGPoint(x: r.maxX, y: r.maxY)), (.topLeft, CGPoint(x: r.minX, y: r.maxY)),
         (.bottom, CGPoint(x: r.midX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
         (.top, CGPoint(x: r.midX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY))]
    }

    /// A handle, or the edge just outside the selection (inside it the marks win).
    private func handle(at p: CGPoint, of r: CGRect) -> Handle? {
        if let hit = Self.handlePoints(r).first(where: { hypot($0.1.x - p.x, $0.1.y - p.y) <= 9 }) { return hit.0 }
        let band: CGFloat = 5
        guard !r.contains(p), r.insetBy(dx: -band, dy: -band).contains(p) else { return nil }
        if p.x < r.minX { return .left }
        if p.x > r.maxX { return .right }
        return p.y < r.minY ? .bottom : .top
    }

    // MARK: Mouse

    func mouseDown(at p: CGPoint, clickCount: Int) {
        cursor = p
        overlays.forEach { $0.overlay.commitText() }
        if showsPalette { showsPalette = false }
        if let selection {
            if let handle = handle(at: p, of: selection) {
                drag = .resizing(handle, original: selection)
                refresh()
                return
            }
            if selection.contains(p) {
                if let tool {
                    beginMark(tool, at: p)
                } else if clickCount >= 2 {
                    finish(settings.primaryAction.outcome)
                } else {
                    drag = .moving(start: p, original: selection)
                    refresh()
                    updateCursor()
                }
                return
            }
            // Outside: a fresh selection, unless that would throw marks away.
            guard document.isEmpty else { return }
            self.selection = nil
            pickedWindow = nil
            tool = nil
        }
        drag = .pressing(p)
        refresh()
    }

    func mouseDragged(to raw: CGPoint, shift: Bool) {
        cursor = raw
        switch drag {
        case .pressing(let start)?:
            guard hypot(raw.x - start.x, raw.y - start.y) >= 4 else { return }
            drag = .selecting(anchor: start)
            hover = nil
            hoverWindow = nil
            select(from: start, to: raw, square: shift)
        case .selecting(let anchor)?:
            select(from: anchor, to: raw, square: shift)
        case .moving(let start, let original)?:
            guard let bounds = frame(of: original)?.frame else { return }
            var r = original.offsetBy(dx: (raw.x - start.x).rounded(), dy: (raw.y - start.y).rounded())
            r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            selection = r
            pickedWindow = nil
        case .resizing(let handle, let original)?:
            guard let bounds = frame(of: original)?.frame else { return }
            let p = clamp(raw, to: bounds)
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            switch handle {
            case .left, .topLeft, .bottomLeft: minX = p.x
            case .right, .topRight, .bottomRight: maxX = p.x
            default: break
            }
            switch handle {
            case .bottom, .bottomLeft, .bottomRight: minY = p.y
            case .top, .topLeft, .topRight: maxY = p.y
            default: break
            }
            selection = snapped(CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY)))
            pickedWindow = nil
        case .drawing?:
            drawMark(to: raw, shift: shift)
            overlays.forEach { $0.overlay.updateLoupe() }
            return
        case nil:
            return
        }
        refresh()
    }

    private func select(from anchor: CGPoint, to raw: CGPoint, square: Bool) {
        guard let bounds = frame(containing: anchor)?.frame else { return }
        var p = clamp(raw, to: bounds)
        if square {
            let side = max(abs(p.x - anchor.x), abs(p.y - anchor.y))
            p = clamp(CGPoint(x: anchor.x + (p.x < anchor.x ? -side : side), y: anchor.y + (p.y < anchor.y ? -side : side)), to: bounds)
        }
        selection = snapped(BrushRenderer.rect(anchor, p))
        pickedWindow = nil
    }

    func mouseUp(at p: CGPoint) {
        cursor = p
        switch drag {
        case .pressing?:
            // A click: the window under the pointer, or the whole display.
            if let hover {
                selection = snapped(hover)
                pickedWindow = hoverWindow
                self.hover = nil
                hoverWindow = nil
            }
        case .selecting?:
            if let s = selection, s.width < 4 || s.height < 4 {
                selection = nil
                drag = nil
                updateHover(at: p)
            }
        case .drawing?:
            endMark()
        default:
            break
        }
        drag = nil
        refresh()
        updateCursor()
    }

    func mouseMoved(to p: CGPoint) {
        cursor = p
        if selection == nil, drag == nil { updateHover(at: p) }
        updateCursor()
    }

    private func updateHover(at p: CGPoint) {
        guard let frame = frame(containing: p) else { return }
        var rect: CGRect?
        var window: CaptureWindow?
        if settings.detectsWindows {
            if let w = windows.first(where: { $0.frame.contains(p) }) {
                let clipped = w.frame.intersection(frame.frame)
                if clipped.width >= 8, clipped.height >= 8 {
                    rect = clipped
                    window = w
                }
            }
            rect = rect ?? frame.frame
        }
        guard rect != hover || window != hoverWindow else { return }
        hover = rect
        hoverWindow = window
        refresh()
    }

    func updateCursor() {
        let p = cursor
        if overlays.contains(where: { $0.overlay.isOverToolbar(p) }) { NSCursor.arrow.set(); return }
        guard let selection else { NSCursor.crosshair.set(); return }
        switch drag {
        case .moving?: NSCursor.closedHand.set(); return
        case .resizing(let handle, _)?: Self.cursor(for: handle).set(); return
        case .selecting?, .pressing?, .drawing?: NSCursor.crosshair.set(); return
        case nil: break
        }
        if let handle = handle(at: p, of: selection) {
            Self.cursor(for: handle).set()
        } else if selection.contains(p) {
            switch tool {
            case nil: NSCursor.openHand.set()
            case .text?: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        } else {
            (document.isEmpty ? NSCursor.crosshair : NSCursor.arrow).set()
        }
    }

    private static func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .top: return .frameResize(position: .top, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .left: return .frameResize(position: .left, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        }
    }

    // MARK: Marks

    private var width: CGFloat { CGFloat(settings.width) }

    private func beginMark(_ tool: BrushTool, at p: CGPoint) {
        switch tool {
        case .text:
            overlays.first { $0.frame.contains(p) }?.overlay.beginText(at: p, color: color, width: width)
        case .counter:
            let number = document.strokes.filter { $0.tool == .counter }.count + 1
            document.commit(BrushStroke(tool: .counter, color: color, width: width, points: [p], text: "\(number)"))
        default:
            document.current = BrushStroke(tool: tool, color: color, width: width, points: [p])
            drag = .drawing
        }
    }

    private func drawMark(to raw: CGPoint, shift: Bool) {
        guard var stroke = document.current, let start = stroke.points.first else { return }
        var p = raw
        if stroke.tool.isShape {
            if shift { p = constrained(start, p, tool: stroke.tool) }
            stroke.points = [start, p]
        } else {
            if let last = stroke.points.last, hypot(last.x - p.x, last.y - p.y) < 1.5 { return }
            stroke.points.append(p)
        }
        document.current = stroke
    }

    private func endMark() {
        guard var stroke = document.current else { return }
        document.current = nil
        if stroke.tool.isShape, let a = stroke.points.first, let b = stroke.points.last, hypot(a.x - b.x, a.y - b.y) < 3 { return }
        stroke.created = Date()
        document.commit(stroke)
    }

    /// Shift: lines snap to 45°, rectangles, ellipses and pixelated areas become squares.
    private func constrained(_ a: CGPoint, _ b: CGPoint, tool: BrushTool) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        if tool == .rectangle || tool == .ellipse || tool == .pixelate {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
        }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
    }

    func commitText(_ text: String, at origin: CGPoint, color: NSColor, width: CGFloat) {
        document.commit(BrushStroke(tool: .text, color: color, width: width, points: [origin], text: text))
    }

    /// A pixelated area: the frozen pixels under it, a few points per block.
    func pixelated(_ stroke: BrushStroke) -> (rect: CGRect, image: CGImage)? {
        guard let a = stroke.points.first, let b = stroke.points.last, let frame = frame(containing: a) else { return nil }
        let rect = BrushRenderer.rect(a, b).intersection(frame.frame)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        if let cached = pixelCache[stroke.id], cached.rect == rect { return cached }
        guard let piece = frame.crop(rect) else { return nil }
        let block: CGFloat = 10
        let columns = max(1, Int((rect.width / block).rounded(.up)))
        let rows = max(1, Int((rect.height / block).rounded(.up)))
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: piece.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ?? CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(piece, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let small = context.makeImage() else { return nil }
        pixelCache[stroke.id] = (rect, small)
        return (rect, small)
    }

    /// Paints marks into the current graphics context; `offset` turns global points into its own.
    func drawMarks(_ strokes: [BrushStroke], offset: CGPoint, in context: CGContext) {
        for stroke in strokes {
            if stroke.tool == .pixelate {
                guard let (rect, image) = pixelated(stroke) else { continue }
                context.saveGState()
                context.interpolationQuality = .none
                context.draw(image, in: rect.offsetBy(dx: -offset.x, dy: -offset.y))
                context.restoreGState()
            } else {
                BrushRenderer.draw(stroke, offset: offset, laserDelay: .infinity)
            }
        }
    }

    // MARK: Toolbar actions

    func selectTool(_ tool: BrushTool?) {
        overlays.forEach { $0.overlay.commitText() }
        self.tool = self.tool == tool ? nil : tool
        showsPalette = false
        refresh()
        updateCursor()
    }

    func chooseColor(_ index: Int) {
        settings.colorIndex = index
        showsPalette = false
    }

    func cycleWidth(by step: Int = 1) {
        let widths = Self.widths
        let current = widths.firstIndex { $0 >= settings.width } ?? 1
        settings.width = widths[(current + step + widths.count) % widths.count]
    }

    func undo() { document.undo() }
    func redo() { document.redo() }

    /// Shows the name of the toolbar button under the pointer; `nil` clears only its own.
    func setHint(_ text: String?, clearing own: String) {
        if let text { hint = text } else if hint == own { hint = nil } else { return }
        overlays.forEach { $0.overlay.refreshHint() }
    }

    private func selectWholeDisplay() {
        guard let frame = frame(containing: cursor) else { return }
        guard document.isEmpty || selection.map({ frame.frame.contains($0) }) == true else { return }
        selection = frame.frame
        pickedWindow = nil
        hover = nil
        refresh()
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let selection, let bounds = frame(of: selection)?.frame else { return }
        var r = selection.offsetBy(dx: dx, dy: dy)
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        self.selection = r
        pickedWindow = nil
        refresh()
    }

    // MARK: Keys

    /// Keys while the overlay has the keyboard. Returns false when the key isn't ours.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        switch code {
        case kVK_Escape:
            if showsPalette { showsPalette = false } else { finish(.cancel) }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if selection != nil { finish(settings.primaryAction.outcome) }
            return true
        default:
            break
        }
        if flags == .command {
            switch code {
            case kVK_ANSI_C: finish(.copy)
            case kVK_ANSI_S: finish(.save)
            case kVK_ANSI_R: finish(.record)
            case kVK_ANSI_Z: undo()
            case kVK_ANSI_A: selectWholeDisplay()
            default: return false
            }
            return true
        }
        if flags == [.command, .shift], code == kVK_ANSI_Z {
            redo()
            return true
        }
        if selection != nil, flags.isSubset(of: .shift) {
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            switch code {
            case kVK_LeftArrow: nudge(dx: -step, dy: 0); return true
            case kVK_RightArrow: nudge(dx: step, dy: 0); return true
            case kVK_UpArrow: nudge(dx: 0, dy: step); return true
            case kVK_DownArrow: nudge(dx: 0, dy: -step); return true
            default: break
            }
        }
        guard flags.isEmpty, selection != nil, let c = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if let digit = c.wholeNumberValue, digit >= 1, digit <= BrushTool.capture.count {
            selectTool(BrushTool.capture[digit - 1])
            return true
        }
        if let match = BrushTool.capture.first(where: { $0.key == c }) {
            selectTool(match)
            return true
        }
        switch c {
        case "[": cycleWidth(by: -1)
        case "]": cycleWidth(by: 1)
        case "c": settings.colorIndex = (settings.colorIndex + 1) % BrushPalette.colors.count
        default: return false
        }
        return true
    }

    // MARK: Output

    /// The selection with its marks, at the display's full resolution.
    private func render(_ selection: CGRect, in frame: CaptureFrame) -> CGImage? {
        guard let base = frame.crop(selection) else { return nil }
        let marks = document.strokes.filter { BrushRenderer.bounds($0).intersects(selection) }
        guard !marks.isEmpty else { return base }
        let width = base.width, height = base.height
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: base.colorSpace ?? sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / selection.width, y: CGFloat(height) / selection.height)
        context.clip(to: CGRect(origin: .zero, size: selection.size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawMarks(marks, offset: selection.origin, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage() ?? base
    }

    // MARK: Repaint

    func refresh() {
        overlays.forEach { $0.overlay.refresh() }
    }
}

extension CapturePrimaryAction {
    var outcome: CaptureSession.Outcome {
        switch self {
        case .copy: return .copy
        case .save: return .save
        case .both: return .copyAndSave
        }
    }
}
