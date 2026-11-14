/// ZoneController.swift
///
/// Snap layouts, as close to Windows 11 as macOS allows. Nothing is fixed: a window dragged
/// as usual stays where it's let go.
/// - Drag a window up to the top of a display (middle part): a panel drops with layouts.
///   Let go over one of their zones and the window goes there; Esc or moving away closes it.
/// - Snap Assist: the other zones of that layout wait to be filled, one at a time, from the
///   open windows (the ⌘ Tab switcher's list: minimized ones and hidden apps' too, other
///   displays' marked); a click puts one in, Esc or a click elsewhere stops.
/// - The windows put by one layout on a display form a group. While one of them is in use
///   each edge two of them share gets one quiet neutral line with a glass grip that resizes
///   both. Resizing one of them by its own edge moves the line too.
/// - A window of a group let go outside a zone leaves it and gets its own size back.
/// - A click on a grip opens its menu: swap an app (the only way a new window comes in),
///   swap the sides, change the layout, share the room equally, unlink (the windows stay
///   where they are and the group is forgotten; "Juntar de novo" undoes it for a few
///   seconds), cancel. The panel keeps a "Último grupo" card per display until it is
///   unlinked or forgotten (its × in the ⌃⌥0 panel).
///
/// - ⌃⌥0 (ctrl + start + 0 on Logitech keyboards; Windows' Win+Z) opens the panel for the
///   window in front: arrows choose a zone, ↑ ↓ another layout, Return snaps it, Esc cancels.
///
/// The drag rides on Rectangle's tracking (SnappingManager): while the panel is open
/// Rectangle's snap areas stand aside; the top corners stay Rectangle's. No event tap of
/// its own; a light timer runs only while a group exists. Main thread only, and the main
/// thread never waits for another app: the list of windows (ZoneWindows), the window in use
/// and the frames of a grip being dragged (ZoneFrameWriter) are asked for in the background.

import AppKit
import Carbon.HIToolbox
import DockKit
import MASShortcut
import os

private let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "Zones")

@MainActor
final class ZoneController {
    static let shared = ZoneController()

    static let enabledKey = "snapLayouts.enabled"

    /// The switch in Janelas (on unless turned off).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Opens the panel for the window in front (MASShortcut key; no dots, the binder reaches
    /// it through a key path).
    static let shortcutKey = "snapLayoutsShortcut"
    /// ⌃⌥0: Rectangle's window actions are on ⌃⌥ + letters and arrows, 0 is free.
    static let defaultShortcut = MASShortcut(keyCode: kVK_ANSI_0, modifierFlags: [.control, .option])

    private let popup = ZonePopup()
    private let preview = ZonePreview()
    private let hint = ZoneHint()
    private let assist = ZoneAssist()
    private let decor = ZoneGroupDecor()
    private let writer = ZoneFrameWriter()

    /// The panel open on a display.
    private struct Session {
        let display: String
        let screen: NSScreen
        let geometry: ZonePopupGeometry
        /// Opened by the shortcut: the window it is for (nil while dragging).
        var target: (element: AccessibilityElement, id: CGWindowID)?
        /// Opened by "Alterar divisórias": the group whose layout is being chosen.
        var relayout: String?
        /// Driven by the keyboard and the pointer (not by a drag).
        var isKeyboard: Bool { target != nil || relayout != nil }
    }

    /// A window put in a zone.
    private struct Placement {
        let display: String
        let template: Int
        let zone: Int
        var frame: CGRect {
            didSet { at = Date() }
        }
        /// When Zonas last set its frame: the window server may lag a moment behind.
        var at = Date()
        /// Its app, so the timer can tell without asking anyone whether it is in front.
        var pid: pid_t = 0
        var group: String { "\(display)-\(template)" }
    }

    /// A group as it was, to put back.
    private struct SavedGroup {
        let template: Int
        let root: ZoneNode
        let zones: [CGWindowID: Int]
        let pids: [CGWindowID: pid_t]
    }

    private var session: Session?
    private var hover: ZonePopupGeometry.Hit?
    /// Per display, the last group of two or more windows.
    private var lastGroups: [String: SavedGroup] = [:]
    private var placements: [CGWindowID: Placement] = [:]
    /// A window's own size before it went into a zone, given back when it leaves.
    private var ownSizes: [CGWindowID: CGSize] = [:]
    /// Each layout's proportions per display, as resized windows and grips left them.
    private var roots: [String: ZoneNode] = [:]

    /// The drag in progress: the lowest the pointer went (the panel opens once it rises).
    private var dragLowest: CGFloat?
    /// A grip being dragged.
    private struct GripDrag {
        let group: String
        /// The layout when the drag started.
        let root: ZoneNode
        /// The windows' Accessibility elements, found once.
        let elements: [CGWindowID: AccessibilityElement]
        /// Gives each app its enhanced UI back when the drag is over.
        let restore: [() -> Void]
        /// Sizes windows refused to go under, by zone, learned as the drag goes.
        var minimums: [Int: CGSize] = [:]
    }

    private var gripDrag: GripDrag?
    /// Where the pointer last asked the line to be (before any window's minimum held it).
    private var gripAsked: (divider: ZoneDivider, position: CGFloat)?
    /// The group whose outlines and grips are showing.
    private var decorGroup: String?
    private var timer: Timer?

    /// The window in use in the app in front, as last answered (asked in the background).
    private var focused: (pid: pid_t, window: CGWindowID?)?
    private var focusQueryRunning = false
    private static let focusQueue = DispatchQueue(label: "com.matheusfaria.Sirena.zones.focus", qos: .userInteractive)

    /// Bumped whenever a pending Snap Assist (its windows are being listed) is no longer wanted.
    private var assistRequest = 0
    /// The open windows as last listed for each display, and who waits for a list on its way.
    private var listed: [String: (at: Date, windows: [ZoneWindow])] = [:]
    private var listing: [String: [([ZoneWindow]) -> Void]] = [:]

    private var isStarted = false
    private var shortcutBound = false
    private var recordingToken: NSObjectProtocol?
    private var suspendedForRecording = false

    private init() {
        popup.onKey = { [weak self] code, flags in self?.keyboardKey(code, flags: flags) }
        popup.onPointer = { [weak self] point, clicked in self?.keyboardPointer(point, clicked: clicked) }
        popup.onResign = { [weak self] in
            guard self?.session?.isKeyboard == true else { return }
            self?.closePopup()
        }
        assist.onPick = { [weak self] window, zone in self?.assistPicked(window, zone: zone) ?? false }
        // The outlines were held back while it showed.
        assist.onClose = { [weak self] in self?.focusMayHaveChanged() }
        writer.onRefused = { [weak self] id, asked, kept in
            MainActor.assumeIsolated { self?.learnMinimum(of: id, asked: asked, kept: kept) }
        }
        decor.onGripBegin = { [weak self] in self?.gripBegan() }
        decor.onGripDrag = { [weak self] divider, position in self?.gripMoved(divider, to: position) }
        decor.onGripEnd = { [weak self] divider in self?.gripEnded(divider) }
        decor.onGripClick = { [weak self] divider, center, view in self?.gripClicked(divider, at: center, in: view) }
    }

    // MARK: - The shortcut

    /// Janelas got Accessibility: the shortcut, while the feature is on.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        recordingToken = NotificationCenter.default.addObserver(forName: .shortcutRecording, object: nil, queue: .main) { [weak self] note in
            let recording = note.object as? Bool ?? false
            MainActor.assumeIsolated {
                // While a shortcut is recorded anywhere in Sirena, ours steps aside (a bound ⌃⌥0
                // would open the panel instead of being recorded).
                guard let self, recording != self.suspendedForRecording else { return }
                self.suspendedForRecording = recording
                self.bindShortcut()
            }
        }
        // The outlines follow the window in use without waiting for the timer.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusMayHaveChanged() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        bindShortcut()
    }

    /// The switch in Janelas changed.
    func enabledChanged() {
        bindShortcut()
        if !Self.isEnabled {
            closePopup()
            hint.hide()
            closeAssist()
            refreshDecor()
        }
    }

    /// A display came, went or changed: what is on screen was laid out for the old ones.
    private func screensChanged() {
        closePopup()
        closeAssist()
        hint.hide()
        hideDecor()
        let displays = Set(NSScreen.screens.map { Self.key(for: $0) })
        for (id, placement) in placements where !displays.contains(placement.display) {
            placements.removeValue(forKey: id)
            ownSizes.removeValue(forKey: id)
        }
        refreshDecor()
    }

    /// The default (⌃⌥0) shows in its recorder even before Sirena binds anything (no
    /// Accessibility yet, or the switch off).
    static func registerDefaultShortcut() {
        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.registerDefaultShortcuts([shortcutKey: defaultShortcut])
    }

    private func bindShortcut() {
        let binder = MASShortcutBinder.shared()
        if shortcutBound {
            binder?.breakBinding(withDefaultsKey: Self.shortcutKey)
            shortcutBound = false
        }
        guard isStarted, Self.isEnabled, !suspendedForRecording else { return }
        Self.registerDefaultShortcut()
        binder?.bindShortcut(withDefaultsKey: Self.shortcutKey) { [weak self] in self?.openForFrontWindow() }
        shortcutBound = true
    }

    /// The shortcut: the panel for the window in front, on its display, driven by the keyboard.
    func openForFrontWindow() {
        guard Self.isEnabled, AccessibilityGuard.isTrusted, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        if session?.isKeyboard == true {
            closePopup()
            return
        }
        guard let element = AccessibilityElement.getFocusedWindowElement(), let id = element.windowId,
              element.pid != ProcessInfo.processInfo.processIdentifier, element.isSnappableWindow,
              element.isFullScreen != true, element.isMinimized != true else {
            NSSound.beep()
            return
        }
        let frame = element.frame
        let center = frame.isNull ? NSEvent.mouseLocation.screenFlipped : frame.centerPoint
        let screen = NSScreen.screens.first { $0.frame.screenFlipped.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        openPopup(on: screen, target: (element, id))
        // Starts on the first layout's first zone, so the keys have something to move from and
        // Return snaps this window (the "Último grupo" card is one ← or ↑ away).
        let rows = keyboardRows()
        if let first = rows.first(where: { $0.first != .lastGroup })?.first ?? rows.first?.first { setHover(first) }
    }

    // MARK: - The keyboard and the pointer (shortcut mode)

    /// The panel's choices, one row per drawing (the last group first, when shown). Choosing a
    /// layout ("Alterar divisórias") has one choice per drawing.
    private func keyboardRows() -> [[ZonePopupGeometry.Hit]] {
        guard let geometry = session?.geometry else { return [] }
        if session?.relayout != nil {
            return [geometry.templates.map { .zone(template: $0, zone: 0) }]
        }
        var rows: [[ZonePopupGeometry.Hit]] = geometry.groupThumb == nil ? [] : [[.lastGroup]]
        for (template, zones) in zip(geometry.templates, geometry.zones) {
            rows.append(zones.indices.map { .zone(template: template, zone: $0) })
        }
        return rows
    }

    private func keyboardKey(_ code: UInt16, flags: NSEvent.ModifierFlags) {
        guard let session, session.isKeyboard else { return }
        let rows = keyboardRows()
        guard !rows.isEmpty else { return }
        let flat = rows.flatMap { $0 }
        let row = rows.firstIndex { $0.contains { $0 == hover } } ?? 0
        let column = hover.flatMap { current in rows[row].firstIndex { $0 == current } } ?? 0
        switch Int(code) {
        case kVK_Escape:
            closePopup()
        case kVK_LeftArrow, kVK_RightArrow:
            let step = Int(code) == kVK_LeftArrow ? -1 : 1
            let index = hover.flatMap { current in flat.firstIndex { $0 == current } } ?? -step
            setHover(flat[(index + step + flat.count) % flat.count])
        case kVK_UpArrow, kVK_DownArrow:
            let next = (row + (Int(code) == kVK_UpArrow ? -1 : 1) + rows.count) % rows.count
            setHover(rows[next][min(column, rows[next].count - 1)])
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commitKeyboard()
        case kVK_Delete, kVK_ForwardDelete:
            if hover == .lastGroup { forgetLastGroup(on: session.screen) }
        default:
            break
        }
    }

    private func keyboardPointer(_ point: CGPoint, clicked: Bool) {
        guard let session, session.isKeyboard else { return }
        if clicked, session.relayout == nil, session.geometry.forgetButton?.contains(point) == true {
            forgetLastGroup(on: session.screen)
            return
        }
        var hit = session.geometry.hit(point)
        if session.relayout != nil {
            if case let .zone(template, _) = hit { hit = .zone(template: template, zone: 0) } else { hit = nil }
        }
        if let hit { setHover(hit) }
        if clicked, hit != nil { commitKeyboard() }
    }

    /// The × on the "Último grupo" card (or Delete on it): that group is forgotten.
    private func forgetLastGroup(on screen: NSScreen) {
        lastGroups[Self.key(for: screen)] = nil
        log.notice("last group forgotten")
        // Open again without the card, for the same window.
        guard let target = session?.target else {
            closePopup()
            return
        }
        closePopup()
        openPopup(on: screen, target: target)
        if let first = keyboardRows().first?.first { setHover(first) }
    }

    /// The window the shortcut was for goes to the chosen zone (or the last group comes back);
    /// with "Alterar divisórias", the group takes the chosen layout.
    private func commitKeyboard() {
        guard let session, session.isKeyboard, let hover else { return }
        closePopup()
        if let group = session.relayout {
            if case let .zone(template, _) = hover { applyLayout(template, to: group, on: session.screen) }
            return
        }
        guard let target = session.target else { return }
        switch hover {
        case .lastGroup:
            relink(on: session.screen)
        case let .zone(template, zone):
            guard let frame = frames(template: template, on: session.screen)[safe: zone] else { return }
            place(target.element, id: target.id, frame: frame,
                  placement: Placement(display: session.display, template: template, zone: zone, frame: frame))
            log.notice("window into zone \(zone + 1) of layout \(template + 1) (keyboard)")
            startAssist(template: template, screen: session.screen)
        }
    }

    /// The zone (or card) lit in the panel, with its preview on the display.
    private func setHover(_ hit: ZonePopupGeometry.Hit?) {
        guard let session, hit != hover else { return }
        hover = hit
        popup.setHover(hit)
        // Still choosing: the list for Snap Assist stays fresh.
        if hit != nil { warmWindows(for: session.screen) }
        if session.relayout == nil, case let .zone(template, zone) = hit, let frame = frames(template: template, on: session.screen)[safe: zone] {
            // The app whose window goes there: the one in front (a drag brings it forward; the
            // shortcut's panel doesn't take the front).
            preview.show(frame, icon: NSWorkspace.shared.frontmostApplication?.icon)
        } else {
            preview.hide()
        }
    }

    // MARK: - From SnappingManager (it isn't main-actor code, but runs on the main thread)

    nonisolated static func dragMoved() -> Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { shared.handleDragMoved() }
    }

    nonisolated static func dragEnded(element: AccessibilityElement?, id: CGWindowID?, cancelled: Bool) -> Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { shared.handleDragEnded(element: element, id: id, cancelled: cancelled) }
    }

    nonisolated static func cancelDrag() {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            shared.closePopup()
            shared.hint.hide()
        }
    }

    nonisolated static func resizeEnded(element: AccessibilityElement?, id: CGWindowID?) {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { shared.handleResizeEnded(element: element, id: id) }
    }

    /// A window is being resized by its edge: its group's outlines would lag behind it.
    nonisolated static func resizeMoved(id: CGWindowID) {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            if shared.placements[id] != nil { shared.hideDecor() }
        }
    }

    /// The mouse button went up: a click may have put another window in use.
    nonisolated static func pointerReleased() {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { shared.focusMayHaveChanged() }
    }

    /// A window action (⌃⌥←, a snap area…) moved a window: it leaves its group.
    nonisolated static func noteWindowAction(on windowID: CGWindowID?) {
        guard let windowID else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { shared.leaveGroup(windowID) }
        } else {
            DispatchQueue.main.async { shared.leaveGroup(windowID) }
        }
    }

    // MARK: - The drag

    /// The dragged window moved. True while the panel is open (Rectangle's snap areas then
    /// stand aside).
    private func handleDragMoved() -> Bool {
        guard Self.isEnabled, AccessibilityGuard.isTrusted else {
            closePopup()
            hint.hide()
            return false
        }
        hideDecor()
        // A drag takes over: the panel opened by the shortcut and Snap Assist give way.
        if session?.isKeyboard == true { closePopup() }
        closeAssist()
        let cursor = NSEvent.mouseLocation.screenFlipped
        dragLowest = max(dragLowest ?? cursor.y, cursor.y)
        if session == nil, let screen = NSScreen.screens.first(where: { $0.frame.screenFlipped.contains(cursor) }) {
            hint.show(on: screen)
        }
        if let session {
            let near = session.geometry.card.insetBy(dx: -70, dy: -70).contains(cursor)
            guard near || isInTopBand(cursor, of: session.screen) else {
                closePopup()
                return false
            }
            let hit = session.geometry.hit(cursor)
            if hit != hover {
                if hit != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                setHover(hit)
            }
            return true
        }
        // Opens when the window is brought up to the top, not when a window that already
        // sits there starts being dragged: the pointer has to rise into the band.
        guard let screen = NSScreen.screens.first(where: { $0.frame.screenFlipped.contains(cursor) }),
              isInTopBand(cursor, of: screen), let lowest = dragLowest, lowest - cursor.y >= 24 else { return false }
        openPopup(on: screen)
        return true
    }

    /// The drag ended. True when the drop was taken here: into a zone, or over the open
    /// panel without one (nothing happens then, like a cancel).
    private func handleDragEnded(element: AccessibilityElement?, id: CGWindowID?, cancelled: Bool) -> Bool {
        dragLowest = nil
        hint.hide()
        defer { closePopup() }
        guard let session, !session.isKeyboard else {
            // Let go elsewhere: it leaves its group and gets its own size back.
            if let id, let element, placements[id] != nil { release(id, element: element) }
            return false
        }
        guard !cancelled, let hover else { return !cancelled }
        switch hover {
        case .lastGroup:
            relink(on: session.screen)
        case let .zone(template, zone):
            guard let element, let id,
                  let frame = frames(template: template, on: session.screen)[safe: zone] else { return true }
            place(element, id: id, frame: frame,
                  placement: Placement(display: session.display, template: template, zone: zone, frame: frame))
            log.notice("window into zone \(zone + 1) of layout \(template + 1)")
            startAssist(template: template, screen: session.screen)
        }
        return true
    }

    private func openPopup(on screen: NSScreen, target: (element: AccessibilityElement, id: CGWindowID)? = nil,
                           relayout: String? = nil) {
        closeAssist()
        let display = Self.key(for: screen)
        // The layouts that suit this display's size and shape (a portrait display gets rows,
        // an ultrawide one more columns, a small one no cramped zones).
        let templates = ZoneTemplate.fitting(layoutArea(screen).size).map(\.rawValue)
        let roots = templates.map { root($0, display: display) }
        // The last group is offered while at least two of its windows are still around (not
        // while choosing a group's new layout).
        let saved = relayout != nil ? nil : lastGroups[display].flatMap { group -> SavedGroup? in
            let alive = Set(WindowUtil.getWindowList(ids: Array(group.zones.keys), all: true, forceRefresh: true).map(\.id))
            return group.zones.keys.filter(alive.contains).count >= 2 ? group : nil
        }
        let geometry = ZonePopupGeometry(visible: screen.visibleFrame, templates: templates, roots: roots, lastGroup: saved?.root)
        session = Session(display: display, screen: screen, geometry: geometry, target: target, relayout: relayout)
        hover = nil
        hint.hide()
        var icons: [Int: pid_t] = [:]
        for (id, zone) in saved?.zones ?? [:] { icons[zone] = saved?.pids[id] }
        popup.open(geometry, roots: roots, groupIcons: icons, keyboard: target != nil || relayout != nil,
                   hint: relayout != nil ? L("Choose the new layout · Return applies · Esc keeps this one") : nil,
                   wholeLayout: relayout != nil)
        warmWindows(for: screen)
    }

    private func closePopup() {
        guard session != nil else { return }
        session = nil
        hover = nil
        popup.close()
        preview.hide()
    }

    /// The top of the display (from the menu bar down to where a dragged title bar sits),
    /// away from the corners Rectangle uses for its quarter snaps.
    private func isInTopBand(_ point: CGPoint, of screen: NSScreen) -> Bool {
        let frame = screen.frame.screenFlipped
        let top = screen.visibleFrame.screenFlipped.minY
        return point.y <= top + 36
            && point.x >= frame.minX + frame.width * 0.2 && point.x <= frame.maxX - frame.width * 0.2
    }

    // MARK: - Snap Assist

    /// How long Snap Assist may take to show after a window was placed.
    private static let assistPatience: TimeInterval = 1.5

    /// Where the assist is, and whether a pick replaces the window of that zone ("Trocar app").
    private var assistContext: (screen: NSScreen, template: Int, replacing: Bool)?

    /// The open windows for `screen` (ZoneWindows, in the background): a list no older than
    /// `maxAge` at once, otherwise as soon as it is built; one is built at a time per display,
    /// and whoever asks meanwhile gets that one. The panel asks as it opens (`warmWindows`),
    /// so by the time a window is let go on a zone Snap Assist has its list, and the pictures
    /// are already taken.
    private func windows(for screen: NSScreen, maxAge: TimeInterval, then: @escaping ([ZoneWindow]) -> Void) {
        let display = Self.key(for: screen)
        if let known = listed[display], Date().timeIntervalSince(known.at) <= maxAge {
            then(known.windows)
            return
        }
        if listing[display] != nil {
            listing[display]?.append(then)
            return
        }
        listing[display] = [then]
        ZoneWindows.list(for: screen) { [weak self] windows in
            guard let self else { return }
            self.listed[display] = (Date(), windows)
            ZoneAssist.warmPreviews(of: windows)
            for waiting in self.listing.removeValue(forKey: display) ?? [] { waiting(windows) }
        }
    }

    /// The panel is up on `screen`: Snap Assist's list and pictures get ready meanwhile.
    private func warmWindows(for screen: NSScreen) {
        windows(for: screen, maxAge: 1) { _ in }
    }

    /// Snap Assist for the zones of `template` nobody is in yet. It shows as soon as the open
    /// windows are known (at once when the panel had them listed), unless something else took
    /// the stage meanwhile.
    private func startAssist(template: Int, screen: NSScreen) {
        guard !freeZones(of: template, on: screen).isEmpty else { return }
        assistRequest += 1
        let request = assistRequest
        let asked = Date()
        windows(for: screen, maxAge: 2.5) { [weak self] windows in
            // Too late (an app took its time to answer): the user has moved on, a panel taking
            // the display and the keyboard now would only be in the way.
            guard let self, request == self.assistRequest, self.session == nil, Self.isEnabled,
                  Date().timeIntervalSince(asked) < Self.assistPatience else { return }
            let group = "\(Self.key(for: screen))-\(template)"
            let members = Set(self.placements.filter { $0.value.group == group }.map(\.key))
            let free = self.freeZones(of: template, on: screen)
            let candidates = windows.filter { !members.contains($0.id) }
            guard !free.isEmpty, !candidates.isEmpty else { return }
            self.assistContext = (screen, template, false)
            Self.logOffer(candidates, zones: free.count)
            self.assist.show(on: screen, zones: free, windows: candidates)
        }
    }

    /// The zones of `template` on `screen` no window of its group is in, in order.
    private func freeZones(of template: Int, on screen: NSScreen) -> [(zone: Int, frame: CGRect)] {
        let group = "\(Self.key(for: screen))-\(template)"
        let taken = Set(placements.values.filter { $0.group == group }.map(\.zone))
        let frames = frames(template: template, on: screen)
        return frames.indices.filter { !taken.contains($0) }.map { (zone: $0, frame: frames[$0]) }
    }

    /// Snap Assist goes away, and one still waiting for its windows never shows.
    private func closeAssist() {
        assistRequest += 1
        assist.close()
    }

    /// The window picked in Snap Assist goes into `zone`. False when it can't be reached (its
    /// app stopped answering, or it closed meanwhile).
    private func assistPicked(_ window: ZoneWindow, zone: Int) -> Bool {
        guard let (screen, template, replacing) = assistContext,
              let frame = frames(template: template, on: screen)[safe: zone],
              let element = AccessibilityElement.getWindowElement(window.id) else { return false }
        // "Trocar app" is one pick: the window that was there leaves the group, where it is
        // (place() sees to that).
        if replacing { closeAssist() }
        // A window in the Dock or of a hidden app may only take its frame once it is back:
        // reveal() settles it then.
        let isAway = window.state == .minimized || window.state == .hidden
        let placement = Placement(display: Self.key(for: screen), template: template, zone: zone, frame: frame)
        place(element, id: window.id, frame: frame, placement: placement, batched: isAway)
        if isAway {
            rememberGroup(placement.group)
            refreshDecor()
        }
        reveal(window, element: element, zone: zone, template: template, screen: screen)
        return true
    }

    /// A window picked in Snap Assist comes into view: out of the Dock, its app unhidden, in
    /// front of the others.
    private func reveal(_ window: ZoneWindow, element: AccessibilityElement, zone: Int, template: Int, screen: NSScreen) {
        let wasAway = window.state == .minimized || window.state == .hidden
        if let app = NSRunningApplication(processIdentifier: window.pid), app.isHidden { app.unhide() }
        if window.state == .minimized || element.isMinimized == true {
            SwitcherWindowActivator.setWindowMinimized(false, windowID: window.id, pid: window.ownerPID)
        }
        element.raise()
        guard wasAway else { return }
        let group = "\(Self.key(for: screen))-\(template)"
        // Once it is back: the frame again when it didn't take (some apps only do then), in
        // front, and at last what it really took.
        for (attempt, delay) in [0.35, 0.8].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let now = self.placements[window.id], now.group == group, now.zone == zone,
                          let frame = self.frames(template: template, on: screen)[safe: zone] else { return }
                    let current = element.frame
                    if !current.isNull, !self.isClose(current, frame) { element.setFrame(frame) }
                    let taken = element.frame
                    self.placements[window.id]?.frame = taken.isNull ? frame : taken
                    element.raise()
                    if attempt == 1 { self.settle(group, elements: [window.id: element]) }
                }
            }
        }
    }

    /// "Trocar app": each window of the group can be replaced; the pick takes its zone. The
    /// only way a window from outside comes into a group.
    private func startReplace(_ group: String) {
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        assistRequest += 1
        let request = assistRequest
        windows(for: screen, maxAge: 1) { [weak self] windows in
            guard let self, request == self.assistRequest, self.session == nil, Self.isEnabled else { return }
            let members = self.placements.filter { $0.value.group == group }
            let frames = self.frames(template: member.template, on: screen)
            let zones = members.values.map(\.zone).sorted().compactMap { zone in frames[safe: zone].map { (zone: zone, frame: $0) } }
            var captions: [Int: String] = [:]
            for placement in members.values {
                let name = NSRunningApplication(processIdentifier: placement.pid)?.localizedName ?? ""
                captions[placement.zone] = L("In place of \(name)")
            }
            let candidates = windows.filter { members[$0.id] == nil }
            guard !zones.isEmpty, !candidates.isEmpty else {
                NSSound.beep()
                return
            }
            self.assistContext = (screen, member.template, true)
            Self.logOffer(candidates, zones: zones.count)
            self.assist.show(on: screen, zones: zones, windows: candidates, captions: captions)
        }
    }

    /// How many windows were offered and where they were (no titles: they are the user's).
    private static func logOffer(_ windows: [ZoneWindow], zones: Int) {
        let here = windows.filter { $0.state == .here }.count
        let minimized = windows.filter { $0.state == .minimized }.count
        let hidden = windows.filter { $0.state == .hidden }.count
        log.notice("assist: \(zones) zones, \(windows.count) windows (\(here) here, \(windows.count - here - minimized - hidden) on other displays, \(minimized) minimized, \(hidden) hidden)")
    }

    // MARK: - Groups

    /// `batched` when several windows are placed in a row: the caller settles and remembers
    /// the group once, at the end (`finishPlacing`).
    private func place(_ element: AccessibilityElement, id: CGWindowID, frame: CGRect, placement: Placement,
                       batched: Bool = false) {
        // One window per zone: the one that was there leaves the group, where it is.
        for (other, spot) in placements where other != id && spot.group == placement.group && spot.zone == placement.zone {
            placements.removeValue(forKey: other)
            ownSizes.removeValue(forKey: other)
        }
        let current = element.frame
        if placements[id] == nil, ownSizes[id] == nil, !current.isNull { ownSizes[id] = current.size }
        element.setFrame(frame)
        var placement = placement
        let taken = element.frame
        placement.frame = taken.isNull ? frame : taken
        placement.pid = element.pid ?? 0
        placements[id] = placement
        // Not Rectangle's snap history: it would give the size back as soon as the drag starts.
        WindowManagementModule.windowHistory.lastRectangleActions.removeValue(forKey: id)
        startTimer()
        if !batched { finishPlacing(placement.group, elements: [id: element]) }
    }

    /// After one window or a row of them went into `group`: what they took, the group as the
    /// display's last one, the outlines.
    private func finishPlacing(_ group: String, elements: [CGWindowID: AccessibilityElement] = [:]) {
        settle(group, elements: elements)
        rememberGroup(group)
        refreshDecor()
    }

    /// What the windows of `group` actually took. One that keeps a bigger size than its zone
    /// (its app's minimum) gets the room it needs: the lines it touches move and the others
    /// follow, so no window ends under a neighbour. It is looked at twice: an app may take a
    /// size a beat after answering, and only what it still keeps a moment later (`confirming`)
    /// is its minimum. `known`: elements already at hand.
    private func settle(_ group: String, elements known: [CGWindowID: AccessibilityElement] = [:], confirming: Bool = false) {
        if confirming, gripDrag != nil || session != nil || NSEvent.pressedMouseButtons & 1 == 1 { return }
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        let members = placements.filter { $0.value.group == group }
        var elements = known.filter { members[$0.key] != nil }
        let missing = members.keys.filter { elements[$0] == nil }
        if !missing.isEmpty { elements.merge(Self.elements(for: missing)) { known, _ in known } }
        let usable = screen.adjustedVisibleFrame().screenFlipped
        let root = self.root(member.template, display: member.display)
        let zones = ZoneGeometry.frames(root, in: usable, gap: gap)
        var taken: [CGWindowID: CGRect] = [:]
        var minimums: [Int: CGSize] = [:]
        for (id, placement) in members {
            guard let frame = elements[id]?.frame, !frame.isNull else { continue }
            taken[id] = frame
            if let zone = zones[safe: placement.zone], frame.width > zone.width + 1.5 || frame.height > zone.height + 1.5 {
                minimums[placement.zone] = frame.size
            }
        }
        for (id, frame) in taken { placements[id]?.frame = frame }
        guard !minimums.isEmpty else { return }
        guard confirming else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.settle(group, elements: elements, confirming: true) }
            }
            return
        }
        let fitted = ZoneGeometry.makingRoom(for: minimums, root: root, in: usable, gap: gap)
        guard fitted != root else { return }
        roots[group] = fitted
        let frames = ZoneGeometry.frames(fitted, in: usable, gap: gap)
        for (id, placement) in members {
            guard let frame = frames[safe: placement.zone], let element = elements[id] else { continue }
            if taken[id] != frame { element.setFrame(frame) }
            let now = element.frame
            placements[id]?.frame = now.isNull ? frame : now
        }
        log.notice("room made for \(minimums.count) window(s) that would not shrink")
        rememberGroup(group)
        hideDecor()
        refreshDecor()
    }

    /// Let go outside a zone: out of the group, with its own size back where it was dropped.
    private func release(_ id: CGWindowID, element: AccessibilityElement) {
        let placement = placements.removeValue(forKey: id)
        let frame = element.frame
        if let size = ownSizes.removeValue(forKey: id), let placement, !frame.isNull,
           abs(frame.width - placement.frame.width) <= 6, abs(frame.height - placement.frame.height) <= 6 {
            element.setFrame(CGRect(origin: frame.origin, size: size), adjustSizeFirst: false)
        }
        refreshDecor()
    }

    private func leaveGroup(_ id: CGWindowID) {
        guard placements.removeValue(forKey: id) != nil else { return }
        ownSizes.removeValue(forKey: id)
        refreshDecor()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDecor() }
        }
    }

    /// The outlines and grips go away (unless a grip is being dragged).
    private func hideDecor() {
        guard !decor.isDraggingGrip else { return }
        decorGroup = nil
        decor.hide()
    }

    /// Something may have put another window in use (a click, another app in front): the
    /// outlines follow now, and once more when the apps have settled.
    private func focusMayHaveChanged() {
        guard !placements.isEmpty, gripDrag == nil else { return }
        // An app with no window in a group came forward (one that just opened, say): the grips
        // must not float over it, not even for the moment the check below takes.
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           !placements.values.contains(where: { $0.pid == front }) {
            hideDecor()
        }
        for delay in [0.04, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.refreshDecor() }
            }
        }
    }

    /// Keeps the groups honest (closed, moved away) and draws the one in use.
    private func refreshDecor() {
        guard gripDrag == nil else { return }
        guard Self.isEnabled, !placements.isEmpty else {
            hideDecor()
            timer?.invalidate()
            timer = nil
            return
        }
        if session != nil || assist.isShown {
            hideDecor()
            return
        }
        // Mouse held: a click, a selection, maybe a drag. Leave the grips as they are (a drag or
        // a resize of a group window hides them itself, see `handleDragMoved` / `resizeMoved`);
        // hiding on every press made them blink at each click inside the windows.
        if NSEvent.pressedMouseButtons & 1 == 1 { return }
        let ids = Array(placements.keys)
        let infos = Dictionary(WindowUtil.getWindowList(ids: ids, forceRefresh: true).map { ($0.id, $0) },
                               uniquingKeysWith: { a, _ in a })
        let visible = Set(WindowUtil.getWindowList(forceRefresh: true).map(\.id))
        for (id, placement) in placements {
            guard let info = infos[id] else {
                // Closed (it would still be listed if only minimized or on another Space).
                if WindowUtil.getWindowList(ids: [id], all: true, forceRefresh: true).isEmpty {
                    placements.removeValue(forKey: id)
                    ownSizes.removeValue(forKey: id)
                }
                continue
            }
            // Moved or resized by something else: no longer in its zone.
            if Date().timeIntervalSince(placement.at) > 1, !isClose(info.frame, placement.frame), visible.contains(id) {
                placements.removeValue(forKey: id)
                ownSizes.removeValue(forKey: id)
            }
        }
        // The group of the window in use, when it has company on screen. The app in front has
        // no window in a group: away at once. It has, but which window is in use is still being
        // asked (the answer comes from the background): keep what shows, no blink.
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              placements.values.contains(where: { $0.pid == front }) else {
            hideDecor()
            return
        }
        let inUse = focusedGroupWindow()
        // No answer for this app yet (it just came forward): the one on its way decides.
        if inUse == nil, focused?.pid != front { return }
        guard let inUse, let group = placements[inUse]?.group else {
            hideDecor()
            return
        }
        let members = placements.filter { $0.value.group == group && visible.contains($0.key) }
        guard members.count >= 2, let first = members.first?.value,
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == first.display }) else {
            hideDecor()
            return
        }
        decorGroup = group
        decor.show(grips: grips(root: root(first.template, display: first.display), zones: Set(members.values.map(\.zone)), on: screen))
    }

    /// What shows a group is held together: a grip in the middle of every edge two of its
    /// windows share (`zones`: the ones that hold a window). No line along the edge: it was
    /// loud, and it blinked with every click.
    private func grips(root: ZoneNode, zones: Set<Int>, on screen: NSScreen) -> [ZoneGroupDecor.Grip] {
        ZoneGeometry.seams(root, in: layoutArea(screen), occupied: zones).map {
            ZoneGroupDecor.Grip(divider: $0.divider, center: $0.center)
        }
    }

    // MARK: - Grips

    /// The grip under the pointer was pressed: the group showing is held, and its windows'
    /// elements are found once for the whole drag.
    private func gripBegan() {
        if let unfinished = gripDrag { finishGrip(unfinished) }
        guard let group = decorGroup, let member = placements.values.first(where: { $0.group == group }) else { return }
        let members = placements.filter { $0.value.group == group }
        let elements = Self.elements(for: Array(members.keys))
        gripAsked = nil
        gripDrag = GripDrag(group: group, root: root(member.template, display: member.display), elements: elements,
                            restore: elements.values.map { $0.beginFrameAdjustments() })
        writer.begin(frames: members.mapValues(\.frame))
    }

    /// The grip follows the pointer at once; the windows are written to in the background
    /// (ZoneFrameWriter), each as fast as its app takes it.
    private func gripMoved(_ divider: ZoneDivider, to position: CGFloat) {
        guard gripDrag != nil else { return }
        gripAsked = (divider, position)
        guard let (frames, line) = layGrip(divider, at: position), let drag = gripDrag else { return }
        var targets: [CGWindowID: ZoneFrameWriter.Target] = [:]
        for (id, frame) in frames {
            if let element = drag.elements[id] { targets[id] = ZoneFrameWriter.Target(element: element, frame: frame) }
        }
        writer.write(targets)
        if let line {
            let pointer = NSEvent.mouseLocation.screenFlipped
            decor.moveGrip(divider, to: divider.axis == .columns ? CGPoint(x: line, y: pointer.y) : CGPoint(x: pointer.x, y: line))
        }
    }

    /// The group's layout with `divider` as near `position` as its windows' known minimum
    /// sizes allow: each window's frame, and where the line ended up.
    private func layGrip(_ divider: ZoneDivider, at position: CGFloat) -> (frames: [CGWindowID: CGRect], line: CGFloat?)? {
        guard let drag = gripDrag,
              let member = placements.values.first(where: { $0.group == drag.group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return nil }
        let usable = screen.adjustedVisibleFrame().screenFlipped
        let area = layoutArea(screen)
        let held = ZoneGeometry.clamping(divider, to: position, root: drag.root, in: usable, gap: gap, minimums: drag.minimums)
        let moved = ZoneGeometry.moving(divider, to: held, root: drag.root, in: area)
        roots[drag.group] = moved
        let zones = ZoneGeometry.frames(moved, in: usable, gap: gap)
        var frames: [CGWindowID: CGRect] = [:]
        for (id, placement) in placements where placement.group == drag.group {
            guard let frame = zones[safe: placement.zone] else { continue }
            placements[id]?.frame = frame
            frames[id] = frame
        }
        let line = ZoneGeometry.dividers(moved, in: area).first { $0.path == divider.path && $0.index == divider.index }
        return (frames, line?.position)
    }

    /// How much bigger than asked a window must stay for it to count as refusing to shrink.
    private static let refusalMargin: CGFloat = 24

    /// A window would not get as small as asked (ZoneFrameWriter): the line goes back to
    /// where that window lets it be, and stops there for the rest of the drag.
    private func learnMinimum(of id: CGWindowID, asked: CGSize, kept: CGSize) {
        guard var drag = gripDrag, let placement = placements[id], placement.group == drag.group else { return }
        // A clear refusal only: a window that sizes in steps (a terminal's rows and columns)
        // keeps a little more or less than asked without being at its minimum.
        var minimum = drag.minimums[placement.zone] ?? .zero
        if kept.width > asked.width + Self.refusalMargin { minimum.width = max(minimum.width, kept.width) }
        if kept.height > asked.height + Self.refusalMargin { minimum.height = max(minimum.height, kept.height) }
        guard minimum != drag.minimums[placement.zone] else { return }
        drag.minimums[placement.zone] = minimum
        gripDrag = drag
        if let asked = gripAsked { gripMoved(asked.divider, to: asked.position) }
    }

    /// The grip was let go: once the last frames are written, the drag is settled.
    private func gripEnded(_ divider: ZoneDivider) {
        guard let drag = gripDrag else { return }
        writer.flush { [weak self] in
            MainActor.assumeIsolated { self?.finishGrip(drag) }
        }
    }

    /// Reads back what the apps accepted (settle: a window still bigger than its zone pulls
    /// its line back), and lets the group go.
    private func finishGrip(_ drag: GripDrag) {
        guard let current = gripDrag, current.group == drag.group else { return }
        endGrip()
        // The outlines stay where the drag left them: no blink at the end of it.
        finishPlacing(drag.group, elements: current.elements)
    }

    /// The drag (or the press that turned out to be a click) is over: the group is let go and
    /// its apps get their enhanced UI back. Returns the group it was.
    @discardableResult
    private func endGrip() -> String? {
        guard let drag = gripDrag else { return nil }
        gripDrag = nil
        gripAsked = nil
        drag.restore.forEach { $0() }
        return drag.group
    }

    /// The Accessibility elements of `ids`, asking each app for its windows once.
    private static func elements(for ids: [CGWindowID]) -> [CGWindowID: AccessibilityElement] {
        var wanted: [pid_t: Set<CGWindowID>] = [:]
        for info in WindowUtil.getWindowList(ids: ids, forceRefresh: true) { wanted[info.pid, default: []].insert(info.id) }
        var elements: [CGWindowID: AccessibilityElement] = [:]
        for (pid, ids) in wanted {
            let app = AccessibilityElement(pid)
            app.setMessagingTimeout(0.35)
            for element in app.windowElements ?? [] {
                if let id = element.windowId, ids.contains(id) { elements[id] = element }
            }
        }
        return elements
    }

    // MARK: - The grip's menu

    private func gripClicked(_ divider: ZoneDivider, at center: CGPoint, in view: NSView) {
        guard let group = endGrip() else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ZoneMenuItem(L("Swap App…"), symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.startReplace(group) })
        menu.addItem(ZoneMenuItem(L("Swap Sides"), symbol: divider.axis == .columns ? "arrow.left.arrow.right" : "arrow.up.arrow.down") { [weak self] in
            self?.swapSides(divider, group: group)
        })
        menu.addItem(ZoneMenuItem(L("Change Layout…"), symbol: "rectangle.split.3x1") { [weak self] in self?.openRelayout(group) })
        menu.addItem(ZoneMenuItem(L("Share the Room Equally"), symbol: "equal.square") { [weak self] in self?.evenSides(divider, group: group) })
        menu.addItem(.separator())
        menu.addItem(ZoneMenuItem(L("Unlink"), symbol: "xmark.circle") { [weak self] in self?.unlink(group, at: center) })
        menu.addItem(ZoneMenuItem(L("Cancel")) {})
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX + 4, y: view.bounds.midY), in: view)
        refreshDecor()
    }

    /// "Inverter lados": the windows on each side of the line trade places, with their room.
    private func swapSides(_ divider: ZoneDivider, group: String) {
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        let (swapped, moved) = ZoneGeometry.swappingSides(divider, root: root(member.template, display: member.display))
        roots[group] = swapped
        let frames = ZoneGeometry.frames(swapped, in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
        let members = placements.filter { $0.value.group == group }
        let elements = Self.elements(for: Array(members.keys))
        // All of them out first (keeping their own sizes), so none pushes another out of the
        // zone it is about to leave.
        for id in members.keys { placements.removeValue(forKey: id) }
        for (id, placement) in members {
            guard let zone = moved[safe: placement.zone], let frame = frames[safe: zone], let element = elements[id] else {
                ownSizes.removeValue(forKey: id)
                continue
            }
            place(element, id: id, frame: frame,
                  placement: Placement(display: placement.display, template: placement.template, zone: zone, frame: frame),
                  batched: true)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        hideDecor()
        finishPlacing(group, elements: elements)
    }

    /// "Alterar divisórias": the panel to choose another layout for the group; Esc keeps it.
    private func openRelayout(_ group: String) {
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        openPopup(on: screen, relayout: group)
        setHover(.zone(template: member.template, zone: 0))
    }

    /// The group's windows go into `template`'s zones, in the order they had. Windows beyond its
    /// zones leave the group; empty zones get Snap Assist.
    private func applyLayout(_ template: Int, to group: String, on screen: NSScreen) {
        let members = placements.filter { $0.value.group == group }.sorted { $0.value.zone < $1.value.zone }
        guard !members.isEmpty else { return }
        let display = Self.key(for: screen)
        let frames = frames(template: template, on: screen)
        let elements = Self.elements(for: members.map(\.key))
        for (id, _) in members { placements.removeValue(forKey: id) }
        var placed = 0
        for (index, member) in members.enumerated() {
            // Beyond the new layout's zones, or gone: out of the group.
            guard let frame = frames[safe: index], let element = elements[member.key] else {
                ownSizes.removeValue(forKey: member.key)
                continue
            }
            place(element, id: member.key, frame: frame,
                  placement: Placement(display: display, template: template, zone: index, frame: frame), batched: true)
            placed += 1
        }
        log.notice("group moved to layout \(template + 1)")
        finishPlacing("\(display)-\(template)", elements: elements)
        if frames.count > members.count, placed > 0 { startAssist(template: template, screen: screen) }
    }

    // MARK: - Unlinking and joining again

    /// "Desvincular": the windows stop going together and stay where they are; the group is
    /// forgotten (no "Último grupo" card), with a few seconds to join it again.
    private func unlink(_ group: String, at center: CGPoint) {
        guard let display = placements.values.first(where: { $0.group == group })?.display else { return }
        rememberGroup(group)
        let saved = lastGroups[display]
        lastGroups[display] = nil
        for (id, placement) in placements where placement.group == group {
            placements.removeValue(forKey: id)
        }
        hideDecor()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        log.notice("group unlinked")
        decor.showRelink(at: center) { [weak self] in
            guard let self, let saved, let screen = NSScreen.screens.first(where: { Self.key(for: $0) == display }) else { return }
            self.relink(saved, on: screen)
        }
    }

    /// Puts the last group of `screen` back (the "Último grupo" card).
    private func relink(on screen: NSScreen) {
        guard let saved = lastGroups[Self.key(for: screen)] else { return }
        relink(saved, on: screen)
    }

    /// Every window of `saved` still open goes back to its zone, with the proportions it had.
    private func relink(_ saved: SavedGroup, on screen: NSScreen) {
        let display = Self.key(for: screen)
        let group = "\(display)-\(saved.template)"
        roots[group] = saved.root
        let frames = frames(template: saved.template, on: screen)
        let elements = Self.elements(for: Array(saved.zones.keys))
        var placed: [AccessibilityElement] = []
        for (id, zone) in saved.zones.sorted(by: { $0.value < $1.value }) {
            guard let frame = frames[safe: zone], let element = elements[id] else { continue }
            place(element, id: id, frame: frame,
                  placement: Placement(display: display, template: saved.template, zone: zone, frame: frame), batched: true)
            placed.append(element)
        }
        finishPlacing(group, elements: elements)
        // All of them in front, the one in use on top.
        let focused = AccessibilityElement.getFocusedWindowElement()
        for element in placed where element != focused { element.raise() }
        focused?.raise()
        decor.hideRelink()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        log.notice("group joined again (\(placed.count) windows)")
    }

    /// Keeps a copy of `group` (two or more windows) as its display's last group.
    private func rememberGroup(_ group: String) {
        let members = placements.filter { $0.value.group == group }
        guard members.count >= 2, let first = members.first?.value else { return }
        var pids: [CGWindowID: pid_t] = [:]
        for info in WindowUtil.getWindowList(ids: Array(members.keys), all: true, forceRefresh: false) {
            pids[info.id] = info.pid
        }
        lastGroups[first.display] = SavedGroup(template: first.template,
                                               root: root(first.template, display: first.display),
                                               zones: members.mapValues(\.zone), pids: pids)
    }

    /// "Dividir igualmente": the two sides of the line get the same room.
    private func evenSides(_ divider: ZoneDivider, group: String) {
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        let evened = ZoneGeometry.evening(divider, root: root(member.template, display: member.display))
        roots[group] = evened
        let frames = ZoneGeometry.frames(evened, in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
        let members = placements.filter { $0.value.group == group }
        let elements = Self.elements(for: Array(members.keys))
        for (id, placement) in members {
            guard let frame = frames[safe: placement.zone], let element = elements[id] else { continue }
            element.setFrame(frame)
            placements[id]?.frame = frame
        }
        hideDecor()
        finishPlacing(group, elements: elements)
    }

    // MARK: - Resizing a window of a group by its edge

    private func handleResizeEnded(element: AccessibilityElement?, id: CGWindowID?) {
        guard Self.isEnabled, let element, let id, let placement = placements[id],
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == placement.display }) else { return }
        let now = element.frame
        guard !now.isNull,
              abs(now.width - placement.frame.width) > 6 || abs(now.height - placement.frame.height) > 6 else { return }
        let root = self.root(placement.template, display: placement.display)
        let resized = ZoneGeometry.resizing(from: placement.frame, to: now, root: root,
                                            in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
        guard resized != root else {
            placements[id]?.frame = now
            return
        }
        roots[placement.group] = resized
        // The other members follow the new lines; one moved away meanwhile is left alone.
        let frames = frames(template: placement.template, on: screen)
        let members = placements.filter { $0.value.group == placement.group }
        var elements = Self.elements(for: members.keys.filter { $0 != id })
        elements[id] = element
        for (other, spot) in members {
            guard let frame = frames[safe: spot.zone], let target = elements[other] else {
                placements.removeValue(forKey: other)
                continue
            }
            if other != id, !isClose(target.frame, spot.frame) {
                placements.removeValue(forKey: other)
                elements.removeValue(forKey: other)
                continue
            }
            target.setFrame(frame)
            placements[other]?.frame = frame
        }
        // A neighbour that can't get that small pushes the line back (settle).
        finishPlacing(placement.group, elements: elements)
    }

    /// The window in use, when its app has a window in a group (otherwise nobody is asked):
    /// the last answer, asked again in the background, so an app that is slow to answer never
    /// holds the main thread. A new answer draws the outlines again.
    private func focusedGroupWindow() -> CGWindowID? {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              placements.values.contains(where: { $0.pid == front }) else {
            focused = nil
            return nil
        }
        if !focusQueryRunning {
            focusQueryRunning = true
            Self.focusQueue.async {
                let window = Self.focusedWindow(of: front)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let zones = ZoneController.shared
                        zones.focusQueryRunning = false
                        let changed = zones.focused?.pid != front || zones.focused?.window != window
                        zones.focused = (front, window)
                        if changed { zones.refreshDecor() }
                    }
                }
            }
        }
        return focused?.pid == front ? focused?.window : nil
    }

    private nonisolated static func focusedWindow(of pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AccessibilityElement(value as! AXUIElement).windowId
    }

    // MARK: - Geometry

    private var gap: CGFloat { CGFloat(max(0, Defaults.gapSize.value)) }

    /// The rect the layout's lines are laid in (the usable area less half a gap).
    private func layoutArea(_ screen: NSScreen) -> CGRect {
        screen.adjustedVisibleFrame().screenFlipped.insetBy(dx: gap / 2, dy: gap / 2)
    }

    private func root(_ template: Int, display: String) -> ZoneNode {
        roots["\(display)-\(template)"] ?? ZoneTemplate(rawValue: template)?.root ?? .zone
    }

    private func frames(template: Int, on screen: NSScreen) -> [CGRect] {
        ZoneGeometry.frames(root(template, display: Self.key(for: screen)),
                            in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
    }

    private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 6 && abs(a.minY - b.minY) <= 6 && abs(a.width - b.width) <= 6 && abs(a.height - b.height) <= 6
    }

    /// A display's stable id (its UUID), its name as a fallback.
    static func key(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) as String? {
            return text
        }
        return screen.localizedName
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// A menu item that runs a closure (the grip's menu).
private final class ZoneMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
