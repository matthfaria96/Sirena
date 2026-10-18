/// PomodoroController.swift
/// Clean-room focus timer: focus sessions, short and long breaks.

import AppKit
import MASShortcut
import SwiftUI
import UserNotifications

enum PomodoroPhase: String {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: L("Focus")
        case .shortBreak: L("Short Break")
        case .longBreak: L("Long Break")
        }
    }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .focus: .red
        case .shortBreak: .green
        case .longBreak: .teal
        }
    }
}

/// Persisted preferences (UserDefaults, keys prefixed `pomodoro.`).
@MainActor
@Observable
final class PomodoroSettings {
    static let shared = PomodoroSettings()
    static let sounds = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Funk", "Blow", "Bottle", "Frog", "Pop", "Sosumi", "Tink"]

    @ObservationIgnored private let defaults = UserDefaults.standard

    var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "pomodoro.focusMinutes") } }
    var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: "pomodoro.shortBreakMinutes") } }
    var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "pomodoro.longBreakMinutes") } }
    var sessionsBeforeLongBreak: Int { didSet { defaults.set(sessionsBeforeLongBreak, forKey: "pomodoro.sessionsBeforeLongBreak") } }
    var autoStartBreaks: Bool { didSet { defaults.set(autoStartBreaks, forKey: "pomodoro.autoStartBreaks") } }
    var autoStartFocus: Bool { didSet { defaults.set(autoStartFocus, forKey: "pomodoro.autoStartFocus") } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: "pomodoro.playSound") } }
    var soundName: String { didSet { defaults.set(soundName, forKey: "pomodoro.soundName") } }
    var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "pomodoro.soundVolume") } }
    var showNotifications: Bool { didSet { defaults.set(showNotifications, forKey: "pomodoro.showNotifications") } }
    var dailyGoal: Int { didSet { defaults.set(dailyGoal, forKey: "pomodoro.dailyGoal") } }

    private init() {
        defaults.register(defaults: [
            "pomodoro.focusMinutes": 25, "pomodoro.shortBreakMinutes": 5, "pomodoro.longBreakMinutes": 15,
            "pomodoro.sessionsBeforeLongBreak": 4, "pomodoro.autoStartBreaks": true, "pomodoro.autoStartFocus": false,
            "pomodoro.playSound": true, "pomodoro.soundName": "Glass", "pomodoro.soundVolume": 0.8,
            "pomodoro.showNotifications": true, "pomodoro.dailyGoal": 8
        ])
        focusMinutes = defaults.integer(forKey: "pomodoro.focusMinutes")
        shortBreakMinutes = defaults.integer(forKey: "pomodoro.shortBreakMinutes")
        longBreakMinutes = defaults.integer(forKey: "pomodoro.longBreakMinutes")
        sessionsBeforeLongBreak = defaults.integer(forKey: "pomodoro.sessionsBeforeLongBreak")
        autoStartBreaks = defaults.bool(forKey: "pomodoro.autoStartBreaks")
        autoStartFocus = defaults.bool(forKey: "pomodoro.autoStartFocus")
        playSound = defaults.bool(forKey: "pomodoro.playSound")
        soundName = defaults.string(forKey: "pomodoro.soundName") ?? "Glass"
        soundVolume = defaults.double(forKey: "pomodoro.soundVolume")
        showNotifications = defaults.bool(forKey: "pomodoro.showNotifications")
        dailyGoal = defaults.integer(forKey: "pomodoro.dailyGoal")
    }

    func minutes(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: max(1, focusMinutes)
        case .shortBreak: max(1, shortBreakMinutes)
        case .longBreak: max(1, longBreakMinutes)
        }
    }

    func playPreview() { PomodoroController.play(soundName, volume: soundVolume) }
}

/// Entry point of the module (Sirena contract: start, terminate, status, quick action).
@MainActor
@Observable
final class PomodoroController {
    static let shared = PomodoroController()
    static let toggleShortcutKey = "pomodoroShortcutToggle"
    static let skipShortcutKey = "pomodoroShortcutSkip"

    private(set) var isRunning = false
    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private let settings = PomodoroSettings.shared
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?

    private(set) var phase: PomodoroPhase = .focus
    /// True while the clock is ticking (not paused, not idle).
    private(set) var isTicking = false
    /// True once a phase has started (ticking or paused).
    private(set) var hasStarted = false {
        // The timer shows beside Sirena's menu bar icon for as long as a session is on.
        didSet { if hasStarted != oldValue { PomodoroMenuBarTimer.shared.setVisible(hasStarted) } }
    }
    private(set) var remaining: TimeInterval = 0
    /// Length of the current phase, fixed when it starts.
    private(set) var phaseTotal: TimeInterval = 0
    @ObservationIgnored private var endDate: Date?
    /// Focus sessions completed in the current cycle (resets after a long break).
    private(set) var cycleCount = 0
    private(set) var todayCount = 0
    private(set) var todayFocusSeconds: TimeInterval = 0

    private init() {
        loadToday()
        remaining = duration(of: .focus)
        phaseTotal = remaining
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PomodoroController.shared.rollTodayIfNeeded() }
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.bindShortcut(withDefaultsKey: Self.toggleShortcutKey) { [weak self] in self?.quickAction() }
        binder?.bindShortcut(withDefaultsKey: Self.skipShortcutKey) { [weak self] in self?.skip() }
        if !hasStarted { remaining = duration(of: phase); phaseTotal = remaining }
    }

    func terminate() {
        guard isRunning else { return }
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.toggleShortcutKey)
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.skipShortcutKey)
        reset()
        isRunning = false
    }

    /// Whether it is doing something right now (Home's check).
    var isActive: Bool { isRunning && isTicking }

    /// One live status line for Home.
    var statusText: String {
        let time = Self.format(remaining)
        if !hasStarted { return L("Ready — \(settings.minutes(for: .focus)) min focus") }
        if !isTicking { return L("Paused · \(phase.title) · \(time)") }
        return phase == .focus ? L("Focus · \(time) left") : L("Break · \(time)")
    }

    /// Fraction of the current phase already elapsed (0…1).
    var progress: Double {
        let total = hasStarted ? phaseTotal : duration(of: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    var remainingText: String { Self.format(remaining) }

    /// The main action, from Home, the sidebar card and the ⚡ menu.
    func quickAction() {
        isTicking ? pause() : resume()
    }

    func resume() {
        guard isRunning else { return }
        rollTodayIfNeeded()
        if !hasStarted { remaining = duration(of: phase); phaseTotal = remaining }
        // Asked when it is first needed, never at launch (it collided with the onboarding).
        if !hasStarted, settings.showNotifications { requestNotificationAuthorization() }
        hasStarted = true
        isTicking = true
        endDate = Date().addingTimeInterval(remaining)
        startTimer()
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isTicking = false
        endDate = nil
        stopTimer()
    }

    /// Back to an idle focus session; the cycle restarts.
    func reset() {
        stopTimer()
        isTicking = false
        hasStarted = false
        endDate = nil
        phase = .focus
        cycleCount = 0
        remaining = duration(of: .focus)
    }

    /// Ends the current phase now, without counting it as completed.
    func skip() {
        guard isRunning else { return }
        advance(completed: false)
    }

    /// Restarts the current phase from its full length.
    func restartPhase() {
        guard isRunning else { return }
        remaining = duration(of: phase)
        phaseTotal = remaining
        if isTicking { endDate = Date().addingTimeInterval(remaining) }
    }

    func select(_ newPhase: PomodoroPhase) {
        guard isRunning, newPhase != phase || hasStarted else { return }
        if phase == .focus && hasStarted { accountFocus(completed: false) }
        stopTimer()
        isTicking = false
        hasStarted = false
        endDate = nil
        phase = newPhase
        remaining = duration(of: newPhase)
        phaseTotal = remaining
    }

    /// Called when a duration setting changes so an idle timer shows the new length.
    func settingsChanged() {
        if !hasStarted { remaining = duration(of: phase); phaseTotal = remaining }
    }

    // MARK: - Clock

    private func duration(of phase: PomodoroPhase) -> TimeInterval {
        TimeInterval(settings.minutes(for: phase) * 60)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isTicking, let endDate else { return }
        rollTodayIfNeeded()
        let left = max(0, endDate.timeIntervalSinceNow)
        remaining = left.rounded(.up)
        if left <= 0 { advance(completed: true) }
    }

    private func advance(completed: Bool) {
        let finished = phase
        if finished == .focus {
            accountFocus(completed: completed)
        } else if finished == .longBreak {
            cycleCount = 0
        }

        let next: PomodoroPhase
        if finished == .focus {
            next = cycleCount >= max(1, settings.sessionsBeforeLongBreak) ? .longBreak : .shortBreak
        } else {
            next = .focus
        }

        if completed { announce(finished: finished, next: next) }

        stopTimer()
        phase = next
        remaining = duration(of: next)
        phaseTotal = remaining
        let autoStart = next == .focus ? settings.autoStartFocus : settings.autoStartBreaks
        if autoStart && (completed || isTicking) {
            hasStarted = true
            isTicking = true
            endDate = Date().addingTimeInterval(remaining)
            startTimer()
        } else {
            isTicking = false
            hasStarted = false
            endDate = nil
        }
    }

    // MARK: - Feedback

    private func announce(finished: PomodoroPhase, next: PomodoroPhase) {
        if settings.playSound { Self.play(settings.soundName, volume: settings.soundVolume) }
        guard settings.showNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = finished == .focus ? L("Focus session complete") : L("Break is over")
        content.body = next == .focus
            ? L("Time to focus for \(settings.minutes(for: .focus)) minutes.")
            : L("Take a \(settings.minutes(for: next))-minute break.")
        let request = UNNotificationRequest(identifier: "pomodoro.phase", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    static func play(_ name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(volume)
        sound.play()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Today's stats

    private static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func loadToday() {
        if defaults.string(forKey: "pomodoro.statsDay") == Self.dayKey() {
            todayCount = defaults.integer(forKey: "pomodoro.statsCount")
            todayFocusSeconds = defaults.double(forKey: "pomodoro.statsFocusSeconds")
        }
    }

    private func rollTodayIfNeeded() {
        guard defaults.string(forKey: "pomodoro.statsDay") != Self.dayKey() else { return }
        todayCount = 0
        todayFocusSeconds = 0
        saveToday()
    }

    private func accountFocus(completed: Bool) {
        rollTodayIfNeeded()
        todayFocusSeconds += max(0, completed ? phaseTotal : phaseTotal - remaining)
        if completed {
            todayCount += 1
            cycleCount += 1
        }
        saveToday()
    }

    private func saveToday() {
        defaults.set(Self.dayKey(), forKey: "pomodoro.statsDay")
        defaults.set(todayCount, forKey: "pomodoro.statsCount")
        defaults.set(todayFocusSeconds, forKey: "pomodoro.statsFocusSeconds")
    }

    func clearToday() {
        todayCount = 0
        todayFocusSeconds = 0
        saveToday()
    }
}
