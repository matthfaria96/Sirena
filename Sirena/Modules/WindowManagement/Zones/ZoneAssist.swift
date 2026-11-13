/// ZoneAssist.swift
///
/// Snap Assist, as in Windows 11: right after a window goes into a zone, the layout's other
/// zones wait to be filled. One of them at a time holds the picker: the open windows by app,
/// with a live picture of each (the ⌘ Tab switcher's previews and their cache; the app's icon
/// without Screen Recording). This display's windows come first, then the other displays', then the
/// minimized ones and those of hidden apps, each saying where it is. The other zones are
/// quiet placeholders; a click on one moves the picker there. A click on a window puts it in
/// the zone and the picker goes on to the next one; Esc or a click anywhere else stops.
///
/// The keyboard: typing filters by app or title, the arrows move through the windows (← →
/// in order, ↑ ↓ by row), Tab goes to another zone, Return puts the window in.

import AppKit
import SwiftUI

@MainActor
final class ZoneAssist {
    struct Spot: Identifiable {
        let zone: Int
        /// Inside the panel (y down).
        let frame: CGRect
        /// What is there now ("Trocar app": the window a pick replaces).
        var caption: String?
        var id: Int { zone }
    }

    /// A window was picked for a zone. False when it couldn't be put there: it stays offered.
    var onPick: ((ZoneWindow, Int) -> Bool)?
    /// It went away (every zone filled, Esc, a click elsewhere, or closed by its owner).
    var onClose: (() -> Void)?

    private var panel: AssistPanel?
    private let model = ZoneAssistModel()
    private var resignToken: NSObjectProtocol?
    private var closeWork: DispatchWorkItem?

    /// From `show` to `close` (the panel itself lingers a moment more, fading out).
    private(set) var isShown = false

    /// `zones` in Accessibility coordinates, in the order they are filled. `captions`: what
    /// each zone holds now, when a pick replaces it.
    func show(on screen: NSScreen, zones: [(zone: Int, frame: CGRect)], windows: [ZoneWindow],
              captions: [Int: String] = [:]) {
        guard !zones.isEmpty, !windows.isEmpty else { return }
        closeWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = screen.frame.screenFlipped.origin
        model.spots = zones.map {
            Spot(zone: $0.zone, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y), caption: captions[$0.zone])
        }
        model.windows = windows
        model.active = 0
        model.focused = nil
        model.usesKeyboard = false
        model.query = ""
        model.isOpen = false
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        isShown = true
        capturePreviews(of: windows)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                      ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.85)) { model.isOpen = true }
        if resignToken == nil {
            resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
    }

    func close() {
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
        guard isShown, let panel else { return }
        isShown = false
        withAnimation(.easeIn(duration: 0.14)) { model.isOpen = false }
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        onClose?()
    }

    // MARK: Pictures

    /// Pictures of the windows, through the ⌘ Tab switcher's provider: what it has cached shows
    /// at once, fresh ones replace them as they are taken, in the order the windows are shown
    /// and off the main thread. It also knows the captures that can't be shown as they come (a
    /// window hanging over the edge of a display comes back as a thin slice) and takes those
    /// another way. Left to finish when the assist closes: the cache is shared, and stopping
    /// here could stop a ⌘ Tab that just opened.
    private func capturePreviews(of windows: [ZoneWindow]) {
        let provider = SwitcherWindowPreviewProvider.shared
        var cached: [CGWindowID: CGImage] = [:]
        for window in windows { cached[window.id] = provider.cachedPreview(for: window.id) }
        model.previews = cached
        provider.refreshPreviews(for: windows.map(Self.item), excludedAppsKey: SwitcherDefaultsKey.switcherPreviewExcludedApps) { [weak self] id, image in
            MainActor.assumeIsolated { self?.publish(image, for: id) }
        }
    }

    /// Takes the pictures ahead of time (the layouts panel is up, Snap Assist may follow): the
    /// cards then show them at once.
    static func warmPreviews(of windows: [ZoneWindow]) {
        SwitcherWindowPreviewProvider.shared.refreshPreviews(for: windows.map(Self.item),
                                                             excludedAppsKey: SwitcherDefaultsKey.switcherPreviewExcludedApps) { _, _ in }
    }

    private static func item(_ window: ZoneWindow) -> SwitcherItem {
        SwitcherItem.window(id: window.id, title: window.title, appName: window.appName, pid: window.pid,
                            windowOwnerPID: window.ownerPID, isOnScreen: window.isOnScreen,
                            isAppHidden: window.state == .hidden, isMinimized: window.state == .minimized,
                            frame: window.frame)
    }

    private func publish(_ image: CGImage, for id: CGWindowID) {
        guard isShown, model.windows.contains(where: { $0.id == id }) else { return }
        if model.previews[id] == nil {
            withAnimation(.easeOut(duration: 0.2)) { model.previews[id] = image }
        } else {
            model.previews[id] = image
        }
    }

    // MARK: Choosing

    private func pick(_ window: ZoneWindow, zone: Int) {
        guard onPick?(window, zone) != false else {
            NSSound.beep()
            return
        }
        // "Trocar app" closes on its pick.
        guard isShown else { return }
        withAnimation(.snappy(duration: 0.22)) {
            model.spots.removeAll { $0.zone == zone }
            model.windows.removeAll { $0.id == window.id }
            model.active = min(model.active, max(0, model.spots.count - 1))
            model.query = ""
            model.focused = model.usesKeyboard ? model.shown.first?.id : nil
        }
        if model.spots.isEmpty || model.windows.isEmpty { close() }
    }

    /// The picker goes to another zone.
    private func activate(_ index: Int) {
        guard model.spots.indices.contains(index), index != model.active else { return }
        withAnimation(.snappy(duration: 0.2)) { model.active = index }
    }

    // MARK: Keyboard

    private var layout: ZonePickerLayout {
        ZonePickerLayout(width: (model.spots.indices.contains(model.active) ? model.spots[model.active].frame.width : 600) - PickerView.inset * 2)
    }

    /// The arrows: ← → through the windows in order, ↑ ↓ by row.
    private func move(dx: Int, dy: Int) {
        let rows = model.rows(columns: layout.columns)
        let current = model.usesKeyboard ? model.focused : nil
        guard let next = ZonePickerLayout.moving(from: current, dx: dx, dy: dy, in: rows) else { return }
        model.usesKeyboard = true
        withAnimation(.snappy(duration: 0.12)) { model.focused = next }
        model.scrollTick += 1
    }

    /// Tab (⇧ Tab): the next (previous) zone to fill.
    private func nextSpot(_ step: Int) {
        guard model.spots.count > 1 else { return }
        activate((model.active + step + model.spots.count) % model.spots.count)
    }

    /// Return: the window under the keyboard (or the pointer) goes into the zone.
    private func choose() {
        guard model.spots.indices.contains(model.active) else { return }
        guard let focused = model.focused, let window = model.shown.first(where: { $0.id == focused }) else {
            move(dx: 1, dy: 0)
            return
        }
        pick(window, zone: model.spots[model.active].zone)
    }

    /// Typing filters the windows; the first one left is ready for Return.
    private func type(_ text: String) {
        if model.query.isEmpty, text.allSatisfy(\.isWhitespace) { return }
        setQuery(model.query + text)
    }

    private func erase() {
        guard !model.query.isEmpty else { return }
        setQuery(String(model.query.dropLast()))
    }

    private func setQuery(_ query: String) {
        withAnimation(.snappy(duration: 0.15)) {
            model.query = query
            model.usesKeyboard = true
            model.focused = model.shown.first?.id
        }
        model.scrollTick += 1
    }

    /// Esc: the filter first, then the assist.
    private func cancel() {
        if model.query.isEmpty { close() } else { setQuery("") }
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
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.onMove = { [weak self] dx, dy in self?.move(dx: dx, dy: dy) }
        panel.onNextSpot = { [weak self] step in self?.nextSpot(step) }
        panel.onChoose = { [weak self] in self?.choose() }
        panel.onType = { [weak self] text in self?.type(text) }
        panel.onErase = { [weak self] in self?.erase() }
        let view = ZoneAssistView(model: model,
                                  pick: { [weak self] window, zone in self?.pick(window, zone: zone) },
                                  activate: { [weak self] index in self?.activate(index) },
                                  dismiss: { [weak self] in self?.close() })
        panel.contentView = FirstClickHostingView(rootView: view)
        return panel
    }
}

/// Takes the keyboard without bringing Sirena forward, so Esc, the arrows, Tab, Return and
/// what is typed reach it. The keys are taken before any view sees them: the list would
/// otherwise scroll on the arrows instead of moving through the windows.
private final class AssistPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onNextSpot: ((Int) -> Void)?
    var onChoose: (() -> Void)?
    var onType: ((String) -> Void)?
    var onErase: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handle(event) { return }
        super.sendEvent(event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: onCancel?()                                     // Esc
        case 123: onMove?(-1, 0)                                 // ←
        case 124: onMove?(1, 0)                                  // →
        case 126: onMove?(0, -1)                                 // ↑
        case 125: onMove?(0, 1)                                  // ↓
        case 48: onNextSpot?(flags.contains(.shift) ? -1 : 1)    // Tab
        case 36, 76: onChoose?()                                 // Return, Enter
        case 51, 117: onErase?()                                 // Delete
        default:
            guard flags.isDisjoint(with: [.command, .control]), let text = event.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) }) else {
                return false
            }
            onType?(text)
        }
        return true
    }
}

/// The first click works even though Sirena isn't the active app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
@Observable
final class ZoneAssistModel {
    enum SectionKind: Int {
        case here, otherDisplays, away
    }

    struct AppGroup: Identifiable {
        let id: String
        let pid: pid_t
        let name: String
        let windows: [ZoneWindow]
    }

    struct Section: Identifiable {
        let kind: SectionKind
        let apps: [AppGroup]
        var id: Int { kind.rawValue }
    }

    var spots: [ZoneAssist.Spot] = []
    var windows: [ZoneWindow] = []
    var previews: [CGWindowID: CGImage] = [:]
    var isOpen = false
    /// The zone that holds the picker (index in `spots`).
    var active = 0
    /// The window under the keyboard or the pointer.
    var focused: CGWindowID?
    /// The keyboard was used: its window stays lit without the pointer on it.
    var usesKeyboard = false
    /// What was typed to filter the windows.
    var query = ""
    /// Bumped when the keyboard moves, so the list scrolls to its window (the pointer never
    /// scrolls it).
    var scrollTick = 0

    /// The windows left by the filter: this display's, the other displays', then the
    /// minimized and hidden ones; in each part by app, in the order the apps first appear
    /// (most recently used first).
    var sections: [Section] {
        let tokens = Self.folded(query).split(separator: " ")
        let matching = tokens.isEmpty ? windows : windows.filter { window in
            let text = Self.folded(window.appName + " " + window.title)
            return tokens.allSatisfy { text.contains($0) }
        }
        return [SectionKind.here, .otherDisplays, .away].compactMap { kind in
            var order: [pid_t] = []
            var groups: [pid_t: [ZoneWindow]] = [:]
            for window in matching where Self.kind(of: window) == kind {
                if groups[window.pid] == nil { order.append(window.pid) }
                groups[window.pid, default: []].append(window)
            }
            guard !order.isEmpty else { return nil }
            return Section(kind: kind, apps: order.map { pid in
                AppGroup(id: "\(kind.rawValue)-\(pid)", pid: pid, name: groups[pid]?.first?.appName ?? "", windows: groups[pid] ?? [])
            })
        }
    }

    /// The windows in the order they are shown.
    var shown: [ZoneWindow] { sections.flatMap { $0.apps.flatMap(\.windows) } }

    /// The cards as the picker lays them, for the arrow keys.
    func rows(columns: Int) -> [[CGWindowID]] {
        sections.flatMap { section in
            ZonePickerLayout.rows(section.apps.map { $0.windows.map(\.id) }, columns: columns)
        }
    }

    private static func kind(of window: ZoneWindow) -> SectionKind {
        switch window.state {
        case .here: return .here
        case .otherDisplay: return .otherDisplays
        case .minimized, .hidden: return .away
        }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

struct ZoneAssistView: View {
    let model: ZoneAssistModel
    let pick: (ZoneWindow, Int) -> Void
    let activate: (Int) -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A click anywhere else ends it (a fully clear window would let clicks through).
            Color.black.opacity(model.isOpen ? 0.12 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            ForEach(Array(model.spots.enumerated()), id: \.element.id) { index, spot in
                Group {
                    if index == model.active {
                        PickerView(spot: spot, model: model, showsTab: model.spots.count > 1) { pick($0, spot.zone) }
                            .transition(.opacity)
                    } else {
                        PlaceholderView(spot: spot) { activate(index) }
                            .transition(.opacity)
                    }
                }
                .frame(width: spot.frame.width, height: spot.frame.height)
                .offset(x: spot.frame.minX, y: spot.frame.minY)
                .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.96)
                .opacity(model.isOpen ? 1 : 0)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The zone being filled: glass, with the open windows to pick from, app by app.
private struct PickerView: View {
    /// The room around the glass inside the zone.
    static let inset: CGFloat = 4

    let spot: ZoneAssist.Spot
    let model: ZoneAssistModel
    let showsTab: Bool
    let pick: (ZoneWindow) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let layout = ZonePickerLayout(width: spot.frame.width - Self.inset * 2)
        let sections = model.sections
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if sections.isEmpty {
                            Text(L("No window matches “\(model.query)”"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }
                        ForEach(sections) { section in
                            if let title = Self.title(of: section.kind) {
                                HStack(spacing: 8) {
                                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
                                    Label(title.text, systemImage: title.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
                                }
                                .padding(.top, 2)
                            }
                            // Apps side by side while they fit whole on a row.
                            let rows = ZonePickerLayout.packing(section.apps.map(\.windows.count), columns: layout.columns)
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: ZonePickerLayout.spacing) {
                                    ForEach(row, id: \.self) { block in
                                        appBlock(section.apps[block.group], block: block, layout: layout, quiet: section.kind != .here)
                                    }
                                }
                            }
                        }
                    }
                    .padding(ZonePickerLayout.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.scrollTick) { _, _ in
                    guard let focused = model.focused else { return }
                    withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(focused) }
                }
            }
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            footer
        }
        .compatGlass(.regular, in: shape)
        // Dense content over whatever is behind: more of the window colour than glass.
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(supportsLiquidGlass ? 0.55 : 0.7)))
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(Self.inset)
    }

    /// What is being replaced ("Trocar app"), and what was typed to filter.
    private var header: some View {
        HStack(spacing: 10) {
            if let caption = spot.caption {
                Label(caption, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 14)
            }
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.query.isEmpty ? .tertiary : .secondary)
            if model.query.isEmpty {
                Text(L("Type to filter"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(model.query)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ZonePickerLayout.padding)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.query.isEmpty ? L("Type to filter") : model.query)
    }

    /// The keys, as many as fit.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                KeyHint(keys: "← ↑ ↓ →", text: L("Move"))
                KeyHint(keys: "↩", text: L("Snap"))
                if showsTab { KeyHint(keys: "⇥", text: L("Other space")) }
                KeyHint(keys: "esc", text: L("Close"))
            }
            HStack(spacing: 14) {
                KeyHint(keys: "↩", text: L("Snap"))
                if showsTab { KeyHint(keys: "⇥", text: L("Other space")) }
                KeyHint(keys: "esc", text: L("Close"))
            }
            HStack(spacing: 14) {
                KeyHint(keys: "↩", text: L("Snap"))
                KeyHint(keys: "esc", text: L("Close"))
            }
            KeyHint(keys: "esc", text: L("Close"))
        }
        .padding(.horizontal, ZonePickerLayout.padding)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    private static func title(of kind: ZoneAssistModel.SectionKind) -> (text: String, symbol: String)? {
        switch kind {
        case .here: return nil
        case .otherDisplays: return (L("On other displays"), "display.2")
        case .away: return (L("Minimized or hidden"), "eye.slash")
        }
    }

    /// A stretch of one app's windows on a row, under the app's header when it is its first.
    private func appBlock(_ app: ZoneAssistModel.AppGroup, block: ZonePickerLayout.Block, layout: ZonePickerLayout,
                          quiet: Bool) -> some View {
        let windows = Array(app.windows[block.range])
        let width = CGFloat(windows.count) * layout.cardWidth + CGFloat(windows.count - 1) * ZonePickerLayout.spacing
        return VStack(alignment: .leading, spacing: 8) {
            if block.isFirst {
                HStack(spacing: 7) {
                    if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if app.windows.count > 1 {
                        Text("\(app.windows.count)")
                            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                }
                .padding(.horizontal, 2)
                .frame(width: width, height: 18, alignment: .leading)
                .opacity(quiet ? 0.7 : 1)
            }
            HStack(alignment: .top, spacing: ZonePickerLayout.spacing) {
                ForEach(windows) { window in
                    WindowCard(window: window, preview: model.previews[window.id], model: model) { pick(window) }
                        .frame(width: layout.cardWidth)
                        .id(window.id)
                }
            }
        }
    }
}

/// A key and what it does, in the picker's footer.
private struct KeyHint: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// A zone waiting for its turn: a click brings the picker to it.
private struct PlaceholderView: View {
    let spot: ZoneAssist.Spot
    let activate: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: activate) {
            VStack(spacing: 8) {
                Image(systemName: spot.caption == nil ? "plus" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(isHovering ? 0.85 : 0.6))
                    .frame(width: 44, height: 44)
                    .compatGlass(.regular, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1.5)
                    .scaleEffect(isHovering ? 1.06 : 1)
                    .padding(.bottom, 2)
                Text(spot.caption ?? L("Free space"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(L("Click to choose its window"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compatGlass(.regular, in: shape)
            .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(isHovering ? 0.3 : 0.15)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(isHovering ? 0.55 : 0.35), Color.white.opacity(isHovering ? 0.25 : 0.1)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5).padding(-0.5))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(PickerView.inset)
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .accessibilityLabel(spot.caption ?? L("Free space"))
        .accessibilityHint(L("Click to choose its window"))
    }
}

/// A window to pick: its picture (its app's icon until there is one), its title, and where it
/// is when not on this display.
private struct WindowCard: View {
    let window: ZoneWindow
    let preview: CGImage?
    let model: ZoneAssistModel
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isLit = model.focused == window.id && (isHovering || model.usesKeyboard)
        let place = Self.place(of: window.state)
        Button(action: action) {
            VStack(spacing: 7) {
                let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
                    if let preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1.5)
                            .padding(6)
                            .transition(.opacity)
                    } else if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity)
                // Which app it is, at a glance, on the corner of its picture.
                .overlay(alignment: .bottomLeading) {
                    if preview != nil, let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: -3, y: 5)
                            .transition(.opacity)
                    }
                }

                Text(window.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                if let place {
                    Label(place.text, systemImage: place.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            // Lit like the system's own ⌘ Tab: brighter, neutral, no accent colour.
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(isLit ? 0.16 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(isLit ? 0.5 : 0.1), lineWidth: isLit ? 1.2 : 0.8))
            .shadow(color: .black.opacity(isLit ? 0.16 : 0), radius: 8, y: 3)
            .scaleEffect(isLit && !reduceMotion ? 1.03 : 1)
            // Not on this display: there to be found, quieter until pointed at.
            .opacity(isLit ? 1 : place?.opacity ?? 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(window.title.isEmpty ? window.appName : "\(window.title), \(window.appName)")
        .accessibilityValue(place?.spoken ?? "")
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovering = hovering
                if hovering { model.focused = window.id }
            }
        }
        .help((window.title.isEmpty ? window.appName : "\(window.title) — \(window.appName)")
              + (place.map { " · " + $0.spoken } ?? ""))
    }

    private static func place(of state: ZoneWindow.State) -> (text: String, symbol: String, spoken: String, opacity: Double)? {
        switch state {
        case .here: return nil
        case .otherDisplay(let name): return (name, "display", L("On \(name)"), 0.55)
        case .minimized: return (L("Minimized"), "minus.circle", L("Minimized"), 0.75)
        case .hidden: return (L("App hidden"), "eye.slash", L("App hidden"), 0.75)
        }
    }
}
