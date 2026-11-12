/// WindowsPage.swift
///
/// "Janela e Dock": everything about windows, the Dock and switching between them, on
/// one page. Janelas holds Rectangle (window actions, snapping), Sirena's ⌘ Tab switcher
/// (from Vorssaint) and the green button; Dock holds DockDoor's previews and the Dock
/// click tweaks. Each feature keeps its own switch inside the page.

import DockKit
import MASShortcut
import SwiftUI

struct WindowsPage: View {
    var body: some View {
        ModulePage(module: .windows, tabs: [
            PageTab("windows", L("Windows")) { WindowsTab() },
            PageTab("dock", L("Dock")) { DockTab() },
            PageTab("finder", L("Finder")) { FinderTab() },
            PageTab("shortcuts", L("Shortcuts")) { ShortcutsTab() }
        ], switchable: false)
    }
}

// MARK: - A feature's switch inside the page

struct FeatureSwitch: View {
    let module: ModuleID
    let title: String
    let caption: String
    @State private var manager = ModuleManager.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { manager.isEnabled(module) && !manager.pendingRestart.contains(module) },
            set: { manager.setEnabled(module, $0) }
        )) {
            Text(title)
            Text(caption)
        }
        if manager.pendingRestart.contains(module) {
            LabeledContent {
                Button(L("Restart Now")) { manager.relaunch() }
            } label: {
                Label(L("This feature stops completely after Sirena restarts."), systemImage: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private extension ModuleManager {
    func isOn(_ module: ModuleID) -> Bool { isEnabled(module) && !pendingRestart.contains(module) }
}

// MARK: - Janelas

private struct WindowsTab: View {
    @State private var manager = ModuleManager.shared
    @State private var tweaks = TweaksSettings.shared
    @State private var hasAccessibility = Showcase.accessibilityShown()
    @AppStorage("windowsAdvancedMode") private var advanced = false
    @AppStorage(ZoneController.enabledKey) private var snapLayouts = true
    @State private var recordingObserver = ShortcutRecordingObserver()
    /// The snap panel rides on drag-to-snap: off, the panel never shows.
    @State private var snappingOn = !Defaults.windowSnapping.userDisabled

    var body: some View {
        Form {
            if !hasAccessibility {
                Section {
                    LabeledContent {
                        Button(L("Allow…")) { AppDelegate.instance.windowManagement.requestAuthorization() }
                    } label: {
                        Text(L("Accessibility"))
                        Text(L("Needed to move and resize windows and to use the switcher."))
                    }
                } header: {
                    SettingsSubheader(L("App Permissions"), symbol: "exclamationmark.triangle.fill")
                }
            }

            // 1. Arranging windows (Rectangle): the switch, then its sub-topics.
            Section {
                FeatureDrawingRow {
                    ArrangeDrawing()
                } content: {
                    FeatureSwitch(module: .windows, title: L("Arrange windows"),
                                  caption: L("Snap, resize and move windows with shortcuts or by dragging to the screen edges."))
                }
                if manager.isOn(.windows) {
                    LabeledContent {
                        Button(L("Open Shortcuts")) { PageNavigator.shared.requestedTab = "shortcuts" }
                    } label: {
                        Text(L("Shortcuts"))
                        Text(L("Every window and switcher shortcut is in the Shortcuts tab."))
                    }
                }
            } header: {
                SettingsSubheader(L("Arrange Windows"), symbol: "rectangle.split.2x2")
            }

            if manager.isOn(.windows) {
                Section {
                    PictureCardPicker(selection: $tweaks.greenButtonFills, choices: [
                        PictureChoice(false, L("Full screen, like macOS"),
                                      detail: L("The window takes the whole screen in its own space; the menu bar and the Dock go away.")) {
                            GreenButtonDrawing(fills: false)
                        },
                        PictureChoice(true, L("Fill the screen"),
                                      detail: L("Like a double-click on the title bar: the window fills the screen and stays with the others. Click again to restore its size.")) {
                            GreenButtonDrawing(fills: true)
                        }
                    ])
                } header: {
                    SettingsSubheader(L("Green button"), parent: L("Arrange Windows"), symbol: "plus.circle.fill")
                }
                SnapAreaSettingsView(showsDetails: $advanced) {
                    // The snap popup: drag a window to the top middle of the screen, pick a zone.
                    Section {
                        FeatureDrawingRow {
                            ZonesDrawing()
                        } content: {
                            Toggle(isOn: $snapLayouts) {
                                Text(L("Layouts at the top of the screen"))
                                Text(L("Drag a window to the top middle of the screen and a panel drops with layouts: let go over a zone to put the window there. Esc cancels."))
                            }
                        }
                        if snapLayouts {
                            LabeledContent {
                                MASShortcutViewRepresentable(defaultsKey: ZoneController.shortcutKey,
                                                             validator: SirenaShortcutValidator(ownKey: ZoneController.shortcutKey),
                                                             recordingObserver: recordingObserver)
                                    .frame(width: 160, height: 22)
                                    .fixedSize()
                            } label: {
                                Text(L("Layouts for the window in front"))
                                Text(L("Opens the panel without dragging: arrows choose a zone, ↑ ↓ another layout, Return snaps the window. ⌃⌥ is ctrl + start on a Logitech keyboard."))
                            }
                        }
                        if snapLayouts && !snappingOn {
                            Label(L("Dragging needs “Snap windows by dragging”, above, turned on."), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        SettingsSubheader(L("Snap Layouts"), parent: L("Arrange Windows"), symbol: "rectangle.split.3x1")
                    } footer: {
                        if snapLayouts {
                            Text(L("In the middle of the top edge the panel takes the place of the top snap area; the top corners keep theirs. Windows put in a layout move together: drag the grip between two of them to resize both, click it to let them go."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 2. Sirena's ⌘ Tab switcher (from Vorssaint).
            Section {
                FeatureDrawingRow {
                    SwitcherDrawing()
                } content: {
                    FeatureSwitch(module: .switcher, title: L("Window Switcher"),
                                  caption: ModuleID.switcher.summary)
                }
            } header: {
                SettingsSubheader(L("⌘ Tab"), symbol: "rectangle.stack")
            }
            if manager.isOn(.switcher) {
                WindowSwitcherSettingsView()
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = Showcase.accessibilityShown()
        }
        .onChange(of: snapLayouts) { _, _ in ZoneController.shared.enabledChanged() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.windowSnapping)) { note in
            snappingOn = note.object as? Bool ?? !Defaults.windowSnapping.userDisabled
        }
    }

}

// MARK: - Dock

private struct DockTab: View {
    @State private var manager = ModuleManager.shared
    @State private var tweaks = TweaksSettings.shared
    @AppStorage(SirenaMinimize.hidesAppKey) private var hidesApp = SirenaMinimize.hidesAppDefault
    @AppStorage(SirenaMinimize.dockTogetherKey) private var dockTogether = SirenaMinimize.dockTogetherDefault
    @State private var hasScreenRecording = Showcase.screenRecordingShown()

    var body: some View {
        Form {
            // 1. Minimizing: the main choice, first.
            Section {
                MinimizeModePicker(hidesApp: $hidesApp, dockTogether: $dockTogether)
                if hidesApp && !manager.isOn(.dock) {
                    LabeledContent {
                        Button(L("Turn On")) { manager.setEnabled(.dock, true) }
                    } label: {
                        Label(L("Needs Dock Previews, which notice when a window is minimized."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                SettingsSubheader(L("Minimizing Windows"), symbol: "macwindow.on.rectangle")
            } footer: {
                Text(hidesApp
                     ? L("Works with the yellow button, ⌘M, Minimize All and a click on the app in front in the Dock. Click the app in the Dock, or pick it with ⌘ Tab, and every window comes back at once.")
                     : dockTogether
                     ? L("The yellow button and ⌘M minimize only that window. Click the app in front in the Dock and all of its windows go at once; click it again and all of them come back, the minimized ones too.")
                     : L("Sirena leaves minimizing and Dock clicks to macOS."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 2. What clicking things in the Dock does.
            Section {
                LabeledContent {
                    Text(hidesApp || dockTogether ? L("Hides all of its windows") : L("What macOS does"))
                        .foregroundStyle(.secondary)
                } label: {
                    Text(L("Clicking the app in front"))
                    Text(L("Follows the minimize mode above."))
                }
                Toggle(L("Clicking a Dock folder reveals it in Finder instead of showing its contents"), isOn: $tweaks.dockFoldersOpenInFinder)
                if manager.isOn(.dock) {
                    DockQuitClickToggle()
                }
            } header: {
                SettingsSubheader(L("Dock Clicks"), symbol: "cursorarrow.click.2")
            }

            // 3. The previews: a switch, then their own sub-topics.
            Section {
                HStack(alignment: .center, spacing: 14) {
                    DockPreviewDrawing()
                        .frame(width: 110, height: 86)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        FeatureSwitch(module: .dock, title: L("Dock Previews"),
                                      caption: L("Hover an app in the Dock to see its windows, and click one to bring it forward."))
                    }
                }
                .padding(.vertical, 2)
                if manager.isOn(.dock) && !hasScreenRecording {
                    LabeledContent {
                        Button(L("Allow…")) { DockController.requestScreenRecordingPermission() }
                    } label: {
                        Text(L("Screen Recording"))
                        Text(L("Needed to show window thumbnails. Without it, previews show only titles and icons."))
                    }
                }
            } header: {
                SettingsSubheader(L("Dock Previews"), symbol: "rectangle.on.rectangle")
            } footer: {
                if manager.isOn(.dock) {
                    Text(L("Their settings are below, by topic."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if manager.isOn(.dock) {
                SirenaDockSettingsSections()
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            hasScreenRecording = Showcase.screenRecordingShown()
        }
    }
}
