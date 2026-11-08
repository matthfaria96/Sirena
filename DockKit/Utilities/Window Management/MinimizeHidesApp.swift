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
    /// Windows of apps that come back on their own when a window is restored while hidden
    /// (Catalyst apps such as WhatsApp): they stay minimized until the app is shown again.
    private var deferred: [pid_t: [AXUIElement]] = [:]
    /// Bundle ids of those apps, learned the first time it happens.
    private static let restoreOnShowKey = "minimizeHidesApp.restoreOnShow"

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self?.queue.async { self?.restoreDeferred(pid) }
        }
    }

    private static func restoresOnShow(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return UserDefaults.standard.stringArray(forKey: restoreOnShowKey)?.contains(bundleID) == true
    }

    /// Whether a window brought back behind this hidden app would show anyway: apps that
    /// learned it, and every Electron app (Discord, Slack, VS Code…), which puts a restored
    /// window back on screen while the app stays marked hidden.
    private static func restoresOnShow(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if restoresOnShow(app.bundleIdentifier) { return true }
        guard let url = app.bundleURL else { return false }
        let electron = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: electron.path)
    }

    /// The app has a regular window on screen right now (window server, not the app).
    private static func hasWindowOnScreen(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Width"] ?? 0) >= 100 && (bounds["Height"] ?? 0) >= 100
        }
    }

    private static func learnRestoresOnShow(_ bundleID: String?) {
        guard let bundleID, !restoresOnShow(bundleID) else { return }
        UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: restoreOnShowKey) ?? []) + [bundleID],
                                  forKey: restoreOnShowKey)
    }

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
        let running = NSRunningApplication(processIdentifier: pid)
        if Self.restoresOnShow(running) {
            deferred[pid, default: []] += windows
            log.notice("pid \(pid, privacy: .public): \(windows.count, privacy: .public) windows come back when the app is shown")
        } else {
            log.notice("pid \(pid, privacy: .public): bringing \(windows.count, privacy: .public) windows back behind the hidden app")
            windows.forEach { restore($0, pid: pid, attempt: 1) }
            queue.asyncAfter(deadline: .now() + 0.5) { self.checkStaysAway(pid, windows: windows, attempt: 1) }
        }
        // Keep the session a moment so late notifications of this burst are still collected.
        queue.asyncAfter(deadline: .now() + Self.sessionQuietTime) {
            guard let current = self.sessions[pid], current.pending.isEmpty,
                  Date().timeIntervalSince(current.lastEvent) >= Self.sessionQuietTime else { return }
            self.sessions[pid] = nil
        }
    }

    /// Brings a window back while its app is hidden: no animation is seen, the app stays hidden,
    /// and the window shows with the others when the app comes back.
    private func restore(_ window: AXUIElement, pid: pid_t, attempt: Int, whileHidden: Bool = true) {
        // The user brought the app back meanwhile: macOS restores the rest its own way.
        if whileHidden, NSRunningApplication(processIdentifier: pid)?.isHidden != true { return }
        AXUIElementSetMessagingTimeout(window, 1.0)
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        // Still busy (finishing its own minimizing): try again shortly.
        if result == .cannotComplete, attempt < 6 {
            queue.asyncAfter(deadline: .now() + 0.3) { self.restore(window, pid: pid, attempt: attempt + 1, whileHidden: whileHidden) }
        } else if result != .success {
            log.error("pid \(pid, privacy: .public): could not bring a window back (\(result.rawValue, privacy: .public))")
        }
    }

    /// After bringing windows back behind a hidden app, make sure nothing shows. An app may
    /// show itself again (it unhides), or put the window on screen while still marked hidden
    /// (Electron, which is caught beforehand, or others). Either way the app is remembered and,
    /// from then on, its windows stay minimized until it is shown.
    private func checkStaysAway(_ pid: pid_t, windows: [AXUIElement], attempt: Int) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if !app.isHidden {
            log.notice("pid \(pid, privacy: .public): came back on its own, hidden again; restoring on show from now on")
            Self.learnRestoresOnShow(app.bundleIdentifier)
            DispatchQueue.main.async { app.hide() }
            return
        }
        if Self.hasWindowOnScreen(pid: pid) {
            log.notice("pid \(pid, privacy: .public): window on screen while hidden, minimized again; restoring on show from now on")
            Self.learnRestoresOnShow(app.bundleIdentifier)
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 1.0)
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
            deferred[pid, default: []] += windows
            return
        }
        // Slow apps take a moment to put the window back: look once more.
        if attempt < 3 {
            queue.asyncAfter(deadline: .now() + 0.5) { self.checkStaysAway(pid, windows: windows, attempt: attempt + 1) }
        }
    }

    /// The app was shown (Dock, ⌘ Tab): bring back the windows kept minimized for it.
    private func restoreDeferred(_ pid: pid_t) {
        guard let windows = deferred.removeValue(forKey: pid), !windows.isEmpty else { return }
        log.notice("pid \(pid, privacy: .public): shown, bringing \(windows.count, privacy: .public) windows back")
        windows.forEach { restore($0, pid: pid, attempt: 1, whileHidden: false) }
    }
}
