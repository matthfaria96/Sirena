/// AppUpdater.swift
///
/// In-app updates through Sparkle. The feed (SUFeedURL), the EdDSA public key
/// (SUPublicEDKey) and the daily automatic check live in Info.plist; updates are signed
/// with the witchmymac EdDSA key and the app with the witchmymac certificate, so
/// Sparkle accepts them and macOS keeps Sirena's permissions across versions.
///
/// Sirena runs without a Dock icon while its window is closed. A scheduled check that
/// finds an update would leave Sparkle's window behind other apps, unseen, so for the
/// length of the update session Sirena becomes a regular app (Dock icon, one bounce)
/// and goes back to the menu bar when the session ends.

import AppKit
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    /// False while a check or an install is already under way.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    /// True while Sparkle shows (or is about to show) an update window. The main window
    /// leaves the Dock icon alone when it closes during that time.
    @ObservationIgnored private(set) var isShowingUpdate = false

    private override init() {
        super.init()
    }

    /// Starts Sparkle's scheduler (daily check, from Info.plist). Call once at launch.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Check for Updates…": always shows a result, even "You're up to date".
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    // MARK: - Dock icon for the update window

    /// Sirena's own windows that keep the Dock icon while they are open (or minimized).
    static let dockWindowIDs: Set<String> = ["SirenaMainWindow", "SirenaOnboardingWindow"]

    private func showDockIconForUpdate() {
        isShowingUpdate = true
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    private func hideDockIconAfterUpdate() {
        guard isShowingUpdate else { return }
        isShowingUpdate = false
        // Back to the menu bar only if no Sirena window still needs the icon (it then hides
        // the icon itself when it closes).
        let ownWindowOpen = NSApp.windows.contains { window in
            (window.isVisible || window.isMiniaturized)
                && Self.dockWindowIDs.contains(window.identifier?.rawValue ?? "")
        }
        if !ownWindowOpen { NSApp.setActivationPolicy(.accessory) }
    }
}

extension AppUpdater: @MainActor NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return canCheckForUpdates
    }
}

extension AppUpdater: @MainActor SPUStandardUserDriverDelegate {
    /// Sirena decides how a scheduled update shows up (see `standardUserDriverWillHandleShowingUpdate`).
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Sparkle shows the window either way; away from launch it doesn't take focus,
        // and the Dock icon added below keeps it easy to find.
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        showDockIconForUpdate()
        if !state.userInitiated, !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        hideDockIconAfterUpdate()
    }
}
