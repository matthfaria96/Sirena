/// FinderTab.swift

import SwiftUI

/// The Finder tab of Janela e Dock (what used to be the Melhorias page).
struct FinderTab: View {
    @State private var settings = TweaksSettings.shared
    @State private var manager = ModuleManager.shared
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                FeatureSwitch(module: .tweaks, title: L("Finder Improvements"),
                              caption: L("Cut and paste files, delete with ⌫, “Copy Path”, installing apps from disk images and more."))
            }

            if !hasAccessibility {
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
                    Text(L("App Permissions"))
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
                Toggle(isOn: $settings.finderCopyPath) {
                    Text(L("“Copy Path” in the Finder menu"))
                    Text(L("Right-click files or folders to copy their full path."))
                }
                Toggle(isOn: $settings.installFromDMG) {
                    Text(L("Install apps from disk images"))
                    Text(L("Opening a .dmg with an app offers to install it: it goes to Applications, the disk image is ejected and the .dmg goes to the Trash."))
                }
                Toggle(isOn: $settings.screenshotsShowPointer) {
                    Text(L("Show mouse pointer in screenshots"))
                    Text(L("Applies to ⇧⌘3, ⇧⌘4 and ⇧⌘5."))
                }
            } header: {
                Text(L("Finder"))
            }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasAccessibility = AXIsProcessTrusted()
            settings.refresh()
        }
    }
}
