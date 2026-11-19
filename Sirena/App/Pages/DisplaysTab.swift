/// DisplaysTab.swift
///
/// Janela e Dock › Monitores (once part of the "Ajustes" card): apps whose new windows open on a
/// chosen display (`AppScreenEngine`), and the displays themselves (main display, resolution,
/// refresh rate, mirroring). Map: .planning/codebase/ADJUSTMENTS.md.

import DockKit
import SwiftUI

struct DisplaysTab: View {
    @State private var rules = AppScreenRules.shared
    @State private var displays = DisplayConfigurator.shared
    @State private var screens = NSScreen.screens
    @State private var hasAccessibility = Showcase.accessibilityShown()

    var body: some View {
        Form {
            displaysSection
            appsSection
        }
        .formStyle(.grouped)
        .onAppear { displays.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = Showcase.accessibilityShown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    private var appsSection: some View {
        Section {
            if !rules.rules.isEmpty && !hasAccessibility {
                AccessibilityNeededRow(reason: L("Needed to move the windows to their display."))
            }
            if rules.rules.isEmpty {
                Text(L("No app yet. Add one and choose its display."))
                    .foregroundStyle(.secondary)
            }
            ForEach(rules.rules) { rule in
                AppScreenRuleRow(rule: rule, screens: screens)
            }
            LabeledContent {
                Button(L("Add App…")) { addApps() }
            } label: {
                if screens.count < 2 {
                    Text(L("Rules for displays not connected now wait for them."))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSubheader(L("Apps on Their Display"), symbol: "macwindow.on.rectangle")
        } footer: {
            Text(L("New windows of these apps open on the chosen display, wherever the pointer or the focus is. Windows you move yourself afterwards stay where you put them."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { rules.add(bundleID: id, screen: screen) }
        }
    }

    /// A pending resolution first, then one group per display (its name on top), then what
    /// applies to all of them.
    @ViewBuilder
    private var displaysSection: some View {
        if let pending = displays.pending {
            Section {
                LabeledContent {
                    HStack {
                        Button(L("Undo")) { displays.revertPending() }
                        Button(L("Keep It")) { displays.keepPending() }
                            .keyboardShortcut(.defaultAction)
                    }
                } label: {
                    Label(L("Keep this resolution?"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L("It goes back by itself in \(pending.secondsLeft) s."))
                }
            }
        }
        ForEach(displays.displays) { display in
            Section {
                DisplayRows(display: display, configurator: displays, canBeMain: displays.displays.count > 1)
            } header: {
                SettingsSubheader(display.name, parent: L("Connected Displays"),
                                  symbol: display.isBuiltin ? "laptopcomputer" : "display")
            }
        }
        Section {
            if displays.displays.count > 1 || displays.isMirroring {
                Toggle(isOn: Binding(get: { displays.isMirroring }, set: { displays.setMirroring($0) })) {
                    Text(L("Mirror displays"))
                    Text(L("Every display shows the same picture as the main one."))
                }
            }
            LabeledContent {
                Button(L("Open Displays Settings")) {
                    SettingsShortcuts.system.flatMap(\.items).first { $0.id == "displays" }?.open()
                }
            } label: {
                Text(L("Arrangement, brightness, Night Shift and more"))
            }
        } header: {
            SettingsSubheader(L("All Displays"), symbol: "display.2")
        } footer: {
            Text(L("A new resolution goes back to the previous one after 15 seconds unless you keep it, in case the display can't show it."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppScreenRuleRow: View {
    let rule: AppScreenRule
    let screens: [NSScreen]

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) }

    var body: some View {
        HStack(spacing: 10) {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? rule.bundleID)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("", selection: Binding(get: { rule.screenID }, set: { id in
                var changed = rule
                changed.screenID = id
                changed.screenName = screens.first { ScreenIdentity.identifier(of: $0) == id }?.localizedName ?? rule.screenName
                AppScreenRules.shared.update(changed)
            })) {
                ForEach(screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(ScreenIdentity.identifier(of: screen))
                }
                if !screens.contains(where: { ScreenIdentity.identifier(of: $0) == rule.screenID }) {
                    Text(L("\(rule.screenName) (not connected)")).tag(rule.screenID)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            Menu {
                Picker(L("Position"), selection: Binding(get: { rule.mode }, set: { mode in
                    var changed = rule
                    changed.mode = mode
                    AppScreenRules.shared.update(changed)
                })) {
                    Text(L("Same size and place")).tag(AppScreenPlacementMode.keep)
                    Text(L("Fill the display")).tag(AppScreenPlacementMode.fill)
                    Text(L("Centered")).tag(AppScreenPlacementMode.center)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle(L("Only windows opened at launch"), isOn: Binding(get: { rule.onlyAtLaunch }, set: { on in
                    var changed = rule
                    changed.onlyAtLaunch = on
                    AppScreenRules.shared.update(changed)
                }))
                Button(L("Move Its Windows Now")) { AppScreenEngine.shared.moveOpenWindows(of: rule.bundleID) }
                Divider()
                Button(L("Remove"), role: .destructive) { AppScreenRules.shared.remove(rule.bundleID) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var summary: String {
        let place: String
        switch rule.mode {
        case .keep: place = L("Same size and place")
        case .fill: place = L("Fill the display")
        case .center: place = L("Centered")
        }
        return rule.onlyAtLaunch ? L("\(place) · only at launch") : place
    }
}

private struct DisplayRows: View {
    let display: DisplayInfo
    let configurator: DisplayConfigurator
    let canBeMain: Bool

    var body: some View {
        if canBeMain {
            LabeledContent {
                if display.isMain {
                    Label(L("This one"), systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    Button(L("Make Main")) { configurator.makeMain(display.id) }
                }
            } label: {
                Text(L("The main one"))
                if display.isMain {
                    Text(L("The main display has the menu bar's first copy, the Dock by default and new windows."))
                }
            }
        }
        if let current = display.current, display.sizes.count > 1 {
            Picker(L("Resolution"), selection: Binding(get: { current.sizeKey }, set: { key in
                guard let option = display.sizes.first(where: { $0.sizeKey == key }) else { return }
                configurator.apply(option, to: display.id)
            })) {
                ForEach(display.sizes) { option in
                    Text("\(option.width) × \(option.height)").tag(option.sizeKey)
                }
            }
        }
        if let current = display.current, display.refreshRates.count > 1 {
            Picker(L("Refresh rate"), selection: Binding(get: { current.id }, set: { id in
                guard let option = display.refreshRates.first(where: { $0.id == id }) else { return }
                configurator.apply(option, to: display.id)
            })) {
                ForEach(display.refreshRates) { option in
                    Text("\(Int(option.refresh.rounded())) Hz").tag(option.id)
                }
            }
        }
    }
}
