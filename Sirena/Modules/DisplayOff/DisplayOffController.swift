/// DisplayOffController.swift
///
/// Turns the display off after a short countdown, so there is time to let go of the
/// mouse (any movement afterwards wakes it again). Uses macOS's own
/// `pmset displaysleepnow`, which needs no administrator rights.

import AppKit
import Combine

@MainActor
final class DisplayOffController: ObservableObject {
    static let shared = DisplayOffController()

    static let delayKey = "displayOff.delaySeconds"
    static let defaultDelay = 10

    /// The waits offered, in seconds (0 = right away).
    static let delays: [(seconds: Int, title: String)] = [
        (0, L("Right away")),
        (3, L("3 seconds")),
        (5, L("5 seconds")),
        (10, L("10 seconds")),
        (30, L("30 seconds"))
    ]

    /// Seconds left before the display goes off; nil when no countdown is running.
    @Published private(set) var remaining: Int?

    private var timer: Timer?

    var isCounting: Bool { remaining != nil }

    var delay: Int {
        let stored = UserDefaults.standard.object(forKey: Self.delayKey) as? Int
        return max(0, stored ?? Self.defaultDelay)
    }

    // MARK: - Lifecycle

    func start() {}

    func terminate() {
        cancel()
    }

    // MARK: - Countdown

    func toggle() {
        isCounting ? cancel() : begin()
    }

    func begin() {
        cancel()
        guard delay > 0 else { return turnOff() }
        remaining = delay
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        remaining = nil
    }

    private func tick() {
        guard let remaining else { return cancel() }
        if remaining <= 1 {
            cancel()
            turnOff()
        } else {
            self.remaining = remaining - 1
        }
    }

    private func turnOff() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
        } catch {
            NSLog("Sirena display off: pmset failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Texts

    /// "Turns the screen off after 10 seconds." / "Turns the screen off right away."
    var summary: String {
        delay == 0 ? L("Turns the screen off right away.") : L("Turns the screen off after \(delay) seconds.")
    }

    /// Shorter, for the narrow menu bar menu.
    var shortSummary: String {
        delay == 0 ? L("Turns off right away") : L("Turns off after \(delay) s")
    }

    /// The button: what a click does now.
    var buttonTitle: String {
        if let remaining { return L("Cancel (\(remaining) s)") }
        return delay == 0 ? L("Turn Off Now") : L("Turn off in \(delay) s")
    }

    /// One line of state for Home.
    var statusText: String {
        if let remaining { return L("Turning off in \(remaining) s") }
        return summary
    }
}
