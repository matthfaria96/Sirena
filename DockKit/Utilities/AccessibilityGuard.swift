/// AccessibilityGuard.swift
///
/// The one place that decides whether Sirena may hold CGEvent taps.
///
/// An active tap from a process that loses Accessibility can stall the whole Mac's input:
/// macOS switches the tap off, and a callback that switched it straight back on (or kept
/// waiting on other threads) fought the system on every click and key press. So:
///
/// - The guard polls `AXIsProcessTrusted()` every second on its own queue (plus the
///   `com.apple.accessibility.api` notice), independent of the main thread.
/// - When trust goes away it disables every registered tap right there, then tells the
///   owners (on the main thread) to invalidate their taps and pause. When trust comes back
///   the owners recreate their taps.
/// - Tap callbacks never re-enable a tap themselves: they hand disable notices to
///   `tapDisabled(_:type:name:)`, which re-enables only while trusted and rate-limited.
/// - Every tap is created only after `mayCreateTap(_:)` and registered with `register`.

import ApplicationServices
import CoreGraphics
import Foundation
import os

public final class AccessibilityGuard: @unchecked Sendable {
    public static let shared = AccessibilityGuard()

    /// Cached trust, cheap on any thread: tap callbacks read it for every event.
    public static var isTrusted: Bool { shared.trusted }

    /// Keeps an observer alive; invalidate it (or let it go) to stop receiving changes.
    public final class Observation {
        fileprivate let id = UUID()

        public func invalidate() {
            AccessibilityGuard.shared.removeObserver(id)
        }

        deinit { invalidate() }
    }

    private struct RegisteredTap {
        let port: CFMachPort
        let name: String
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.matheusfaria.Sirena.AccessibilityGuard", qos: .userInteractive)
    private let log = Logger(subsystem: "com.matheusfaria.Sirena", category: "AccessibilityGuard")
    private let pollInterval: TimeInterval = 1

    // Guarded by `lock`.
    private var tracker: AccessibilityTrustTracker
    private var taps: [ObjectIdentifier: RegisteredTap] = [:]
    private var limiters: [String: EventTapReEnableLimiter] = [:]
    private var refusedTaps: Set<String> = []
    private var observers: [UUID: @MainActor (Bool) -> Void] = [:]

    private var timer: DispatchSourceTimer?
    private var notificationObserver: NSObjectProtocol?

    private var trusted: Bool { lock.withLock { tracker.trusted } }

    private init() {
        let initial = AXIsProcessTrusted()
        tracker = AccessibilityTrustTracker(initial: initial)
        log.notice("Accessibility guard started: \(initial ? "trusted" : "not trusted", privacy: .public)")
        startPolling()
    }

    /// Creates the guard so it polls from launch (it starts on first use anyway).
    public func activate() {}

    // MARK: - Polling

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.evaluate() }
        timer.resume()
        self.timer = timer

        // Posted when the Accessibility list changes: check sooner than the next tick.
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.queue.asyncAfter(deadline: .now() + 0.25) { self?.evaluate() }
        }
    }

    /// Runs on `queue`.
    private func evaluate() {
        let sample = AXIsProcessTrusted()
        let (transition, ports) = lock.withLock { () -> (AccessibilityTrustTransition?, [CFMachPort]) in
            let transition = tracker.update(sample)
            if transition != nil { refusedTaps.removeAll() }
            return (transition, transition == .lost ? taps.values.map(\.port) : [])
        }
        guard let transition else { return }

        switch transition {
        case .lost:
            // Off first, from this thread: the owners' teardown runs on the main thread and
            // may come late, while a disabled tap never holds anyone's input.
            for port in ports {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            log.error("Accessibility revoked: disabled \(ports.count) event taps, pausing features")
        case .regained:
            log.notice("Accessibility granted: restarting features")
        }

        let isTrusted = transition == .regained
        let handlers = lock.withLock { Array(observers.values) }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in handlers {
                    handler(isTrusted)
                }
            }
        }
    }

    // MARK: - Observers

    /// `handler` runs on the main thread on every trust change: false means tear every tap
    /// down and pause, true means recreate them.
    public func observe(_ handler: @escaping @MainActor (Bool) -> Void) -> Observation {
        let observation = Observation()
        lock.withLock { observers[observation.id] = handler }
        return observation
    }

    fileprivate func removeObserver(_ id: UUID) {
        lock.withLock { _ = observers.removeValue(forKey: id) }
    }

    // MARK: - Taps

    /// Whether a tap may be created now. Both the cached state and a live check must agree;
    /// a refusal is logged once per tap until trust changes.
    public func mayCreateTap(_ name: String) -> Bool {
        let live = AXIsProcessTrusted()
        let (allowed, firstRefusal) = lock.withLock { () -> (Bool, Bool) in
            if live, tracker.trusted { return (true, false) }
            return (false, refusedTaps.insert(name).inserted)
        }
        if !allowed {
            if firstRefusal {
                log.notice("\(name, privacy: .public): no event tap without Accessibility")
            }
            if live != trusted {
                queue.async { [weak self] in self?.evaluate() }
            }
        }
        return allowed
    }

    public func register(_ tap: CFMachPort, name: String) {
        let trustedNow = lock.withLock { () -> Bool in
            taps[ObjectIdentifier(tap)] = RegisteredTap(port: tap, name: name)
            return tracker.trusted
        }
        if !trustedNow {
            // Trust went away while the tap was being created.
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        log.notice("\(name, privacy: .public): event tap created")
    }

    public func unregister(_ tap: CFMachPort) {
        let removed = lock.withLock { taps.removeValue(forKey: ObjectIdentifier(tap)) }
        if let removed {
            log.notice("\(removed.name, privacy: .public): event tap removed")
        }
    }

    private func isRegistered(_ tap: CFMachPort) -> Bool {
        lock.withLock { taps[ObjectIdentifier(tap)] != nil }
    }

    private func spendReEnable(_ name: String) -> Bool {
        lock.withLock { limiters[name, default: EventTapReEnableLimiter()].allow(at: ProcessInfo.processInfo.systemUptime) }
    }

    /// Call from a tap callback on `.tapDisabledByTimeout` / `.tapDisabledByUserInput`, then
    /// pass the event through. Never blocks: the tap is already off, and anything slower than
    /// the timeout path's live trust check happens on the guard's queue.
    public func tapDisabled(_ tap: CFMachPort?, type: CGEventType, name: String) {
        guard let tap else { return }
        let kind: EventTapDisableKind = type == .tapDisabledByTimeout ? .timeout : .userInput
        let trustedNow = kind == .timeout ? (trusted && AXIsProcessTrusted()) : trusted

        switch EventTapPolicy.action(for: kind, trusted: trustedNow, limiterAllows: { spendReEnable(name) }) {
        case .reEnable:
            guard isRegistered(tap) else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            log.notice("\(name, privacy: .public): event tap timed out, re-enabled")
        case .deferToGuard:
            // Usually the owner switching its own tap off on the way out (it unregisters
            // first). If the tap is still registered, valid and off a moment later, the
            // system did it: re-enable only after a fresh trust check.
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.reEnableAfterCheck(tap, name: name)
            }
        case .tearDown:
            if trustedNow {
                log.error("\(name, privacy: .public): event tap timed out too often, leaving it off")
            }
            queue.async { [weak self] in self?.evaluate() }
        }
    }

    /// Runs on `queue`.
    private func reEnableAfterCheck(_ tap: CFMachPort, name: String) {
        evaluate()
        guard isRegistered(tap), CFMachPortIsValid(tap), !CGEvent.tapIsEnabled(tap: tap) else { return }
        guard trusted, AXIsProcessTrusted() else { return }
        guard spendReEnable(name) else {
            log.error("\(name, privacy: .public): event tap keeps getting switched off, leaving it off")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        log.notice("\(name, privacy: .public): event tap switched off by the system, re-enabled")
    }
}

/// For tap callbacks: passes the event straight through when it is a disable notice (handed
/// to AccessibilityGuard) or when Sirena isn't trusted; nil means handle the event normally.
func passthroughIfTapUnsafe(tap: CFMachPort?, type: CGEventType, event: CGEvent, name: String) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        AccessibilityGuard.shared.tapDisabled(tap, type: type, name: name)
        return Unmanaged.passUnretained(event)
    }
    guard AccessibilityGuard.isTrusted else { return Unmanaged.passUnretained(event) }
    return nil
}
