/// WindowDragController.swift
///
/// Starts and stops the "Arrastar de qualquer lugar" tap: it exists only while the option is
/// on and Accessibility is granted (`AccessibilityGuard`), and goes away at once otherwise.

import AppKit
import DockKit

@MainActor
final class WindowDragController {
    static let shared = WindowDragController()

    private var engine: WindowDragEngine?
    private var isRunning = false
    private var accessibilityObservation: AccessibilityGuard.Observation?
    private var observers: [NSObjectProtocol] = []
    private var retryTimer: Timer?

    var isActive: Bool { engine != nil }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        accessibilityObservation = AccessibilityGuard.shared.observe { [weak self] _ in self?.apply() }
        observers = [
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WindowDragEngine.screens = AppScreenEngine.screenSnapshots() }
            }
        ]
        WindowDragEngine.screens = AppScreenEngine.screenSnapshots()
        apply()
    }

    func terminate() {
        isRunning = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        accessibilityObservation?.invalidate()
        accessibilityObservation = nil
        retryTimer?.invalidate()
        retryTimer = nil
        engine?.stop()
        engine = nil
    }

    /// Reads the settings again and creates or drops the tap to match.
    func apply() {
        WindowDragSnapshot.refresh()
        let wanted = isRunning && WindowDragSnapshot.current.enabled && AccessibilityGuard.isTrusted
        if wanted, engine == nil {
            let engine = WindowDragEngine { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.engine?.stop()
                        self?.engine = nil
                        self?.apply()
                    }
                }
            }
            if engine.start() {
                self.engine = engine
                retryTimer?.invalidate()
                retryTimer = nil
            } else {
                retrySoon()
            }
        } else if !wanted, let engine {
            engine.stop()
            self.engine = nil
        }
    }

    /// A tap that couldn't be created (trusted, but refused) gets another try.
    private func retrySoon() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTimer = nil
                self?.apply()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }
}
