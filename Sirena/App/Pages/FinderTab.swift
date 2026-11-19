/// FinderTab.swift

import DockKit
import SwiftUI

/// The Finder tab of Janela e Dock (what used to be the Melhorias page).
struct FinderTab: View {
    @State private var settings = TweaksSettings.shared
    @State private var manager = ModuleManager.shared
    @State private var hasAccessibility = Showcase.accessibilityShown()

    var body: some View {
        Form {
            Section {
                FeatureSwitch(module: .tweaks, title: L("Finder Improvements"),
                              caption: L("Cut and paste files, delete with ⌫, “Copy Path”, installing apps from disk images and more."))
            }

            if manager.isEnabled(.tweaks) && !hasAccessibility {
                Section {
                    LabeledContent {
                        Button(L("Allow…")) { TweaksController.shared.requestAccessibility() }
                    } label: {
                        Label {
                            Text(L("Accessibility"))
                            Text(L("Needed to change what keys do in the Finder."))
                        } icon: {
                            Image(systemName: "accessibility").foregroundStyle(.orange)
                        }
                    }
                } header: {
                    SettingsSubheader(L("App Permissions"), symbol: "exclamationmark.triangle.fill")
                }
            }

            if manager.isEnabled(.tweaks) {
            Section {
                Toggle(isOn: $settings.finderCutAndPaste) {
                    Text(L("Move files with cut and paste"))
                    Text(L("⌘X then ⌘V moves the selected files instead of copying them."))
                }
                Toggle(L("Play sound effect when cutting"), isOn: $settings.finderCutSound)
                    .disabled(!settings.finderCutAndPaste)
                Toggle(L("Move files to trash with ⌫ instead of ⌘⌫"), isOn: $settings.finderDeleteMovesToTrash)
                Toggle(isOn: $settings.finderAddressBar) {
                    Text(L("Address bar with ⌘L"))
                    Text(L("In a Finder window, ⌘L shows its path to edit or paste another one; Return takes the window there, Tab completes."))
                }
                Toggle(isOn: $settings.finderCopyPath) {
                    Text(L("“Copy Path” in the Finder menu"))
                    Text(L("Right-click files or folders to copy their full path."))
                }
                Toggle(isOn: $settings.installFromDMG) {
                    Text(L("Install apps from disk images"))
                    Text(L("Opening a .dmg with an app offers to install it: it goes to Applications, the disk image is ejected and the .dmg goes to the Trash."))
                }
            } header: {
                SettingsSubheader(L("Finder"), symbol: "folder")
            }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = Showcase.accessibilityShown()
        }
    }
}
