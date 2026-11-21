/// CaptureOverlay.swift
///
/// One display's part of a screen capture: its frozen image, a veil outside the selection,
/// the selection's line and handles, the marks, a loupe while dragging and, on the display
/// that holds the selection, the two toolbars. Quiet on purpose: one thin white line, small
/// handles, neutral glass bars.

import AppKit
import SwiftUI

/// Borderless panel over one display, above menus, the Dock and Desenho Livre.
final class CaptureOverlayWindow: NSPanel {
    static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)

    let overlay: CaptureOverlayView

    init(capture: CaptureFrame, session: CaptureSession) {
        overlay = CaptureOverlayView(capture: capture, session: session)
        super.init(contentRect: capture.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Self.level
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        contentView = overlay
        setFrame(capture.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class CaptureOverlayView: NSView, NSTextFieldDelegate {
    let capture: CaptureFrame
    private unowned let session: CaptureSession
    private let imageView = CaptureImageView()
    private let marks: CaptureMarksView
    private let decor = CaptureDecorView()
    private let loupe: CaptureLoupeView
    private lazy var tools: NSHostingView<CaptureToolsBar> = makeHost(CaptureToolsBar(session: session))
    private lazy var actions: NSHostingView<CaptureActionsBar> = makeHost(CaptureActionsBar(session: session))
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textStyle: (color: NSColor, width: CGFloat) = (.systemRed, 4)

    private var origin: CGPoint { capture.frame.origin }

    init(capture: CaptureFrame, session: CaptureSession) {
        self.capture = capture
        self.session = session
        marks = CaptureMarksView(session: session, origin: capture.frame.origin)
        loupe = CaptureLoupeView(capture: capture)
        super.init(frame: CGRect(origin: .zero, size: capture.frame.size))
        wantsLayer = true
        for view in [imageView, marks, decor] as [NSView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        imageView.image = capture.image
        loupe.isHidden = true
        addSubview(loupe)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func makeHost<Content: View>(_ view: Content) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        host.isHidden = true
        addSubview(host)
        return host
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func global(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + origin.x, y: local.y + origin.y)
    }

    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }

    // MARK: State → layers

    /// The selection, when it is on this display, in this view's coordinates.
    private var localSelection: CGRect? {
        guard let selection = session.selection, capture.frame.contains(CGPoint(x: selection.midX, y: selection.midY)) else { return nil }
        return local(selection)
    }

    func refresh() {
        let scale = window?.backingScaleFactor ?? 2
        let selection = localSelection
        var hover: CGRect?
        if session.selection == nil, let rect = session.hover, capture.frame.intersects(rect) { hover = local(rect) }

        var label: String?
        if let selection {
            label = "\(Int(selection.width)) × \(Int(selection.height))"
        } else if let hover {
            let size = "\(Int(hover.width)) × \(Int(hover.height))"
            label = session.hoverWindow.map { "\($0.owner)  ·  \(size)" } ?? "\(L("Whole screen"))  ·  \(size)"
        }
        let dim: CGFloat = selection != nil ? 0.42 : hover != nil ? 0.3 : (session.selection == nil ? 0.2 : 0.42)
        decor.update(hole: selection ?? hover, dim: dim, line: selection ?? hover,
                     lineAlpha: selection != nil ? 1 : 0.7,
                     handles: selection != nil && session.drag != .drawing,
                     label: label, labelInside: selection == nil, scale: scale)
        marks.clip = selection
        layoutToolbars(selection)
        refreshHint()
        updateLoupe()
    }

    private func layoutToolbars(_ selection: CGRect?) {
        guard let selection, session.showsToolbars else {
            if tools.isHidden == false { tools.isHidden = true }
            if actions.isHidden == false { actions.isHidden = true }
            return
        }
        let margin: CGFloat = 8, gap: CGFloat = 8
        let t = tools.fittingSize, a = actions.fittingSize
        // Actions under the selection's right end; above it, then inside, when there is no room.
        var ay = selection.minY - gap - a.height
        if ay < margin {
            ay = selection.maxY + gap
            if ay + a.height > bounds.maxY - margin { ay = selection.minY + gap }
        }
        let ax = min(max(selection.maxX - a.width, margin), bounds.maxX - margin - a.width)
        // Tools beside the selection's right edge, bottom-aligned; on the left, then inside.
        var tx = selection.maxX + gap
        if tx + t.width > bounds.maxX - margin {
            tx = selection.minX - gap - t.width
            if tx < margin { tx = selection.maxX - margin - t.width }
        }
        var ty = min(max(selection.minY, margin), bounds.maxY - margin - t.height)
        let actionsRect = CGRect(x: ax, y: ay, width: a.width, height: a.height)
        if CGRect(x: tx, y: ty, width: t.width, height: t.height).intersects(actionsRect.insetBy(dx: -4, dy: -4)) {
            ty = min(actionsRect.maxY + gap, bounds.maxY - margin - t.height)
        }
        tools.frame = CGRect(x: tx.rounded(), y: ty.rounded(), width: t.width, height: t.height)
        actions.frame = actionsRect.integral
        tools.isHidden = false
        actions.isHidden = false
    }

    func refreshHint() {
        guard let hint = session.hint, !actions.isHidden else {
            decor.updateHint(nil, at: .zero, scale: 1)
            return
        }
        let scale = window?.backingScaleFactor ?? 2
        let size = CaptureDecorView.pillSize(hint)
        let bar = actions.frame
        // Beside the actions, on the side with room.
        var x = bar.minX - 8 - size.width
        if x < 8 { x = bar.maxX + 8 }
        decor.updateHint(hint, at: CGPoint(x: x, y: bar.midY - size.height / 2), scale: scale)
    }

    func updateLoupe() {
        guard session.showsLoupe, capture.frame.contains(session.cursor) else {
            if !loupe.isHidden { loupe.isHidden = true }
            return
        }
        let p = CGPoint(x: session.cursor.x - origin.x, y: session.cursor.y - origin.y)
        let size = loupe.fittingSize
        var x = p.x + 18, y = p.y - 18 - size.height
        if x + size.width > bounds.maxX - 4 { x = p.x - 18 - size.width }
        if y < 4 { y = p.y + 18 }
        loupe.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        if let selection = session.selection {
            loupe.label = "\(Int(selection.width)) × \(Int(selection.height))"
        } else {
            loupe.label = "\(Int(p.x)), \(Int(bounds.height - p.y))"
        }
        loupe.cursor = session.cursor
        loupe.isHidden = false
        loupe.needsDisplay = true
    }

    func marksChanged(_ change: BrushChange) {
        marks.handle(change)
    }

    func isOverToolbar(_ point: CGPoint) -> Bool {
        let p = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        return (!tools.isHidden && tools.frame.contains(p)) || (!actions.isHidden && actions.frame.contains(p))
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { session.updateCursor() }

    override func mouseMoved(with event: NSEvent) {
        session.mouseMoved(to: global(event))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        session.mouseDown(at: global(event), clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        session.mouseDragged(to: global(event), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        session.mouseUp(at: global(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        // Before anything is selected a right click leaves, like Esc.
        if session.selection == nil { session.finish(.cancel) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !session.handleKey(event) { super.keyDown(with: event) }
    }

    /// ⌘C, ⌘S, ⌘R… reach the capture before any menu does. While a text is being typed,
    /// ⌘A and ⌘Z stay with it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.modifierFlags.contains(.command) else { return false }
        if textField != nil, [UInt16(0x00), UInt16(0x06)].contains(event.keyCode) { return false } // A, Z
        return session.handleKey(event) || super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { session.finish(.cancel) }

    // MARK: Text

    func beginText(at p: CGPoint, color: NSColor, width: CGFloat) {
        commitText()
        let sample = BrushStroke(tool: .text, color: color, width: width, points: [p])
        let field = NSTextField(string: "")
        field.font = .systemFont(ofSize: sample.fontSize, weight: .semibold)
        field.textColor = color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = L("Type…")
        let height = sample.fontSize * 1.4
        let x = p.x - origin.x - 2
        let right = localSelection?.maxX ?? bounds.maxX
        field.frame = CGRect(x: x, y: p.y - origin.y - height, width: max(160, right - x - 4), height: height)
        addSubview(field)
        textField = field
        textOrigin = p
        textStyle = (color, width)
        window?.makeFirstResponder(field)
    }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        session.commitText(text, at: textOrigin, color: textStyle.color, width: textStyle.width)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            // Esc drops the text being typed, not the whole capture.
            textField?.stringValue = ""
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }
}

// MARK: - Layers

/// The frozen display image, as a layer's contents (no redraw while the selection moves).
private final class CaptureImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contentsGravity = .resize
        layer?.contents = image
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The marks, clipped to the selection; repaints only what a change touches.
private final class CaptureMarksView: NSView {
    private unowned let session: CaptureSession
    private let origin: CGPoint
    var clip: CGRect? {
        didSet { if clip != oldValue { needsDisplay = true } }
    }

    init(session: CaptureSession, origin: CGPoint) {
        self.session = session
        self.origin = origin
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func handle(_ change: BrushChange) {
        switch change {
        case .strokes:
            needsDisplay = true
        case .area(let rect):
            let hit = rect.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds)
            if !hit.isNull, !hit.isEmpty { setNeedsDisplay(hit) }
        case .spotlight:
            break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let clip, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        context.clip(to: clip)
        let dirty = dirtyRect.offsetBy(dx: origin.x, dy: origin.y)
        let strokes = (session.document.strokes + [session.document.current].compactMap { $0 })
            .filter { BrushRenderer.bounds($0).intersects(dirty) }
        session.drawMarks(strokes, offset: origin, in: context)
    }
}

/// Veil, selection line, handles and the small labels: Core Animation layers only.
final class CaptureDecorView: NSView {
    private let veil = CAShapeLayer()
    private let line = CAShapeLayer()
    private let knobs = CAShapeLayer()
    private let label = PillLayer()
    private let hint = PillLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        veil.fillRule = .evenOdd
        veil.fillColor = NSColor.black.cgColor
        line.fillColor = nil
        line.strokeColor = NSColor.white.cgColor
        line.lineWidth = 1
        line.shadowColor = NSColor.black.cgColor
        line.shadowOpacity = 0.45
        line.shadowRadius = 1.5
        line.shadowOffset = .zero
        knobs.fillColor = NSColor.white.cgColor
        knobs.strokeColor = NSColor.black.withAlphaComponent(0.3).cgColor
        knobs.lineWidth = 0.5
        knobs.shadowColor = NSColor.black.cgColor
        knobs.shadowOpacity = 0.35
        knobs.shadowRadius = 2
        knobs.shadowOffset = .zero
        for sub in [veil, line, knobs, label, hint] { layer?.addSublayer(sub) }
        label.isHidden = true
        hint.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func pillSize(_ text: String) -> CGSize {
        let size = PillLayer.attributed(text).size()
        return CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
    }

    func update(hole: CGRect?, dim: CGFloat, line rect: CGRect?, lineAlpha: CGFloat, handles: Bool,
                label text: String?, labelInside: Bool, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        veil.frame = bounds
        let veilPath = CGMutablePath()
        veilPath.addRect(bounds)
        if let hole { veilPath.addRect(hole) }
        veil.path = veilPath
        veil.opacity = Float(dim)

        line.frame = bounds
        line.path = rect.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        line.opacity = Float(lineAlpha)

        knobs.frame = bounds
        if handles, let rect {
            let path = CGMutablePath()
            // Side handles only where the side is long enough to grab them apart from the corners.
            for (handle, p) in CaptureSession.handlePoints(rect) {
                let isSide = [.top, .bottom].contains(handle) ? rect.width < 40 : [.left, .right].contains(handle) ? rect.height < 40 : false
                if isSide { continue }
                path.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            }
            knobs.path = path
        } else {
            knobs.path = nil
        }

        if let text, let rect {
            label.setText(text, scale: scale)
            let size = label.bounds.size
            var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
            if labelInside || origin.y + size.height > bounds.maxY - 4 {
                origin = CGPoint(x: rect.minX + 8, y: rect.maxY - 8 - size.height)
            }
            origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 4)
            origin.y = max(origin.y, 4)
            label.frame.origin = origin
            label.isHidden = false
        } else {
            label.isHidden = true
        }
        CATransaction.commit()
    }

    func updateHint(_ text: String?, at origin: CGPoint, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let text {
            hint.setText(text, scale: scale)
            hint.frame.origin = origin
            hint.isHidden = false
        } else {
            hint.isHidden = true
        }
        CATransaction.commit()
    }

    /// A small dark capsule with white text.
    final class PillLayer: CALayer {
        private let text = CATextLayer()

        static func attributed(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ])
        }

        override init() {
            super.init()
            backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
            masksToBounds = true
            text.alignmentMode = .center
            addSublayer(text)
        }

        override init(layer: Any) { super.init(layer: layer) }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func setText(_ string: String, scale: CGFloat) {
            let size = CaptureDecorView.pillSize(string)
            bounds = CGRect(origin: .zero, size: size)
            cornerRadius = size.height / 2
            text.contentsScale = scale
            text.string = Self.attributed(string)
            text.frame = CGRect(x: 0, y: 4, width: size.width, height: size.height - 8)
        }
    }
}

/// The pixels around the pointer, eight times bigger, with the size or position under it.
private final class CaptureLoupeView: NSView {
    private let capture: CaptureFrame
    var cursor: CGPoint = .zero
    var label = ""
    private let diameter: CGFloat = 112
    /// Points around the pointer shown across the loupe.
    private let span: CGFloat = 14

    init(capture: CaptureFrame) {
        self.capture = capture
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize { NSSize(width: diameter + 8, height: diameter + 32) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let circle = CGRect(x: 4, y: 26, width: diameter, height: diameter)

        // The zoomed pixels, cut from the frozen image (top-left rows) and drawn unsmoothed.
        context.saveGState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 6
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: circle).fill()
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        let region = CGRect(x: cursor.x - span / 2, y: cursor.y - span / 2, width: span, height: span)
        let visible = region.intersection(capture.frame)
        if !visible.isNull, let piece = capture.crop(visible) {
            let zoom = diameter / span
            let dest = CGRect(x: circle.minX + (visible.minX - region.minX) * zoom,
                              y: circle.minY + (visible.minY - region.minY) * zoom,
                              width: visible.width * zoom, height: visible.height * zoom)
            context.interpolationQuality = .none
            context.draw(piece, in: dest)
        }
        // The point under the pointer.
        let cell = diameter / span
        let center = CGRect(x: circle.midX - cell / 2, y: circle.midY - cell / 2, width: cell, height: cell)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let mark = NSBezierPath(rect: center)
        mark.lineWidth = 1
        mark.stroke()
        context.restoreGState()

        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.75, dy: 0.75))
        ring.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.85).setStroke()
        ring.stroke()

        let text = CaptureDecorView.PillLayer.attributed(label)
        let size = text.size()
        let pill = CGRect(x: circle.midX - size.width / 2 - 8, y: 0, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 4))
    }
}
