// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct NotchLowBatteryStrings {
    let title: String
    let caption: String
    let threshold: String
    let early: String
    let earlyCaption: String
    let earlyThreshold: String
    let menuBar: String

    static func localized(_ language: IslandLanguage) -> NotchLowBatteryStrings {
        return .init(title: L("Turn red when low"), caption: L("Shows the charge in red at or below this level while on battery."),
                         threshold: L("Red level"), early: L("Turn amber first"),
                         earlyCaption: L("Shows the charge in amber at or below a higher level, as an early warning."),
                         earlyThreshold: L("Amber level"), menuBar: L("Also in the menu bar"))
    }
}
