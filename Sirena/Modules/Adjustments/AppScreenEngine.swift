/// AppScreenEngine.swift
///
/// Puts the new windows of an app on the display its rule names (Ajustes › Monitores), wherever
/// the pointer or the focus is. It listens to Accessibility's "window created" for the apps that
/// have a rule (an AXObserver per running app, nothing for the others) and moves each new
/// standard window once, then checks it again shortly after, since some apps put their windows
/// back where they last were.
///
/// No event tap. Every Accessibility call (observers, reading and writing frames) runs on the
/// engine's own thread: the main thread never waits for another app. The main thread only sends
/// snapshots (rules, displays, running apps) over.

import AppKit
import DockKit
import OSLog

/// The engine's view of a display, in global top-left coordinates (the ones AX uses).
struct ScreenSnapshot {
    let id: String
    let frame: CGRect
    let usable: CGRect
}

final class AppScreenEngine: @unchecked Sendable {
    static let shared = AppScreenEngine()

    fileprivate static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "AppScreens")
    /// "Only at launch" covers the windows that open within this time after the app starts.
    private static let launchWindow: TimeInterval = 8
    /// Checks after a move: an app that restores its own frame gets moved again.
    private static let rechecks: [TimeInterval] = [0.4, 1.2]

    // MARK: Main-thread side

    @MainActor private var started = false
    @MainActor private var workspaceObservers: [NSObjectProtocol] = []
    @MainActor private var screenObserver: NSObjectProtocol?
    @MainActor private var accessibilityObservation: AccessibilityGuard.Observation?

    // MARK: Engine-thread side (touched only on `thread`)

    private let thread = EngineThread()
    private var rules: [String: AppScreenRule] = [:]
    private var screens: [ScreenSnapshot] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var bundleIDs: [pid_t: String] = [:]
    private var launchTimes: [pid_t: Date] = [:]
    /// Windows already placed, per app (moved once; later moves are the user's).
    private var placed: [pid_t: Set<CGWindowID>] = [:]
    private var active = false

    // MARK: - Starting and stopping (main thread)

    @MainActor
    func start() {
        guard !started else { return }
        started = true
        thread.start()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let pid = app.processIdentifier
                self?.thread.perform { self?.appLaunched(pid: pid, bundleID: bundleID) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                self?.thread.perform { self?.appTerminated(pid: pid) }
            }
        ]
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        accessibilityObservation = AccessibilityGuard.shared.observe { [weak self] _ in self?.sync() }
        sync()
    }

    @MainActor
    func stop() {
        guard started else { return }
        started = false
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        accessibilityObservation?.invalidate()
        accessibilityObservation = nil
        thread.perform { [self] in configure(active: false, rules: [:], screens: [], apps: []) }
    }

    @MainActor
    func rulesChanged() {
        if started { sync() }
    }

    /// Moves the windows `bundleID` has open now to its display (the "Move now" button).
    @MainActor
    func moveOpenWindows(of bundleID: String) {
        guard let rule = AppScreenRules.shared.rules.first(where: { $0.bundleID == bundleID }) else { return }
        let screens = Self.screenSnapshots()
        let pids = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
        thread.perform { [self] in
            for pid in pids {
                for window in Self.windows(of: pid) {
                    place(window, rule: rule, screens: screens, force: true)
                }
            }
        }
    }

    /// Sends the current rules, displays and running apps to the engine thread.
    @MainActor
    private func sync() {
        let rules = Dictionary(AppScreenRules.shared.rules.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        let active = started && AccessibilityGuard.isTrusted && !rules.isEmpty
        let screens = Self.screenSnapshots()
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
            guard let id = app.bundleIdentifier, rules[id] != nil else { return nil }
            return (app.processIdentifier, id)
        }
        thread.perform { [self] in configure(active: active, rules: rules, screens: screens, apps: apps) }
    }

    @MainActor
    static func screenSnapshots() -> [ScreenSnapshot] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.map {
            ScreenSnapshot(id: ScreenIdentity.identifier(of: $0), frame: flipped($0.frame), usable: flipped($0.visibleFrame))
        }
    }

    // MARK: - Engine thread

    private func configure(active: Bool, rules: [String: AppScreenRule], screens: [ScreenSnapshot], apps: [(pid_t, String)]) {
        self.active = active
        self.rules = rules
        self.screens = screens
        guard active else {
            for pid in Array(observers.keys) { removeObserver(pid) }
            return
        }
        let wanted = Dictionary(apps, uniquingKeysWith: { a, _ in a })
        for pid in Array(observers.keys) where wanted[pid] == nil { removeObserver(pid) }
        for (pid, bundleID) in wanted where observers[pid] == nil { addObserver(pid: pid, bundleID: bundleID) }
    }

    private func appLaunched(pid: pid_t, bundleID: String) {
        guard active, rules[bundleID] != nil else { return }
        launchTimes[pid] = Date()
        addObserver(pid: pid, bundleID: bundleID)
        // The first window may come before the observer is in place.
        for delay in [0.3, 1.0, 2.5] {
            thread.perform(after: delay) { [self] in
                guard active, observers[pid] != nil, let rule = rules[bundleID] else { return }
                for window in Self.windows(of: pid) { handleNewWindow(window, pid: pid, rule: rule) }
            }
        }
    }

    private func appTerminated(pid: pid_t) {
        removeObserver(pid)
        launchTimes[pid] = nil
        placed[pid] = nil
    }

    private func addObserver(pid: pid_t, bundleID: String) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, refcon in
            guard let refcon else { return }
            let engine = Unmanaged<AppScreenEngine>.fromOpaque(refcon).takeUnretainedValue()
            engine.windowCreated(element)
        }, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon) == .success else {
            Self.log.notice("Could not watch an app's windows")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        bundleIDs[pid] = bundleID
    }

    private func removeObserver(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        bundleIDs[pid] = nil
    }

    /// AX callback (engine thread: the observers' sources are on its run loop).
    private func windowCreated(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard active, AXUIElementGetPid(window, &pid) == .success,
              let bundleID = bundleIDs[pid], let rule = rules[bundleID] else { return }
        handleNewWindow(window, pid: pid, rule: rule)
    }

    private func handleNewWindow(_ window: AXUIElement, pid: pid_t, rule: AppScreenRule) {
        if rule.onlyAtLaunch {
            guard let launched = launchTimes[pid], Date().timeIntervalSince(launched) < Self.launchWindow else { return }
        }
        guard let id = Self.windowID(window), placed[pid]?.contains(id) != true else { return }
        guard place(window, rule: rule, screens: screens, force: false) else { return }
        placed[pid, default: []].insert(id)
        for delay in Self.rechecks {
            thread.perform(after: delay) { [self] in
                guard active, let rule = rules[rule.bundleID] else { return }
                place(window, rule: rule, screens: screens, force: false)
            }
        }
    }

    /// Moves `window` to the rule's display. Returns false when the window isn't one to move
    /// (a panel, a dialog, full screen, minimized) or the display isn't connected.
    @discardableResult
    private func place(_ window: AXUIElement, rule: AppScreenRule, screens: [ScreenSnapshot], force: Bool) -> Bool {
        guard let target = screens.first(where: { $0.id == rule.screenID }) else { return false }
        guard Self.string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              Self.bool(window, "AXFullScreen") != true,
              Self.bool(window, kAXMinimizedAttribute) != true,
              let frame = Self.frame(of: window) else { return false }
        let frames = screens.map(\.frame)
        let current = AppScreenPlacement.screenIndex(of: frame, in: frames).map { screens[$0] }
        if current?.id == target.id && !force { return true }
        if current?.id == target.id && rule.mode != .fill { return true }
        let from = current?.usable ?? target.usable
        let new = AppScreenPlacement.frame(for: frame, from: from, to: target.usable, mode: rule.mode)
        // Size, position, size: a window crossing to a smaller display may first be clamped to
        // the display it leaves.
        Self.setSize(window, new.size)
        Self.setPosition(window, new.origin)
        Self.setSize(window, new.size)
        Self.log.notice("Moved a new window to its display")
        return true
    }

    // MARK: - AX helpers

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}

/// A thread with its own run loop: the AX observers' callbacks arrive here, and everything the
/// engine does runs here, in order.
private final class EngineThread: Thread, @unchecked Sendable {
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didStart = false

    override init() {
        super.init()
        name = "com.matheusfaria.Sirena.appScreens"
        qualityOfService = .userInitiated
    }

    override func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !didStart else { return }
        didStart = true
        super.start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop running while no observer is installed.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func perform(after delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.perform(block)
        }
    }
}
