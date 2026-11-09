//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import Foundation
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isPreventing = false
    private var isUserSessionActive = true

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        releaseSleepAssertion()
        assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Prevents the system from sleeping
    func preventSleep() {
        self.isPreventing = true
        self.assertionTimer?.invalidate()
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshSleepAssertion()
        }
        // .common: the refresh keeps running while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.assertionTimer = timer
        self.refreshSleepAssertion()
    }

    /// Allows the system to sleep normally
    func allowSleep() {
        self.isPreventing = false
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseSleepAssertion()
    }

    // MARK: - Private Methods

    /// The assertion has no timeout, so a late timer can't open a gap: the display sleeps the
    /// moment none is held if it has been idle long enough. macOS drops it if Sirena dies. The
    /// periodic refresh only covers an assertion lost some other way (powerd restarting), and
    /// the new one exists before the old one goes.
    private func refreshSleepAssertion() {
        guard self.isPreventing, self.isUserSessionActive else { return }

        var assertionID: IOPMAssertionID = 0
        let reason = String(localized: "Caffeine prevents sleep") as CFString
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            0, // No timeout: held until released
            nil as CFString?,
            &assertionID
        )

        guard result == kIOReturnSuccess else { return }
        if let previous = self.sleepAssertionID {
            IOPMAssertionRelease(previous)
        }
        self.sleepAssertionID = assertionID
    }

    private func releaseSleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func sessionDidResignActive() {
        self.isUserSessionActive = false
        self.releaseSleepAssertion()
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
        self.refreshSleepAssertion()
    }
}
