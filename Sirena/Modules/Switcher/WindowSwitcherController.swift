// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; Sirena port.
//
// WindowSwitcherController.swift
//
// Sirena facade over the window/app switcher ported from Vorssaint
// (SwitcherAppSwitcher and friends). The switcher listens through its own
// CGEvent tap, so it can own ⌘Tab, which a normal global hotkey cannot.

import AppKit

@MainActor
final class WindowSwitcherController {
    static let shared = WindowSwitcherController()

    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        SwitcherDefaults.registerSwitcherDefaults()
    }

    /// Gives back any macOS ⌘Tab / ⌘` hotkeys a previous run disabled and did
    /// not restore (crash, force quit). Safe to call at every launch, whether
    /// or not the module is enabled.
    static func recoverSystemShortcuts() {
        SwitcherDefaults.registerSwitcherDefaults()
        SwitcherSystemShortcutTakeover.recoverIfNeeded(keeping: [])
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        SwitcherDefaults.registerSwitcherDefaults()
        SwitcherSystemShortcutTakeover.recoverIfNeeded(keeping: SwitcherAppSwitcher.launchTakeoverIDs())
        SwitcherAppFeature.setSwitcherRunning(true)
        SwitcherWindowUseTracker.shared.syncWithFeatures()
        SwitcherAppSwitcher.shared.syncWithPreferences()

        // Accessibility may be granted after launch; the tap can only be
        // installed once it is, so re-sync whenever the app comes forward.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowSwitcherController.shared.syncWithPreferences() }
        })
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        SwitcherAppFeature.setSwitcherRunning(false)
        SwitcherAppSwitcher.shared.syncWithPreferences()
        SwitcherAppSwitcher.shared.suspend()
        SwitcherWindowUseTracker.shared.syncWithFeatures()
        SwitcherSystemShortcutTakeover.setWanted([], for: SwitcherSystemShortcutTakeover.switcherSource)
        SwitcherSystemShortcutTakeover.restoreAll()
    }

    /// Re-applies the stored preferences (shortcut, take-over, layout…).
    func syncWithPreferences() {
        guard isRunning else { return }
        SwitcherAppSwitcher.shared.syncWithPreferences()
    }

    /// While a shortcut field is recording, every key must reach it.
    func setCapturingShortcut(_ capturing: Bool) {
        SwitcherAppSwitcher.shared.setCapturingShortcut(capturing)
    }
}
