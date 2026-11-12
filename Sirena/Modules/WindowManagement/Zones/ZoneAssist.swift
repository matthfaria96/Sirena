/// ZoneAssist.swift
///
/// Snap Assist, as in Windows 11: right after a window goes into a zone, the other zones of
/// that layout light up on the display, each listing the open windows grouped by app, with a
/// live picture of each (the ⌘ Tab switcher's capture; just the app icon without Screen
/// Recording). A click on one puts it in that zone; the rest stay until they are filled, Esc
/// is pressed or the click lands anywhere else. The keyboard works too: arrows move through
/// the windows, Tab goes to the next zone, Return puts the window there.

import AppKit
import SwiftUI

@MainActor
final class ZoneAssist {
    struct Candidate: Identifiable {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
        /// The display it is on, when not the one being filled (shown apart, quieter).
        var otherDisplay: String?
    }

    struct Spot: Identifiable {
        let zone: Int
        /// Inside the panel (y down).
        let frame: CGRect
        /// What is there now ("Trocar app": the window a pick replaces).
        var caption: String?
        var id: Int { zone }
    }

    /// A candidate was picked for a zone.
    var onPick: ((CGWindowID, Int) -> Void)?

    private var panel: AssistPanel?
    private let model = ZoneAssistModel()
    private var resignToken: NSObjectProtocol?

    var isShown: Bool { panel?.isVisible == true }

    /// `zones` in Accessibility coordinates. `captions`: what each zone holds now, when a pick
    /// replaces it. `hint`: the line at the bottom, when not the Snap Assist one.
    func show(on screen: NSScreen, zones: [(zone: Int, frame: CGRect)], candidates: [Candidate],
              captions: [Int: String] = [:], hint: String? = nil) {
        guard !zones.isEmpty, !candidates.isEmpty else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = screen.frame.screenFlipped.origin
        model.spots = zones.map { Spot(zone: $0.zone, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y), caption: captions[$0.zone]) }
        model.hint = hint
        model.candidates = candidates
        model.previews = [:]
        model.focusSpot = 0
        model.focused = nil
        model.isOpen = false
        capturePreviews(of: candidates)
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                      ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.85)) { model.isOpen = true }
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
            model.focusSpot = min(model.focusSpot, max(0, model.spots.count - 1))
            if model.focused == candidate { model.focused = model.ordered.first?.id }
        }
        onPick?(candidate, zone)
        if model.spots.isEmpty || model.candidates.isEmpty { close() }
    }

    // MARK: Keyboard

    /// ← → ↑ ↓: the previous or next window (in the order they are shown).
    private func move(_ step: Int) {
        let ordered = model.ordered
        guard !ordered.isEmpty else { return }
        let current = model.focused.flatMap { id in ordered.firstIndex { $0.id == id } }
        let next = current.map { ($0 + step + ordered.count) % ordered.count } ?? (step > 0 ? 0 : ordered.count - 1)
        withAnimation(.snappy(duration: 0.12)) { model.focused = ordered[next].id }
    }

    /// Tab (⇧ Tab): the next (previous) zone to fill.
    private func nextSpot(_ step: Int) {
        guard model.spots.count > 1 else { return }
        withAnimation(.snappy(duration: 0.15)) {
            model.focusSpot = (model.focusSpot + step + model.spots.count) % model.spots.count
            if model.focused == nil { model.focused = model.ordered.first?.id }
        }
    }

    /// Return: the window under the keyboard goes into the zone under the keyboard.
    private func choose() {
        guard let focused = model.focused, model.spots.indices.contains(model.focusSpot) else {
            move(1)
            return
        }
        pick(focused, zone: model.spots[model.focusSpot].zone)
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
        panel.onMove = { [weak self] step in self?.move(step) }
        panel.onNextSpot = { [weak self] step in self?.nextSpot(step) }
        panel.onChoose = { [weak self] in self?.choose() }
        let view = ZoneAssistView(model: model,
                                  pick: { [weak self] candidate, zone in self?.pick(candidate, zone: zone) },
                                  dismiss: { [weak self] in self?.close() })
        panel.contentView = FirstClickHostingView(rootView: view)
        return panel
    }
}

/// Takes the keyboard without bringing Sirena forward, so Esc, the arrows, Tab and Return
/// reach it.
private final class AssistPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onNextSpot: ((Int) -> Void)?
    var onChoose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()                                     // Esc
        case 123, 126: onMove?(-1)                               // ← ↑
        case 124, 125: onMove?(1)                                // → ↓
        case 48: onNextSpot?(event.modifierFlags.contains(.shift) ? -1 : 1) // Tab
        case 36, 76: onChoose?()                                 // Return, Enter
        default: super.keyDown(with: event)
        }
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
    /// The line at the bottom (nil: Snap Assist's).
    var hint: String?
    /// The zone and the window under the keyboard (nil until a key is used).
    var focusSpot = 0
    var focused: CGWindowID?

    /// The candidates in the order they are shown: this display's first, then the others'.
    var ordered: [ZoneAssist.Candidate] { (byApp(here: true) + byApp(here: false)).flatMap(\.windows) }

    /// The windows of this display (`here`) or of the other displays, by app, in the order
    /// their first window appears (front to back).
    func byApp(here: Bool) -> [(pid: pid_t, name: String, windows: [ZoneAssist.Candidate])] {
        var order: [pid_t] = []
        var groups: [pid_t: [ZoneAssist.Candidate]] = [:]
        for candidate in candidates where (candidate.otherDisplay == nil) == here {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A click anywhere else ends it (a fully clear window would let clicks through).
            Color.black.opacity(model.isOpen ? 0.12 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            ForEach(Array(model.spots.enumerated()), id: \.element.id) { index, spot in
                SpotView(spot: spot, model: model, isFocused: model.focused != nil && index == model.focusSpot) {
                    pick($0, spot.zone)
                }
                .frame(width: spot.frame.width, height: spot.frame.height)
                .offset(x: spot.frame.minX, y: spot.frame.minY)
                .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.96)
                .opacity(model.isOpen ? 1 : 0)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            }
            AssistHint(text: model.hint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .opacity(model.isOpen ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// How to use it, low in the middle of the display.
private struct AssistHint: View {
    let text: String?

    var body: some View {
        Text(text ?? L("Choose a window for each space · arrows and Return · Esc closes"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .compatGlass(.regular, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.8))
    }
}

/// One zone to fill: glass, with the open windows to pick from, app by app.
private struct SpotView: View {
    let spot: ZoneAssist.Spot
    let model: ZoneAssistModel
    /// The zone the keyboard fills.
    let isFocused: Bool
    let pick: (CGWindowID) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                if let caption = spot.caption {
                    Label(caption, systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                ForEach(model.byApp(here: true), id: \.pid) { app in
                    appSection(app, elsewhere: false)
                }
                let elsewhere = model.byApp(here: false)
                if !elsewhere.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
                        Label(L("On other displays"), systemImage: "display.2")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
                    }
                    .padding(.top, 4)
                    ForEach(elsewhere, id: \.pid) { app in
                        appSection(app, elsewhere: true)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .compatGlass(.regular, in: shape)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(supportsLiquidGlass ? 0.25 : 0.5)))
        .overlay(shape.strokeBorder(Color.accentColor.opacity(isFocused ? 1 : 0.75), lineWidth: isFocused ? 3 : 2))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(4)
    }

    /// One app: its header, then its windows. Narrow zones get smaller cards, so a few still fit
    /// side by side.
    private func appSection(_ app: (pid: pid_t, name: String, windows: [ZoneAssist.Candidate]), elsewhere: Bool) -> some View {
        let minimum = min(200, max(130, spot.frame.width / 3.4))
        return VStack(alignment: .leading, spacing: 8) {
            appHeader(app)
                .opacity(elsewhere ? 0.6 : 1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 280), spacing: 12)], spacing: 12) {
                ForEach(app.windows) { candidate in
                    CandidateCard(candidate: candidate, preview: model.previews[candidate.id],
                                  isFocused: isFocused && model.focused == candidate.id) { pick(candidate.id) }
                }
            }
        }
    }

    private func appHeader(_ app: (pid: pid_t, name: String, windows: [ZoneAssist.Candidate])) -> some View {
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
    }
}

/// A window to pick: its picture (or its app's icon until there is one) and its title.
private struct CandidateCard: View {
    let candidate: ZoneAssist.Candidate
    let preview: CGImage?
    /// Under the keyboard (arrows), lit like under the pointer.
    var isFocused = false
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isLit = isHovering || isFocused
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
                if let display = candidate.otherDisplay {
                    Label(display, systemImage: "display")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isLit ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isLit ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isLit ? 2 : 1))
            .scaleEffect(isLit && !reduceMotion ? 1.03 : 1)
            // On another display: there to be found, quieter until pointed at.
            .opacity(candidate.otherDisplay != nil && !isLit ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.title.isEmpty ? candidate.appName : "\(candidate.title), \(candidate.appName)")
        .accessibilityValue(candidate.otherDisplay.map { L("On \($0)") } ?? "")
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .help((candidate.title.isEmpty ? candidate.appName : "\(candidate.title) — \(candidate.appName)")
              + (candidate.otherDisplay.map { " · " + L("On \($0)") } ?? ""))
    }
}
