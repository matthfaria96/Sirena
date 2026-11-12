/// ZoneController.swift
///
/// Snap layouts, as close to Windows 11 as macOS allows. Nothing is fixed: a window dragged
/// as usual stays where it's let go.
/// - Drag a window up to the top of a display (middle part): a panel drops with layouts.
///   Let go over one of their zones and the window goes there; Esc or moving away closes it.
/// - Snap Assist: the other zones of that layout light up with the open windows; a click
///   puts one in, Esc or a click elsewhere stops.
/// - The windows put by one layout on a display form a group. While one of them is in use
///   they get an accent outline, and each line two of them share gets a grip that resizes
///   both. Resizing one of them by its own edge moves the line too.
/// - A window of a group let go outside a zone leaves it and gets its own size back.
/// - A click on a grip lets the whole group go (windows stay where they are); "Join again"
///   stays a few seconds, and the panel keeps a "Last group" card per display that puts
///   them all back. A double click on a grip evens its two sides.
///
/// - ⌃⌥0 (ctrl + start + 0 on Logitech keyboards; Windows' Win+Z) opens the panel for the
///   window in front: arrows choose a zone, ↑ ↓ another layout, Return snaps it, Esc cancels.
///
/// The drag rides on Rectangle's tracking (SnappingManager): while the panel is open
/// Rectangle's snap areas stand aside; the top corners stay Rectangle's. No event tap of
/// its own; a light timer runs only while a group exists. Main thread only.

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

    /// The panel open on a display.
    private struct Session {
        let display: String
        let screen: NSScreen
        let geometry: ZonePopupGeometry
        /// Opened by the shortcut: the window it is for (nil while dragging).
        var target: (element: AccessibilityElement, id: CGWindowID)?
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
    /// A single click on a grip waits for a possible second one.
    private var pendingUnlink: DispatchWorkItem?
    private var placements: [CGWindowID: Placement] = [:]
    /// A window's own size before it went into a zone, given back when it leaves.
    private var ownSizes: [CGWindowID: CGSize] = [:]
    /// Each layout's proportions per display, as resized windows and grips left them.
    private var roots: [String: ZoneNode] = [:]

    /// The drag in progress: the lowest the pointer went (the panel opens once it rises).
    private var dragLowest: CGFloat?
    /// A grip being dragged: the group and its layout when it started.
    private var gripDrag: (group: String, root: ZoneNode, lastWrite: Date)?
    /// The last place a grip was dragged to, applied when it's let go.
    private var gripTarget: (divider: ZoneDivider, position: CGFloat)?
    private var timer: Timer?

    private var isStarted = false
    private var shortcutBound = false
    private var recordingToken: NSObjectProtocol?
    private var suspendedForRecording = false

    private init() {
        popup.onKey = { [weak self] code, flags in self?.keyboardKey(code, flags: flags) }
        popup.onPointer = { [weak self] point, clicked in self?.keyboardPointer(point, clicked: clicked) }
        popup.onResign = { [weak self] in
            guard self?.session?.target != nil else { return }
            self?.closePopup()
        }
        assist.onPick = { [weak self] id, zone in self?.assistPicked(id, zone: zone) }
        decor.onGripBegin = { [weak self] in self?.gripBegan() }
        decor.onGripDrag = { [weak self] divider, position in self?.gripMoved(divider, to: position) }
        decor.onGripEnd = { [weak self] divider in self?.gripEnded(divider) }
        decor.onGripClick = { [weak self] divider, count, center in self?.gripClicked(divider, count: count, at: center) }
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
        bindShortcut()
    }

    /// The switch in Janelas changed.
    func enabledChanged() {
        bindShortcut()
        if !Self.isEnabled {
            closePopup()
            hint.hide()
            assist.close()
            refreshDecor()
        }
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
        if session?.target != nil {
            closePopup()
            return
        }
        guard let element = AccessibilityElement.getFocusedWindowElement(), let id = element.windowId,
              element.pid != ProcessInfo.processInfo.processIdentifier, element.isStandardWindow,
              element.isFullScreen != true, element.isMinimized != true else {
            NSSound.beep()
            return
        }
        let frame = element.frame
        let center = frame.isNull ? NSEvent.mouseLocation.screenFlipped : frame.centerPoint
        let screen = NSScreen.screens.first { $0.frame.screenFlipped.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        assist.close()
        openPopup(on: screen, target: (element, id))
        // Starts on the first zone, so the keys have something to move from.
        if let first = keyboardRows().first?.first { setHover(first) }
    }

    // MARK: - The keyboard and the pointer (shortcut mode)

    /// The panel's choices, one row per drawing (the last group first, when shown).
    private func keyboardRows() -> [[ZonePopupGeometry.Hit]] {
        guard let geometry = session?.geometry else { return [] }
        var rows: [[ZonePopupGeometry.Hit]] = geometry.groupThumb == nil ? [] : [[.lastGroup]]
        for (template, zones) in geometry.zones.enumerated() {
            rows.append(zones.indices.map { .zone(template: template, zone: $0) })
        }
        return rows
    }

    private func keyboardKey(_ code: UInt16, flags: NSEvent.ModifierFlags) {
        guard session?.target != nil else { return }
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
        default:
            break
        }
    }

    private func keyboardPointer(_ point: CGPoint, clicked: Bool) {
        guard let session, session.target != nil else { return }
        let hit = session.geometry.hit(point)
        if let hit { setHover(hit) }
        if clicked, hit != nil { commitKeyboard() }
    }

    /// The window the shortcut was for goes to the chosen zone (or the last group comes back).
    private func commitKeyboard() {
        guard let session, let target = session.target, let hover else { return }
        closePopup()
        switch hover {
        case .lastGroup:
            relink(on: session.screen)
        case let .zone(template, zone):
            guard let frame = frames(template: template, on: session.screen)[safe: zone] else { return }
            place(target.element, id: target.id, frame: frame,
                  placement: Placement(display: session.display, template: template, zone: zone, frame: frame))
            log.notice("window into zone \(zone + 1) of layout \(template + 1) (keyboard)")
            startAssist(after: target.id, template: template, screen: session.screen)
        }
    }

    /// The zone (or card) lit in the panel, with its preview on the display.
    private func setHover(_ hit: ZonePopupGeometry.Hit?) {
        guard let session, hit != hover else { return }
        hover = hit
        popup.setHover(hit)
        if case let .zone(template, zone) = hit, let frame = frames(template: template, on: session.screen)[safe: zone] {
            preview.show(frame)
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
        decor.hide()
        // The panel opened by the shortcut gives way to a drag.
        if session?.target != nil { closePopup() }
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
        guard let session, session.target == nil else {
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
            startAssist(after: id, template: template, screen: session.screen)
        }
        return true
    }

    private func openPopup(on screen: NSScreen, target: (element: AccessibilityElement, id: CGWindowID)? = nil) {
        assist.close()
        let display = Self.key(for: screen)
        let roots = ZoneTemplate.allCases.map { root($0.rawValue, display: display) }
        // The last group is offered while at least two of its windows are still around.
        let saved = lastGroups[display].flatMap { group -> SavedGroup? in
            let alive = Set(WindowUtil.getWindowList(ids: Array(group.zones.keys), all: true, forceRefresh: true).map(\.id))
            return group.zones.keys.filter(alive.contains).count >= 2 ? group : nil
        }
        let geometry = ZonePopupGeometry(screen: screen, roots: roots, lastGroup: saved?.root)
        session = Session(display: display, screen: screen, geometry: geometry, target: target)
        hover = nil
        hint.hide()
        var icons: [Int: pid_t] = [:]
        for (id, zone) in saved?.zones ?? [:] { icons[zone] = saved?.pids[id] }
        popup.open(geometry, roots: roots, groupIcons: icons, keyboard: target != nil)
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

    private func startAssist(after placed: CGWindowID, template: Int, screen: NSScreen) {
        let display = Self.key(for: screen)
        let group = "\(display)-\(template)"
        let taken = Set(placements.values.filter { $0.group == group }.map(\.zone))
        let frames = frames(template: template, on: screen)
        let free = frames.indices.filter { !taken.contains($0) }.map { (zone: $0, frame: frames[$0]) }
        guard !free.isEmpty else { return }
        let members = Set(placements.filter { $0.value.group == group }.map(\.key))
        let candidates = openWindows().filter { !members.contains($0.id) && $0.id != placed }
        guard !candidates.isEmpty else { return }
        assistContext = (screen, template)
        assist.show(on: screen, zones: free, candidates: candidates)
    }

    private var assistContext: (screen: NSScreen, template: Int)?

    private func assistPicked(_ id: CGWindowID, zone: Int) {
        guard let (screen, template) = assistContext,
              let frame = frames(template: template, on: screen)[safe: zone],
              let element = AccessibilityElement.getWindowElement(id) else { return }
        place(element, id: id, frame: frame,
              placement: Placement(display: Self.key(for: screen), template: template, zone: zone, frame: frame))
        element.raise()
    }

    /// The standard windows on the current Space, front to back.
    private func openWindows() -> [ZoneAssist.Candidate] {
        let own = ProcessInfo.processInfo.processIdentifier
        let infos = WindowUtil.getWindowList(forceRefresh: true).filter {
            $0.level == 0 && $0.pid != own && $0.frame.width >= 80 && $0.frame.height >= 60
                && !["Dock", "WindowManager", "Window Server"].contains($0.processName ?? "")
        }
        var standard: [CGWindowID: AccessibilityElement] = [:]
        for pid in Set(infos.map(\.pid)) {
            let app = AccessibilityElement(pid)
            app.setMessagingTimeout(0.25)
            for element in app.windowElements ?? [] {
                guard let id = element.windowId, element.isStandardWindow, element.isMinimized != true else { continue }
                standard[id] = element
            }
        }
        return infos.compactMap { info in
            guard let element = standard[info.id] else { return nil }
            let appName = NSRunningApplication(processIdentifier: info.pid)?.localizedName ?? info.processName ?? ""
            return ZoneAssist.Candidate(id: info.id, pid: info.pid, title: element.title ?? "", appName: appName)
        }
    }

    // MARK: - Groups

    private func place(_ element: AccessibilityElement, id: CGWindowID, frame: CGRect, placement: Placement) {
        let current = element.frame
        if placements[id] == nil, ownSizes[id] == nil, !current.isNull { ownSizes[id] = current.size }
        element.setFrame(frame)
        var placement = placement
        placement.frame = element.frame.isNull ? frame : element.frame
        placement.pid = element.pid ?? 0
        placements[id] = placement
        rememberGroup(placement.group)
        // Not Rectangle's snap history: it would give the size back as soon as the drag starts.
        WindowManagementModule.windowHistory.lastRectangleActions.removeValue(forKey: id)
        startTimer()
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
        placements.removeValue(forKey: id)
        ownSizes.removeValue(forKey: id)
        refreshDecor()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDecor() }
        }
    }

    /// Keeps the groups honest (closed, moved away) and draws the one in use.
    private func refreshDecor() {
        guard gripDrag == nil else { return }
        guard Self.isEnabled, !placements.isEmpty else {
            decor.hide()
            timer?.invalidate()
            timer = nil
            return
        }
        // Mouse held: a drag or a resize is going on; decide when it's over.
        if NSEvent.pressedMouseButtons & 1 == 1 || session != nil || assist.isShown {
            decor.hide()
            return
        }
        let ids = Array(placements.keys)
        let infos = Dictionary(WindowUtil.getWindowList(ids: ids, forceRefresh: true).map { ($0.id, $0) },
                               uniquingKeysWith: { a, _ in a })
        for (id, placement) in placements {
            guard let info = infos[id] else {
                // Closed (it would still be listed if only minimized or on another Space).
                if WindowUtil.getWindowList(ids: [id], all: true, forceRefresh: true).isEmpty { leaveGroup(id) }
                continue
            }
            // Moved or resized by something else: no longer in its zone.
            if Date().timeIntervalSince(placement.at) > 1, !isClose(info.frame, placement.frame), WindowUtil.getWindowList(forceRefresh: false).contains(where: { $0.id == id }) {
                placements.removeValue(forKey: id)
                ownSizes.removeValue(forKey: id)
            }
        }
        // The group of the window in use, when it has company on screen. The app in front is
        // only asked which window that is when one of its windows is in a group.
        let visible = Set(WindowUtil.getWindowList(forceRefresh: false).map(\.id))
        guard let focused = focusedGroupWindow(), let group = placements[focused]?.group else {
            decor.hide()
            return
        }
        let members = placements.filter { $0.value.group == group && visible.contains($0.key) }
        guard members.count >= 2, let first = members.first?.value,
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == first.display }) else {
            decor.hide()
            return
        }
        decor.show(frames: members.mapValues(\.frame), grips: grips(for: first, members: Array(members.values), on: screen))
    }

    /// A grip on every line two members of the group share.
    private func grips(for placement: Placement, members: [Placement], on screen: NSScreen) -> [ZoneGroupDecor.Grip] {
        let area = layoutArea(screen)
        let root = self.root(placement.template, display: placement.display)
        let regions = ZoneGeometry.regions(root, in: area)
        let used = Set(members.map(\.zone))
        return ZoneGeometry.dividers(root, in: area).compactMap { divider in
            let line = divider.line
            func touches(_ region: CGRect, before: Bool) -> Bool {
                if divider.axis == .columns {
                    let edge = before ? region.maxX : region.minX
                    return abs(edge - line.minX) <= 1 && region.minY < line.maxY && region.maxY > line.minY
                }
                let edge = before ? region.maxY : region.minY
                return abs(edge - line.minY) <= 1 && region.minX < line.maxX && region.maxX > line.minX
            }
            let before = regions.indices.filter { used.contains($0) && touches(regions[$0], before: true) }
            let after = regions.indices.filter { used.contains($0) && touches(regions[$0], before: false) }
            guard !before.isEmpty, !after.isEmpty else { return nil }
            // Centred on the part of the line the members share.
            let spans = (before + after).map { regions[$0] }
            let center: CGPoint
            if divider.axis == .columns {
                let low = max(line.minY, spans.map(\.minY).min() ?? line.minY)
                let high = min(line.maxY, spans.map(\.maxY).max() ?? line.maxY)
                center = CGPoint(x: line.minX, y: (low + high) / 2)
            } else {
                let low = max(line.minX, spans.map(\.minX).min() ?? line.minX)
                let high = min(line.maxX, spans.map(\.maxX).max() ?? line.maxX)
                center = CGPoint(x: (low + high) / 2, y: line.minY)
            }
            return ZoneGroupDecor.Grip(divider: divider, center: center)
        }
    }

    // MARK: - Grips

    /// The grip under the pointer was pressed: the group of the window in use is held.
    private func gripBegan() {
        guard let focused = focusedGroupWindow(), let member = placements[focused] else { return }
        gripDrag = (member.group, root(member.template, display: member.display), .distantPast)
    }

    private func gripMoved(_ divider: ZoneDivider, to position: CGFloat, force: Bool = false) {
        guard let drag = gripDrag,
              let member = placements.values.first(where: { $0.group == drag.group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        gripTarget = (divider, position)
        // About 30 writes a second: AX moves are not free.
        guard force || Date().timeIntervalSince(drag.lastWrite) > 1 / 30 else { return }
        gripDrag?.lastWrite = Date()
        let group = drag.group
        let area = layoutArea(screen)
        let moved = ZoneGeometry.moving(divider, to: position, root: drag.root, in: area)
        roots[group] = moved
        let frames = ZoneGeometry.frames(moved, in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
        var outlines: [CGWindowID: CGRect] = [:]
        for (id, placement) in placements where placement.group == group {
            guard let frame = frames[safe: placement.zone], let element = AccessibilityElement.getWindowElement(id) else { continue }
            element.setFrame(frame)
            placements[id]?.frame = frame
            outlines[id] = frame
        }
        let line = ZoneGeometry.dividers(moved, in: area).first { $0.path == divider.path && $0.index == divider.index }
        if let line {
            let center = divider.axis == .columns
                ? CGPoint(x: line.line.minX, y: NSEvent.mouseLocation.screenFlipped.y)
                : CGPoint(x: NSEvent.mouseLocation.screenFlipped.x, y: line.line.minY)
            decor.moveGrip(divider, to: center)
        }
        decor.show(frames: outlines, grips: [])
    }

    private func gripEnded(_ divider: ZoneDivider) {
        if let target = gripTarget { gripMoved(target.divider, to: target.position, force: true) }
        gripTarget = nil
        guard let drag = gripDrag else { return }
        gripDrag = nil
        // Read back what the apps accepted.
        for (id, placement) in placements where placement.group == drag.group {
            if let frame = AccessibilityElement.getWindowElement(id)?.frame, !frame.isNull {
                placements[id]?.frame = frame
            }
        }
        _ = divider
        rememberGroup(drag.group)
        decor.hide()
        refreshDecor()
    }

    // MARK: - Letting a group go and joining it again

    private func gripClicked(_ divider: ZoneDivider, count: Int, at center: CGPoint) {
        let group = gripDrag?.group
        gripDrag = nil
        gripTarget = nil
        pendingUnlink?.cancel()
        guard let group else { return }
        if count >= 2 {
            evenSides(divider, group: group)
            return
        }
        // Wait to see whether a second click makes it a double click.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.unlink(group, at: center) }
        }
        pendingUnlink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    /// The windows of `group` stop going together; they stay where they are.
    private func unlink(_ group: String, at center: CGPoint) {
        guard let display = placements.values.first(where: { $0.group == group })?.display else { return }
        rememberGroup(group)
        for (id, placement) in placements where placement.group == group {
            placements.removeValue(forKey: id)
        }
        decor.hide()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        log.notice("group let go")
        decor.showRelink(at: center) { [weak self] in
            guard let self, let screen = NSScreen.screens.first(where: { Self.key(for: $0) == display }) else { return }
            self.relink(on: screen)
        }
    }

    /// Puts the last group of `screen` back: every window of it still open goes to its zone,
    /// with the proportions it had.
    private func relink(on screen: NSScreen) {
        let display = Self.key(for: screen)
        guard let saved = lastGroups[display] else { return }
        let group = "\(display)-\(saved.template)"
        roots[group] = saved.root
        let frames = frames(template: saved.template, on: screen)
        var placed: [AccessibilityElement] = []
        for (id, zone) in saved.zones.sorted(by: { $0.value < $1.value }) {
            guard let frame = frames[safe: zone], let element = AccessibilityElement.getWindowElement(id) else { continue }
            place(element, id: id, frame: frame,
                  placement: Placement(display: display, template: saved.template, zone: zone, frame: frame))
            placed.append(element)
        }
        // All of them in front, the one in use on top.
        let focused = AccessibilityElement.getFocusedWindowElement()
        for element in placed where element != focused { element.raise() }
        focused?.raise()
        decor.hideRelink()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        log.notice("group joined again (\(placed.count) windows)")
        refreshDecor()
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

    /// A double click on a grip: its two sides get the same room.
    private func evenSides(_ divider: ZoneDivider, group: String) {
        guard let member = placements.values.first(where: { $0.group == group }),
              let screen = NSScreen.screens.first(where: { Self.key(for: $0) == member.display }) else { return }
        let evened = ZoneGeometry.evening(divider, root: root(member.template, display: member.display))
        roots[group] = evened
        let frames = ZoneGeometry.frames(evened, in: screen.adjustedVisibleFrame().screenFlipped, gap: gap)
        for (id, placement) in placements where placement.group == group {
            guard let frame = frames[safe: placement.zone], let element = AccessibilityElement.getWindowElement(id) else { continue }
            element.setFrame(frame)
            placements[id]?.frame = element.frame.isNull ? frame : element.frame
        }
        rememberGroup(group)
        decor.hide()
        refreshDecor()
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
        for (other, spot) in placements where spot.group == placement.group {
            guard let frame = frames[safe: spot.zone],
                  let target = other == id ? element : AccessibilityElement.getWindowElement(other) else {
                placements.removeValue(forKey: other)
                continue
            }
            if other != id, !isClose(target.frame, spot.frame) {
                placements.removeValue(forKey: other)
                continue
            }
            target.setFrame(frame)
            placements[other]?.frame = target.frame.isNull ? frame : target.frame
        }
        rememberGroup(placement.group)
        refreshDecor()
    }

    /// The window in use, when its app has a window in a group (otherwise nobody is asked).
    private func focusedGroupWindow() -> CGWindowID? {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              placements.values.contains(where: { $0.pid == front }) else { return nil }
        let app = AXUIElementCreateApplication(front)
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
