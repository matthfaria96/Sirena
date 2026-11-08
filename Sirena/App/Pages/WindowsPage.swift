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

    var body: some View {
        Form {
            if !hasAccessibility {
                Section {
                    LabeledContent {
                        Button(L("Allow…")) { AppDelegate.instance.windowManagement.requestAuthorization() }
                    } label: {
                        Label {
                            Text(L("Accessibility"))
                            Text(L("Needed to move and resize windows and to use the switcher."))
                        } icon: {
                            Image(systemName: "accessibility").foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text(L("App Permissions"))
                }
            }

            // Rectangle: shortcuts and snapping.
            Section {
                FeatureSwitch(module: .windows, title: L("Arrange windows"),
                              caption: L("Snap, resize and move windows with shortcuts or by dragging to the screen edges."))
                if manager.isOn(.windows) {
                    Toggle(isOn: $tweaks.greenButtonFills) {
                        Text(L("Fill window when clicking green traffic light button"))
                        Text(L("Like a double-click on the title bar, instead of full screen. Click again to restore the size."))
                    }
                }
            } header: {
                Text(L("Apps & Windows"))
            }

            if manager.isOn(.windows) {
                Section {
                    Toggle(isOn: $advanced.animation()) {
                        Text(L("Advanced mode"))
                        Text(L("Snap areas: what each edge and corner of the screen does when you drag a window there."))
                    }
                }
                if advanced {
                    SnapAreaSettingsView()
                }
                Section {
                    LabeledContent {
                        Button(L("Open Shortcuts")) { PageNavigator.shared.requestedTab = "shortcuts" }
                    } label: {
                        Text(L("Shortcuts"))
                        Text(L("Every window and switcher shortcut is in the Shortcuts tab."))
                    }
                }
            }

            // Sirena's ⌘ Tab switcher (from Vorssaint).
            Section {
                FeatureSwitch(module: .switcher, title: L("Window Switcher"),
                              caption: ModuleID.switcher.summary)
            } header: {
                Text(L("⌘ Tab"))
            }
            if manager.isOn(.switcher) {
                WindowSwitcherSettingsView()
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = Showcase.accessibilityShown()
        }
    }

}

// MARK: - Dock

private struct DockTab: View {
    @State private var manager = ModuleManager.shared
    @State private var tweaks = TweaksSettings.shared
    @AppStorage(SirenaMinimize.hidesAppKey) private var hidesApp = true
    @State private var hasScreenRecording = Showcase.screenRecordingShown()

    var body: some View {
        Form {
            Section {
                FeatureSwitch(module: .dock, title: L("Dock Previews"),
                              caption: L("Hover an app in the Dock to see its windows, and click one to bring it forward."))
                if manager.isOn(.dock) && !hasScreenRecording {
                    LabeledContent {
                        Button(L("Allow…")) { DockController.requestScreenRecordingPermission() }
                    } label: {
                        Text(L("Screen Recording"))
                        Text(L("Needed to show window thumbnails. Without it, previews show only titles and icons."))
                    }
                }
            }

            if manager.isOn(.dock) {
                SirenaDockSettingsSections()
            }

            // One choice says how windows are put away; the Dock click follows it.
            Section {
                Picker(L("Minimizing"), selection: $hidesApp) {
                    Text(L("Hides the app: all windows go and come back together")).tag(true)
                    Text(L("Sends each window to the Dock, like macOS")).tag(false)
                }
                if hidesApp && !manager.isOn(.dock) {
                    Label(L("Turn on Dock Previews above: they notice when a window is minimized."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Toggle(isOn: $tweaks.dockClickPutsAway) {
                    Text(L("Clicking the app in front in the Dock puts its windows away"))
                    Text(hidesApp ? L("Hides the app, like minimizing. Click it again to bring everything back.")
                                  : L("Minimizes all of its windows at once, without the one-by-one animation."))
                }
                if !hidesApp {
                    Toggle(L("Unminimize all windows instead of one when clicking Dock icon"), isOn: $tweaks.dockUnminimizeAll)
                }
            } header: {
                Text(L("Minimizing Windows"))
            } footer: {
                Text(hidesApp
                     ? L("Minimizing a window (yellow button, ⌘M or Minimize All) hides all of the app's windows at once, instead of macOS shrinking them one by one. Click the app in the Dock, or pick it with ⌘ Tab, and they all come back together.")
                     : L("Each window goes into the Dock, as macOS does it. Bringing them back, macOS animates one window at a time."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("Clicking a Dock folder reveals it in Finder instead of showing its contents"), isOn: $tweaks.dockFoldersOpenInFinder)
            } header: {
                Text(L("Dock Clicks"))
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            hasScreenRecording = Showcase.screenRecordingShown()
        }
    }
}
