/// MinimizeHidesApp.swift
///
/// Sirena: "Minimizar esconde todas as janelas do app". macOS animates minimizing and restoring
/// one window at a time inside the app itself (≈0.3 s each down, ≈0.4 s each back), so an app
/// with 8 windows takes seconds either way, and nothing outside the app can skip that. Hiding
/// the app takes every window away at once and brings them all back at once.
///
/// With the option on (the default), minimizing a window (yellow button, ⌘M) in an app with
/// 3 or more open windows hides the whole app right away; the minimized window is brought back
/// while the app is hidden (invisible, the app stays hidden), so the Dock icon or ⌘ Tab shows
/// every window again together. With 1 or 2 windows, minimizing stays as it is. ⌥⌘M (Minimize
/// All) is left to macOS: with "minimize into application icon" on, the windows it takes away
/// drop out of Accessibility at once, so there is nothing to follow.
///
/// Driven by the Accessibility notification for minimized windows (no event tap). Everything runs
/// on its own queue: AX calls never touch the main thread or the observer callback.

import AppKit
import ApplicationServices
import Defaults

extension Defaults.Keys {
    static let minimizeHidesAllWindows = Key<Bool>("minimizeHidesAllWindows", default: true)
}

final class MinimizeHidesApp: @unchecked Sendable {
    static let shared = MinimizeHidesApp()

    /// From how many open windows minimizing hides the whole app.
    static let minimumWindows = 3
    /// Time for a hide to land, and the quiet that ends a burst, before windows come back.
    private static let hideSettleDelay: TimeInterval = 0.35
    /// A burst (⌥⌘M) is over after this long without another minimized window.
    private static let sessionQuietTime: TimeInterval = 1.5

    private struct Session {
        var pending: [AXUIElement] = []
        var lastEvent = Date()
    }

    private let queue = DispatchQueue(label: "Sirena.MinimizeHidesApp", qos: .userInteractive)
    // Touched only on `queue`.
    private var sessions: [pid_t: Session] = [:]
    private var ownMinimizeUntil: [pid_t: Date] = [:]

    private init() {}

    static var isEnabled: Bool { Defaults[.minimizeHidesAllWindows] }

    /// Sirena is about to minimize this app's windows itself: leave those alone.
    func markOwnMinimize(pid: pid_t) {
        queue.async { self.ownMinimizeUntil[pid] = Date().addingTimeInterval(3) }
    }

    /// Called from the AX observer callback (main thread) for every minimized window.
    func windowMinimized(_ window: AXUIElement, pid: pid_t) {
        guard Self.isEnabled, pid != ProcessInfo.processInfo.processIdentifier else { return }
        queue.async { self.handle(window, pid: pid) }
    }

    // MARK: - On the queue

    private func handle(_ window: AXUIElement, pid: pid_t) {
        if let until = ownMinimizeUntil[pid] {
            if until > Date() { return }
            ownMinimizeUntil[pid] = nil
        }

        // Another window of the same burst (⌥⌘M goes through every window): collect it.
        if var session = sessions[pid] {
            session.lastEvent = Date()
            session.pending.append(window)
            sessions[pid] = session
            scheduleFlush(pid, attempt: 1)
            return
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard !Self.bool(app, kAXHiddenAttribute) else { return }
        let others = Self.standardWindows(of: app).filter { !CFEqual($0, window) && !Self.bool($0, kAXMinimizedAttribute) }
        guard others.count + 1 >= Self.minimumWindows else { return }

        sessions[pid] = Session(pending: [window])
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.hide()
        }
        scheduleFlush(pid, attempt: 1)
    }

    /// Brings the collected windows back once the burst is over and the app is really hidden.
    /// While the app is still minimizing its own windows (⌥⌘M), restoring them fights its loop;
    /// once it is quiet, restoring behind the hidden app is unseen and the app stays hidden.
    private func scheduleFlush(_ pid: pid_t, attempt: Int) {
        queue.asyncAfter(deadline: .now() + Self.hideSettleDelay) { self.flush(pid, attempt: attempt) }
    }

    private func flush(_ pid: pid_t, attempt: Int) {
        guard var session = sessions[pid] else { return }
        // Still minimizing: a newer event has its own flush coming.
        guard Date().timeIntervalSince(session.lastEvent) >= Self.hideSettleDelay * 0.9 else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard Self.bool(app, kAXHiddenAttribute) else {
            // Not hidden (yet, or the app came back on its own): never restore in plain sight.
            // The windows then stay minimized, as macOS left them.
            if attempt < 8 {
                scheduleFlush(pid, attempt: attempt + 1)
            } else {
                sessions[pid] = nil
            }
            return
        }
        let windows = session.pending.filter { Self.bool($0, kAXMinimizedAttribute) }
        session.pending.removeAll()
        sessions[pid] = session
        windows.forEach(restore)
        // Keep the session a moment so late notifications of this burst are still collected.
        queue.asyncAfter(deadline: .now() + Self.sessionQuietTime) {
            guard let current = self.sessions[pid], current.pending.isEmpty,
                  Date().timeIntervalSince(current.lastEvent) >= Self.sessionQuietTime else { return }
            self.sessions[pid] = nil
        }
    }

    /// Brings a window back while its app is hidden: no animation is seen, the app stays hidden,
    /// and the window shows with the others when the app comes back.
    private func restore(_ window: AXUIElement) {
        AXUIElementSetMessagingTimeout(window, 0.5)
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    // MARK: - AX helpers

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Regular document windows (no panels, sheets or palettes).
    private static func standardWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
    }
}
