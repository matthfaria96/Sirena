// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchStrings {
    let title: String
    let combineActivities: String
    let enable: String
    let description: String
    let menuBarAccessHint: String
    let display: String
    let automatic: String
    let builtIn: String
    let mainDisplay: String
    let followPointer: String
    let allDisplays: String
    let hover: String
    let modules: String
    let events: String
    let clipboardActivity: String
    let captureActivity: String
    let privacy: String
    let open: String
    let collapse: String
    let pin: String
    let unpin: String
    let panel: String
    let dropHint: String
    let empty: String
    let volume: String
    let inputSource: String
    let brightness: String
    let battery: String
    let onBattery: String
    let charging: String
    let charged: String
    let lowBattery: String
    let controls: String
    let system: String
    let disabled: String
    let files: String
    let hideInFullscreen: String
    let showInCaptures: String
    let clipboardWindow: String
    let tools: String
    let size: String
    let showOutline: String
    let compact: String
    let spacious: String
    let hoverExpand: String
    let shelfWindow: String
    let dragReveal: String
    let captureControls: String
    let quickPanel: String
    let appPanel: String
    let idleContent: String
    let idleNone: String
    let coverMenus: String
    let coverMenusHint: String
    let controlShortcuts: String
    let activity: String
    let playingMusic: String
    let custom: String
    let width: String
    let maximumHeight: String
    let sizeHint: String
    let cameraFit: String
    let height: String
    let cameraFitHint: String
    let hideMenuBarGap: String
    let hideMenuBarGapHint: String
    let withoutNotch: String
    let capsuleShape: String
    let notchShape: String
    let capsuleFit: String
    let fromTop: String
    let capsuleFitHint: String
    let hapticFeedback: String
    let hapticHint: String
    let playbackPosition: String
    let musicHint: String
    let music: String
    let captures: String
    let newTrack: String
    let customizeTools: String
    let switchSection: String
    let sectionsTitle: String
    let searchSections: String
    let sectionKeyboardHint: String
    let quickAccessLeft: String
    let quickAccessRight: String
    let translucentBackground: String
    let translucentBackgroundHint: String
    let translucentBackgroundGlassHint: String
}

extension IslandStrings {
    static func notch(_ language: IslandLanguage) -> NotchStrings {
        return .enUS
    }
}

extension NotchStrings {
    static let enUS = NotchStrings(
        title: L("Dynamic Island"),
        combineActivities: L("Combine"),
        enable: L("Enable Dynamic Island"),
        description: L("Your music, controls and everyday tools, together at the top of your screen."),
        menuBarAccessHint: L("Allow Accessibility so Dynamic Island can appear on this display without covering the menus."),
        display: L("Display"),
        automatic: L("Automatic"),
        builtIn: L("Built-in display"),
        mainDisplay: L("Main display"),
        followPointer: L("Follow pointer"),
        allDisplays: L("All displays"),
        hover: L("Open when the pointer rests on the Dynamic Island"),
        modules: L("What appears"),
        events: L("More options"),
        clipboardActivity: L("Notify when something is copied"),
        captureActivity: L("Show screenshot previews here"),
        privacy: L("Copied content stays private until you open the clipboard. These options follow the original feature’s settings."),
        open: L("Open Dynamic Island"),
        collapse: L("Collapse"),
        pin: L("Keep open"),
        unpin: L("Allow automatic closing"),
        panel: L("Open app panel"),
        dropHint: L("Drop files here"),
        empty: L("Choose what appears in Dynamic Island settings."),
        volume: L("Volume"),
        inputSource: L("Input source"),
        brightness: L("Brightness"),
        battery: L("Battery"),
        onBattery: L("On battery"),
        charging: L("Charging"),
        charged: L("Fully charged"),
        lowBattery: L("Low battery"),
        controls: L("Controls"),
        system: L("System"),
        disabled: L("Enable the corresponding feature to use it here."),
        files: L("Files"),
        hideInFullscreen: L("Hide content in full screen"),
        showInCaptures: L("Show in screenshots and videos"),
        clipboardWindow: L("Open clipboard history in the Dynamic Island"),
        tools: L("Tools"),
        size: L("Size"),
        showOutline: L("Show outline"),
        compact: L("Compact"),
        spacious: L("Spacious"),
        hoverExpand: L("Expand fully on hover"),
        shelfWindow: L("Open the file shelf in the Dynamic Island"),
        dragReveal: L("Show a drop target while dragging"),
        captureControls: L("Show screen capture controls in the Dynamic Island"),
        quickPanel: L("Open the quick panel in the Dynamic Island"),
        appPanel: L("Open the app panel in the Dynamic Island"),
        idleContent: L("While inactive"),
        idleNone: L("Nothing"),
        coverMenus: L("Show over the menus"),
        coverMenusHint: L("Keeps the timer, music and other compact activity on screen when the menu bar has no room, covering the menus beside the camera."),
        controlShortcuts: L("Controls and shortcuts"),
        activity: L("Activity"),
        playingMusic: L("Show music while playing"),
        custom: L("Custom"),
        width: L("Width"),
        maximumHeight: L("Maximum height"),
        sizeHint: L("Controls stay compact. Longer lists use up to this height."),
        cameraFit: L("Notch fit"),
        height: L("Height"),
        cameraFitHint: L("If an edge of the notch shows around Dynamic Island, adjust these values until it disappears."),
        hideMenuBarGap: L("Hide gap below notch"),
        hideMenuBarGapHint: L("Extends Dynamic Island to the bottom of the menu bar to hide the thin strip below the notch."),
        withoutNotch: L("Displays without a notch"),
        capsuleShape: L("Capsule"),
        notchShape: L("Notch"),
        capsuleFit: L("Capsule fit"),
        fromTop: L("Distance from top"),
        capsuleFitHint: L("Resizes the capsule and lowers it from the top of the screen on displays without a notch."),
        hapticFeedback: L("Haptic feedback"),
        hapticHint: L("Gentle taps when opening, switching sections or adjusting timer minutes, on a compatible trackpad."),
        playbackPosition: L("Playback position"),
        musicHint: L("Your music and playback controls appear here."),
        music: L("Music"),
        captures: L("Captures"),
        newTrack: L("New track"),
        customizeTools: L("Customize tools"),
        switchSection: L("Switch section"),
        sectionsTitle: L("Explore"),
        searchSections: L("Find a section"),
        sectionKeyboardHint: L("Use the arrow keys, then press Return"),
        quickAccessLeft: L("Left"),
        quickAccessRight: L("Right"),
        translucentBackground: L("Translucent background"),
        translucentBackgroundHint: L("When open, Dynamic Island blurs what is behind it with the system’s own material."),
        translucentBackgroundGlassHint: L("Liquid Glass is on, so Dynamic Island uses it instead.")
    )















}
