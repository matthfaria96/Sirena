/// KeepAwakeModule.swift
///
/// App-side glue for sleep prevention, ported from Caffeine (MIT).
/// Caffeine's own menu bar icon is replaced by the Sirena menu.

import AppKit

@MainActor
final class KeepAwakeModule {
    static let shared = KeepAwakeModule()

    let viewModel = CaffeineViewModel()
    private(set) var isRunning = false

    /// The durations Caffeine offered in its menu, in minutes (0 = indefinitely).
    static let durations: [(minutes: Int, title: String)] = [
        (0, String(localized: "Indefinitely")),
        (5, String(localized: "5 minutes")),
        (10, String(localized: "10 minutes")),
        (15, String(localized: "15 minutes")),
        (30, String(localized: "30 minutes")),
        (60, String(localized: "1 hour")),
        (120, String(localized: "2 hours")),
        (300, String(localized: "5 hours"))
    ]

    func start() {
        isRunning = true
    }

    func terminate() {
        viewModel.deactivate()
    }
}
