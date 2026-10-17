// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; Sirena port.
//
// WindowSwitcherSettingsView.swift
//
// Settings for the ported Vorssaint switcher, as sections of a grouped Form. Mirrors the
// options of Vorssaint's SwitcherSettings page.

import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct WindowSwitcherSettingsView: View {
    @AppStorage(SwitcherDefaultsKey.switcherEnabled) private var enabled = true
    @AppStorage(SwitcherDefaultsKey.switcherShortcut) private var shortcutStorage = SwitcherGlobalShortcut.switcherDefault.storageValue
    @AppStorage(SwitcherDefaultsKey.switcherWindowShortcut) private var windowShortcutStorage = SwitcherGlobalShortcut.switcherWindowDefault.storageValue
    @AppStorage(SwitcherDefaultsKey.switcherTakeOverSystemShortcuts) private var takeOver = true
    @AppStorage(SwitcherDefaultsKey.switcherIconRowMode) private var iconRowMode = false
    @AppStorage(SwitcherDefaultsKey.switcherSimpleMode) private var simpleMode = false
    @AppStorage(SwitcherDefaultsKey.switcherMergeTabs) private var mergeTabs = false
    @AppStorage(SwitcherDefaultsKey.switcherWindowlessApps) private var windowlessApps = SwitcherWindowlessApps.fallback.rawValue
    @AppStorage(SwitcherDefaultsKey.switcherMinimizedPlacement) private var minimizedPlacement = SwitcherWindowSwitchMinimizedPlacement.normal.rawValue
    @AppStorage(SwitcherDefaultsKey.switcherTreatHiddenAppsLikeMinimized) private var hiddenLikeMinimized = true
    @AppStorage(SwitcherDefaultsKey.switcherShowFullscreenWindows) private var showFullscreen = true
    @AppStorage(SwitcherDefaultsKey.switcherScreenPlacement) private var screenPlacement = SwitcherScreenPlacement.fallback.rawValue
    @AppStorage(SwitcherDefaultsKey.switcherCurrentDisplayOnly) private var currentDisplayOnly = false
    @AppStorage(SwitcherDefaultsKey.switcherCurrentSpaceOnly) private var currentSpaceOnly = false
    @AppStorage(SwitcherDefaultsKey.switcherSearchPinEnabled) private var searchPin = false
    @AppStorage(SwitcherDefaultsKey.switcherShowShortcutHints) private var shortcutHints = true
    @AppStorage(SwitcherDefaultsKey.switcherAppearanceDelay) private var appearanceDelay = SwitcherSupport.defaultAppearanceDelayMilliseconds
    @AppStorage(SwitcherDefaultsKey.switcherInstantSelection) private var instantSelection = false
    @AppStorage(SwitcherDefaultsKey.switcherMaxColumns) private var maxColumns = 0
    @AppStorage(SwitcherDefaultsKey.switcherPreviewSize) private var previewSize = "normal"
    @AppStorage(SwitcherDefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @AppStorage(SwitcherDefaultsKey.switcherLiquidGlass) private var liquidGlass = true

    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    private enum Layout: String, Hashable { case windows, icons, simple }

    private var layout: Binding<Layout> {
        Binding(
            get: { simpleMode ? .simple : (iconRowMode ? .icons : .windows) },
            set: {
                simpleMode = $0 == .simple
                iconRowMode = $0 == .icons
                sync()
            })
    }

    private var windowlessSelection: Binding<String> {
        Binding(
            get: { SwitcherWindowlessApps.mode(storedValue: windowlessApps, takeOverSystemShortcuts: takeOver).rawValue },
            set: { if !takeOver { windowlessApps = $0 } })
    }

    var body: some View {
        Group {
            if !accessibilityGranted || (!screenRecordingGranted && SwitcherSupport.capturesPreviews(simpleMode: simpleMode)) {
                Section(L("Permission required")) {
                    if !accessibilityGranted {
                        permissionRow(L("Accessibility"),
                                      caption: L("Needed to read keys while the switcher is open and to focus, close and quit windows."),
                                      url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                    }
                    if !screenRecordingGranted && SwitcherSupport.capturesPreviews(simpleMode: simpleMode) {
                        permissionRow(L("Screen Recording"),
                                      caption: L("Needed for live window previews. The simple list works without it."),
                                      url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            _ = CGRequestScreenCaptureAccess()
                        }
                    }
                }
            }

            Section(L("Window switcher")) {
                Picker(L("Layout"), selection: layout) {
                    Text(L("Window previews")).tag(Layout.windows)
                    Text(L("Large icons")).tag(Layout.icons)
                    Text(L("Simple list")).tag(Layout.simple)
                }
                Text(layoutCaption)
                    .font(.caption).foregroundStyle(.secondary)

            }

            Section(L("Options")) {
                LabeledContent {
                    HStack {
                        Slider(value: appearanceDelayBinding,
                               in: Double(SwitcherSupport.appearanceDelayMillisecondsRange.lowerBound)
                                   ... Double(SwitcherSupport.appearanceDelayMillisecondsRange.upperBound),
                               step: 25)
                            .frame(width: 140)
                        Text("\(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: appearanceDelay)) ms")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text(L("Appearance delay"))
                    Text(L("How long the shortcut must be held before the switcher appears."))
                }
                LabeledContent {
                    HStack {
                        Slider(value: maxColumnsBinding,
                               in: Double(SwitcherSupport.maxColumnsRange.lowerBound - 1)
                                   ... Double(SwitcherSupport.maxColumnsRange.upperBound),
                               step: 1)
                            .frame(width: 140)
                        Text(SwitcherSupport.sanitizedMaxColumns(maxColumns).map(String.init) ?? L("Auto"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text(L("Maximum columns"))
                    Text(L("Wraps onto more rows after this many items. Useful on ultrawide displays."))
                }
                Toggle(isOn: $instantSelection) {
                    Text(L("Instant selection"))
                    Text(L("Moves the highlight and scroll position immediately as you browse apps and windows."))
                }
                Toggle(isOn: $searchPin) {
                    Text(L("Pin search with S"))
                    Text(L("S starts a search and pins the switcher open, so typing no longer produces special characters when your shortcut uses ⌥, and a search starting with Q or W no longer closes the window or quits the app by mistake."))
                }
                if simpleMode || iconRowMode {
                    Toggle(isOn: $shortcutHints) {
                        Text(L("Show shortcut hints"))
                        Text(L("Shows the app and window shortcuts below the icons."))
                    }
                }
                Toggle(isOn: $mergeTabs) {
                    Text(L("Show one entry per app"))
                    Text(L("Collapses all of an app’s windows into one entry in the switcher, instead of one entry per window."))
                }
                Toggle(L("Show fullscreen windows"), isOn: $showFullscreen)
                    .onChange(of: showFullscreen) { _, _ in sync() }
                Picker(L("Minimized windows"), selection: $minimizedPlacement) {
                    Text(L("Normal ordering")).tag(SwitcherWindowSwitchMinimizedPlacement.normal.rawValue)
                    Text(L("Place at end")).tag(SwitcherWindowSwitchMinimizedPlacement.end.rawValue)
                    Text(L("Hide")).tag(SwitcherWindowSwitchMinimizedPlacement.hidden.rawValue)
                }
                .onChange(of: minimizedPlacement) { _, _ in sync() }
                if minimizedPlacement != SwitcherWindowSwitchMinimizedPlacement.normal.rawValue {
                    Toggle(L("Treat hidden apps like minimized windows"), isOn: $hiddenLikeMinimized)
                        .onChange(of: hiddenLikeMinimized) { _, _ in sync() }
                }
                Picker(selection: $screenPlacement) {
                    Text(L("Display with the pointer")).tag(SwitcherScreenPlacement.pointer.rawValue)
                    Text(L("Display with the menu bar")).tag(SwitcherScreenPlacement.menuBar.rawValue)
                    Text(L("Display with the active window")).tag(SwitcherScreenPlacement.activeWindow.rawValue)
                } label: {
                    Text(L("Show on"))
                    Text(L("Which display the switcher opens on when more than one is connected."))
                }
                Toggle(isOn: $currentDisplayOnly) {
                    Text(L("Show only the current display"))
                    Text(L("Lists only windows on the display under the pointer. If that display has no windows, the switcher does not open."))
                }
                Toggle(isOn: $currentSpaceOnly) {
                    Text(L("Show only the current desktop"))
                    Text(L("Lists windows from the current desktop. Fullscreen windows from other desktops also appear while “Show fullscreen windows” is on."))
                }
            }

            Section {
                Picker(selection: windowlessSelection) {
                    Text(L("Do not show")).tag(SwitcherWindowlessApps.off.rawValue)
                    Text(L("Finder only")).tag(SwitcherWindowlessApps.finder.rawValue)
                    Text(L("All apps")).tag(SwitcherWindowlessApps.all.rawValue)
                } label: {
                    Text(L("Apps with no open window"))
                    Text(L("Chooses which running apps with no window at all show up in the switcher."))
                }
                .disabled(takeOver)
                if takeOver {
                    Text(String(format: L("All running apps stay reachable while “%@” is on. Turn it off to choose."),
                                L("Replace macOS ⌘Tab and ⌘`")))
                        .font(.caption).foregroundStyle(.secondary)
                }
                SwitcherAppRulesSection()
            } header: {
                Text(L("Rules by app"))
            } footer: {
                Text(L("Choose how each app appears. Apps without a rule use the choice above."))
            }

            Section(L("Window thumbnails")) {
                Picker(L("Preview size"), selection: $previewSize) {
                    Text(L("Small")).tag("small")
                    Text(L("Normal")).tag("normal")
                    Text(L("Large")).tag("large")
                    Text(L("Extra large")).tag("xlarge")
                }
                .onChange(of: previewSize) { _, _ in sync() }
                Toggle(L("Liquid Glass background"), isOn: $liquidGlass)
                Toggle(isOn: $minimalPreviews) {
                    Text(L("Minimal previews"))
                    Text(L("Hide titles, buttons and decorative details in switcher previews. The selection stays visible."))
                }
                SwitcherBundleListSection(
                    key: SwitcherDefaultsKey.switcherPreviewExcludedApps,
                    title: L("Pause in these apps"),
                    caption: L("Window thumbnails stop while one of these apps is in front."))
            }
        }
        .onAppear {
            // The page's switch turns the switcher on and off now.
            if !enabled { enabled = true; sync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private var layoutCaption: String {
        switch layout.wrappedValue {
        case .windows: return L("One preview per window, minimized ones included.")
        case .icons: return L("Shows one icon per app with that app’s window previews above it.")
        case .simple: return L("Shows app icons and window titles, without previews or screen capture by the switcher.")
        }
    }

    private func sync() {
        WindowSwitcherController.shared.syncWithPreferences()
    }

    private func permissionRow(_ title: String, caption: String, url: String,
                               request: @escaping () -> Void) -> some View {
        LabeledContent {
            Button(L("Open Settings")) {
                request()
                if let url = URL(string: url) { NSWorkspace.shared.open(url) }
            }
        } label: {
            Text(title)
            Text(caption)
        }
    }

    private var appearanceDelayBinding: Binding<Double> {
        Binding(
            get: { Double(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: appearanceDelay)) },
            set: { appearanceDelay = SwitcherSupport.sanitizedAppearanceDelay(milliseconds: Int($0.rounded())) })
    }

    /// The slider's leftmost step, one below the range, stands for Auto.
    private var maxColumnsBinding: Binding<Double> {
        let auto = SwitcherSupport.maxColumnsRange.lowerBound - 1
        return Binding(
            get: { Double(SwitcherSupport.sanitizedMaxColumns(maxColumns) ?? auto) },
            set: {
                let value = Int($0.rounded())
                maxColumns = value <= auto ? 0 : SwitcherSupport.sanitizedMaxColumns(value) ?? 0
            })
    }
}

// MARK: - Shortcut recorder

/// Records a shortcut in Vorssaint's `SwitcherGlobalShortcut` storage format.
/// While listening, the switcher's tap lets every key through.
struct SwitcherShortcutRecorder: View {
    @Binding var storage: String
    let fallback: SwitcherGlobalShortcut
    let onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    private var current: SwitcherGlobalShortcut {
        SwitcherGlobalShortcut(storageValue: storage) ?? fallback
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : begin()
            } label: {
                Text(recording ? L("Type shortcut…") : current.displayString)
                    .frame(minWidth: 90)
            }
            if storage != fallback.storageValue {
                Button {
                    storage = fallback.storageValue
                    onChange()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(L("Reset to default"))
            }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: .windowActionShortcutRecordingStarted)) { _ in
            if recording { stop() }
        }
    }

    private func begin() {
        recording = true
        WindowSwitcherController.shared.setCapturingShortcut(true)
        // Window actions, Shelf and the rest stop listening, so a combination already
        // in use gets recorded here instead of running.
        Notification.Name.shortcutRecording.post(object: true)
        NotificationCenter.default.post(name: .switcherShortcutRecordingStarted, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stop()
                return nil
            }
            let modifiers = SwitcherGlobalShortcutModifiers(eventFlags: event.modifierFlags)
            let candidate = SwitcherGlobalShortcut(keyCode: Int64(event.keyCode), modifiers: modifiers)
            if candidate.isValid {
                storage = candidate.storageValue
                stop()
                onChange()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            WindowSwitcherController.shared.setCapturingShortcut(false)
            Notification.Name.shortcutRecording.post(object: false)
        }
        recording = false
    }
}

extension Notification.Name {
    /// A switcher shortcut started recording: the window-action recorders stop.
    static let switcherShortcutRecordingStarted = Notification.Name("sirena.switcherShortcutRecordingStarted")
}

// MARK: - App lists

private func switcherPickApplication() -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Bundle(url: url)?.bundleIdentifier
}

private func switcherAppName(_ bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
    return bundleID
}

private func switcherAppIcon(_ bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

private struct SwitcherAppLabel: View {
    let bundleID: String
    var body: some View {
        HStack(spacing: 8) {
            if let icon = switcherAppIcon(bundleID) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(switcherAppName(bundleID))
        }
    }
}

/// Per-app rules (show without windows, windows only, never show).
private struct SwitcherAppRulesSection: View {
    @State private var rules: [String: SwitcherAppRule] = Self.savedRules

    var body: some View {
        ForEach(rules.keys.sorted(), id: \.self) { bundleID in
            LabeledContent {
                HStack {
                    Picker(L("Switcher behavior"), selection: binding(for: bundleID)) {
                        Text(L("Show without windows")).tag(SwitcherAppRule.showWithoutWindows)
                        Text(L("Windows only")).tag(SwitcherAppRule.windowsOnly)
                        Text(L("Never show")).tag(SwitcherAppRule.hidden)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        var updated = rules
                        updated.removeValue(forKey: bundleID)
                        save(updated)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help(L("Remove"))
                }
            } label: {
                SwitcherAppLabel(bundleID: bundleID)
            }
        }
        Button(L("Add an app…")) {
            guard let bundleID = switcherPickApplication() else { return }
            var updated = rules
            updated[bundleID] = .showWithoutWindows
            save(updated)
        }
    }

    private static var savedRules: [String: SwitcherAppRule] {
        SwitcherAppRule.rules(storedValue: UserDefaults.standard.dictionary(forKey: SwitcherDefaultsKey.switcherAppRules))
    }

    private func binding(for bundleID: String) -> Binding<SwitcherAppRule> {
        Binding(
            get: { rules[bundleID] ?? .windowsOnly },
            set: {
                var updated = rules
                updated[bundleID] = $0
                save(updated)
            })
    }

    private func save(_ updated: [String: SwitcherAppRule]) {
        let stored = SwitcherAppRule.storedValue(updated)
        UserDefaults.standard.set(stored, forKey: SwitcherDefaultsKey.switcherAppRules)
        rules = SwitcherAppRule.rules(storedValue: stored as [String: Any])
    }
}

/// A list of bundle identifiers stored as a string array.
private struct SwitcherBundleListSection: View {
    let key: String
    let title: String
    let caption: String
    @State private var ids: [String] = []

    var body: some View {
        LabeledContent {
            Button(L("Add an app…")) {
                guard let bundleID = switcherPickApplication() else { return }
                save(ids + [bundleID])
            }
        } label: {
            Text(title)
            Text(caption)
        }
        .onAppear { ids = UserDefaults.standard.stringArray(forKey: key) ?? [] }
        ForEach(ids, id: \.self) { bundleID in
            LabeledContent {
                Button {
                    save(ids.filter { $0 != bundleID })
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help(L("Remove"))
            } label: {
                SwitcherAppLabel(bundleID: bundleID)
            }
        }
    }

    private func save(_ updated: [String]) {
        let clean = SwitcherDefaults.sanitizedBundleIdentifierList(updated)
        UserDefaults.standard.set(clean, forKey: key)
        ids = clean
    }
}

/// The switcher's shortcuts, for the Atalhos tab of Janela e Dock.
struct SwitcherShortcutsSection: View {
    @AppStorage(SwitcherDefaultsKey.switcherShortcut) private var shortcutStorage = SwitcherGlobalShortcut.switcherDefault.storageValue
    @AppStorage(SwitcherDefaultsKey.switcherWindowShortcut) private var windowShortcutStorage = SwitcherGlobalShortcut.switcherWindowDefault.storageValue
    @AppStorage(SwitcherDefaultsKey.switcherTakeOverSystemShortcuts) private var takeOver = true

    var body: some View {
        Section {
            LabeledContent(L("Apps")) {
                SwitcherShortcutRecorder(storage: $shortcutStorage, fallback: .switcherDefault) { sync() }
            }
            LabeledContent {
                SwitcherShortcutRecorder(storage: $windowShortcutStorage, fallback: .switcherWindowDefault) { sync() }
            } label: {
                Text(L("Windows"))
                Text(L("Opens a switcher for the frontmost app’s windows. While the switcher is open, jumps between the selected app’s windows."))
            }
            Toggle(isOn: $takeOver) {
                Text(L("Replace macOS ⌘Tab and ⌘`"))
                Text(L("Disables the matching macOS app and window shortcuts only while the Sirena switcher is active. All running apps stay reachable."))
            }
            .onChange(of: takeOver) { _, _ in sync() }
        } header: {
            Text(L("Window Switcher"))
        } footer: {
            Text(String(format: L("Hold %@ to navigate; release to activate the window. Shift or ← goes back; W closes the window; Q quits the app; Esc cancels."),
                        (SwitcherGlobalShortcut(storageValue: shortcutStorage) ?? .switcherDefault).displayString))
        }
    }

    private func sync() {
        WindowSwitcherController.shared.syncWithPreferences()
    }
}
