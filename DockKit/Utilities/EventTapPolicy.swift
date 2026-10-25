/// EventTapPolicy.swift
///
/// Pure decisions behind AccessibilityGuard, kept free of AppKit and of any global state
/// so they can be tested on their own (scripts/test-event-tap-policy.sh).

import Foundation

/// Why macOS stopped delivering events to a tap.
enum EventTapDisableKind: Equatable {
    /// The callback took too long (kCGEventTapDisabledByTimeout).
    case timeout
    /// The tap was switched off: by its owner (tapEnable(false) reports this too) or by the
    /// system, for example when Accessibility is revoked (kCGEventTapDisabledByUserInput).
    case userInput
}

/// What happens to a tap that macOS reported as disabled.
enum EventTapDisableAction: Equatable {
    /// Re-enable the same port right away (timeout while trusted, under the rate limit).
    case reEnable
    /// Leave it off for now; AccessibilityGuard re-checks trust before anything else.
    case deferToGuard
    /// Leave it off for good: no trust, or it timed out too often.
    case tearDown
}

enum EventTapPolicy {
    /// `limiterAllows` is only consulted (and only spends budget) for a trusted timeout.
    static func action(for kind: EventTapDisableKind, trusted: Bool,
                       limiterAllows: () -> Bool) -> EventTapDisableAction {
        guard trusted else { return .tearDown }
        switch kind {
        case .userInput:
            return .deferToGuard
        case .timeout:
            return limiterAllows() ? .reEnable : .tearDown
        }
    }
}

/// Sliding-window limit: at most `limit` re-enables per `window` seconds.
struct EventTapReEnableLimiter: Equatable {
    let limit: Int
    let window: TimeInterval
    private var stamps: [TimeInterval] = []

    init(limit: Int = 3, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    /// Spends one re-enable at `now` when the budget allows it.
    mutating func allow(at now: TimeInterval) -> Bool {
        stamps.removeAll { now - $0 >= window || $0 > now }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }
}

/// Trust edges seen by the guard's poll.
enum AccessibilityTrustTransition: Equatable {
    case lost
    case regained
}

struct AccessibilityTrustTracker: Equatable {
    private(set) var trusted: Bool

    init(initial: Bool) {
        trusted = initial
    }

    /// Records a fresh sample; returns the edge it crossed, if any.
    mutating func update(_ sample: Bool) -> AccessibilityTrustTransition? {
        guard sample != trusted else { return nil }
        trusted = sample
        return sample ? .regained : .lost
    }
}
