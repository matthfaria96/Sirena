/// ScreenDimmer.swift
///
/// With two or more displays, the ones you are not using fade to dark after a moment and come
/// back as soon as the pointer (or the focused window) gets there. One black, click-through
/// window per display does it: below the Dock and the menu bar, left out of screen recordings
/// and screen sharing, and absent from full-screen Spaces unless asked. The active display is
/// read by polling the pointer (no event tap, no event monitor); the focused-window mode asks
/// Accessibility off the main thread and falls back to the pointer without it.

import AppKit
import ApplicationServices

@MainActor
@Observable
final class ScreenDimmer {
    static let shared = ScreenDimmer()

    enum Follow: String, CaseIterable, Identifiable {
        case pointer, focusedWindow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pointer: return L("The one with the pointer")
            case .focusedWindow: return L("The one with the focused window")
            }
        }
    }

    static let enabledKey = "screenDimmer.enabled"
    static let opacityKey = "screenDimmer.opacity"
    static let delayKey = "screenDimmer.delay"
    static let followKey = "screenDimmer.follow"
    static let fullScreenKey = "screenDimmer.dimFullScreen"
    static let defaultOpacity = 0.5
    static let defaultDelay = 2
    static let delays: [(seconds: Int, title: String)] = [
        (0, L("Right away")), (2, L("2 seconds")), (5, L("5 seconds")), (10, L("10 seconds")), (30, L("30 seconds"))
    ]

    var isEnabled = UserDefaults.standard.bool(forKey: ScreenDimmer.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }

    /// Connected displays, for the pages and the menu ("needs a second display").
    private(set) var screenCount = NSScreen.screens.count

    var hasSeveralScreens: Bool { screenCount > 1 }
    /// Doing something right now.
    var isDimming: Bool { isEnabled && hasSeveralScreens && started }

    @ObservationIgnored private var started = false
    @ObservationIgnored private var overlays: [CGDirectDisplayID: DimWindow] = [:]
    @ObservationIgnored private var inactiveSince: [CGDirectDisplayID: Date] = [:]
    @ObservationIgnored private var activeDisplay: CGDirectDisplayID?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var focusQuery = false
    @ObservationIgnored private var focusedWindowDisplay: CGDirectDisplayID?
    @ObservationIgnored private let axQueue = DispatchQueue(label: "Sirena.ScreenDimmer.focus", qos: .utility)

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        // Settings changed on the page take effect right away.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        apply()
    }

    func stop() {
        started = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        tearDown()
    }

    // MARK: - Settings

    private var opacity: Double {
        let value = UserDefaults.standard.object(forKey: Self.opacityKey) as? Double ?? Self.defaultOpacity
        return min(max(value, 0.1), 0.9)
    }

    private var delay: TimeInterval {
        TimeInterval(max(0, UserDefaults.standard.object(forKey: Self.delayKey) as? Int ?? Self.defaultDelay))
    }

    private var follow: Follow {
        Follow(rawValue: UserDefaults.standard.string(forKey: Self.followKey) ?? "") ?? .pointer
    }

    private var dimsFullScreen: Bool { UserDefaults.standard.bool(forKey: Self.fullScreenKey) }

    @ObservationIgnored private var appliedFullScreen: Bool?

    private func settingsChanged() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if enabled != isEnabled { isEnabled = enabled }
        if appliedFullScreen != nil, appliedFullScreen != dimsFullScreen {
            // The Spaces a window joins are set when it is made: rebuild the overlays.
            tearDown()
            apply()
        }
    }

    // MARK: - Overlays

    private func screensChanged() {
        screenCount = NSScreen.screens.count
        tearDown()
        apply()
    }

    private func apply() {
        screenCount = NSScreen.screens.count
        guard started, isEnabled, hasSeveralScreens else {
            tearDown()
            return
        }
        let screens = NSScreen.screens
        let ids = Set(screens.compactMap(\.dimmerDisplayID))
        for (id, window) in overlays where !ids.contains(id) {
            window.orderOut(nil)
            overlays[id] = nil
        }
        appliedFullScreen = dimsFullScreen
        for screen in screens {
            guard let id = screen.dimmerDisplayID else { continue }
            if let window = overlays[id] {
                window.setFrame(screen.frame, display: false)
            } else {
                let window = DimWindow(screen: screen, joinsFullScreen: dimsFullScreen)
                window.orderFrontRegardless()
                overlays[id] = window
            }
        }
        if timer == nil {
            let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        inactiveSince.removeAll()
        activeDisplay = nil
        appliedFullScreen = nil
    }

    // MARK: - Following the active display

    private func tick() {
        guard let active = currentActiveDisplay() else { return }
        let now = Date()
        let changed = active != activeDisplay
        activeDisplay = active
        for (id, window) in overlays {
            if id == active {
                inactiveSince[id] = nil
                window.fade(to: 0, duration: 0.15)
            } else {
                let since = inactiveSince[id] ?? now
                inactiveSince[id] = since
                if now.timeIntervalSince(since) >= delay {
                    window.fade(to: opacity, duration: changed && delay == 0 ? 0.25 : 0.6)
                }
            }
        }
    }

    private func currentActiveDisplay() -> CGDirectDisplayID? {
        if follow == .focusedWindow, AXIsProcessTrusted() {
            refreshFocusedWindowDisplay()
            if let focused = focusedWindowDisplay, overlays[focused] != nil { return focused }
        }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        return screen?.dimmerDisplayID ?? activeDisplay
    }

    /// Asks Accessibility where the focused window is, off the main thread (an app that hangs
    /// must not stall the pointer), one question at a time.
    private func refreshFocusedWindowDisplay() {
        guard !focusQuery, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        focusQuery = true
        axQueue.async { [weak self] in
            let frame = Self.focusedWindowFrame(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.focusQuery = false
                    guard let frame else { return }
                    self.focusedWindowDisplay = Self.display(containingCGRect: frame)
                }
            }
        }
    }

    nonisolated private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// The display holding the middle of a rect in global (top-left origin) coordinates.
    private static func display(containingCGRect rect: CGRect) -> CGDirectDisplayID? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard CGGetDisplaysWithPoint(center, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }
}

// MARK: - The dark window

private final class DimWindow: NSPanel {
    private var target: CGFloat = 0

    init(screen: NSScreen, joinsFullScreen: Bool) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = false
        hasShadow = false
        alphaValue = 0
        ignoresMouseEvents = true
        // Under the Dock and the menu bar, above every app window.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if joinsFullScreen { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
        // Calls and recordings show the screen as it is.
        sharingType = .none
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fade(to value: Double, duration: TimeInterval) {
        let value = CGFloat(value)
        guard abs(value - target) > 0.001 else { return }
        target = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = value
        }
    }
}

private extension NSScreen {
    var dimmerDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
