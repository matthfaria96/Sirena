/// GeneralPage.swift

import DockKit
import SwiftUI

struct GeneralPage: View {
    @State private var launchOnLogin = Defaults.launchOnLogin.enabled
    @State private var hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
    @State private var manager = ModuleManager.shared
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var hasScreenRecording = DockController.hasScreenRecordingPermission

    var body: some View {
        Form {
            Section {
                Toggle(L("Open Sirena at login"), isOn: $launchOnLogin)
                    .onChange(of: launchOnLogin) {
                        LaunchOnLogin.isEnabled = launchOnLogin
                        Defaults.launchOnLogin.enabled = launchOnLogin
                    }
                Toggle(L("Hide the Sirena icon in the menu bar"), isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) {
                        Defaults.hideMenuBarIcon.enabled = hideMenuBarIcon
                        SirenaStatusItem.instance.refreshVisibility()
                    }
                if hideMenuBarIcon {
                    Text(L("Open Sirena again from Finder or Spotlight to see this window."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sirena")
            }

            Section {
                ForEach(ModuleID.allCases.filter { !$0.isTool }) { module in
                    Toggle(isOn: Binding(
                        get: { manager.isEnabled(module) && !manager.pendingRestart.contains(module) },
                        set: { manager.setEnabled(module, $0) }
                    )) {
                        Label {
                            Text(module.title)
                            Text(L("Based on \(module.origin.name)"))
                        } icon: {
                            ModuleIcon(module: module, size: 24)
                        }
                    }
                }
                if !manager.pendingRestart.isEmpty {
                    HStack {
                        Text(L("Some features stop completely after Sirena restarts."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Restart Now")) { manager.relaunch() }
                    }
                }
            } header: {
                Text(L("Features"))
            }

            Section {
                LabeledContent {
                    if isTrusted {
                        Label(L("Allowed"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L("Allow Access…")) {
                            AppDelegate.instance.windowManagement.requestAuthorization()
                        }
                    }
                } label: {
                    Text(L("Accessibility"))
                    Text(L("Needed to move windows, paste from the clipboard history and keep apps active."))
                }
                LabeledContent {
                    if hasScreenRecording {
                        Label(L("Allowed"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L("Allow Access…")) {
                            DockController.requestScreenRecordingPermission()
                        }
                    }
                } label: {
                    Text(L("Screen Recording"))
                    Text(L("Needed to show window thumbnails in Dock previews and the window switcher."))
                }
            } header: {
                Text(L("Permissions"))
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = AXIsProcessTrusted()
            hasScreenRecording = DockController.hasScreenRecordingPermission
        }
    }
}
