/// DockSetupSections.swift
///
/// The Dock's own setup on Janela e Dock › Dock (once the "Ajustes" card): the Dock kept on one
/// display, spaces between apps, macOS's Dock options and a copy of the Dock to go back to.
/// Map: .planning/codebase/ADJUSTMENTS.md.

import DockKit
import SwiftUI

/// Asks for Accessibility when a feature here needs it and it's missing.
struct AccessibilityNeededRow: View {
    let reason: String

    var body: some View {
        LabeledContent {
            Button(L("Allow…")) { AppDelegate.instance.windowManagement.requestAuthorization() }
        } label: {
            Label(L("Accessibility"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(reason)
        }
    }
}

/// Janela e Dock › Dock: the Dock kept on one display (`DockLockService`).
struct DockLockSection: View {
    @State private var lockOn = DockAndDisplaysController.dockLockEnabled
    @State private var lockedScreen = DockLockService.lockedScreenIdentifier.isEmpty
        ? DockLockService.mainDisplayIdentifier : DockLockService.lockedScreenIdentifier
    @State private var modifier = DockLockService.overrideModifier
    @State private var screens = NSScreen.screens
    @State private var hasAccessibility = Showcase.accessibilityShown()

    var body: some View {
        Section {
            FeatureDrawingRow {
                DockLockDrawing()
            } content: {
                Toggle(isOn: $lockOn) {
                    Text(L("Keep the Dock on one display"))
                    Text(L("The Dock itself stays on the display below and never jumps to another one when the pointer reaches its bottom edge. The icons stay as they are: you can still add, remove and move them."))
                }
                .onChange(of: lockOn) { _, on in
                    if on && lockedScreen.isEmpty {
                        lockedScreen = DockLockService.mainDisplayIdentifier
                        DockLockService.lockedScreenIdentifier = lockedScreen
                    }
                    DockAndDisplaysController.dockLockEnabled = on
                }
            }
            if lockOn && !hasAccessibility {
                AccessibilityNeededRow(reason: L("Needed to keep the Dock in place."))
            }
            Picker(selection: $lockedScreen) {
                Text(L("Main display (\(DockLockService.mainDisplay?.localizedName ?? "—"))"))
                    .tag(DockLockService.mainDisplayIdentifier)
                Divider()
                ForEach(screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(DockLockService.identifier(of: screen))
                }
                if lockedScreen != DockLockService.mainDisplayIdentifier
                    && !screens.contains(where: { DockLockService.identifier(of: $0) == lockedScreen }) {
                    Text(L("Not connected")).tag(lockedScreen)
                }
            } label: {
                Text(L("Display for the Dock"))
                Text(L("“Main display” follows the one set as main in macOS (the one with the menu bar)."))
            }
            .disabled(!lockOn)
            .onChange(of: lockedScreen) { _, id in DockLockService.lockedScreenIdentifier = id }
            if lockOn {
                Picker(L("Hold to move the Dock"), selection: $modifier) {
                    Text("⌥ Option").tag(0)
                    Text("⌃ Control").tag(1)
                    Text("⇧ Shift").tag(2)
                    Text("⌘ Command").tag(3)
                }
                .onChange(of: modifier) { _, value in DockLockService.overrideModifier = value }
                if screens.count < 2 {
                    Label(L("With a single display there is nothing to lock: it works as soon as another one is connected."), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSubheader(L("Dock on One Display"), symbol: "lock.display")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = Showcase.accessibilityShown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

/// Janela e Dock › Dock: spaces between apps, macOS's Dock options and the copy of the Dock
/// (`DockPreferences`, written to `com.apple.dock`).
struct DockLayoutSections: View {
    @State private var prefs = DockPreferences.shared

    var body: some View {
        spacersSection
            .onAppear { prefs.reload() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                prefs.reload()
            }
        behaviorSection
    }

    private var spacersSection: some View {
        Section {
            DockStrip(prefs: prefs)
            LabeledContent {
                HStack {
                    Button(L("Small")) { prefs.insertSpacer(small: true, at: Int.max) }
                    Button(L("Large")) { prefs.insertSpacer(small: false, at: Int.max) }
                }
            } label: {
                Text(L("Add a space at the end"))
            }
            if prefs.spacerCount > 0 {
                LabeledContent {
                    Button(L("Remove All"), role: .destructive) { prefs.removeAllSpacers() }
                } label: {
                    Text(prefs.spacerCount == 1 ? L("1 space in the Dock") : L("\(prefs.spacerCount) spaces in the Dock"))
                }
            }
        } header: {
            SettingsSubheader(L("Spaces Between Apps"), symbol: "space")
        } footer: {
            Text(L("Click between two icons to put a space there, or on a space to take it out. A space at the end can be dragged in the Dock like any icon. The Dock restarts for a moment after each change."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        Section {
            optionToggle(.autohide, L("Hide the Dock automatically"), L("It shows when the pointer reaches the edge."))
            if prefs.isOn(.autohide) {
                optionToggle(.instantReveal, L("Show it without waiting"), L("No half-second pause before the hidden Dock comes up."))
                Picker(L("Animation"), selection: Binding(get: { prefs.animationSpeed }, set: { prefs.setAnimationSpeed($0) })) {
                    ForEach(DockAnimationSpeed.allCases) { Text($0.title).tag($0) }
                }
            }
            optionToggle(.staticOnly, L("Show only open apps"), L("Apps kept in the Dock show only while they run."))
            optionToggle(.showHidden, L("Dim hidden apps"), L("An app hidden with ⌘H shows a translucent icon."))
            optionToggle(.showRecents, L("Show recent apps"), L("Up to three apps used lately, in their own section."))
            optionToggle(.launchAnimation, L("Bounce apps while they open"), nil)
            optionToggle(.lockContents, L("Freeze the icons in the Dock"), L("No icon can be added, removed or dragged to another place. This doesn't keep the Dock on a display: for that, see Dock on One Display, above."))
            optionToggle(.lockSize, L("Lock the Dock's size"), nil)
            LabeledContent {
                HStack {
                    Button(L("Save Now")) { prefs.saveBackup() }
                    Button(L("Restore…")) { confirmRestore() }
                        .disabled(prefs.backupDate == nil)
                }
            } label: {
                Text(L("Copy of the Dock"))
                if let date = prefs.backupDate {
                    Text(L("Saved \(date.formatted(date: .abbreviated, time: .shortened)). Restoring brings back its icons, spaces and options."))
                } else {
                    Text(L("Saved by itself before Sirena changes the Dock for the first time."))
                }
            }
        } header: {
            SettingsSubheader(L("Dock Options"), symbol: "dock.rectangle")
        }
    }

    private func optionToggle(_ option: DockOption, _ title: String, _ detail: String?) -> some View {
        Toggle(isOn: Binding(get: { prefs.isOn(option) }, set: { prefs.set(option, $0) })) {
            Text(title)
            if let detail { Text(detail) }
        }
    }

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = L("Restore the Dock from the copy?")
        alert.informativeText = L("Its icons, spaces and options go back to how they were when the copy was saved.")
        alert.addButton(withTitle: L("Restore"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { prefs.restoreBackup() }
    }
}

/// The apps side of the Dock as a strip: click between two icons for a space, on a space to
/// remove it.
private struct DockStrip: View {
    let prefs: DockPreferences

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(prefs.tiles) { tile in
                    SpacerSlot(index: tile.id, prefs: prefs)
                    DockTileView(tile: tile, prefs: prefs)
                }
                SpacerSlot(index: prefs.tiles.count, prefs: prefs)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.automatic)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SpacerSlot: View {
    let index: Int
    let prefs: DockPreferences
    @State private var hovering = false

    var body: some View {
        Menu {
            Button(L("Small Space")) { prefs.insertSpacer(small: true, at: index) }
            Button(L("Large Space")) { prefs.insertSpacer(small: false, at: index) }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 16, height: 36)
        .opacity(hovering ? 1 : 0.18)
        .onHover { hovering = $0 }
        .help(L("Put a space here"))
    }
}

private struct DockTileView: View {
    let tile: DockTile
    let prefs: DockPreferences
    @State private var hovering = false

    var body: some View {
        switch tile.kind {
        case .spacer, .smallSpacer:
            Button {
                prefs.removeSpacer(at: tile.id)
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(hovering ? 0.8 : 0.35), lineWidth: 1)
                    .overlay {
                        if hovering { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                    }
                    .frame(width: tile.kind == .smallSpacer ? 14 : 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(tile.kind == .smallSpacer ? L("Small space — click to remove") : L("Large space — click to remove"))
        case .app, .other:
            Group {
                if let path = tile.path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .help(tile.label)
        }
    }
}

/// Two displays, the Dock held on the left one with a small lock.
private struct DockLockDrawing: View {
    var body: some View {
        HStack(spacing: 4) {
            miniDisplay(dock: true)
            miniDisplay(dock: false)
        }
    }

    private func miniDisplay(dock: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.primary.opacity(0.18)).frame(height: 3)
            Spacer(minLength: 0)
            if dock {
                HStack(spacing: 2) {
                    Capsule().fill(.primary.opacity(0.25)).frame(width: 22, height: 4)
                    Image(systemName: "lock.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 3)
            }
        }
        .frame(width: 46, height: 34)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}

