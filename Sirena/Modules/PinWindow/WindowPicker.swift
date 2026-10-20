/// WindowPicker.swift
///
/// "Click a window to pin it": a see-through overlay on every screen that highlights
/// the window under the pointer. Click picks it, Esc or a right click cancels.

import AppKit

@MainActor
final class WindowPicker {
    private var overlays: [PickerOverlayWindow] = []
    private var windows: [PinnableWindow] = []
    private var hovered: PinnableWindow?
    private var completion: ((PinnableWindow?) -> Void)?
    private var isPinned: (CGWindowID) -> Bool = { _ in false }

    var isActive: Bool { !overlays.isEmpty }

    func begin(isPinned: @escaping (CGWindowID) -> Bool, completion: @escaping (PinnableWindow?) -> Void) {
        guard !isActive else { return }
        self.isPinned = isPinned
        self.completion = completion
        windows = WindowList.onScreen()

        for screen in NSScreen.screens {
            let overlay = PickerOverlayWindow(screen: screen)
            overlay.pickerView.picker = self
            overlay.orderFrontRegardless()
            overlays.append(overlay)
        }
        SirenaActivation.activateForTool()
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKey()
        pointerMoved(to: mouse)
    }

    func cancel() {
        finish(with: nil)
    }

    fileprivate func pointerMoved(to point: CGPoint) {
        let window = WindowList.window(atCocoaPoint: point, in: windows)
        guard window?.id != hovered?.id else { return }
        hovered = window
        for overlay in overlays {
            overlay.pickerView.highlight = window.map { (PinGeometry.cocoaRect(fromCG: $0.frame), $0, isPinned($0.id)) }
        }
    }

    fileprivate func clicked(at point: CGPoint) {
        pointerMoved(to: point)
        finish(with: hovered)
    }

    private func finish(with window: PinnableWindow?) {
        let completion = completion
        self.completion = nil
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()
        hovered = nil
        windows = []
        completion?(window)
    }
}

private final class PickerOverlayWindow: NSWindow {
    let pickerView: PickerView

    init(screen: NSScreen) {
        pickerView = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = pickerView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    weak var picker: WindowPicker?

    /// Highlighted window: frame in screen coordinates, the window, whether it is pinned.
    var highlight: (CGRect, PinnableWindow, Bool)? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseMoved(with event: NSEvent) {
        picker?.pointerMoved(to: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        picker?.clicked(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        picker?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            picker?.cancel()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        picker?.cancel()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        if let (screenRect, window, pinned) = highlight, let screenFrame = self.window?.frame {
            let rect = screenRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            if rect.intersects(bounds) {
                let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 4
                path.stroke()
                let label = pinned ? L("Click to unpin \(window.appName)") : L("Click to pin \(window.appName)")
                drawPill(label, centeredIn: rect)
            }
        }

        drawPill(L("Click a window to pin it · Esc to cancel"),
                 at: CGPoint(x: bounds.midX, y: bounds.maxY - 90))
    }

    private func drawPill(_ text: String, centeredIn rect: CGRect) {
        drawPill(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func drawPill(_ text: String, at center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pill = CGRect(x: center.x - size.width / 2 - 14, y: center.y - size.height / 2 - 7,
                          width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 7))
    }
}
