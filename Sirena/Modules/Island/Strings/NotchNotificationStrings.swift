// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchNotificationStrings {
    let title: String
    let description: String
    let privacy: String
    let empty: String
    let waiting: String
    let open: String
    let dismiss: String
    let clearAll: String
    let unavailable: String
    let hideSystemBanner: String
    let hideSystemBannerHint: String
}

extension IslandStrings {
    static func notchNotifications(_ language: IslandLanguage) -> NotchNotificationStrings {
        return NotchNotificationStrings(
            title: L("Notifications"),
            description: L("New system notifications in the Dynamic Island."),
            privacy: L("Show new visible banners only. Messages stay in memory and are cleared when you lock this Mac or turn this off."),
            empty: L("New notifications will appear here"),
            waiting: L("Waiting for the system notification service"),
            open: L("Open"),
            dismiss: L("Dismiss"),
            clearAll: L("Clear All"),
            unavailable: L("This notification can no longer accept this action."),
            hideSystemBanner: L("Hide the system banner"),
            hideSystemBannerHint: L("Hide the original while the Dynamic Island shows it."))
    }
}
