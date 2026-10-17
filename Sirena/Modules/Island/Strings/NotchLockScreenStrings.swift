// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchLockScreenStrings {
    /// The name System Settings gives its own Lock Screen pane.
    let title: String
    let show: String
    let showHint: String
    let sounds: String
    let soundsHint: String
    /// Beside the names of the agents working while the Mac is locked.
    let working: String
}

extension IslandStrings {
    static func notchLockScreen(_ language: IslandLanguage) -> NotchLockScreenStrings {
        return NotchLockScreenStrings(
            title: L("Lock Screen"),
            show: L("Show on the Lock Screen"),
            showHint: L("Music and the Dynamic Island’s activities, like a timer, downloads and your next event, appear above the password field. Anyone who can see your screen can read them."),
            sounds: L("Lock and unlock sounds"),
            soundsHint: L("Play the macOS padlock sound when your Mac locks and unlocks."),
            working: L("Working"))
    }
}
