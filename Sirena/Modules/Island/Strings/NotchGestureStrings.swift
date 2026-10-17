// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchGestureStrings {
    let title: String
    let description: String
    let hint: String
}

extension IslandStrings {
    static func notchGestures(_ language: IslandLanguage) -> NotchGestureStrings {
        return NotchGestureStrings(
            title: L("Dynamic Island Gestures"),
            description: L("Open and close the Dynamic Island with scrolling, and swipe to change tracks."),
            hint: L("Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Lists keep their own scrolling."))
    }
}
