/// DockAndDisplaysController.swift
///
/// Runs what Janela e Dock › Dock and › Monitores switch on (once the "Ajustes" card): the Dock
/// kept on one display (one event tap, through `AccessibilityGuard`) and apps that open on a
/// chosen display (AX observers only for the apps that have a rule). Started with the other
/// modules, whatever card is on; each part runs only while its own switch or list asks for it.
/// Map: .planning/codebase/ADJUSTMENTS.md.

import AppKit
import DockKit

@MainActor
final class DockAndDisplaysController {
    static let shared = DockAndDisplaysController()

    /// "Keep the Dock on one display" (off by default). The key predates the move to Janela e Dock.
    static let dockLockKey = "adjustments.dockLock.enabled"

    private var isRunning = false

    static var dockLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: dockLockKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: dockLockKey)
            shared.applyDockLock()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        applyDockLock()
        AppScreenEngine.shared.start()
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        DockLockService.shared.stop()
        AppScreenEngine.shared.stop()
    }

    private func applyDockLock() {
        if isRunning && Self.dockLockEnabled {
            DockLockService.shared.start()
        } else {
            DockLockService.shared.stop()
        }
    }
}
