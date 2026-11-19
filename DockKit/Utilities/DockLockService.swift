import Cocoa
import Defaults

/// Sirena: keeps the Dock on one display (Ajustes › Dock). The `DockLocker` came with DockDoor,
/// where it lived inside the Dock previews; here it has a single owner of its own, so it works
/// with the previews off. The locker's tap follows `AccessibilityGuard` like every other tap.
@MainActor
public final class DockLockService {
    public static let shared = DockLockService()

    private var locker: DockLocker?
    private var accessibilityObservation: AccessibilityGuard.Observation?
    private var wakeObservers: [NSObjectProtocol] = []

    public var isRunning: Bool { locker != nil }

    /// "The main display": follows whichever display macOS has as main (Displays settings),
    /// not one display in particular. The default.
    public static let mainDisplayIdentifier = NSScreen.systemMainDisplayIdentifier

    /// The main display now (the one with the menu bar's first copy).
    public static var mainDisplay: NSScreen? { NSScreen.systemMain }

    /// The display the Dock stays on: `mainDisplayIdentifier` or a hardware UUID (empty: none
    /// chosen yet, treated as the main display).
    public static var lockedScreenIdentifier: String {
        get { Defaults[.lockedDockScreenIdentifier] }
        set { Defaults[.lockedDockScreenIdentifier] = newValue }
    }

    /// The key that lets the Dock move while held: 0 ⌥, 1 ⌃, 2 ⇧, 3 ⌘.
    public static var overrideModifier: Int {
        get { Defaults[.dockLockOverrideModifier] }
        set { Defaults[.dockLockOverrideModifier] = newValue }
    }

    /// The identifier `lockedScreenIdentifier` expects for a display.
    public static func identifier(of screen: NSScreen) -> String {
        screen.uniqueIdentifier()
    }

    /// The display that holds the Dock now (asks the Dock through Accessibility).
    public static func screenHoldingDock() -> NSScreen? {
        DockUtils.dockScreen()
    }

    /// The Dock sits at the bottom, left or right (the lock does nothing for other values).
    public static var dockIsOnAnEdgeItCanLock: Bool {
        [.bottom, .left, .right].contains(DockUtils.getDockPosition())
    }

    public func start() {
        guard locker == nil else { return }
        NSScreen.migrateScreenIdentifier(.lockedDockScreenIdentifier)
        if Self.lockedScreenIdentifier.isEmpty {
            Self.lockedScreenIdentifier = Self.mainDisplayIdentifier
        }
        locker = DockLocker()
        accessibilityObservation = AccessibilityGuard.shared.observe { [weak self] trusted in
            if trusted { self?.locker?.reset() } else { self?.locker?.suspendEventTap() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard AccessibilityGuard.isTrusted else { return }
                    self?.locker?.reset()
                }
            })
        }
    }

    public func stop() {
        guard let old = locker else { return }
        accessibilityObservation?.invalidate()
        accessibilityObservation = nil
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        locker = nil
        old.suspendEventTap()
        // The tap's callback holds the locker unretained: keep it alive until the tap thread has
        // removed the tap (that block runs first), then let it go on the main thread.
        EventTapThread.shared.perform {
            DispatchQueue.main.async { withExtendedLifetime(old) {} }
        }
    }
}
