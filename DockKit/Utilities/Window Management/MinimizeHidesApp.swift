/// MinimizeHidesApp.swift
///
/// Sirena: "Minimizar esconde todas as janelas do app". macOS animates minimizing and restoring
/// one window at a time inside the app itself (≈0.3 s each down, ≈0.4 s each back), so an app
/// with 8 windows takes seconds either way, and nothing outside the app can skip that. Hiding
/// the app takes every window away at once and brings them all back at once.
///
/// With the option on (the default), minimizing a window (yellow button, ⌘M, Minimize All) hides
/// the whole app right away, however many windows it has; the rest of a Minimize All then goes
/// by unseen and fast. The minimized windows are brought back while the app is hidden (invisible,
/// the app stays hidden), so the Dock icon or ⌘ Tab shows every window again together.
///
/// Driven by the Accessibility notification for minimized windows (no event tap). Everything runs
/// on its own queue: AX calls never touch the main thread or the observer callback.

import AppKit
import ApplicationServices
import Defaults
import os

private let log = Logger(subsystem: "com.matheusfaria.Sirena", category: "MinimizeHidesApp")

extension Defaults.Keys {
    static let minimizeHidesAllWindows = Key<Bool>(SirenaMinimize.hidesAppKey, default: true)
}

/// The minimize mode, as Sirena's Dock tab and Tweaks see it.
public enum SirenaMinimize {
    /// true: minimizing hides the app (all windows go and come back together).
    /// false: windows minimize to the Dock, as macOS does.
    public static let hidesAppKey = "minimizeHidesAllWindows"

    public static var hidesApp: Bool {
        UserDefaults.standard.object(forKey: hidesAppKey) as? Bool ?? true
    }
}

final class MinimizeHidesApp: @unchecked Sendable {
    static let shared = MinimizeHidesApp()

    /// From how many windows Sirena's own minimizing (option off) skips the animations.
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
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard Self.isEnabled else {
            log.notice("window minimized in pid \(pid, privacy: .public): option off")
            return
        }
        log.notice("window minimized in pid \(pid, privacy: .public)")
        queue.async { self.handle(window, pid: pid) }
    }

    // MARK: - On the queue

    private func handle(_ window: AXUIElement, pid: pid_t) {
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        if let until = ownMinimizeUntil[pid] {
            if until > Date() {
                log.notice("\(name, privacy: .public): minimized by Sirena itself, left alone")
                return
            }
            ownMinimizeUntil[pid] = nil
        }

        // Another window of the same burst (⌥⌘M goes through every window): collect it.
        if var session = sessions[pid] {
            session.lastEvent = Date()
            session.pending.append(window)
            sessions[pid] = session
            log.notice("\(name, privacy: .public): another window of the same burst")
            scheduleFlush(pid, attempt: 1)
            return
        }

        // Nothing here asks the app anything: while it animates (⌥⌘M goes window by window)
        // it answers Accessibility late or not at all, and the hide has to land right away.
        guard let running = NSRunningApplication(processIdentifier: pid), !running.isHidden else {
            log.notice("\(name, privacy: .public): window minimized while hidden, left alone")
            return
        }
        log.notice("\(name, privacy: .public): hiding the app")
        sessions[pid] = Session(pending: [window])
        DispatchQueue.main.async {
            running.hide()
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
        guard NSRunningApplication(processIdentifier: pid)?.isHidden == true else {
            // Not hidden (yet, or the app came back on its own): never restore in plain sight.
            // The windows then stay minimized, as macOS left them.
            if attempt < 8 {
                scheduleFlush(pid, attempt: attempt + 1)
            } else {
                log.error("pid \(pid, privacy: .public): the app never hid, windows left minimized")
                sessions[pid] = nil
            }
            return
        }
        let windows = session.pending
        // An earlier check already brought these back.
        guard !windows.isEmpty else { return }
        session.pending.removeAll()
        sessions[pid] = session
        log.notice("pid \(pid, privacy: .public): bringing \(windows.count, privacy: .public) windows back behind the hidden app")
        windows.forEach { restore($0, pid: pid, attempt: 1) }
        // Keep the session a moment so late notifications of this burst are still collected.
        queue.asyncAfter(deadline: .now() + Self.sessionQuietTime) {
            guard let current = self.sessions[pid], current.pending.isEmpty,
                  Date().timeIntervalSince(current.lastEvent) >= Self.sessionQuietTime else { return }
            self.sessions[pid] = nil
        }
    }

    /// Brings a window back while its app is hidden: no animation is seen, the app stays hidden,
    /// and the window shows with the others when the app comes back.
    private func restore(_ window: AXUIElement, pid: pid_t, attempt: Int) {
        // The user brought the app back meanwhile: macOS restores the rest its own way.
        guard NSRunningApplication(processIdentifier: pid)?.isHidden == true else { return }
        AXUIElementSetMessagingTimeout(window, 1.0)
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        // Still busy (finishing its own minimizing): try again shortly.
        if result == .cannotComplete, attempt < 6 {
            queue.asyncAfter(deadline: .now() + 0.3) { self.restore(window, pid: pid, attempt: attempt + 1) }
        } else if result != .success {
            log.error("pid \(pid, privacy: .public): could not bring a window back (\(result.rawValue, privacy: .public))")
        }
    }
}
