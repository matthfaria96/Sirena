/// ZoneGroupDecor.swift
///
/// What shows that windows are held together: while one window of a group (windows put in
/// the zones of the same layout on a display) is the one in use, every edge two of them share
/// gets one quiet line — neutral, translucent, never the accent colour — with a small glass
/// grip in its middle. Nothing is drawn around the windows themselves. Dragging a grip resizes
/// the windows on both sides at once (Windows 11's snap group resize); a click opens its menu
/// (swap an app, swap the sides, change the layout, even, let go).

import AppKit
import SwiftUI

@MainActor
final class ZoneGroupDecor {
    /// The stretch of a line two windows share, in Accessibility coordinates.
    struct Line: Equatable {
        let divider: ZoneDivider
        let from: CGPoint
        let to: CGPoint
    }

    struct Grip: Equatable {
        let divider: ZoneDivider
        /// Its centre, in Accessibility coordinates.
        let center: CGPoint
    }

    /// A grip is being dragged: where the line should be now (Accessibility coordinates).
    var onGripBegin: (() -> Void)?
    var onGripDrag: ((ZoneDivider, CGFloat) -> Void)?
    var onGripEnd: ((ZoneDivider) -> Void)?
    /// A grip was clicked without dragging: its line, its centre, and the view to open a menu in.
    var onGripClick: ((ZoneDivider, CGPoint, NSView) -> Void)?

    private var relinkPanel: NSPanel?
    private var relinkHide: DispatchWorkItem?

    private var lines: [NSPanel] = []
    private var shownLines: [Line] = []
    private var grips: [NSPanel] = []
    private var shownGrips: [Grip] = []
    private(set) var isDraggingGrip = false

    /// How thick a line's panel is (the line itself is thinner, with room for its soft edge)
    /// and how far it stays from the ends of the edge.
    private static let lineThickness: CGFloat = 9
    private static let lineInset: CGFloat = 12

    /// The lines between the windows, and the grips. While a grip is dragged the lines follow
    /// and the grips are left alone (`moveGrip` moves the one in hand).
    func show(lines: [Line], grips: [Grip]) {
        if lines != shownLines {
            while self.lines.count > lines.count { self.lines.removeLast().orderOut(nil) }
            for (index, line) in lines.enumerated() {
                if index == self.lines.count { self.lines.append(makeLine()) }
                let panel = self.lines[index]
                let frame = Self.frame(of: line).screenFlipped
                if panel.frame != frame { panel.setFrame(frame, display: true) }
                if !panel.isVisible { fadeIn(panel) }
            }
            shownLines = lines
        }
        guard !isDraggingGrip, grips != shownGrips else { return }
        shownGrips = grips
        for panel in self.grips { panel.orderOut(nil) }
        self.grips = grips.map { grip in
            let vertical = grip.divider.axis == .columns
            let size = vertical ? CGSize(width: 16, height: 64) : CGSize(width: 64, height: 16)
            let frame = CGRect(x: grip.center.x - size.width / 2, y: grip.center.y - size.height / 2,
                               width: size.width, height: size.height)
            let panel = makeGrip(grip)
            panel.setFrame(frame.screenFlipped, display: true)
            fadeIn(panel)
            return panel
        }
    }

    /// A line's panel: along the shared edge, short of its ends.
    private static func frame(of line: Line) -> CGRect {
        let half = lineThickness / 2
        if line.divider.axis == .columns {
            let inset = min(lineInset, max(0, (line.to.y - line.from.y) / 2 - 8))
            return CGRect(x: line.from.x - half, y: line.from.y + inset, width: lineThickness, height: max(1, line.to.y - line.from.y - inset * 2))
        }
        let inset = min(lineInset, max(0, (line.to.x - line.from.x) / 2 - 8))
        return CGRect(x: line.from.x + inset, y: line.from.y - half, width: max(1, line.to.x - line.from.x - inset * 2), height: lineThickness)
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
        for panel in lines {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        lines.removeAll()
        shownLines.removeAll()
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

    private func makeLine() -> NSPanel {
        let panel = basePanel(ignoresMouse: true)
        panel.contentView = NSHostingView(rootView: SeamShape())
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
        view.onClick = { [weak self, weak view] _ in
            guard let self, let view else { return }
            self.isDraggingGrip = false
            self.onGripClick?(grip.divider, grip.center, view)
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

/// The line between two windows of a group: thin, neutral and translucent, a light core
/// with a darker hairline so it reads over light and dark windows alike without standing out.
private struct SeamShape: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5))
            .padding(3)
    }
}

/// The grip: a small glass pill on the line, a little bigger under the pointer, with the
/// resize cursor over it. Dragging resizes; a click (or two) without moving goes to `onClick`.
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
        toolTip = L("Drag to resize both windows; click for more options.")
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(L("Line between the windows"))
        setAccessibilityHelp(L("Drag to resize both windows; click for more options."))
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
        if pressedAt == nil { hosting.rootView = GripShape(vertical: axis == .columns, hovering: false) }
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = NSEvent.mouseLocation
        dragged = false
        hosting.rootView = GripShape(vertical: axis == .columns, hovering: true)
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
        let thickness: CGFloat = hovering ? 8 : 6
        let length: CGFloat = hovering ? 52 : 42
        Capsule()
            .fill(Color.white.opacity(hovering ? 0.55 : 0.3))
            .compatGlass(.regular, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.6))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5).padding(-0.5))
            // Under the pointer, two small dots say it can be taken.
            .overlay {
                if hovering {
                    let dots = ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color.black.opacity(0.35)).frame(width: 2.5, height: 2.5)
                    }
                    Group {
                        if vertical { VStack(spacing: 3) { dots } } else { HStack(spacing: 3) { dots } }
                    }
                    .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 2, y: 0.5)
            .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy(duration: 0.15), value: hovering)
    }
}

/// "Join again": back to the group that was just let go. Glass, like the grip.
private struct RelinkButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(L("Join again"), systemImage: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(Color.primary.opacity(isHovering ? 0.12 : 0.04)))
                .compatGlass(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                .scaleEffect(isHovering ? 1.03 : 1)
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
