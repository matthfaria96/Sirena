/// ZoneAssist.swift
///
/// Snap Assist, as in Windows 11: right after a window goes into a zone, the other zones of
/// that layout light up on the display, each listing the open windows grouped by app, with a
/// live picture of each (the ⌘ Tab switcher's capture; just the app icon without Screen
/// Recording). A click on one puts it in that zone; the rest stay until they are filled, Esc
/// is pressed or the click lands anywhere else.

import AppKit
import SwiftUI

@MainActor
final class ZoneAssist {
    struct Candidate: Identifiable {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
    }

    struct Spot: Identifiable {
        let zone: Int
        /// Inside the panel (y down).
        let frame: CGRect
        var id: Int { zone }
    }

    /// A candidate was picked for a zone.
    var onPick: ((CGWindowID, Int) -> Void)?

    private var panel: AssistPanel?
    private let model = ZoneAssistModel()
    private var resignToken: NSObjectProtocol?

    var isShown: Bool { panel?.isVisible == true }

    /// `zones` in Accessibility coordinates.
    func show(on screen: NSScreen, zones: [(zone: Int, frame: CGRect)], candidates: [Candidate]) {
        guard !zones.isEmpty, !candidates.isEmpty else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = screen.frame.screenFlipped.origin
        model.spots = zones.map { Spot(zone: $0.zone, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) }
        model.candidates = candidates
        model.previews = [:]
        model.isOpen = false
        capturePreviews(of: candidates)
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { model.isOpen = true }
        resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        captureTask?.cancel()
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
        guard let panel, panel.isVisible else { return }
        withAnimation(.easeIn(duration: 0.14)) { model.isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak panel] in panel?.orderOut(nil) }
    }

    /// Pictures of the windows, one after another, small enough to keep the panel light.
    private func capturePreviews(of candidates: [Candidate]) {
        captureTask?.cancel()
        guard CGPreflightScreenCaptureAccess() else { return }
        captureTask = Task { [model] in
            for candidate in candidates {
                guard !Task.isCancelled else { return }
                guard let image = await SwitcherWindowPreviewProvider.captureViaWindowServer(candidate.id),
                      let small = Self.downscaled(image, maxSide: 520) else { continue }
                withAnimation(.easeOut(duration: 0.2)) { model.previews[candidate.id] = small }
            }
        }
    }

    private var captureTask: Task<Void, Never>?

    private static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = Int(CGFloat(image.width) * scale), height = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private func pick(_ candidate: CGWindowID, zone: Int) {
        withAnimation(.snappy(duration: 0.22)) {
            model.spots.removeAll { $0.zone == zone }
            model.candidates.removeAll { $0.id == candidate }
        }
        onPick?(candidate, zone)
        if model.spots.isEmpty || model.candidates.isEmpty { close() }
    }

    private func makePanel() -> AssistPanel {
        let panel = AssistPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.onCancel = { [weak self] in self?.close() }
        let view = ZoneAssistView(model: model,
                                  pick: { [weak self] candidate, zone in self?.pick(candidate, zone: zone) },
                                  dismiss: { [weak self] in self?.close() })
        panel.contentView = FirstClickHostingView(rootView: view)
        return panel
    }
}

/// Takes the keyboard without bringing Sirena forward, so Esc reaches it.
private final class AssistPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}

/// The first click works even though Sirena isn't the active app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
@Observable
final class ZoneAssistModel {
    var spots: [ZoneAssist.Spot] = []
    var candidates: [ZoneAssist.Candidate] = []
    var previews: [CGWindowID: CGImage] = [:]
    var isOpen = false

    /// The candidates by app, in the order their first window appears (front to back).
    var byApp: [(pid: pid_t, name: String, windows: [ZoneAssist.Candidate])] {
        var order: [pid_t] = []
        var groups: [pid_t: [ZoneAssist.Candidate]] = [:]
        for candidate in candidates {
            if groups[candidate.pid] == nil { order.append(candidate.pid) }
            groups[candidate.pid, default: []].append(candidate)
        }
        return order.map { pid in (pid, groups[pid]?.first?.appName ?? "", groups[pid] ?? []) }
    }
}

private struct ZoneAssistView: View {
    let model: ZoneAssistModel
    let pick: (CGWindowID, Int) -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A click anywhere else ends it (a fully clear window would let clicks through).
            Color.black.opacity(model.isOpen ? 0.12 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            ForEach(model.spots) { spot in
                SpotView(spot: spot, model: model) { pick($0, spot.zone) }
                    .frame(width: spot.frame.width, height: spot.frame.height)
                    .offset(x: spot.frame.minX, y: spot.frame.minY)
                    .scaleEffect(model.isOpen ? 1 : 0.96)
                    .opacity(model.isOpen ? 1 : 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One zone to fill: glass, with the open windows to pick from, app by app.
private struct SpotView: View {
    let spot: ZoneAssist.Spot
    let model: ZoneAssistModel
    let pick: (CGWindowID) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        // Narrow zones get smaller cards, so a few still fit side by side.
        let minimum = min(200, max(130, spot.frame.width / 3.4))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                ForEach(model.byApp, id: \.pid) { app in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(app.name)
                                .font(.system(size: 12.5, weight: .semibold))
                            if app.windows.count > 1 {
                                Text("\(app.windows.count)")
                                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 2)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 280), spacing: 12)], spacing: 12) {
                            ForEach(app.windows) { candidate in
                                CandidateCard(candidate: candidate, preview: model.previews[candidate.id]) { pick(candidate.id) }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .compatGlass(.regular, in: shape)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(supportsLiquidGlass ? 0.25 : 0.5)))
        .overlay(shape.strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 2))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(4)
    }
}

/// A window to pick: its picture (or its app's icon until there is one) and its title.
private struct CandidateCard: View {
    let candidate: ZoneAssist.Candidate
    let preview: CGImage?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                    if let preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            .padding(5)
                            .transition(.opacity)
                    } else if let icon = NSRunningApplication(processIdentifier: candidate.pid)?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .opacity(0.9)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Text(candidate.title.isEmpty ? candidate.appName : candidate.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovering ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isHovering ? 2 : 1))
            .scaleEffect(isHovering ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .help(candidate.title.isEmpty ? candidate.appName : "\(candidate.title) — \(candidate.appName)")
    }
}
