// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena: the Dynamic Island's keys, defaults and language shim.

import Combine
import Foundation

/// Every UserDefaults key the island uses. All start with `island` and none
/// contains a dot, so they are safe as KVO key paths.
enum IslandKey {
    static let brightnessControlEnabled = "islandBrightnessControlEnabled"
    static let notchAccessoriesEnabled = "islandAccessoriesEnabled"
    static let notchAppPanel = "islandAppPanel"
    static let notchBattery = "islandBattery"
    static let notchBrightness = "islandBrightness"
    static let notchBrowserCovers = "islandBrowserCovers"
    static let notchCalendarChosenCountdowns = "islandCalendarChosenCountdowns"
    static let notchCalendarCountdown = "islandCalendarCountdown"
    static let notchCalendarEnabled = "islandCalendarEnabled"
    static let notchCalendarExcluded = "islandCalendarExcluded"
    static let notchCalendarTimeLeft = "islandCalendarTimeLeft"
    static let notchCalendarWeekNumbers = "islandCalendarWeekNumbers"
    static let notchCameraEnabled = "islandCameraEnabled"
    static let notchCameraFitHeight = "islandCameraFitHeight"
    static let notchCameraFitWidth = "islandCameraFitWidth"
    static let notchCapsuleFitDrop = "islandCapsuleFitDrop"
    static let notchCapsuleFitHeight = "islandCapsuleFitHeight"
    static let notchCapsuleFitWidth = "islandCapsuleFitWidth"
    static let notchCapture = "islandCapture"
    static let notchCaptureControls = "islandCaptureControls"
    static let notchCloseDelay = "islandCloseDelay"
    static let notchControlOrder = "islandControlOrder"
    static let notchCoversMenus = "islandCoversMenus"
    static let notchCustomHeight = "islandCustomHeight"
    static let notchCustomWidth = "islandCustomWidth"
    static let notchDismissNativeNotifications = "islandDismissNativeNotifications"
    static let notchDisplay = "islandDisplay"
    static let notchDownloadsEnabled = "islandDownloadsEnabled"
    static let notchDownloadsFolderBookmark = "islandDownloadsFolderBookmark"
    static let notchDragReveal = "islandDragReveal"
    static let notchGesturesEnabled = "islandGesturesEnabled"
    static let notchHapticFeedback = "islandHapticFeedback"
    static let notchHiddenControls = "islandHiddenControls"
    static let notchHiddenModules = "islandHiddenModules"
    static let notchHideInCaptures = "islandHideInCaptures"
    static let notchHideInFullscreen = "islandHideInFullscreen"
    static let notchHideMenuBarGap = "islandHideMenuBarGap"
    static let notchHideTimerCountdown = "islandHideTimerCountdown"
    static let notchHideUntilHover = "islandHideUntilHover"
    static let notchHidesMenuBarIcon = "islandHidesMenuBarIcon"
    static let notchHomeModule = "islandHomeModule"
    static let notchHoverDelay = "islandHoverDelay"
    static let notchHoverExpands = "islandHoverExpands"
    static let notchIdleContent = "islandIdleContent"
    static let notchIncludeOtherPlayers = "islandIncludeOtherPlayers"
    static let notchInputSource = "islandInputSource"
    static let notchKeepAwakeActivity = "islandKeepAwakeActivity"
    static let notchKeyboardLight = "islandKeyboardLight"
    static let notchKeyboardLightControlHidden = "islandKeyboardLightControlHidden"
    static let notchLiquidGlassEnabled = "islandLiquidGlassEnabled"
    static let notchLiveEqualizer = "islandLiveEqualizer"
    static let notchLockScreen = "islandLockScreen"
    static let notchLockSounds = "islandLockSounds"
    static let notchLowBatteryEarly = "islandLowBatteryEarly"
    static let notchLowBatteryEarlyThreshold = "islandLowBatteryEarlyThreshold"
    static let notchLowBatteryMenuBar = "islandLowBatteryMenuBar"
    static let notchLowBatteryThreshold = "islandLowBatteryThreshold"
    static let notchLowBatteryTint = "islandLowBatteryTint"
    static let notchLyricsEnabled = "islandLyricsEnabled"
    static let notchLyricsOnline = "islandLyricsOnline"
    static let notchMascotEnabled = "islandMascotEnabled"
    static let notchMascotHidesWhenIdle = "islandMascotHidesWhenIdle"
    static let notchMascotPalette = "islandMascotPalette"
    static let notchMascotReactions = "islandMascotReactions"
    static let notchMascotShape = "islandMascotShape"
    static let notchMascotSide = "islandMascotSide"
    static let notchMascotStyle = "islandMascotStyle"
    static let notchMascotVisitFrequency = "islandMascotVisitFrequency"
    static let notchMascotVisits = "islandMascotVisits"
    static let notchMicrophone = "islandMicrophone"
    static let notchModuleOrder = "islandModuleOrder"
    static let notchMusicActivity = "islandMusicActivity"
    static let notchNotificationsEnabled = "islandNotificationsEnabled"
    static let notchOpenOnHover = "islandOpenOnHover"
    static let notchOpensActivity = "islandOpensActivity"
    static let notchOutlineEnabled = "islandOutlineEnabled"
    static let notchPomodoroFocusMinutes = "islandPomodoroFocusMinutes"
    static let notchPomodoroLongBreakInterval = "islandPomodoroLongBreakInterval"
    static let notchPomodoroLongBreakMinutes = "islandPomodoroLongBreakMinutes"
    static let notchPomodoroShortBreakMinutes = "islandPomodoroShortBreakMinutes"
    static let notchPomodoroTotalSessions = "islandPomodoroTotalSessions"
    static let notchPreferredPlayer = "islandPreferredPlayer"
    static let notchQueueEnabled = "islandQueueEnabled"
    static let notchQuickAccessLayout = "islandQuickAccessLayout"
    static let notchQuickAccessSecond = "islandQuickAccessSecond"
    static let notchQuickAccessSide = "islandQuickAccessSide"
    static let notchQuickAccessThird = "islandQuickAccessThird"
    static let notchQuickPanel = "islandQuickPanel"
    static let notchReturnHome = "islandReturnHome"
    static let notchShelf = "islandShelf"
    static let notchShortcut = "islandShortcut"
    static let notchShortcutEnabled = "islandShortcutEnabled"
    static let notchShowInCaptures = "islandShowInCaptures"
    static let notchShowPlayingMusic = "islandShowPlayingMusic"
    static let notchSilhouette = "islandSilhouette"
    static let notchSize = "islandSize"
    static let notchTimerEnabled = "islandTimerEnabled"
    static let notchTimerMinutes = "islandTimerMinutes"
    static let notchTimerMode = "islandTimerMode"
    static let notchTimerSoundEnabled = "islandTimerSoundEnabled"
    static let notchTrackChange = "islandTrackChange"
    static let notchTranslucentBackground = "islandTranslucentBackground"
    static let notchVolume = "islandVolume"
}

/// Sirena localizes through `L(_:)`, so the island only ever renders one
/// language: the table lookup already picked the user's.
enum IslandLanguage: String, CaseIterable, Identifiable {
    case enUS = "en"
    var id: String { rawValue }
    var countAgreement: IslandCountAgreement { .oneAndMany }
    func formattingLocale(system: Locale = .autoupdatingCurrent) -> Locale { system }
    static var systemDefault: IslandLanguage { .enUS }
}

enum IslandCountAgreement { case oneAndMany, byLastDigits, byWholeNumber }

/// Namespace the ported string tables hang off.
enum IslandStrings {}

final class IslandL10n: ObservableObject {
    static let shared = IslandL10n()
    @Published var language: IslandLanguage = .enUS
    private init() {}
}

enum IslandDefaults {
    static let registered: [String: Any] = [
        IslandKey.brightnessControlEnabled: true,
        IslandKey.notchLiquidGlassEnabled: false,
        IslandKey.notchShowPlayingMusic: true,
        IslandKey.notchIncludeOtherPlayers: true,
        IslandKey.notchPreferredPlayer: "",
        IslandKey.notchIdleContent: NotchIdleContent.music.rawValue,
        IslandKey.notchHiddenControls: NotchControlItem.defaultHidden,
        IslandKey.notchKeyboardLightControlHidden: false,
        IslandKey.notchControlOrder: "",
        IslandKey.notchSize: NotchSize.spacious.rawValue,
        IslandKey.notchOutlineEnabled: false,
        IslandKey.notchHideMenuBarGap: false,
        IslandKey.notchCustomWidth: NotchSize.defaultWidth,
        IslandKey.notchCustomHeight: NotchSize.defaultHeight,
        IslandKey.notchCameraFitWidth: 0.0,
        IslandKey.notchCameraFitHeight: 0.0,
        IslandKey.notchHapticFeedback: true,
        IslandKey.notchTranslucentBackground: false,
        IslandKey.notchShelf: true,
        IslandKey.notchDragReveal: true,
        IslandKey.notchCaptureControls: true,
        IslandKey.notchQuickPanel: true,
        IslandKey.notchAppPanel: false,
        IslandKey.notchHidesMenuBarIcon: false,
        IslandKey.notchKeepAwakeActivity: false,
        IslandKey.notchHoverExpands: true,
        IslandKey.notchGesturesEnabled: true,
        IslandKey.notchKeyboardLight: true,
        IslandKey.notchNotificationsEnabled: true,
        IslandKey.notchDismissNativeNotifications: false,
        IslandKey.notchTimerEnabled: true,
        IslandKey.notchTimerMode: NotchTimerMode.timer.rawValue,
        IslandKey.notchTimerMinutes: 15,
        IslandKey.notchTimerSoundEnabled: true,
        IslandKey.notchHideTimerCountdown: false,
        IslandKey.notchPomodoroFocusMinutes: 25,
        IslandKey.notchPomodoroShortBreakMinutes: 5,
        IslandKey.notchPomodoroLongBreakMinutes: 15,
        IslandKey.notchPomodoroLongBreakInterval: 4,
        IslandKey.notchPomodoroTotalSessions: 4,
        IslandKey.notchCameraEnabled: true,
        IslandKey.notchAccessoriesEnabled: true,
        IslandKey.notchCalendarEnabled: true,
        IslandKey.notchCalendarCountdown: false,
        IslandKey.notchCalendarTimeLeft: false,
        IslandKey.notchCalendarWeekNumbers: false,
        IslandKey.notchCalendarExcluded: [String](),
        IslandKey.notchLyricsEnabled: true,
        IslandKey.notchLyricsOnline: false,
        IslandKey.notchBrowserCovers: false,
        IslandKey.notchLiveEqualizer: false,
        IslandKey.notchQueueEnabled: true,
        IslandKey.notchDownloadsEnabled: true,
        IslandKey.notchDisplay: NotchDisplay.automatic.rawValue,
        IslandKey.notchSilhouette: NotchSilhouette.capsule.rawValue,
        IslandKey.notchCapsuleFitWidth: 0.0,
        IslandKey.notchCapsuleFitHeight: 0.0,
        IslandKey.notchCapsuleFitDrop: 0.0,
        IslandKey.notchOpenOnHover: false,
        IslandKey.notchShortcutEnabled: false,
        IslandKey.notchHideInFullscreen: false,
        IslandKey.notchHideUntilHover: false,
        IslandKey.notchCoversMenus: true,
        IslandKey.notchLowBatteryTint: false,
        IslandKey.notchLowBatteryThreshold: NotchSupport.defaultLowBatteryThreshold,
        IslandKey.notchLowBatteryEarly: false,
        IslandKey.notchLowBatteryEarlyThreshold: NotchSupport.defaultEarlyBatteryThreshold,
        IslandKey.notchLowBatteryMenuBar: true,
        IslandKey.notchHoverDelay: NotchSupport.defaultHoverDelay,
        IslandKey.notchCloseDelay: NotchSupport.defaultCloseDelay,
        IslandKey.notchReturnHome: false,
        IslandKey.notchHomeModule: NotchModule.controls.rawValue,
        IslandKey.notchOpensActivity: true,
        IslandKey.notchHiddenModules: "",
        IslandKey.notchModuleOrder: "",
        IslandKey.notchQuickAccessLayout: Data(),
        IslandKey.notchVolume: true,
        IslandKey.notchInputSource: true,
        IslandKey.notchMicrophone: true,
        IslandKey.notchBrightness: true,
        IslandKey.notchBattery: true,
        IslandKey.notchCapture: true,
        IslandKey.notchTrackChange: true,
        IslandKey.notchMusicActivity: false,
        IslandKey.notchShowInCaptures: true,
        IslandKey.notchLockScreen: false,
        IslandKey.notchLockSounds: false,
        IslandKey.notchMascotEnabled: false,
        IslandKey.notchMascotVisits: true,
        IslandKey.notchMascotReactions: true,
        IslandKey.notchMascotStyle: NotchMascotStyle.minimal.rawValue,
        IslandKey.notchMascotShape: NotchMascotShape.ball.rawValue,
        IslandKey.notchMascotPalette: NotchMascotPalette.pearl.rawValue,
        IslandKey.notchMascotSide: NotchMascotSide.left.rawValue,
        IslandKey.notchMascotVisitFrequency: NotchMascotVisitFrequency.normal.rawValue,
        IslandKey.notchMascotHidesWhenIdle: true,
        IslandKey.notchHideInCaptures: false,
    ]
    static func register() { UserDefaults.standard.register(defaults: registered) }
}

/// The Vorssaint features the island leans on. In Sirena they are either part
/// of the island itself or of another Sirena module, so each is simply there.
enum IslandFeature: String, CaseIterable {
    case notch, notchAccessories, notchCalendar, notchDownloads, notchGestures, notchLiveEqualizer
    case notchLyrics, notchMascot, notchNotifications, notchQueue, notchTimer
    case brightness, cameraPreview, keepAwake, micMute, shelf, connectedDevices, volume, battery

    var isAvailable: Bool { true }
    func isAvailable(in defaults: UserDefaults) -> Bool { true }
}

/// A reading with every digit as a zero, so a countdown keeps its width.
enum NotchReadingShape {
    static func of(_ reading: String) -> String {
        String(reading.map { $0.isNumber ? "0" : $0 })
    }
}

import SwiftUI

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the island, whose surfaces draw on its own dark base.
    var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}
