// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena from Vorssaint's NotchSettings.swift: the island's options
// as one grouped form, in Sirena's settings style.

import EventKit
import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject private var l10n = IslandL10n.shared
    @ObservedObject private var permissions = IslandPermissions.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    // Layout
    @AppStorage(IslandKey.notchDisplay) private var display = NotchDisplay.automatic.rawValue
    @AppStorage(IslandKey.notchSilhouette) private var silhouette = NotchSilhouette.capsule.rawValue
    @AppStorage(IslandKey.notchSize) private var size = NotchSize.spacious.rawValue
    @AppStorage(IslandKey.notchCustomWidth) private var customWidth = NotchSize.defaultWidth
    @AppStorage(IslandKey.notchCustomHeight) private var customHeight = NotchSize.defaultHeight
    @AppStorage(IslandKey.notchOutlineEnabled) private var outlineEnabled = false
    @AppStorage(IslandKey.notchHideMenuBarGap) private var hideMenuBarGap = false
    @AppStorage(IslandKey.notchTranslucentBackground) private var translucentBackground = false
    @AppStorage(IslandKey.notchLiquidGlassEnabled) private var liquidGlass = false
    @AppStorage(IslandKey.notchCoversMenus) private var coversMenus = true
    @AppStorage(IslandKey.notchHideInFullscreen) private var hideInFullscreen = false
    @AppStorage(IslandKey.notchShowInCaptures) private var showInCaptures = true

    // Behavior
    @AppStorage(IslandKey.notchOpenOnHover) private var hover = false
    @AppStorage(IslandKey.notchHoverExpands) private var hoverExpand = true
    @AppStorage(IslandKey.notchHideUntilHover) private var hideUntilHover = false
    @AppStorage(IslandKey.notchHoverDelay) private var hoverDelay = NotchSupport.defaultHoverDelay
    @AppStorage(IslandKey.notchCloseDelay) private var closeDelay = NotchSupport.defaultCloseDelay
    @AppStorage(IslandKey.notchShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(IslandKey.notchGesturesEnabled) private var gesturesEnabled = true
    @AppStorage(IslandKey.notchHapticFeedback) private var hapticFeedback = true
    @AppStorage(IslandKey.notchOpensActivity) private var opensActivity = true
    @AppStorage(IslandKey.notchShelf) private var shelfDrop = true
    @AppStorage(IslandKey.notchDragReveal) private var dragReveal = true

    // Sections and controls
    @AppStorage(IslandKey.notchHiddenModules) private var hiddenModules = ""
    @AppStorage(IslandKey.notchHiddenControls) private var hiddenControls = NotchControlItem.defaultHidden
    @AppStorage(IslandKey.notchTimerEnabled) private var timerEnabled = true
    @AppStorage(IslandKey.notchCameraEnabled) private var cameraEnabled = true
    @AppStorage(IslandKey.notchCalendarEnabled) private var calendarEnabled = true
    @AppStorage(IslandKey.notchNotificationsEnabled) private var notificationsEnabled = true
    @AppStorage(IslandKey.notchDownloadsEnabled) private var downloadsEnabled = true

    // At rest and indicators
    @AppStorage(IslandKey.notchIdleContent) private var idle = NotchIdleContent.music.rawValue
    @AppStorage(IslandKey.notchKeepAwakeActivity) private var keepAwakeActivity = false
    @AppStorage(IslandKey.notchLowBatteryTint) private var lowBatteryTint = false
    @AppStorage(IslandKey.notchLowBatteryThreshold) private var lowBatteryThreshold = NotchSupport.defaultLowBatteryThreshold
    @AppStorage(IslandKey.notchVolume) private var volume = true
    @AppStorage(IslandKey.notchBrightness) private var brightness = true
    @AppStorage(IslandKey.brightnessControlEnabled) private var brightnessControl = true
    @AppStorage(IslandKey.notchKeyboardLight) private var keyboardLight = true
    @AppStorage(IslandKey.notchMicrophone) private var microphone = true
    @AppStorage(IslandKey.notchBattery) private var battery = true
    @AppStorage(IslandKey.notchAccessoriesEnabled) private var accessories = true
    @AppStorage(IslandKey.notchTrackChange) private var trackChange = true
    @AppStorage(IslandKey.notchInputSource) private var inputSource = true

    // Music
    @AppStorage(IslandKey.notchShowPlayingMusic) private var showPlayingMusic = true
    @AppStorage(IslandKey.notchLyricsEnabled) private var lyricsEnabled = true
    @AppStorage(IslandKey.notchLyricsOnline) private var lyricsOnline = false
    @AppStorage(IslandKey.notchBrowserCovers) private var browserCovers = false
    @AppStorage(IslandKey.notchLiveEqualizer) private var liveEqualizer = false
    @AppStorage(IslandKey.notchPreferredPlayer) private var preferredPlayer = NotchPreferredPlayer.automatic
    @State private var preferredPlayers: [NotchPreferredPlayer.Choice]?

    // Calendar, timer, notifications
    @AppStorage(IslandKey.notchCalendarCountdown) private var calendarCountdown = false
    @AppStorage(IslandKey.notchCalendarTimeLeft) private var calendarTimeLeft = false
    @AppStorage(IslandKey.notchCalendarWeekNumbers) private var calendarWeekNumbers = false
    @AppStorage(IslandKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage(IslandKey.notchHideTimerCountdown) private var hideTimerCountdown = false
    @AppStorage(IslandKey.notchDismissNativeNotifications) private var dismissNativeNotifications = false

    // Lock screen
    @AppStorage(IslandKey.notchLockScreen) private var lockScreen = false
    @AppStorage(IslandKey.notchLockSounds) private var lockSounds = false

    // Companion
    @AppStorage(IslandKey.notchMascotEnabled) private var mascotEnabled = false
    @AppStorage(IslandKey.notchMascotVisits) private var mascotVisits = true
    @AppStorage(IslandKey.notchMascotReactions) private var mascotReactions = true
    @AppStorage(IslandKey.notchMascotHidesWhenIdle) private var mascotHidesWhenIdle = true
    @AppStorage(IslandKey.notchMascotStyle) private var mascotStyle = NotchMascotStyle.minimal.rawValue
    @AppStorage(IslandKey.notchMascotShape) private var mascotShape = NotchMascotShape.ball.rawValue
    @AppStorage(IslandKey.notchMascotPalette) private var mascotPalette = NotchMascotPalette.pearl.rawValue
    @AppStorage(IslandKey.notchMascotSide) private var mascotSide = NotchMascotSide.left.rawValue
    @AppStorage(IslandKey.notchMascotVisitFrequency) private var mascotFrequency = NotchMascotVisitFrequency.normal.rawValue

    private var text: NotchStrings { IslandStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { IslandStrings.notchEditor(l10n.language) }
    private var activities: NotchActivityStrings { IslandStrings.notchActivities(l10n.language) }
    private var music: NotchMusicExtrasStrings { IslandStrings.notchMusicExtras(l10n.language) }
    private var calendar: NotchCalendarStrings { IslandStrings.notchCalendar(l10n.language) }
    private var mascot: NotchMascotStrings { IslandStrings.notchMascot(l10n.language) }

    var body: some View {
        Form {
            layoutSection
            behaviorSection
            sectionsSection
            controlsSection
            restingSection
            indicatorsSection
            musicSection
            calendarSection
            timerSection
            notificationsSection
            cameraSection
            downloadsSection
            lockScreenSection
            companionSection
        }
        .formStyle(.grouped)
        .onAppear {
            IslandDefaults.register()
            permissions.refresh()
        }
        .onChange(of: browserCovers) { _, _ in NotchMusicService.shared.syncBrowserCovers() }
        .onChange(of: lyricsEnabled) { _, _ in
            if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() }
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        Section {
            Picker(text.display, selection: $display) {
                Text(text.automatic).tag(NotchDisplay.automatic.rawValue)
                Text(text.builtIn).tag(NotchDisplay.builtIn.rawValue)
                Text(text.mainDisplay).tag(NotchDisplay.main.rawValue)
                Text(text.followPointer).tag(NotchDisplay.pointer.rawValue)
                Text(text.allDisplays).tag(NotchDisplay.all.rawValue)
            }
            Picker(text.size, selection: $size) {
                Text(text.compact).tag(NotchSize.compact.rawValue)
                Text(text.spacious).tag(NotchSize.spacious.rawValue)
                Text(text.custom).tag(NotchSize.custom.rawValue)
            }
            if size == NotchSize.custom.rawValue {
                dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange)
                dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange)
            }
            if NotchSupport.hasDisplayWithoutNotch {
                Picker(text.withoutNotch, selection: $silhouette) {
                    Text(text.capsuleShape).tag(NotchSilhouette.capsule.rawValue)
                    Text(text.notchShape).tag(NotchSilhouette.notch.rawValue)
                }
            }
            if NotchSupport.hasNotchedDisplay {
                Toggle(isOn: $hideMenuBarGap) {
                    Text(text.hideMenuBarGap)
                    Text(text.hideMenuBarGapHint)
                }
            }
            Toggle(text.showOutline, isOn: $outlineEnabled)
            Toggle(isOn: $translucentBackground) {
                Text(text.translucentBackground)
                Text(text.translucentBackgroundHint)
            }
            if #available(macOS 26, *) {
                Toggle(L("Liquid Glass"), isOn: $liquidGlass)
            }
            Toggle(isOn: $coversMenus) {
                Text(text.coverMenus)
                Text(text.coverMenusHint)
            }
            Toggle(text.hideInFullscreen, isOn: $hideInFullscreen)
            Toggle(text.showInCaptures, isOn: $showInCaptures)
            if !permissions.accessibility, !NotchSupport.hasNotchedDisplay {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.menuBarAccessHint).font(.callout).foregroundStyle(.secondary)
                    Button(IslandL10n.shared.s.permissionRequest) { permissions.requestAccessibility() }
                }
            }
        } header: {
            Text(L("Appearance"))
        } footer: {
            Text(text.description)
        }
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 2).frame(minWidth: 160)
                Text("\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }

    // MARK: Behavior

    private enum OpeningMode: String, CaseIterable, Identifiable {
        case click, preview, expand, hidden
        var id: String { rawValue }
    }

    private var opening: Binding<OpeningMode> {
        Binding(get: {
            guard hover else { return .click }
            if hideUntilHover { return .hidden }
            return hoverExpand ? .expand : .preview
        }, set: { mode in
            switch mode {
            case .click: hideUntilHover = false; hover = false
            case .preview: hideUntilHover = false; hover = true; hoverExpand = false
            case .expand: hideUntilHover = false; hover = true; hoverExpand = true
            case .hidden: hover = true; hoverExpand = true; hideUntilHover = true
            }
        })
    }

    private var behaviorSection: some View {
        Section {
            Picker(editor.opening, selection: opening) {
                Text(editor.clickOpen).tag(OpeningMode.click)
                Text(editor.hoverPreview).tag(OpeningMode.preview)
                Text(editor.hoverExpand).tag(OpeningMode.expand)
                Text(editor.hiddenUntilHover).tag(OpeningMode.hidden)
            }
            if hover {
                delaySlider(editor.activationTime, hint: editor.activationTimeHint, value: $hoverDelay,
                            range: NotchSupport.hoverDelayRange, sanitize: NotchSupport.sanitizedHoverDelay)
                if hoverExpand {
                    delaySlider(editor.closeTime, hint: editor.closeTimeHint, value: $closeDelay,
                                range: NotchSupport.closeDelayRange, sanitize: NotchSupport.sanitizedCloseDelay)
                }
            }
            Toggle(isOn: $opensActivity) {
                Text(editor.openActivity)
                Text(editor.openActivityHint)
            }
            Toggle(isOn: $gesturesEnabled) {
                Text(IslandStrings.notchGestures(l10n.language).title)
                Text(IslandStrings.notchGestures(l10n.language).hint)
            }
            Toggle(text.hapticFeedback, isOn: $hapticFeedback)
            Toggle(L("Open with a keyboard shortcut"), isOn: $shortcutEnabled)
            if shortcutEnabled {
                ShortcutRow(title: text.title, defaultsKey: IslandKey.notchShortcut,
                            recordingObserver: recordingObserver)
            }
            Toggle(isOn: $shelfDrop) {
                Text(L("Drop files on the island to add them to the Shelf"))
                Text(L("Sirena’s Shelf must be on."))
            }
            if shelfDrop {
                Toggle(text.dragReveal, isOn: $dragReveal)
            }
        } header: {
            Text(editor.behavior)
        }
    }

    private func delaySlider(_ title: String, hint: String, value stored: Binding<Double>,
                             range: ClosedRange<Double>, sanitize: @escaping (Double) -> Double) -> some View {
        let value = Binding(get: { sanitize(stored.wrappedValue) }, set: { stored.wrappedValue = sanitize($0) })
        let formatted = String(format: editor.activationTimeFormat, value.wrappedValue)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack {
                    Slider(value: value, in: range, step: 0.05).frame(minWidth: 160)
                    Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Sections

    private func moduleShown(_ module: NotchModule) -> Binding<Bool> {
        Binding(get: {
            !Set(hiddenModules.split(separator: ",").map(String.init)).contains(module.rawValue)
        }, set: { shown in
            var hidden = Set(hiddenModules.split(separator: ",").map(String.init))
            if shown { hidden.remove(module.rawValue) } else { hidden.insert(module.rawValue) }
            hiddenModules = NotchModule.allCases.map(\.rawValue).filter(hidden.contains).joined(separator: ",")
        })
    }

    private func moduleEnabled(_ module: NotchModule) -> Binding<Bool> {
        switch module {
        case .timer: return $timerEnabled
        case .camera: return $cameraEnabled
        case .calendar: return $calendarEnabled
        case .notifications: return $notificationsEnabled
        case .downloads: return $downloadsEnabled
        case .controls, .music: return moduleShown(module)
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        let shown = moduleShown(module)
        let enabled = moduleEnabled(module)
        return Binding(get: { shown.wrappedValue && enabled.wrappedValue },
                       set: { shown.wrappedValue = $0; enabled.wrappedValue = $0 })
    }

    private var sectionsSection: some View {
        Section {
            ForEach(NotchModule.allCases) { module in
                Toggle(isOn: moduleBinding(module)) {
                    Label { Text(module.title(l10n.language)) } icon: { Image(systemName: module.symbol) }
                    Text(editor.summary(module))
                }
            }
        } header: {
            Text(editor.sections)
        }
    }

    private func controlShown(_ item: NotchControlItem) -> Binding<Bool> {
        Binding(get: {
            !Set(hiddenControls.split(separator: ",").map(String.init)).contains(item.rawValue)
        }, set: { shown in
            var hidden = Set(hiddenControls.split(separator: ",").map(String.init))
            if shown { hidden.remove(item.rawValue) } else { hidden.insert(item.rawValue) }
            hiddenControls = NotchControlItem.allCases.map(\.rawValue).filter(hidden.contains).joined(separator: ",")
        })
    }

    private var controlsSection: some View {
        Section {
            ForEach(NotchControlItem.allCases.filter { $0 != .keyboardLight || NotchControlItem.keyboardLightIsSupported() }) { item in
                Toggle(isOn: controlShown(item)) {
                    Label { Text(item.title(l10n)) } icon: { Image(systemName: item.symbol) }
                }
            }
        } header: {
            Text(text.controls)
        } footer: {
            Text(editor.controlsSummary)
        }
    }

    // MARK: At rest and indicators

    private var restingSection: some View {
        Section {
            Picker(editor.resting, selection: $idle) {
                Text(mascotEnabled ? mascot.title : text.idleNone).tag(NotchIdleContent.none.rawValue)
                if IslandPowerSampler.hasInternalBattery {
                    Text(text.battery).tag(NotchIdleContent.battery.rawValue)
                }
                Text(text.music).tag(NotchIdleContent.music.rawValue)
            }
            if idle == NotchIdleContent.battery.rawValue {
                let strings = NotchLowBatteryStrings.localized(l10n.language)
                Toggle(isOn: $lowBatteryTint) {
                    Text(strings.title)
                    Text(strings.caption)
                }
                if lowBatteryTint {
                    LabeledContent(strings.threshold) {
                        Stepper("\(lowBatteryThreshold)%", value: $lowBatteryThreshold,
                                in: NotchSupport.batteryLevelScale, step: 5)
                    }
                }
            }
            Toggle(isOn: $keepAwakeActivity) {
                Text(activities.keepAwakeActivity)
                Text(activities.keepAwakeActivityHint)
            }
        } header: {
            Text(editor.resting)
        }
    }

    private var indicatorsSection: some View {
        Section {
            Toggle(text.volume, isOn: $volume)
            Toggle(text.brightness, isOn: Binding(get: { brightness && brightnessControl },
                                                  set: { brightness = $0; brightnessControl = $0 }))
            if NotchControlItem.keyboardLightIsSupported() {
                Toggle(IslandStrings.brightness(l10n.language).keyboardLight, isOn: $keyboardLight)
            }
            Toggle(IslandL10n.shared.s.micMuteName, isOn: $microphone)
            if IslandPowerSampler.hasInternalBattery {
                Toggle(text.battery, isOn: $battery)
            }
            Toggle(isOn: $accessories) {
                Text(activities.accessories)
                Text(activities.accessoryDescription)
            }
            Toggle(text.newTrack, isOn: $trackChange)
            Toggle(text.inputSource, isOn: $inputSource)
        } header: {
            Text(editor.feedback)
        }
    }

    // MARK: Pages

    private var musicSection: some View {
        Section {
            Toggle(text.playingMusic, isOn: $showPlayingMusic)
            Picker(music.preferredPlayer, selection: $preferredPlayer) {
                Text(music.automaticSource).tag(NotchPreferredPlayer.automatic)
                ForEach(NotchPreferredPlayer.choices(in: preferredPlayers ?? [], including: preferredPlayer),
                        id: \.bundleID) { app in
                    Text(app.name).tag(app.bundleID)
                }
            }
            .task {
                guard let choices = await NotchPreferredPlayer.loadInstalled(), !Task.isCancelled else { return }
                preferredPlayers = choices
            }
            Toggle(music.enableLyrics, isOn: $lyricsEnabled)
            if lyricsEnabled {
                Toggle(isOn: $lyricsOnline) {
                    Text(music.online)
                    Text(music.onlineHint)
                }
            }
            Toggle(isOn: $browserCovers) {
                Text(music.browserCovers)
                Text(music.browserCoversHint)
            }
            Toggle(isOn: $liveEqualizer) {
                Text(music.liveEqualizer)
                Text(NotchAudioLevelSupport.isSupported ? music.liveEqualizerHint : music.liveEqualizerUnavailable)
            }
            .disabled(!NotchAudioLevelSupport.isSupported)
        } header: {
            Text(NotchModule.music.title(l10n.language))
        }
    }

    private var calendarSection: some View {
        Section {
            if permissions.calendarAccess == .fullAccess {
                Toggle(isOn: $calendarCountdown) {
                    Text(calendar.countdown)
                    Text(calendar.countdownHint)
                }
                Toggle(isOn: $calendarTimeLeft) {
                    Text(calendar.timeLeft)
                    Text(calendar.timeLeftHint)
                }
                Toggle(calendar.weekNumbers, isOn: $calendarWeekNumbers)
                NotchCalendarSelection()
            } else {
                Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                    Button(calendar.settings, action: permissions.openCalendarSettings)
                }
                if permissions.calendarRequestFailed {
                    Text(calendar.requestFailed).font(.caption).foregroundStyle(.orange)
                }
            }
        } header: {
            Text(calendar.title)
        }
        .onChange(of: [calendarCountdown, calendarTimeLeft, calendarWeekNumbers]) { _, _ in
            NotchCalendarService.shared.syncWithPreferences()
        }
    }

    private var timerSection: some View {
        Section {
            Toggle(activities.hideTimerCountdown, isOn: $hideTimerCountdown)
            Toggle(activities.soundEnabled, isOn: $timerSoundEnabled)
        } header: {
            Text(activities.timer)
        }
    }

    private var notificationsSection: some View {
        Section {
            let notifications = IslandStrings.notchNotifications(l10n.language)
            Toggle(isOn: $dismissNativeNotifications) {
                Text(notifications.hideSystemBanner)
                Text(notifications.hideSystemBannerHint)
            }
            if !permissions.accessibility {
                IslandSettingsAccessibilityRow()
            }
        } header: {
            Text(IslandStrings.notchNotifications(l10n.language).title)
        } footer: {
            Text(IslandStrings.notchNotifications(l10n.language).privacy)
        }
    }

    private var cameraSection: some View {
        Section {
            Text(activities.cameraHint).foregroundStyle(.secondary)
            Button(IslandL10n.shared.s.permissionOpenSettings, action: permissions.openCameraSettings)
        } header: {
            Text(activities.camera)
        }
    }

    private var downloadsSection: some View {
        Section {
            let files = IslandStrings.notchFiles(l10n.language)
            Text(files.downloadsHint).foregroundStyle(.secondary)
            if downloads.folderUnavailable {
                Text(files.folderUnavailable).foregroundStyle(.orange)
            } else if let name = downloads.folderName {
                Label(name, systemImage: "folder").lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button(files.chooseFolder, action: downloads.chooseFolder)
                if downloads.folderName != nil || downloads.folderUnavailable {
                    Button(files.clearFolder, action: downloads.forgetFolder)
                }
            }
        } header: {
            Text(IslandStrings.notchFiles(l10n.language).downloadsTitle)
        }
    }

    private var lockScreenSection: some View {
        Section {
            let locked = IslandStrings.notchLockScreen(l10n.language)
            Toggle(isOn: $lockScreen) {
                Text(locked.show)
                Text(locked.showHint)
            }
            Toggle(isOn: $lockSounds) {
                Text(locked.sounds)
                Text(locked.soundsHint)
            }
        } header: {
            Text(IslandStrings.notchLockScreen(l10n.language).title)
        }
    }

    // MARK: Companion

    private var companionSection: some View {
        Section {
            Toggle(isOn: $mascotEnabled) {
                Text(mascot.title)
                Text(mascot.hint)
            }
            if mascotEnabled {
                Toggle(isOn: $mascotVisits) {
                    Text(mascot.visits)
                    Text(mascot.visitsHint)
                }
                if mascotVisits {
                    Picker(mascot.frequency, selection: $mascotFrequency) {
                        ForEach(NotchMascotVisitFrequency.allCases) { Text(mascot.frequency($0)).tag($0.rawValue) }
                    }
                }
                Toggle(isOn: $mascotReactions) {
                    Text(mascot.reactions)
                    Text(mascot.reactionsHint)
                }
                Toggle(isOn: $mascotHidesWhenIdle) {
                    Text(mascot.hidesWhenIdle)
                    Text(mascot.hidesWhenIdleHint)
                }
                Picker(mascot.style, selection: $mascotStyle) {
                    ForEach(NotchMascotStyle.allCases) { Text(mascot.style($0)).tag($0.rawValue) }
                }
                Picker(mascot.shape, selection: $mascotShape) {
                    ForEach(NotchMascotShape.allCases) { Text(mascot.shape($0)).tag($0.rawValue) }
                }
                Picker(mascot.color, selection: $mascotPalette) {
                    ForEach(NotchMascotPalette.allCases) { Text(mascot.palette($0)).tag($0.rawValue) }
                }
                Picker(mascot.side, selection: $mascotSide) {
                    ForEach(NotchMascotSide.allCases) { Text(mascot.side($0)).tag($0.rawValue) }
                }
                Button(mascot.sayHi) { _ = NotchService.shared.greetMascot() }
            }
        } header: {
            Text(mascot.title)
        }
    }
}

/// Accessibility for the island's notifications, in Settings' own style.
private struct IslandSettingsAccessibilityRow: View {
    @ObservedObject private var permissions = IslandPermissions.shared
    @ObservedObject private var l10n = IslandL10n.shared

    var body: some View {
        LabeledContent {
            HStack {
                Button(l10n.s.permissionRequest) { permissions.requestAccessibility() }
                Button(l10n.s.permissionOpenSettings) { permissions.openAccessibilitySettings() }
            }
        } label: {
            Text(l10n.s.permissionAccessibility)
            Text(l10n.s.permissionMissing)
        }
    }
}
