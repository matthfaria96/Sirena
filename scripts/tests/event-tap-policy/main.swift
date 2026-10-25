// Focused tests for DockKit/Utilities/EventTapPolicy.swift (the decisions behind
// AccessibilityGuard). No app, no TCC: compiled together with that file by
// scripts/test-event-tap-policy.sh.

import Foundation

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

// Untrusted: never re-enable, whatever the reason, and never spend budget.
do {
    var consulted = false
    for kind in [EventTapDisableKind.timeout, .userInput] {
        let action = EventTapPolicy.action(for: kind, trusted: false) { consulted = true; return true }
        expect(action == .tearDown, "untrusted \(kind) must tear down, got \(action)")
    }
    expect(!consulted, "untrusted must not consult the limiter")
}

// Trusted, switched off (by the owner or the system): never re-enabled in the callback.
do {
    var consulted = false
    let action = EventTapPolicy.action(for: .userInput, trusted: true) { consulted = true; return true }
    expect(action == .deferToGuard, "trusted userInput must defer to the guard, got \(action)")
    expect(!consulted, "userInput must not spend re-enable budget")
}

// Trusted timeout: re-enable while the limiter allows it, tear down after.
do {
    expect(EventTapPolicy.action(for: .timeout, trusted: true) { true } == .reEnable, "trusted timeout under budget re-enables")
    expect(EventTapPolicy.action(for: .timeout, trusted: true) { false } == .tearDown, "trusted timeout over budget tears down")
}

// Limiter: 3 per 60 s, sliding.
do {
    var limiter = EventTapReEnableLimiter(limit: 3, window: 60)
    expect(limiter.allow(at: 0), "1st allowed")
    expect(limiter.allow(at: 1), "2nd allowed")
    expect(limiter.allow(at: 2), "3rd allowed")
    expect(!limiter.allow(at: 3), "4th within the window refused")
    expect(!limiter.allow(at: 59.9), "still refused just before the first stamp expires")
    expect(limiter.allow(at: 60), "allowed once the first stamp is 60 s old")
    expect(!limiter.allow(at: 60.5), "refused again: three stamps in the window")
    expect(limiter.allow(at: 200), "allowed after a quiet period")
}

// Limiter: refusals don't consume budget, and a clock going backwards doesn't wedge it.
do {
    var limiter = EventTapReEnableLimiter(limit: 1, window: 10)
    expect(limiter.allow(at: 100), "first allowed")
    for t in stride(from: 100.5, to: 109.9, by: 1) { _ = limiter.allow(at: t) }
    expect(limiter.allow(at: 110), "refusals did not extend the window")
    var backwards = EventTapReEnableLimiter(limit: 1, window: 10)
    expect(backwards.allow(at: 500), "allowed")
    expect(backwards.allow(at: 5), "stamps from the future are dropped")
}

// Policy + limiter together: a tap timing out in a loop gets at most `limit` re-enables.
do {
    var limiter = EventTapReEnableLimiter(limit: 3, window: 60)
    var reEnables = 0
    for second in 0..<30 {
        let action = EventTapPolicy.action(for: .timeout, trusted: true) { limiter.allow(at: TimeInterval(second)) }
        if action == .reEnable { reEnables += 1 }
    }
    expect(reEnables == 3, "a timeout storm re-enables 3 times per minute, got \(reEnables)")
}

// Trust tracker: edges only.
do {
    var tracker = AccessibilityTrustTracker(initial: true)
    expect(tracker.update(true) == nil, "no edge while trusted")
    expect(tracker.update(false) == .lost, "lost")
    expect(tracker.update(false) == nil, "no edge while untrusted")
    expect(!tracker.trusted, "state follows samples")
    expect(tracker.update(true) == .regained, "regained")
    var untrusted = AccessibilityTrustTracker(initial: false)
    expect(untrusted.update(false) == nil, "starting untrusted is not an edge")
    expect(untrusted.update(true) == .regained, "first grant is an edge")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
