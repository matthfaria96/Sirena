// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchTourStrings {
    let preview: String
    let caption: String
}

extension IslandStrings {
    static func notchTour(_ language: IslandLanguage) -> NotchTourStrings {
        return NotchTourStrings(preview: L("Preview for 3.4"),
            caption: L("Control music, timers, volume and brightness. Choose the floating shortcuts you use most."))
    }
}
