// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchEditorStrings {
    let layout: String
    let content: String
    let activity: String
    let behavior: String
    let layoutHint: String
    let addButton: String
    let editButton: String
    let removeButton: String
    let buttonName: String
    let position: String
    let bottom: String
    let sectionActions: String
    let quickActions: String
    let findAction: String
    let reorderHint: String
    let opening: String
    let clickOpen: String
    let hoverPreview: String
    let hoverExpand: String
    let hiddenUntilHover: String
    let resting: String
    let destinations: String
    let separate: String
    let feedback: String
    let privacy: String
    let reopening: String
    let lastPage: String
    let openActivity: String
    let openActivityHint: String
    let activationTime: String
    let activationTimeHint: String
    let activationTimeFormat: String
    let closeTime: String
    let closeTimeHint: String
    let enableFeatureFormat: String
    let enableSettingFormat: String
    let showPageFormat: String
    let keyboardLightUnavailable: String
    let appPanelHint: String
    let hideMenuBarIcon: String
    let hideMenuBarIconHint: String
    let sections: String
    let sectionsHint: String
    let preview: String
    let hiddenInIsland: String
    let openFeatures: String
    let cameraPreview: String
    let noOptions: String
    let controlsSummary: String
    let mixerSummary: String
    let musicSummary: String
    let clipboardSummary: String
    let capturesSummary: String
    let filesSummary: String
    let systemSummary: String
    let toolsSummary: String
    let calendarSummary: String
    let notificationsSummary: String
    let timerSummary: String
    let cameraSummary: String
    let downloadsSummary: String
    let scratchpadSummary: String
    let agentsSummary: String
    let watchSummary: String

    func enableFeature(_ title: String) -> String { String(format: enableFeatureFormat, title) }
    func enableSetting(_ title: String) -> String { String(format: enableSettingFormat, title) }
    func showPage(_ title: String) -> String { String(format: showPageFormat, title) }

    /// One line on what a section of the island shows.
    func summary(_ module: NotchModule) -> String {
        switch module {
        case .controls: return controlsSummary
        case .music: return musicSummary
        case .calendar: return calendarSummary
        case .notifications: return notificationsSummary
        case .timer: return timerSummary
        case .camera: return cameraSummary
        case .downloads: return downloadsSummary
        }
    }
}

extension IslandStrings {
    static func notchEditor(_ language: IslandLanguage) -> NotchEditorStrings {
        return NotchEditorStrings(
            layout: L("Layout"),
            content: L("Content"),
            activity: L("Activity"),
            behavior: L("Behavior"),
            layoutHint: L("Click + to add a button. Drag buttons around the island. Click a button to edit it."),
            addButton: L("Add button"),
            editButton: L("Edit button"),
            removeButton: L("Remove button"),
            buttonName: L("Name"),
            position: L("Position"),
            bottom: L("Bottom"),
            sectionActions: L("Open a section"),
            quickActions: L("Quick actions"),
            findAction: L("Find an action"),
            reorderHint: L("Drag to reorder. Click the checkmark to show or hide."),
            opening: L("Opening"),
            clickOpen: L("Click to open"),
            hoverPreview: L("Preview on hover"),
            hoverExpand: L("Expand on hover"),
            hiddenUntilHover: L("Hidden until hover"),
            resting: L("At rest"),
            destinations: L("Where things open"),
            separate: L("Separate window"),
            feedback: L("Indicators"),
            privacy: L("Privacy"),
            reopening: L("When reopening"),
            lastPage: L("Last page"),
            openActivity: L("Open the visible activity"),
            openActivityHint: L("When the closed island shows music, a timer or another activity, it opens on that page instead."),
            activationTime: L("Activation time"),
            activationTimeHint: L("Keep the pointer over the island for this long to open it."),
            activationTimeFormat: L("%.2f s"),
            closeTime: L("Closing time"),
            closeTimeHint: L("Wait this long after the pointer leaves the island before closing it."),
            enableFeatureFormat: L("Enable “%@” in Features."),
            enableSettingFormat: L("Enable “%@” in its settings."),
            showPageFormat: L("Show “%@” on the Content tab."),
            keyboardLightUnavailable: L("Keyboard backlight control is unavailable on this Mac."),
            appPanelHint: L("Choose where clicking the Sirena menu bar icon opens the app panel, on any display."),
            hideMenuBarIcon: L("Hide the menu bar icon"),
            hideMenuBarIconHint: L("Settings and the app panel open from Dynamic Island. The icon returns when the island is off or hidden in full screen, or when an update is ready or the microphone is muted."),
            sections: L("Sections"),
            sectionsHint: L("Drag to reorder. Uncheck a section to hide it from the island."),
            preview: L("Preview"),
            hiddenInIsland: L("Hidden from the island"),
            openFeatures: L("Open Features"),
            cameraPreview: L("The camera turns on only in the island."),
            noOptions: L("This section has no options."),
            controlsSummary: L("Playback, volume, brightness and your shortcuts."),
            mixerSummary: L("The volume of each app, and where sound plays."),
            musicSummary: L("The song playing now, with its controls."),
            clipboardSummary: L("What you copied recently, ready to paste again."),
            capturesSummary: L("Your latest screenshots and recordings."),
            filesSummary: L("A shelf for the files you drop on the island."),
            systemSummary: L("CPU, memory, disk, network and battery at a glance."),
            toolsSummary: L("Tools and utilities, one click away."),
            calendarSummary: L("Today’s events and the month ahead."),
            notificationsSummary: L("Your Mac’s notifications, kept in the island."),
            timerSummary: L("Timer, Pomodoro and stopwatch."),
            cameraSummary: L("A mirror to check yourself before a call."),
            downloadsSummary: L("Downloads in progress and just finished."),
            scratchpadSummary: L("Quick notes that save by themselves."),
            agentsSummary: L("Claude Code, Codex, OpenCode and GitHub Copilot usage, limits and costs."),
            watchSummary: L("Any part of a window, read live, with an alert when it changes.")
        )
    }
}
