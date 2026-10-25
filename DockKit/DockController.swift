/// DockController.swift
///
/// Sirena entry point for Dock previews and the window switcher, ported from
/// DockDoor (GPL-3.0, © Ethan Bills). Replaces DockDoor's AppDelegate: it starts the
/// Dock observer, the preview coordinator and the keyboard switcher, without
/// DockDoor's status item, onboarding, updater or settings window.

import ApplicationServices
import Cocoa
import Defaults

@MainActor
public final class DockController: NSObject {
    public static let shared = DockController()

    private var dockObserver: DockObserver?
    private var appClosureObserver: WindowManipulationObservers?
    private var windowSeeder: WindowSeeder?
    private var previewCoordinator: SharedPreviewWindowCoordinator?
    private var keybindHelper: KeybindHelper?
    private var windowGestureController: WindowGestureController?
    private var activeAppIndicator: ActiveAppIndicatorCoordinator?
    private var dockLocker: DockLocker?
    private var wakeRecoveryTask: Task<Void, Never>?
    private var screenParametersDebounce: DispatchWorkItem?
    private var accessibilityObservation: AccessibilityGuard.Observation?
    private(set) var started = false

    public var isRunning: Bool { started }

    /// Called when DockDoor code asks to open its settings (Sirena shows its Dock page).
    public var onOpenSettings: (() -> Void)?
    /// Called when a setting needs Sirena to restart to take effect.
    public var onRestartRequested: (() -> Void)?

    public func start() {
        guard !started else { return }
        started = true

        Defaults[.launched] = true
        reconcileImagePreviewWithPermission()
        SirenaSwitcherShortcuts.applyDefaultOnce()

        // Set global AX timeout to prevent hangs from unresponsive apps
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        // Losing Accessibility drops every tap at once; getting it back recreates them.
        accessibilityObservation = AccessibilityGuard.shared.observe { [weak self] trusted in
            if trusted {
                self?.recoverObserversAndTaps()
            } else {
                self?.suspendTaps()
            }
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSystemWake), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        MediaRemoteService.shared.activate()
        ScreenReservations.shared.start()

        let coordinator = SharedPreviewWindowCoordinator()
        previewCoordinator = coordinator
        dockObserver = DockObserver(previewCoordinator: coordinator)
        appClosureObserver = WindowManipulationObservers(previewCoordinator: coordinator)

        if Defaults[.enableWindowSwitcher] || Defaults[.enableCmdTabEnhancements] {
            keybindHelper = KeybindHelper(previewCoordinator: coordinator)
        }

        if Defaults[.enableWindowGestures] {
            windowGestureController = WindowGestureController(previewCoordinator: coordinator) { [weak self] event in
                self?.keybindHelper?.handleGestureSwitcher(event)
            }
        }

        if Defaults[.showActiveAppIndicator] {
            activeAppIndicator = ActiveAppIndicatorCoordinator()
        }

        NSScreen.migrateScreenIdentifier(.lockedDockScreenIdentifier)
        NSScreen.migrateScreenIdentifier(.pinnedScreenIdentifier)
        if Defaults[.enableDockLocking] {
            dockLocker = DockLocker()
        }

        Task(priority: .high) {
            await WindowUtil.updateAllWindowsInCurrentSpace()
        }

        // Cold-start: seed all windows (including minimized and other Spaces) and start live AX tracker
        let seeder = WindowSeeder()
        seeder.run()
        windowSeeder = seeder
    }

    public func terminate() {
        guard started else { return }
        wakeRecoveryTask?.cancel()
        WindowUtil.saveWindowOrderFromCache()
    }

    // MARK: - Facts shown on Sirena's pages

    public static var hasScreenRecordingPermission: Bool {
        WindowUtil.hasScreenRecordingPermission()
    }

    public static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    // Clear the onboarding skip's disableImagePreview only when permission was newly granted since last launch.
    private func reconcileImagePreviewWithPermission() {
        let hasPermission = WindowUtil.hasScreenRecordingPermission()
        let hadPermission = Defaults[.lastKnownScreenRecordingPermission]
        Defaults[.lastKnownScreenRecordingPermission] = hasPermission

        if hasPermission, !hadPermission, Defaults[.disableImagePreview] {
            Defaults[.disableImagePreview] = false
        }
    }

    @objc private func handleScreenParametersChanged() {
        screenParametersDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.handleSystemWake() }
        screenParametersDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    @objc private func handleSystemWake() {
        wakeRecoveryTask?.cancel()

        wakeRecoveryTask = Task {
            var delay: UInt64 = 1_000_000_000 // 1s
            var totalWaited: UInt64 = 0
            let maxWait: UInt64 = 15_000_000_000 // 15s

            while !Task.isCancelled, totalWaited < maxWait {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                totalWaited += delay

                if isAccessibilityReady() {
                    DebugLogger.log("Wake recovery", details: "AX canary passed after \(totalWaited / 1_000_000)ms")
                    break
                }

                DebugLogger.log("Wake recovery", details: "AX canary failed after \(totalWaited / 1_000_000)ms, backing off")
                delay = min(delay * 2, maxWait - totalWaited)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.recoverObserversAndTaps()
            }
        }
    }

    private func suspendTaps() {
        wakeRecoveryTask?.cancel()
        dockObserver?.suspendEventTap()
        keybindHelper?.suspendEventTaps()
        dockLocker?.suspendEventTap()
        windowGestureController?.suspend()
    }

    func recoverObserversAndTaps() {
        dockObserver?.reset()
        keybindHelper?.recover()
        appClosureObserver?.reset()
        dockLocker?.reset()
        windowGestureController?.reset()
    }

    func openSettings() {
        onOpenSettings?()
    }

    func restartApp() {
        onRestartRequested?()
    }
}
