/// AreaSelector.swift
///
/// Drag a rectangle over the screen to pick the area to read. A see-through overlay
/// covers every screen; while it is up, letter keys toggle options (line breaks,
/// additive clipboard, speech) and Esc or a right click cancels.

import AppKit

/// An option that can be switched with a key while selecting.
struct AreaSelectorToggle {
    let key: Character
    let title: String
    let isOn: () -> Bool
    let toggle: () -> Void
}

@MainActor
final class AreaSelector {
    private var overlays: [AreaOverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?
    fileprivate private(set) var hint = ""
    fileprivate private(set) var toggles: [AreaSelectorToggle] = []
    /// Selection in Cocoa screen coordinates.
    fileprivate private(set) var selection: CGRect?
    private var anchor: CGPoint?

    var isActive: Bool { !overlays.isEmpty }

    /// Calls back with the selected area in Core Graphics global coordinates, or nil.
    func begin(hint: String, toggles: [AreaSelectorToggle], completion: @escaping (CGRect?) -> Void) {
        guard !isActive else { return }
        self.hint = hint
        self.toggles = toggles
        self.completion = completion
        selection = nil
        anchor = nil
        for screen in NSScreen.screens {
            let overlay = AreaOverlayWindow(screen: screen)
            overlay.areaView.selector = self
            overlay.orderFrontRegardless()
            overlays.append(overlay)
        }
        SirenaActivation.activateForTool()
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKey()
    }

    func cancel() {
        finish(nil)
    }

    fileprivate func mouseDown(at point: CGPoint) {
        anchor = point
        selection = CGRect(origin: point, size: .zero)
        redraw()
    }

    fileprivate func mouseDragged(to point: CGPoint) {
        guard let anchor else { return }
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
        redraw()
    }

    fileprivate func mouseUp(at point: CGPoint) {
        mouseDragged(to: point)
        anchor = nil
        guard let selection, selection.width >= 6, selection.height >= 6 else {
            self.selection = nil
            redraw()
            return
        }
        finish(PinGeometry.cocoaRect(fromCG: selection))
    }

    fileprivate func keyPressed(_ characters: String) {
        guard let character = characters.lowercased().first,
              let toggle = toggles.first(where: { $0.key == character }) else { return }
        toggle.toggle()
        redraw()
    }

    private func redraw() {
        overlays.forEach { $0.areaView.needsDisplay = true }
    }

    private func finish(_ rect: CGRect?) {
        let completion = completion
        self.completion = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        selection = nil
        anchor = nil
        toggles = []
        completion?(rect)
    }
}

private final class AreaOverlayWindow: NSWindow {
    let areaView: AreaView

    init(screen: NSScreen) {
        areaView = AreaView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = areaView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

private final class AreaView: NSView {
    weak var selector: AreaSelector?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) { selector?.mouseDown(at: NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { selector?.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { selector?.mouseUp(at: NSEvent.mouseLocation) }
    override func rightMouseDown(with event: NSEvent) { selector?.cancel() }
    override func cancelOperation(_ sender: Any?) { selector?.cancel() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            selector?.cancel()
        } else if let characters = event.charactersIgnoringModifiers {
            selector?.keyPressed(characters)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selector, let screenFrame = window?.frame else { return }
        let dim = NSBezierPath(rect: bounds)
        var local: CGRect?
        if let selection = selector.selection {
            let rect = selection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            if rect.intersects(bounds) {
                local = rect
                dim.append(NSBezierPath(rect: rect))
                dim.windingRule = .evenOdd
            }
        }
        NSColor.black.withAlphaComponent(0.25).setFill()
        dim.fill()

        if let local {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: local.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            let size = "\(Int(local.width)) × \(Int(local.height))"
            drawPill(size, at: CGPoint(x: local.midX, y: max(local.minY - 22, 16)), fontSize: 11)
        }

        var lines = [selector.hint]
        let toggles = selector.toggles.map { toggle in
            "\(String(toggle.key).uppercased()) \(toggle.title): \(toggle.isOn() ? L("On") : L("Off"))"
        }
        if !toggles.isEmpty { lines.append(toggles.joined(separator: "   ")) }
        drawPill(lines.joined(separator: "\n"), at: CGPoint(x: bounds.midX, y: bounds.maxY - 100), fontSize: 14)
    }

    private func drawPill(_ text: String, at center: CGPoint, fontSize: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
        let size = string.boundingRect(with: CGSize(width: 900, height: 200), options: [.usesLineFragmentOrigin]).size
        let pill = CGRect(x: center.x - size.width / 2 - 14, y: center.y - size.height / 2 - 7,
                          width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.72).setFill()
        let radius = min(pill.height / 2, 16)
        NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        string.draw(with: CGRect(x: pill.minX + 14, y: pill.minY + 7, width: size.width, height: size.height),
                    options: [.usesLineFragmentOrigin])
    }
}
