/// ZoneGroupDecor.swift
///
/// What shows that windows are held together: while one window of a group (windows put in
/// the zones of the same layout on a display) is the one in use, each member gets a thin
/// accent outline, and every line two members share gets a grip. Dragging a grip resizes
/// the windows on both sides at once (Windows 11's snap group resize); a click lets the
/// windows go (a "join again" bubble stays a few seconds), a double click evens the sides.

import AppKit
import SwiftUI

@MainActor
final class ZoneGroupDecor {
    struct Grip: Equatable {
        let divider: ZoneDivider
        /// Its centre, in Accessibility coordinates.
        let center: CGPoint
    }

    /// A grip is being dragged: where the line should be now (Accessibility coordinates).
    var onGripBegin: (() -> Void)?
    var onGripDrag: ((ZoneDivider, CGFloat) -> Void)?
    var onGripEnd: ((ZoneDivider) -> Void)?
    /// A grip was clicked without dragging (1 or 2 clicks), with its centre.
    var onGripClick: ((ZoneDivider, Int, CGPoint) -> Void)?

    private var relinkPanel: NSPanel?
    private var relinkHide: DispatchWorkItem?

    private var outlines: [CGWindowID: NSPanel] = [:]
    private var grips: [NSPanel] = []
    private var shownGrips: [Grip] = []
    private(set) var isDraggingGrip = false

    /// Outlines around `frames` (Accessibility coordinates) and the grips.
    func show(frames: [CGWindowID: CGRect], grips: [Grip]) {
        for (id, panel) in outlines where frames[id] == nil {
            panel.orderOut(nil)
            outlines.removeValue(forKey: id)
        }
        for (id, frame) in frames {
            let panel = outlines[id] ?? makeOutline()
            outlines[id] = panel
            let target = frame.insetBy(dx: -3, dy: -3).screenFlipped
            if panel.frame != target { panel.setFrame(target, display: true) }
            if !panel.isVisible { fadeIn(panel) }
        }
        guard !isDraggingGrip, grips != shownGrips else { return }
        shownGrips = grips
        for panel in self.grips { panel.orderOut(nil) }
        self.grips = grips.map { grip in
            let vertical = grip.divider.axis == .columns
            let size = vertical ? CGSize(width: 14, height: 64) : CGSize(width: 64, height: 14)
            let frame = CGRect(x: grip.center.x - size.width / 2, y: grip.center.y - size.height / 2,
                               width: size.width, height: size.height)
            let panel = makeGrip(grip)
            panel.setFrame(frame.screenFlipped, display: true)
            fadeIn(panel)
            return panel
        }
    }

    /// Moves a grip with its line while it's dragged.
    func moveGrip(_ divider: ZoneDivider, to center: CGPoint) {
        guard let index = shownGrips.firstIndex(where: { $0.divider.path == divider.path && $0.divider.index == divider.index }),
              index < grips.count else { return }
        let panel = grips[index]
        var frame = panel.frame.screenFlipped
        frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        panel.setFrame(frame.screenFlipped, display: true)
    }

    /// The "join again" bubble at `center` (Accessibility coordinates) for a few seconds.
    func showRelink(at center: CGPoint, action: @escaping () -> Void) {
        relinkHide?.cancel()
        relinkPanel?.orderOut(nil)
        let panel = basePanel(ignoresMouse: false)
        let size = CGSize(width: 156, height: 34)
        let button = RelinkButton { [weak self] in
            self?.hideRelink()
            action()
        }
        let hosting = FirstClickView(rootView: button)
        panel.contentView = hosting
        panel.setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height).screenFlipped, display: true)
        fadeIn(panel)
        relinkPanel = panel
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideRelink() }
        }
        relinkHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func hideRelink() {
        relinkHide?.cancel()
        guard let panel = relinkPanel else { return }
        relinkPanel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    func hide() {
        guard !isDraggingGrip else { return }
        for panel in outlines.values {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        outlines.removeAll()
        for panel in grips { panel.orderOut(nil) }
        grips.removeAll()
        shownGrips.removeAll()
    }

    private func fadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func basePanel(ignoresMouse: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = ignoresMouse
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        return panel
    }

    private func makeOutline() -> NSPanel {
        let panel = basePanel(ignoresMouse: true)
        // Present for as long as one of the windows is in use: quiet enough to live with.
        panel.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.45)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 2)
                .shadow(color: Color.accentColor.opacity(0.25), radius: 4))
        return panel
    }

    private func makeGrip(_ grip: Grip) -> NSPanel {
        let panel = basePanel(ignoresMouse: false)
        let view = GripView(axis: grip.divider.axis)
        view.onDown = { [weak self] in
            guard let self else { return }
            self.isDraggingGrip = true
            self.onGripBegin?()
        }
        view.onDrag = { [weak self] point in
            self?.onGripDrag?(grip.divider, grip.divider.axis == .columns ? point.x : point.y)
        }
        view.onClick = { [weak self] count in
            guard let self else { return }
            self.isDraggingGrip = false
            self.onGripClick?(grip.divider, count, grip.center)
        }
        view.onEnd = { [weak self] in
            guard let self else { return }
            self.isDraggingGrip = false
            self.onGripEnd?(grip.divider)
        }
        panel.contentView = view
        return panel
    }
}

/// The grip: a pill with a ⟷ (or ↕) mark, a link while the pointer is on it, the resize
/// cursor over it. Dragging resizes; a click (or two) without moving goes to `onClick`.
private final class GripView: NSView {
    let axis: ZoneNode.Axis
    var onDown: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    var onClick: ((Int) -> Void)?
    private var pressedAt: CGPoint?
    private var dragged = false
    private let hosting: NSHostingView<GripShape>

    init(axis: ZoneNode.Axis) {
        self.axis = axis
        hosting = NSHostingView(rootView: GripShape(vertical: axis == .columns, hovering: false))
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor), hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor), hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(L("Line between the windows"))
        setAccessibilityHelp(L("Drag to resize both windows, click to let them go, double click to share the room equally."))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .columns ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        hosting.rootView = GripShape(vertical: axis == .columns, hovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        hosting.rootView = GripShape(vertical: axis == .columns, hovering: false)
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = NSEvent.mouseLocation
        dragged = false
        onDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt else { return }
        let now = NSEvent.mouseLocation
        if !dragged, hypot(now.x - start.x, now.y - start.y) < 3 { return }
        dragged = true
        onDrag?(now.screenFlipped)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedAt != nil else { return }
        pressedAt = nil
        if dragged {
            onEnd?()
        } else {
            onClick?(event.clickCount)
        }
    }
}

private struct GripShape: View {
    let vertical: Bool
    let hovering: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            Image(systemName: hovering ? "link" : (vertical ? "arrow.left.and.right" : "arrow.up.and.down"))
                .font(.system(size: hovering ? 8.5 : 8, weight: .heavy))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(hovering && vertical ? 90 : 0))
        }
        .padding(1)
    }
}

/// "Join again": back to the group that was just let go.
private struct RelinkButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(L("Join again"), systemImage: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                                          startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .scaleEffect(isHovering ? 1.04 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(2)
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
    }
}

/// The first click works even though Sirena isn't the active app.
private final class FirstClickView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
