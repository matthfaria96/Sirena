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
    /// The last group's drawing, first, when there is one.
    let groupThumb: CGRect?
    let thumbs: [CGRect]
    let zones: [[CGRect]]
    let groupZones: [CGRect]

    init(screen: NSScreen, roots: [ZoneNode], lastGroup: ZoneNode?) {
        let visible = screen.visibleFrame
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

    /// What `point` picks: anywhere over the card counts, for the closest drawing (and the
    /// closest zone in it).
    func hit(_ point: CGPoint) -> Hit? {
        guard card.insetBy(dx: -8, dy: -8).contains(point), !thumbs.isEmpty else { return nil }
        let template = thumbs.indices.min { a, b in
            Self.distance(point, thumbs[a]) < Self.distance(point, thumbs[b])
        } ?? 0
        if let groupThumb, Self.distance(point, groupThumb) < Self.distance(point, thumbs[template]) {
            return .lastGroup
        }
        let zones = self.zones[template]
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
    private var panel: NSPanel?
    private let model = ZonePopupModel()
    private var closeWork: DispatchWorkItem?

    /// `groupIcons`: the app in each zone of the last group.
    func open(_ geometry: ZonePopupGeometry, roots: [ZoneNode], groupIcons: [Int: pid_t] = [:]) {
        closeWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = geometry.panelFrame.origin
        model.roots = roots
        model.card = geometry.card.offsetBy(dx: -origin.x, dy: -origin.y)
        model.thumbs = geometry.thumbs.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        model.zones = geometry.zones.map { $0.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) } }
        model.groupThumb = geometry.groupThumb?.offsetBy(dx: -origin.x, dy: -origin.y)
        model.groupZones = geometry.groupZones.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        model.groupIcons = groupIcons
        model.hover = nil
        model.isOpen = false
        panel.setFrame(geometry.panelFrame.screenFlipped, display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [model] in
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                          ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.78)) {
                model.isOpen = true
            }
        }
    }

    func setHover(_ hover: ZonePopupGeometry.Hit?) {
        let new: [Int]?
        switch hover {
        case .zone(let template, let zone): new = [template, zone]
        case .lastGroup: new = [-1, -1]
        case nil: new = nil
        }
        guard model.hover != new else { return }
        withAnimation(.snappy(duration: 0.14)) { model.hover = new }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        withAnimation(.easeIn(duration: 0.14)) { model.isOpen = false }
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
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
        panel.contentView = NSHostingView(rootView: ZonePopupView(model: model))
        return panel
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
    /// [layout, zone] under the pointer ([-1, -1] for the last group).
    var hover: [Int]?
    var isOpen = false
}

private struct ZonePopupView: View {
    let model: ZonePopupModel

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
                        let isOn = model.hover == [template, zone]
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
                    .frame(width: thumb.width + 20)
                    .offset(x: thumb.minX - 10, y: thumb.maxY + 7)
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: thumb.height)
                    .offset(x: thumb.maxX + 15, y: thumb.minY)
            }

            let hintStart = model.groupThumb.map { $0.maxX + 16 } ?? model.card.minX
            Text(L("Drop on a zone · Esc cancels"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: max(1, model.card.maxX - hintStart))
                .offset(x: hintStart, y: model.card.maxY - ZonePopupGeometry.hintHeight + 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(model.isOpen ? 1 : 0.9, anchor: .top)
        .offset(y: model.isOpen ? 0 : -12)
        .opacity(model.isOpen ? 1 : 0)
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
