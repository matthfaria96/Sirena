/// ZonePopup.swift
///
/// What the snap popup draws: a glass card that drops from the top of the display while a
/// window is dragged there, with the layouts drawn small (the zone under the pointer lit), and
/// a preview on the display of where the window will go. The geometry is computed once
/// (ZonePopupGeometry) and used both to draw and to find the zone under the pointer, so the
/// two can't disagree.

import AppKit
import SwiftUI

/// Where everything sits, in Accessibility coordinates (top left, y down).
struct ZonePopupGeometry {
    enum Hit: Equatable {
        case zone(template: Int, zone: Int)
        /// The last group of this display, to put back.
        case lastGroup
    }

    static let hintHeight: CGFloat = 24
    /// Room around the card for its shadow.
    static let margin: CGFloat = 34

    let card: CGRect
    /// The layout (`ZoneTemplate` raw value) of each drawing, in order: each display gets
    /// its own list (`ZoneTemplate.fitting`), so a drawing's index is not its layout.
    let templates: [Int]
    /// The last group's drawing, first, when there is one.
    let groupThumb: CGRect?
    let thumbs: [CGRect]
    let zones: [[CGRect]]
    let groupZones: [CGRect]

    /// `visible`: the display's visible frame (AppKit coordinates).
    init(visible: CGRect, templates: [Int], roots: [ZoneNode], lastGroup: ZoneNode?) {
        let aspect = min(max(visible.height > 0 ? visible.width / visible.height : 1.6, 0.6), 2.2)
        let count = CGFloat(roots.count + (lastGroup == nil ? 0 : 1))
        // Big enough to aim at with a window in hand, small enough to fit the display.
        var thumbHeight: CGFloat = 84
        var spacing: CGFloat = 16
        var padding: CGFloat = 18
        let separator: CGFloat = lastGroup == nil ? 0 : 14
        let room = visible.width - 80
        let natural = padding * 2 + count * thumbHeight * aspect + max(0, count - 1) * spacing + separator
        if natural > room {
            let scale = room / natural
            thumbHeight *= scale
            spacing *= scale
            padding *= scale
        }
        let thumbWidth = (thumbHeight * aspect).rounded()
        let width = padding * 2 + count * thumbWidth + max(0, count - 1) * spacing + separator
        let height = padding * 2 + thumbHeight + Self.hintHeight
        let top = visible.screenFlipped
        let card = CGRect(x: (top.midX - width / 2).rounded(), y: top.minY + 8, width: width, height: height)
        var x = card.minX + padding
        var groupThumb: CGRect?
        if lastGroup != nil {
            groupThumb = CGRect(x: x, y: card.minY + padding, width: thumbWidth, height: thumbHeight)
            x += thumbWidth + spacing + separator
        }
        let start = x
        let thumbs = roots.indices.map { index in
            CGRect(x: start + CGFloat(index) * (thumbWidth + spacing),
                   y: card.minY + padding, width: thumbWidth, height: thumbHeight)
        }
        self.card = card
        self.templates = templates
        self.groupThumb = groupThumb
        self.thumbs = thumbs
        zones = zip(roots, thumbs).map { root, thumb in
            ZoneGeometry.regions(root, in: thumb).map { $0.insetBy(dx: 2, dy: 2) }
        }
        if let lastGroup, let groupThumb {
            groupZones = ZoneGeometry.regions(lastGroup, in: groupThumb).map { $0.insetBy(dx: 2, dy: 2) }
        } else {
            groupZones = []
        }
    }

    var panelFrame: CGRect { card.insetBy(dx: -Self.margin, dy: -Self.margin) }

    /// The × on the last group's card (keyboard mode): forgets that group.
    var forgetButton: CGRect? {
        groupThumb.map { CGRect(x: $0.maxX - 13, y: $0.minY - 9, width: 22, height: 22) }
    }

    /// What `point` picks: anywhere in the row of drawings counts, for the closest drawing (and
    /// the closest zone in it). Not the top of the card: that is where the dragged window
    /// arrives, and letting go there must not snap it by surprise.
    func hit(_ point: CGPoint) -> Hit? {
        guard let first = thumbs.first else { return nil }
        let row = CGRect(x: card.minX - 8, y: first.minY - 10, width: card.width + 16, height: first.height + 20)
        guard row.contains(point) else { return nil }
        let index = thumbs.indices.min { a, b in
            Self.distance(point, thumbs[a]) < Self.distance(point, thumbs[b])
        } ?? 0
        if let groupThumb, Self.distance(point, groupThumb) < Self.distance(point, thumbs[index]) {
            return .lastGroup
        }
        let template = templates[index]
        let zones = self.zones[index]
        if let inside = zones.firstIndex(where: { $0.contains(point) }) { return .zone(template: template, zone: inside) }
        let nearest = zones.indices.min { a, b in Self.distance(point, zones[a]) < Self.distance(point, zones[b]) }
        return nearest.map { .zone(template: template, zone: $0) }
    }

    static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

// MARK: - The popup

@MainActor
final class ZonePopup {
    private var panel: ZonePopupPanel?
    private let model = ZonePopupModel()
    private var closeWork: DispatchWorkItem?
    private var resignToken: NSObjectProtocol?

    /// Keyboard mode (opened by the shortcut), handled by the controller: a key; the pointer
    /// moving over the panel or clicking it (Accessibility coordinates); the panel losing the
    /// keyboard (a click elsewhere).
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onPointer: ((CGPoint, _ clicked: Bool) -> Void)?
    var onResign: (() -> Void)?

    /// `groupIcons`: the app in each zone of the last group. `keyboard`: opened by the
    /// shortcut, so the panel takes the keyboard and the pointer; dragging leaves both alone.
    /// `hint`: the line at the bottom, when not the default one. `wholeLayout`: the choice is a
    /// layout, not a zone ("Alterar divisórias"), so the lit drawing lights up entirely.
    func open(_ geometry: ZonePopupGeometry, roots: [ZoneNode], groupIcons: [Int: pid_t] = [:], keyboard: Bool = false,
              hint: String? = nil, wholeLayout: Bool = false) {
        closeWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = geometry.panelFrame.origin
        model.roots = roots
        templates = geometry.templates
        model.card = geometry.card.offsetBy(dx: -origin.x, dy: -origin.y)
        model.thumbs = geometry.thumbs.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        model.zones = geometry.zones.map { $0.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) } }
        model.groupThumb = geometry.groupThumb?.offsetBy(dx: -origin.x, dy: -origin.y)
        model.groupZones = geometry.groupZones.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        model.groupIcons = groupIcons
        model.forgetButton = keyboard ? geometry.forgetButton?.offsetBy(dx: -origin.x, dy: -origin.y) : nil
        model.hint = hint
        model.wholeLayout = wholeLayout
        model.hover = nil
        model.isOpen = false
        model.keyboard = keyboard
        panel.keyboardMode = keyboard
        panel.ignoresMouseEvents = !keyboard
        panel.setFrame(geometry.panelFrame.screenFlipped, display: true)
        if keyboard {
            panel.makeKeyAndOrderFront(nil)
            resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onResign?() }
            }
        } else {
            panel.orderFrontRegardless()
        }
        DispatchQueue.main.async { [model] in
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                          ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.78)) {
                model.isOpen = true
            }
        }
    }

    /// The layout of each drawing, to find a hit's drawing.
    private var templates: [Int] = []

    func setHover(_ hover: ZonePopupGeometry.Hit?) {
        let new: [Int]?
        switch hover {
        case .zone(let template, let zone): new = templates.firstIndex(of: template).map { [$0, zone] }
        case .lastGroup: new = [-1, -1]
        case nil: new = nil
        }
        guard model.hover != new else { return }
        withAnimation(.snappy(duration: 0.14)) { model.hover = new }
    }

    func close() {
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
        guard let panel, panel.isVisible else { return }
        panel.keyboardMode = false
        panel.ignoresMouseEvents = true
        withAnimation(.easeIn(duration: 0.14)) { model.isOpen = false }
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func makePanel() -> ZonePopupPanel {
        let panel = ZonePopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.onKey = { [weak self] code, flags in self?.onKey?(code, flags) }
        let hosting = ZonePopupHostingView(rootView: ZonePopupView(model: model))
        hosting.onPointer = { [weak self] point, clicked in self?.onPointer?(point, clicked) }
        panel.contentView = hosting
        return panel
    }
}

/// Takes the keyboard (without bringing Sirena forward) only when opened by the shortcut.
private final class ZonePopupPanel: NSPanel {
    var keyboardMode = false
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    override var canBecomeKey: Bool { keyboardMode }
    override func keyDown(with event: NSEvent) {
        guard keyboardMode else { return super.keyDown(with: event) }
        onKey?(event.keyCode, event.modifierFlags)
    }
    override func cancelOperation(_ sender: Any?) {
        if keyboardMode { onKey?(53, []) }
    }
}

/// Tells where the pointer is over the panel (and clicks), in Accessibility coordinates.
private final class ZonePopupHostingView: NSHostingView<ZonePopupView> {
    var onPointer: ((CGPoint, Bool) -> Void)?

    required init(rootView: ZonePopupView) {
        super.init(rootView: rootView)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { report(event, clicked: false) }
    override func mouseDown(with event: NSEvent) { report(event, clicked: true) }

    private func report(_ event: NSEvent, clicked: Bool) {
        guard let window else { return }
        onPointer?(window.convertPoint(toScreen: event.locationInWindow).screenFlipped, clicked)
    }
}

@MainActor
@Observable
final class ZonePopupModel {
    var roots: [ZoneNode] = []
    var card: CGRect = .zero
    var thumbs: [CGRect] = []
    var zones: [[CGRect]] = []
    var groupThumb: CGRect?
    var groupZones: [CGRect] = []
    var groupIcons: [Int: pid_t] = [:]
    /// [drawing, zone] under the pointer ([-1, -1] for the last group).
    var hover: [Int]?
    var isOpen = false
    /// Opened by the shortcut: the hint speaks of keys.
    var keyboard = false
    var hint: String?
    var wholeLayout = false
    /// The × on the last group's card, inside the panel.
    var forgetButton: CGRect?
}

private struct ZonePopupView: View {
    let model: ZonePopupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(supportsLiquidGlass ? 0.3 : 0.15))
                .compatGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
                .frame(width: model.card.width, height: model.card.height)
                .offset(x: model.card.minX, y: model.card.minY)

            ForEach(model.thumbs.indices, id: \.self) { template in
                let thumb = model.thumbs[template]
                let isHovered = model.hover?.first == template
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
                    .frame(width: thumb.width + 6, height: thumb.height + 6)
                    .offset(x: thumb.minX - 3, y: thumb.minY - 3)
                if template < model.zones.count {
                    ForEach(model.zones[template].indices, id: \.self) { zone in
                        let frame = model.zones[template][zone]
                        let isOn = model.hover == [template, zone] || (model.wholeLayout && model.hover?.first == template)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                                                      startPoint: .top, endPoint: .bottom))
                                       : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.2 : 0.14)))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isOn ? Color.white.opacity(0.35) : Color.primary.opacity(0.15), lineWidth: 0.7))
                            .shadow(color: isOn ? Color.accentColor.opacity(0.5) : .clear, radius: 6)
                            .frame(width: max(1, frame.width), height: max(1, frame.height))
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }

            if let thumb = model.groupThumb {
                let isOn = model.hover == [-1, -1]
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.28)) : AnyShapeStyle(Color.accentColor.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isOn ? 1 : 0.5), lineWidth: isOn ? 2 : 1))
                    .shadow(color: isOn ? Color.accentColor.opacity(0.45) : .clear, radius: 8)
                    .frame(width: thumb.width + 6, height: thumb.height + 6)
                    .offset(x: thumb.minX - 3, y: thumb.minY - 3)
                ForEach(model.groupZones.indices, id: \.self) { zone in
                    let frame = model.groupZones[zone]
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isOn ? 0.22 : 0.14))
                        .overlay {
                            if let pid = model.groupIcons[zone], let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: min(22, frame.width - 4, frame.height - 4),
                                           height: min(22, frame.width - 4, frame.height - 4))
                            }
                        }
                        .frame(width: max(1, frame.width), height: max(1, frame.height))
                        .offset(x: frame.minX, y: frame.minY)
                }
                Label(L("Last group"), systemImage: "link")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    // One line even under a portrait display's narrow drawing.
                    .frame(width: max(thumb.width + 20, 110))
                    .offset(x: thumb.midX - max(thumb.width + 20, 110) / 2, y: thumb.maxY + 7)
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: thumb.height)
                    .offset(x: thumb.maxX + 15, y: thumb.minY)
                if let forget = model.forgetButton {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.35))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: forget.width, height: forget.height)
                        .offset(x: forget.minX, y: forget.minY)
                        .help(L("Forget this group"))
                }
            }

            let hintStart = model.groupThumb.map { $0.maxX + 16 } ?? model.card.minX
            Text(model.hint ?? (model.keyboard ? L("Arrows choose · Return snaps the window · Esc cancels") : L("Drop on a zone · Esc cancels")))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: max(1, model.card.maxX - hintStart))
                .offset(x: hintStart, y: model.card.maxY - ZonePopupGeometry.hintHeight + 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.9, anchor: .top)
        .offset(y: model.isOpen || reduceMotion ? 0 : -12)
        .opacity(model.isOpen ? 1 : 0)
    }
}

// MARK: - The hint at the top while dragging

/// A small glass pill at the top middle of the display while a window is dragged, where the
/// panel drops from (Windows 11 shows the same), so the layouts can be found.
@MainActor
final class ZoneHint {
    private static let size = CGSize(width: 132, height: 30)
    private var panel: NSPanel?
    private var screenFrame: CGRect?

    func show(on screen: NSScreen) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.isVisible, panel.alphaValue > 0, screenFrame == screen.frame { return }
        screenFrame = screen.frame
        let top = screen.visibleFrame.screenFlipped
        let frame = CGRect(x: (top.midX - Self.size.width / 2).rounded(), y: top.minY + 6,
                           width: Self.size.width, height: Self.size.height)
        panel.setFrame(frame.screenFlipped, display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        screenFrame = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.contentView = NSHostingView(rootView: ZoneHintView())
        return panel
    }
}

struct ZoneHintView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compatGlass(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
        .padding(2)
        .accessibilityLabel(L("Layouts at the top of the screen"))
    }
}

// MARK: - Where the window will go

@MainActor
final class ZonePreview {
    private var panel: NSPanel?

    /// `frame` in Accessibility coordinates.
    func show(_ frame: CGRect) {
        let target = frame.screenFlipped
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.isVisible, panel.alphaValue > 0 {
            guard panel.frame != target else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 3))
                .padding(3))
        return panel
    }
}
