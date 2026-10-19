/// ScreenBrushAreaSelector.swift
///
/// Picks an area of the screen for a Freehand Drawing screenshot, like ⇧⌘4: a crosshair,
/// drag to select, Esc to cancel. One transparent panel per display sits above the drawing
/// (and its toolbar) so the strokes stay visible while choosing.

import AppKit
import Carbon.HIToolbox

@MainActor
final class ScreenBrushAreaSelector {
    /// Called once with the chosen rect in global AppKit coordinates (bottom-left origin),
    /// or nil when cancelled.
    typealias Completion = (CGRect?) -> Void

    private var panels: [AreaSelectionPanel] = []
    private var completion: Completion?

    var isSelecting: Bool { completion != nil }

    func begin(_ completion: @escaping Completion) {
        cancel()
        self.completion = completion
        panels = NSScreen.screens.map { screen in
            let panel = AreaSelectionPanel(screen: screen)
            panel.selectionView.onFinish = { [weak self] rect in self?.finish(rect) }
            panel.orderFrontRegardless()
            return panel
        }
        let mouse = NSEvent.mouseLocation
        let active = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
        active?.makeKey()
        active.map { $0.makeFirstResponder($0.selectionView) }
        NSCursor.crosshair.set()
    }

    func cancel() { finish(nil) }

    private func finish(_ rect: CGRect?) {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        let completion = completion
        self.completion = nil
        completion?(rect)
    }
}

final class AreaSelectionPanel: NSPanel {
    let selectionView: AreaSelectionView

    init(screen: NSScreen) {
        selectionView = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), screenOrigin: screen.frame.origin)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the drawing (.screenSaver) and its toolbar (.screenSaver + 1).
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Never part of the screenshot it is choosing.
        sharingType = .none
        contentView = selectionView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}

final class AreaSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private let screenOrigin: CGPoint
    private var start: CGPoint?
    private var selection: CGRect?

    init(frame: CGRect, screenOrigin: CGPoint) {
        self.screenOrigin = screenOrigin
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func draw(_ dirtyRect: NSRect) {
        // A light veil outside the selection, so the chosen area reads clearly.
        NSColor.black.withAlphaComponent(selection == nil ? 0.12 : 0.28).setFill()
        let veil = NSBezierPath(rect: bounds)
        if let selection {
            veil.append(NSBezierPath(rect: selection))
            veil.windingRule = .evenOdd
        }
        veil.fill()
        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        label.draw(at: CGPoint(x: selection.maxX + 6, y: max(selection.minY - 18, 4)), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        // A click without a drag picks nothing: keep selecting (like ⇧⌘4).
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish?(selection.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }
}
