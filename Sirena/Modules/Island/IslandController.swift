// SPDX-License-Identifier: GPL-3.0-or-later
// Sirena's entry point to the Dynamic Island ported from Vorssaint
// (Copyright (C) 2026 Vorssaint, GPL-3.0-or-later).

import AppKit

/// Starts and stops the Dynamic Island. Everything else about it is read from
/// its own preferences (`IslandKey`), which `IslandSettingsView` edits and the
/// island follows as they change.
@MainActor
final class IslandController {
    static let shared = IslandController()

    private(set) var isRunning = false

    /// Read by the island's own code, which runs outside the main actor's
    /// checking: on while the module runs.
    nonisolated(unsafe) static var isActive = false

    /// What the island's "Settings…" actions open. Sirena points this at the
    /// Dynamic Island page; without it they only close the island.
    nonisolated(unsafe) static var openSettingsHandler: (() -> Void)?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        IslandDefaults.register()
        Self.isActive = true
        NotchControlItem.keyboardLightIsSupported = { IslandBrightness.shared.hasKeyboardLight }
        NotchService.shared.syncWithPreferences()
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        Self.isActive = false
        NotchService.shared.stop()
        NotchMusicService.shared.stop()
        NotchLyricsService.shared.stop()
        IslandCameraPreviewService.shared.hideEmbedded()
        NotchAudioLevelService.shared.stop()
        IslandPeripheralMonitor.shared.setMonitoring(false)
    }

    /// Opens the island, as its shortcut does.
    func toggleIsland() {
        guard isRunning else { return }
        NotchService.shared.toggleFromShortcut()
    }
}
