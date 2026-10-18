/// ScreenBrushCanvas.swift
///
/// The transparent full-screen panel and the view that draws and takes the mouse.

import AppKit

/// Borderless panel covering one screen, above menus and the Dock.
final class BrushOverlayPanel: NSPanel {
    let canvas: BrushCanvasView
    let displayID: CGDirectDisplayID

    init(screen: NSScreen, document: BrushDocument) {
        displayID = screen.displayID
        canvas = BrushCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size), document: document, screenOrigin: screen.frame.origin)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        contentView = canvas
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class BrushCanvasView: NSView, NSTextFieldDelegate {
    private let document: BrushDocument
    private let screenOrigin: CGPoint
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var settings: ScreenBrushSettings { ScreenBrushSettings.shared }
    /// Committed strokes and background, rendered once per change.
    private var cache: CGImage?
    private var cacheDirty = true
    private let spotlightLayer = CAShapeLayer()

    init(frame: CGRect, document: BrushDocument, screenOrigin: CGPoint) {
        self.document = document
        self.screenOrigin = screenOrigin
        super.init(frame: frame)
        wantsLayer = true
        spotlightLayer.fillRule = .evenOdd
        spotlightLayer.fillColor = NSColor.black.withAlphaComponent(0.6).cgColor
        spotlightLayer.isHidden = true
        spotlightLayer.zPosition = 10
        layer?.addSublayer(spotlightLayer)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func global(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenOrigin.x, y: local.y + screenOrigin.y)
    }

    // MARK: Drawing

    private var globalFrame: CGRect { CGRect(origin: screenOrigin, size: bounds.size) }

    /// Repaints only what a document change touches on this screen.
    func handle(_ change: BrushChange) {
        switch change {
        case .strokes:
            cacheDirty = true
            needsDisplay = true
        case .area(let rect):
            let hit = rect.intersection(globalFrame)
            guard !hit.isNull, !hit.isEmpty else { return }
            setNeedsDisplay(hit.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y))
        case .spotlight:
            updateSpotlight()
        }
    }

    private func updateSpotlight() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spotlightLayer.frame = bounds
        spotlightLayer.isHidden = !document.spotlight
        if document.spotlight {
            let r = settings.spotlightRadius
            let c = CGPoint(x: document.cursor.x - screenOrigin.x, y: document.cursor.y - screenOrigin.y)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            spotlightLayer.path = path
        }
        CATransaction.commit()
    }

    private func renderCache() {
        cacheDirty = false
        let scale = window?.backingScaleFactor ?? 2
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { cache = nil; return }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        switch document.background {
        case .none: break
        case .dim: NSColor.black.withAlphaComponent(0.45).setFill(); bounds.fill()
        case .whiteboard: NSColor.white.setFill(); bounds.fill()
        case .blackboard: NSColor(white: 0.08, alpha: 1).setFill(); bounds.fill()
        }
        let frame = globalFrame
        for stroke in document.strokes where BrushRenderer.bounds(stroke).intersects(frame) {
            BrushRenderer.draw(stroke, offset: screenOrigin, laserDelay: .infinity)
        }
        NSGraphicsContext.restoreGraphicsState()
        cache = ctx.makeImage()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        if cacheDirty { renderCache() }
        if let cache { ctx.draw(cache, in: bounds) }
        let dirty = dirtyRect.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y)
        let delay = settings.laserDelay
        for laser in document.lasers where BrushRenderer.bounds(laser).intersects(dirty) {
            BrushRenderer.draw(laser, offset: screenOrigin, laserDelay: delay)
        }
        if let current = document.current { BrushRenderer.draw(current, offset: screenOrigin, laserDelay: .infinity) }
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) {
        document.cursor = global(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let p = global(event)
        document.cursor = p
        commitText()
        switch settings.tool {
        case .text:
            beginText(at: p)
        case .eraser:
            document.beginErase()
            document.erase(at: p, radius: CGFloat(settings.width) * 2 + 6)
        default:
            document.current = BrushStroke(tool: settings.tool, color: BrushPalette.color(settings.colorIndex),
                                           width: CGFloat(settings.width), points: [p], filled: settings.fillShapes)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        var p = global(event)
        document.cursor = p
        if settings.tool == .eraser {
            document.erase(at: p, radius: CGFloat(settings.width) * 2 + 6)
            return
        }
        guard var stroke = document.current, let start = stroke.points.first else { return }
        if stroke.tool.isShape {
            if event.modifierFlags.contains(.shift) { p = constrained(start, p, tool: stroke.tool) }
            stroke.points = [start, p]
        } else {
            if let last = stroke.points.last, hypot(last.x - p.x, last.y - p.y) < 1.5 { return }
            stroke.points.append(p)
        }
        document.current = stroke
        if stroke.tool == .laser { ScreenBrushController.shared.startLaserTimer() }
    }

    override func mouseUp(with event: NSEvent) {
        guard var stroke = document.current else { return }
        document.current = nil
        if stroke.tool.isShape, let a = stroke.points.first, let b = stroke.points.last, hypot(a.x - b.x, a.y - b.y) < 3 { return }
        stroke.created = Date()
        document.commit(stroke)
        if stroke.tool == .laser { ScreenBrushController.shared.startLaserTimer() }
    }

    /// Shift: lines snap to 45°, rectangles and ellipses become squares and circles.
    private func constrained(_ a: CGPoint, _ b: CGPoint, tool: BrushTool) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        if tool == .rectangle || tool == .ellipse {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
        }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        let sample = BrushStroke(tool: .text, color: BrushPalette.color(settings.colorIndex), width: CGFloat(settings.width), points: [p])
        let field = NSTextField(string: "")
        field.font = .systemFont(ofSize: sample.fontSize, weight: .semibold)
        field.textColor = sample.color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = L("Type…")
        let height = sample.fontSize * 1.4
        field.frame = CGRect(x: p.x - screenOrigin.x - 2, y: p.y - screenOrigin.y - height, width: max(200, bounds.maxX - (p.x - screenOrigin.x) - 20), height: height)
        addSubview(field)
        textField = field
        textOrigin = p
        window?.makeFirstResponder(field)
    }

    var isEditingText: Bool { textField != nil }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        document.commit(BrushStroke(tool: .text, color: BrushPalette.color(settings.colorIndex),
                                    width: CGFloat(settings.width), points: [textOrigin], text: text))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !ScreenBrushController.shared.handleKey(event) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { ScreenBrushController.shared.stopDrawing() }
}
