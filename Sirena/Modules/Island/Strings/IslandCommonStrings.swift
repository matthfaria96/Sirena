// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena: the few app-wide Vorssaint strings the island shows.

import Foundation

struct IslandCommonStrings {
    var keepAwakeTitle: String { L("Keep awake") }
    var micMutedHUD: String { L("Microphone muted") }
    var actionClear: String { L("Clear") }
    var actionMute: String { L("Mute") }
    var actionPause: String { L("Pause") }
    var actionSearch: String { L("Search") }
    var actionUnmute: String { L("Unmute") }
    var mediaCancel: String { L("Cancel") }
    var mediaOpenInFinder: String { L("Show") }
    var menuSettings: String { L("Settings…") }
    var micMuteName: String { L("Mute microphone") }
    var micUnmuteName: String { L("Unmute microphone") }
    var mixerOutputUnavailable: String { L("Output unavailable") }
    var mixerSection: String { L("Volume mixer") }
    var mixerSystemOutputTitle: String { L("Output") }
    var obBack: String { L("Back") }
    var permissionOpenSettings: String { L("Open System Settings…") }
    var shelfActionOpen: String { L("Open") }
    var supportIntroDoneButton: String { L("Done") }
    var uninstallerCancel: String { L("Cancel") }
    var updateBannerAction: String { L("Update") }
    var keepAwakeEndsIn: String { L("Ends in") }
    var keepAwakeUntilDisabled: String { L("Active until you turn it off") }
    var permissionAccessibility: String { L("Accessibility") }
    var permissionMissing: String { L("Not granted") }
    var permissionRequest: String { L("Grant access") }
    var noResults: String { L("No results") }
    var micUnmutedHUD: String { L("Mute off") }
    var powerPluggedIn: String { L("Plugged in") }
}

extension IslandL10n {
    var s: IslandCommonStrings { IslandCommonStrings() }
}

struct IslandMediaStrings {
    var mediaLabel: String { L("Control") }
    var mediaPlayPause: String { L("Play or pause") }
    var mediaPrevious: String { L("Previous track") }
    var mediaNext: String { L("Next track") }
    var mediaNowPlaying: String { L("Now Playing") }
    var mediaNothingPlaying: String { L("Nothing playing") }
    var mediaOpenAppFormat: String { L("Open %@") }
}

extension IslandStrings {
    static func radialMenu(_ language: IslandLanguage) -> IslandMediaStrings { IslandMediaStrings() }
}

struct IslandBrightnessStrings {
    var noDisplays: String { L("No display found.") }
    var keyboardLight: String { L("Keyboard light") }
}

extension IslandStrings {
    static func brightness(_ language: IslandLanguage) -> IslandBrightnessStrings { IslandBrightnessStrings() }
}
