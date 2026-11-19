/// WindowDragEngine.swift
///
/// The event tap behind "Arrastar de qualquer lugar" (ported from AnyDrag, Xueshi Qiao,
/// GPL-3.0). With the chosen key held:
/// - left drag anywhere on a window moves it (`TitleBarDragStrategy`);
/// - right drag resizes it from the nearest corner (`CornerResizeStrategy`);
/// - a double click maximizes it, and again gives its size back.
/// A press that never becomes a drag is handed back whole to the app (down and up together),
/// so a held-key click keeps doing what it did before (⌥-click, ⌘-click, a context menu).
///
/// Rules (CLAUDE.md, event taps): the tap goes through `AccessibilityGuard`; while not
/// trusted every event passes untouched; the callback makes no Accessibility call and never
/// waits for the main thread. Bringing the window forward and maximizing run on `axQueue`.

import AppKit
import DockKit
import OSLog

final class WindowDragEngine: @unchecked Sendable {
    /// Marks the clicks Sirena hands back, so the tap lets them through.
    static let ownEventMarker: Int64 = 0x5349_4452 // "SIDR"
    fileprivate static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "WindowDrag")
    private static let axQueue = DispatchQueue(label: "com.matheusfaria.Sirena.windowDrag.ax", qos: .userInteractive)
    private static let axTimeout: Float = 0.15

    private let onLostTrust: () -> Void
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?

    // Tap-thread state.
    private let move = TitleBarDragStrategy()
    private let resize = CornerResizeStrategy()
    private var pendingClick: (location: CGPoint, flags: CGEventFlags, right: Bool)?
    private var swallowLeftUp = false

    // Displays (top-left coordinates), set on the main thread, read on `axQueue`.
    private static let screensLock = NSLock()
    nonisolated(unsafe) private static var storedScreens: [ScreenSnapshot] = []
    static var screens: [ScreenSnapshot] {
        get { screensLock.lock(); defer { screensLock.unlock() }; return storedScreens }
        set { screensLock.lock(); storedScreens = newValue; screensLock.unlock() }
    }

    /// Frames before a maximize, per window (only touched on `axQueue`).
    nonisolated(unsafe) private static var savedFrames: [CGWindowID: (pid: pid_t, frame: CGRect)] = [:]

    init(onLostTrust: @escaping () -> Void) {
        self.onLostTrust = onLostTrust
    }

    // MARK: - Lifecycle

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
        thread.name = "Sirena.WindowDrag.EventTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
        return created
    }

    /// Tears the tap down on its own thread, so stopping can't race a callback.
    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            if let tap {
                AccessibilityGuard.shared.unregister(tap)
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            tap = nil
            move.reset()
            resize.reset()
            self.runLoop = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
        thread = nil
    }

    private func installTap() -> Bool {
        guard AccessibilityGuard.shared.mayCreateTap("WindowDrag") else { return false }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: windowDragTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // After the enable: registering switches the tap off if trust went away meanwhile.
        AccessibilityGuard.shared.register(tap, name: "WindowDrag")
        self.tap = tap
        return true
    }

    /// AccessibilityGuard re-enables only while trusted, rate-limited; never here. Events
    /// were missed while it was off: whatever gesture was going on is dropped.
    fileprivate func tapDisabled(_ type: CGEventType) {
        AccessibilityGuard.shared.tapDisabled(tap, type: type, name: "WindowDrag")
        move.reset()
        resize.reset()
        pendingClick = nil
        swallowLeftUp = false
        if !AccessibilityGuard.isTrusted { onLostTrust() }
    }

    // MARK: - Events

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown: return leftDown(event)
        case .leftMouseDragged: return move.isActive ? move.dragged(event) : Unmanaged.passUnretained(event)
        case .leftMouseUp: return leftUp(event)
        case .rightMouseDown: return rightDown(event)
        case .rightMouseDragged: return resize.isActive ? resize.dragged(event) : Unmanaged.passUnretained(event)
        case .rightMouseUp: return rightUp(event)
        default: return Unmanaged.passUnretained(event)
        }
    }

    private func leftDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // The button was up: a move still marked active lost its release.
        if move.isActive { move.reset() }
        swallowLeftUp = false
        let settings = WindowDragSnapshot.current
        Self.note("left", event, settings)
        guard settings.enabled, Self.matches(event.flags, settings.modifier),
              let target = Self.windowUnderCursor(at: event.location, excluded: settings.excluded)
        else { return Unmanaged.passUnretained(event) }
        Self.log.debug("left press: window \(target.windowID) of pid \(target.pid) at \(String(describing: target.frame))")

        if settings.maximize && event.getIntegerValueField(.mouseEventClickState) >= 2 {
            swallowLeftUp = true
            Self.axQueue.async { Self.toggleMaximize(target) }
            return nil
        }
        guard !target.fillsDisplay else { return Unmanaged.passUnretained(event) }
        move.begin(pid: target.pid, windowID: target.windowID, windowFrame: target.frame, cursor: event.location)
        pendingClick = (event.location, event.flags, false)
        Self.axQueue.async { Self.bringForward(target) }
        return nil
    }

    private func leftUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if swallowLeftUp {
            swallowLeftUp = false
            return nil
        }
        guard move.isActive else { return Unmanaged.passUnretained(event) }
        if move.pressSent { return move.released(event) }
        // Never became a drag: give the app its click back, whole.
        move.reset()
        if let click = pendingClick { Self.replay(click) }
        pendingClick = nil
        return nil
    }

    private func rightDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if resize.isActive { resize.reset() }
        let settings = WindowDragSnapshot.current
        Self.note("right", event, settings)
        guard settings.enabled, settings.resize, Self.matches(event.flags, settings.modifier),
              let target = Self.windowUnderCursor(at: event.location, excluded: settings.excluded),
              !target.fillsDisplay
        else { return Unmanaged.passUnretained(event) }
        resize.begin(pid: target.pid, windowID: target.windowID, windowFrame: target.frame,
                     cursor: event.location)
        pendingClick = (event.location, event.flags, true)
        Self.axQueue.async { Self.bringForward(target) }
        return nil
    }

    private func rightUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard resize.isActive else { return Unmanaged.passUnretained(event) }
        if resize.pressSent { return resize.released(event) }
        resize.reset()
        if let click = pendingClick { Self.replay(click) }
        pendingClick = nil
        return nil
    }

    // MARK: - Matching

    /// A press with any of ⌃⌥⇧⌘ held, logged (debug) to tell why a gesture didn't start.
    private static func note(_ button: String, _ event: CGEvent, _ settings: WindowDragSnapshot) {
        let held = event.flags.intersection(modifierMask)
        guard !held.isEmpty else { return }
        log.debug("\(button) press with flags \(String(held.rawValue, radix: 16)): enabled \(settings.enabled), wanted \(String(settings.modifier.flags.rawValue, radix: 16)), matches \(matches(event.flags, settings.modifier))")
    }

    private static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    private static func matches(_ flags: CGEventFlags, _ modifier: WindowDragModifier) -> Bool {
        flags.intersection(modifierMask) == modifier.flags
    }

    struct Target {
        let pid: pid_t
        let windowID: CGWindowID
        let frame: CGRect
        /// Covers a whole display (full screen): it can't be moved or resized, and its top edge
        /// is the app's content (a browser's tabs), so only the double click applies.
        let fillsDisplay: Bool
    }

    /// The window under the pointer, if it's an app's normal window: anything else in front
    /// (menu bar, Dock, a floating panel, Sirena's own windows, an excluded app) lets the press
    /// through. Window server only.
    private static func windowUnderCursor(at point: CGPoint, excluded: Set<String>) -> Target? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[CFString: Any]] else { return nil }
        var displays: [CGRect]?
        for window in windows {
            guard let bounds = window[kCGWindowBounds] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point) else { continue }
            // Invisible overlays don't count.
            guard (window[kCGWindowAlpha] as? Double ?? 1) > 0.01 else { continue }
            let layer = window[kCGWindowLayer] as? Int ?? 0
            if layer != 0 {
                // The Dock keeps a whole-screen window above everything, and other tools park
                // whole-display overlays there too: those never take the press. Anything else
                // in front (menu bar, a floating panel, a menu) lets it through.
                if window[kCGWindowOwnerName] as? String == "Dock" { continue }
                if displays == nil { displays = activeDisplayBounds() }
                if displays!.contains(where: { Self.same($0, frame) }) { continue }
                log.debug("no target: \(window[kCGWindowOwnerName] as? String ?? "?") layer \(layer) is in front")
                return nil
            }
            guard let pid = window[kCGWindowOwnerPID] as? pid_t, pid != getpid(),
                  let id = window[kCGWindowNumber] as? CGWindowID,
                  frame.width > 60, frame.height > 40 else { return nil }
            if !excluded.isEmpty, let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
               excluded.contains(bundleID) { return nil }
            if displays == nil { displays = activeDisplayBounds() }
            return Target(pid: pid, windowID: id, frame: frame, fillsDisplay: displays!.contains { Self.same($0, frame) })
        }
        return nil
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    // MARK: - Handing a click back

    private static func replay(_ click: (location: CGPoint, flags: CGEventFlags, right: Bool)) {
        // Posted off the tap thread: posting from the callback can re-enter the tap.
        DispatchQueue.global(qos: .userInteractive).async {
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            source.userData = ownEventMarker
            // Posting freezes the real pointer for 0.25 s by default.
            source.localEventsSuppressionInterval = 0
            let types: (CGEventType, CGEventType) = click.right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
            let button: CGMouseButton = click.right ? .right : .left
            guard let down = CGEvent(mouseEventSource: source, mouseType: types.0, mouseCursorPosition: click.location, mouseButton: button),
                  let up = CGEvent(mouseEventSource: source, mouseType: types.1, mouseCursorPosition: click.location, mouseButton: button)
            else { return }
            for event in [down, up] {
                event.flags = click.flags
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Accessibility (axQueue only)

    private static func window(of target: Target) -> AXUIElement? {
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            AXUIElementSetMessagingTimeout(window, axTimeout)
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success, id == target.windowID { return window }
        }
        // Some apps don't answer the window id: match the frame's top-left corner.
        for window in windows {
            if let frame = frame(of: window),
               abs(frame.minX - target.frame.minX) < 5, abs(frame.minY - target.frame.minY) < 5 { return window }
        }
        return nil
    }

    /// Brings just this window forward and makes it key, without the app's other windows.
    private static func bringForward(_ target: Target) {
        let window = window(of: target)
        var made = false
        if let window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            made = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue) == .success
        }
        if WindowServerFocus.focus(pid: target.pid, windowID: target.windowID) { return }
        if made {
            DispatchQueue.main.async { _ = NSRunningApplication(processIdentifier: target.pid)?.activate(options: []) }
            return
        }
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
    }

    /// Fills the display's usable area; again (while it still fills it) gives the old frame back.
    private static func toggleMaximize(_ target: Target) {
        // A full-screen window has no frame to give: only one Sirena filled (menu bar and Dock
        // hidden) goes back.
        if target.fillsDisplay, savedFrames[target.windowID]?.pid != target.pid { return }
        guard let window = window(of: target), let current = frame(of: window) else { return }
        bringForward(target)
        let screens = Self.screens
        guard let index = AppScreenPlacement.screenIndex(of: current, in: screens.map(\.frame)) else { return }
        let usable = screens[index].usable
        let fills = abs(current.minX - usable.minX) < 24 && abs(current.minY - usable.minY) < 24
            && abs(current.maxX - usable.maxX) < 24 && abs(current.maxY - usable.maxY) < 24
        if fills, let saved = savedFrames[target.windowID], saved.pid == target.pid {
            savedFrames[target.windowID] = nil
            setFrame(window, saved.frame)
            log.notice("Window restored")
        } else {
            savedFrames[target.windowID] = (target.pid, current)
            setFrame(window, usable)
            log.notice("Window maximized")
        }
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

    private static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        // Size, position, size: a window may first be held back by the edge of its display.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
}

private func windowDragTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                                   _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<WindowDragEngine>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        engine.tapDisabled(type)
        return Unmanaged.passUnretained(event)
    }
    guard AccessibilityGuard.isTrusted else { return Unmanaged.passUnretained(event) }
    return engine.handle(type, event)
}

// MARK: - Window server focus

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

/// Makes one window front-most and key without bringing its app's other windows (the private
/// calls AltTab and yabai use, from AnyDrag). Looked up at first use: if a macOS removes them
/// the lookup is nil and `bringForward` uses the public way.
private enum WindowServerFocus {
    private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let userGenerated: UInt32 = 0x200
    private static let setFront: SetFrontFn? = lookup("_SLPSSetFrontProcessWithOptions")
    private static let postEvent: PostEventFn? = lookup("SLPSPostEventRecordTo")

    private static func lookup<T>(_ name: String) -> T? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFront, let postEvent else { return false }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }
        guard setFront(&psn, windowID, userGenerated) == .success else { return false }
        // Tell the app its window became key (event record: 0x01 key down, 0x02 key up).
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { raw in
            for k in 0..<4 { bytes[0x3c + k] = raw[k] }
        }
        for k in 0x20..<0x30 { bytes[k] = 0xff }
        bytes[0x08] = 0x01
        _ = postEvent(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEvent(&psn, &bytes)
        return true
    }
}
