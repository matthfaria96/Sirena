/// TweaksController.swift
///
/// Tweaks, modeled on Supercharge: small behavior changes for windows, the Dock and the
/// Finder. They all work the same way: an event tap sees the click or key press before
/// the Dock, the Finder or the window does, and swaps it for something more useful.
///
/// Every click and key press on the Mac passes through the tap, so it runs on a thread
/// of its own (never Sirena's main thread), filters by position and target before any
/// Accessibility call, and gives each Accessibility call its own short timeout.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Owns the tap's lifetime and the Accessibility trust checks.
@MainActor
final class TweaksController {
    static let shared = TweaksController()

    private(set) var isRunning = false
    private var engine: TweaksEngine?
    private var trustTimer: Timer?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        TweaksSettings.applyGreenButton(TweaksSettings.shared.greenButtonFills)
        applyFinderSwitch()
        startWhenTrusted()
    }

    /// Melhorias' switch, read on any thread.
    nonisolated static var finderTweaksOn: Bool {
        UserDefaults.standard.object(forKey: "sirena.module.tweaks.enabled") as? Bool ?? true
    }

    /// The engine always runs (the Dock tweaks don't depend on Melhorias); the Finder's
    /// extras follow Melhorias' switch right away.
    func applyFinderSwitch() {
        let on = Self.finderTweaksOn
        FinderCopyPathExtension.setEnabled(on && TweaksSettings.shared.finderCopyPath)
        if on { DMGInstaller.shared.start() } else { DMGInstaller.shared.stop() }
    }

    func terminate() {
        TweaksSettings.applyGreenButton(false)
        DMGInstaller.shared.stop()
        engine?.stop()
        engine = nil
        trustTimer?.invalidate()
        trustTimer = nil
        isRunning = false
    }

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        PinAX.requestTrust()
    }

    /// The tap needs Accessibility; until it's granted, check again every few seconds.
    private func startWhenTrusted() {
        guard isRunning, engine == nil else { return }
        guard hasAccessibility else {
            guard trustTimer == nil else { return }
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.hasAccessibility else { return }
                    self.trustTimer?.invalidate()
                    self.trustTimer = nil
                    self.startWhenTrusted()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
            return
        }
        let engine = TweaksEngine { [weak self] in
            // Accessibility was revoked while running: drop the tap and wait for it again.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.engine?.stop()
                    self.engine = nil
                    self.startWhenTrusted()
                }
            }
        }
        if engine.start() { self.engine = engine }
    }
}

// MARK: - Settings snapshot

/// The tweaks' settings, read straight from UserDefaults (safe on any thread).
private struct TweaksSnapshot {
    let greenButtonFills: Bool
    let dockActiveAppClick: DockActiveAppClick
    let dockUnminimizeAll: Bool
    let dockFoldersOpenInFinder: Bool
    let finderCutAndPaste: Bool
    let finderCutSound: Bool
    let finderDeleteMovesToTrash: Bool

    static var current: TweaksSnapshot {
        let defaults = UserDefaults.standard
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        // The Finder tweaks follow Melhorias' switch; the Dock ones live on Janela e Dock.
        let finder = TweaksController.finderTweaksOn
        return TweaksSnapshot(
            greenButtonFills: flag("tweaks.greenButtonFills"),
            dockActiveAppClick: DockActiveAppClick(rawValue: defaults.string(forKey: "tweaks.dockActiveAppClick") ?? "") ?? .minimizeWindows,
            dockUnminimizeAll: flag("tweaks.dockUnminimizeAll"),
            dockFoldersOpenInFinder: flag("tweaks.dockFoldersOpenInFinder"),
            finderCutAndPaste: finder && flag("tweaks.finderCutAndPaste"),
            finderCutSound: flag("tweaks.finderCutSound"),
            finderDeleteMovesToTrash: finder && flag("tweaks.finderDeleteMovesToTrash")
        )
    }

    var anyClickTweak: Bool {
        dockActiveAppClick != .nothing || dockUnminimizeAll || dockFoldersOpenInFinder
    }

    var anyKeyTweak: Bool { finderCutAndPaste || finderDeleteMovesToTrash }
}

// MARK: - Engine (runs on its own thread)

/// All state below is only touched on the tap thread (directly in the callback, or
/// through `later`, which schedules onto that thread's run loop).
final class TweaksEngine: @unchecked Sendable {
    private let onLostTrust: () -> Void
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?

    /// Marks events Sirena posts itself, so the tap lets them through untouched.
    private static let ownEventMarker: Int64 = 0x5349_5245 // "SIRE"
    private static let axTimeout: Float = 0.2
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    /// A click being held back: its action runs on mouse-up, unless the pointer moves or
    /// the button is held, in which case the original press is handed back (drag, menu).
    private struct PendingClick {
        let id = UUID()
        let down: CGEvent
        let location: CGPoint
        /// For buttons: releasing outside cancels, like a normal button.
        let releaseRect: CGRect?
        let action: () -> Void
    }

    private var pending: PendingClick?
    /// Runs shortly after the mouse-up of a click that went through.
    private var afterClickAction: (() -> Void)?
    /// Key codes whose key-up must get the same change as their key-down.
    private var rewrittenKeys: [Int64: (rewrite: (CGEvent) -> Void, date: Date)] = [:]
    /// Pasteboard change count of the last Finder "cut": pasting it moves the files.
    private var cutChangeCount: Int?

    init(onLostTrust: @escaping () -> Void) {
        self.onLostTrust = onLostTrust
    }

    /// Starts the tap thread; false if the tap couldn't be created.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        var created = false
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            created = self.installTap()
            self.runLoop = CFRunLoopGetCurrent()
            ready.signal()
            if created { CFRunLoopRun() }
        }
        thread.name = "Sirena.Tweaks.EventTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
        return created
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        if let runLoop { CFRunLoopStop(runLoop) }
        runLoop = nil
        thread = nil
    }

    private func installTap() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // The annotated session tap tells which process a key press is going to.
        guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: tweaksTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// Runs `block` on the tap thread after `delay` seconds.
    private func later(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        guard let runLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .commonModes)
    }

    private static func onMain(_ block: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    fileprivate func tapDisabled() {
        if AXIsProcessTrusted() {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else {
            onLostTrust()
        }
    }

    // MARK: Events

    /// Returns the event to deliver (possibly changed), or nil to swallow it.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker { return event }
        switch type {
        case .leftMouseDown: return mouseDown(event)
        case .leftMouseDragged: return mouseDragged(event)
        case .leftMouseUp: return mouseUp(event)
        case .keyDown: return keyDown(event)
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if let entry = rewrittenKeys.removeValue(forKey: code), Date().timeIntervalSince(entry.date) < 3 {
                entry.rewrite(event)
            }
            return event
        default:
            return event
        }
    }

    private func mouseDown(_ event: CGEvent) -> CGEvent? {
        pending = nil
        afterClickAction = nil
        let settings = TweaksSnapshot.current
        // Modified clicks keep their usual meaning (⌥-click on the green button zooms…).
        guard settings.anyClickTweak, event.flags.intersection(Self.modifierMask).isEmpty else { return event }

        let point = event.location
        // Cheapest first: a click away from the Dock's windows needs no window list.
        guard Self.mayBeOnDock(point) else { return event }
        // Then: which window is under the pointer?
        guard let window = Self.windowUnderPoint(point) else { return event }

        // (The green button is handled by the Windows feature, see TweaksSettings.)
        guard window.isDock else { return event }
        return dockClick(event, at: point, dockPID: window.pid, settings: settings)
    }

    private func mouseDragged(_ event: CGEvent) -> CGEvent? {
        guard let click = pending else { return event }
        guard hypot(event.location.x - click.location.x, event.location.y - click.location.y) > 4 else { return nil }
        // A drag, not a click: give the press back, then this drag.
        handBack(click)
        Self.post(event)
        return nil
    }

    private func mouseUp(_ event: CGEvent) -> CGEvent? {
        if let click = pending {
            pending = nil
            if let rect = click.releaseRect, !rect.contains(event.location) {
                return nil // released outside the button: cancelled, like a real button
            }
            click.action()
            return nil
        }
        if let action = afterClickAction {
            afterClickAction = nil
            later(0.35, action)
        }
        return event
    }

    /// Holds a click back, handing it back to the system if it turns into a hold.
    private func hold(_ event: CGEvent, releaseRect: CGRect? = nil, action: @escaping () -> Void) -> CGEvent? {
        guard let copy = event.copy() else { return event }
        let click = PendingClick(down: copy, location: event.location, releaseRect: releaseRect, action: action)
        pending = click
        later(0.45) { [weak self] in
            guard let self, let current = self.pending, current.id == click.id else { return }
            // Still pressed and not moved: a long press (e.g. the Dock's menu).
            self.handBack(current)
        }
        return nil
    }

    private func handBack(_ click: PendingClick) {
        pending = nil
        Self.post(click.down)
    }

    private static func post(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: ownEventMarker)
        copy.post(tap: .cgSessionEventTap)
    }

    // MARK: Window under the pointer

    private struct WindowHit {
        let pid: pid_t
        let layer: Int
        let frame: CGRect
        let isDock: Bool
    }

    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// The Dock's window frames, refreshed at most every 2 s (tap thread only).
    private static var dockFrames: [CGRect] = []
    private static var dockFramesDate = Date.distantPast

    private static func mayBeOnDock(_ point: CGPoint) -> Bool {
        if Date().timeIntervalSince(dockFramesDate) > 2 {
            let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            dockFrames = windows.compactMap { window in
                guard window[kCGWindowOwnerName as String] as? String == "Dock",
                      window[kCGWindowLayer as String] as? Int == dockLayer,
                      let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: bounds)
            }
            dockFramesDate = Date()
        }
        return dockFrames.contains { $0.contains(point) }
    }

    private static func windowUnderPoint(_ point: CGPoint) -> WindowHit? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point),
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String
            // Front-most window under the pointer decides; Sirena's own windows are left alone.
            guard pid != ownPID else { return nil }
            if owner == "Dock" && layer == Int(CGWindowLevelForKey(.dockWindow)) {
                return WindowHit(pid: pid, layer: layer, frame: frame, isDock: true)
            }
            guard layer == 0 else { return nil }
            return WindowHit(pid: pid, layer: layer, frame: frame, isDock: false)
        }
        return nil
    }

    // MARK: Dock

    private func dockClick(_ event: CGEvent, at point: CGPoint, dockPID: pid_t, settings: TweaksSnapshot) -> CGEvent? {
        let dock = Self.element(AXUIElementCreateApplication(dockPID))
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit) == .success, let item = hit.map(Self.element),
              Self.string(item, kAXRoleAttribute) == "AXDockItem", let url = Self.url(item) else { return event }
        let subrole = Self.string(item, kAXSubroleAttribute)

        if subrole == "AXFolderDockItem" {
            guard settings.dockFoldersOpenInFinder else { return event }
            return hold(event) { Self.onMain { NSWorkspace.shared.open(url) } }
        }

        guard subrole == "AXApplicationDockItem",
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
              }) else { return event }

        let windows = Self.standardWindows(of: app.processIdentifier)
        let minimized = windows.filter(PinAX.isMinimized)
        let visible = windows.count - minimized.count

        if app.isActive, visible > 0, !app.isHidden {
            switch settings.dockActiveAppClick {
            case .nothing:
                break
            case .minimizeWindows:
                return hold(event) {
                    for window in windows where !PinAX.isMinimized(window) { PinAX.minimize(window) }
                }
            case .hideApp:
                return hold(event) { Self.onMain { app.hide() } }
            }
        }

        // The Dock brings back one minimized window; bring back the rest after it.
        if settings.dockUnminimizeAll, visible == 0, minimized.count > 1 {
            afterClickAction = {
                for window in minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            }
        }
        return event
    }

    private static func standardWindows(of pid: pid_t) -> [AXUIElement] {
        let app = element(AXUIElementCreateApplication(pid))
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.map(element).filter { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
    }

    // MARK: Finder

    private func keyDown(_ event: CGEvent) -> CGEvent? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        rewrittenKeys[code] = nil
        let settings = TweaksSnapshot.current
        guard settings.anyKeyTweak else { return event }
        let modifiers = event.flags.intersection(Self.modifierMask)
        let isCut = Int(code) == kVK_ANSI_X && modifiers == [.maskCommand] && settings.finderCutAndPaste
        let isPaste = Int(code) == kVK_ANSI_V && modifiers == [.maskCommand] && settings.finderCutAndPaste
        let isDelete = Int(code) == kVK_Delete && modifiers.isEmpty && settings.finderDeleteMovesToTrash
            && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        guard isCut || isPaste || isDelete else { return event }

        // Only key presses going to the Finder itself (not Spotlight, Raycast, Sirena's
        // panels or any other floating window while the Finder is in front).
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(finder.processIdentifier),
              finder.isActive, !Self.isEditingText(in: finder) else { return event }

        if isCut {
            // The Finder can't cut files: copy them, and remember that the copy was a cut,
            // but only once the copy has really changed the clipboard.
            let rewrite: (CGEvent) -> Void = { $0.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_C)) }
            rewrite(event)
            rewrittenKeys[code] = (rewrite, Date())
            let before = NSPasteboard.general.changeCount
            cutChangeCount = nil
            watchForCut(after: before, attempts: 10, sound: settings.finderCutSound)
        } else if isPaste {
            guard let cut = cutChangeCount, cut == NSPasteboard.general.changeCount else { return event }
            // ⌥⌘V is the Finder's own "Move Item Here".
            cutChangeCount = nil
            let rewrite: (CGEvent) -> Void = { $0.flags.insert(.maskAlternate) }
            rewrite(event)
            rewrittenKeys[code] = (rewrite, Date())
        } else {
            let rewrite: (CGEvent) -> Void = { $0.flags.insert(.maskCommand) }
            rewrite(event)
            rewrittenKeys[code] = (rewrite, Date())
        }
        return event
    }

    private func watchForCut(after before: Int, attempts: Int, sound: Bool) {
        later(0.12) { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != before {
                guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
                self.cutChangeCount = pasteboard.changeCount
                if sound { Self.onMain { NSSound(named: "Pop")?.play() } }
            } else if attempts > 0 {
                self.watchForCut(after: before, attempts: attempts - 1, sound: sound)
            }
        }
    }

    /// Typing a file name or searching: keys must behave as usual. When the Finder
    /// doesn't answer, assume it is, and leave the key alone.
    private static func isEditingText(in app: NSRunningApplication) -> Bool {
        let element = element(AXUIElementCreateApplication(app.processIdentifier))
        guard let focused = child(element, kAXFocusedUIElementAttribute) else { return true }
        let role = string(focused, kAXRoleAttribute)
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role)
            || string(focused, kAXSubroleAttribute) == kAXSearchFieldSubrole
    }

    // MARK: Accessibility helpers (each element gets its own short timeout)

    private static func element(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        return element
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return Self.element(value as! AXUIElement)
    }

    private static func url(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success else { return nil }
        return value as? URL
    }
}

private func tweaksTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                               _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<TweaksEngine>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        engine.tapDisabled()
        return Unmanaged.passUnretained(event)
    }
    return engine.handle(type, event).map { Unmanaged.passUnretained($0) }
}
