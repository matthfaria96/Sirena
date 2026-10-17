/// GeneralPage.swift

import AVFoundation
import DockKit
import SwiftUI

struct GeneralPage: View {
    @State private var launchOnLogin = Defaults.launchOnLogin.enabled
    @State private var hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
    @State private var manager = ModuleManager.shared
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var hasScreenRecording = DockController.hasScreenRecordingPermission
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
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
                permissionRow(L("Camera"), L("Needed for the mirror and “Peek” from the menu."),
                              granted: AVCaptureDevice.authorizationStatus(for: .video) == .authorized) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in }
                }
                permissionRow(L("Microphone"), L("Needed for the microphone level in the mirror and the microphone controls."),
                              granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                }
            } header: {
                Text(L("Permissions"))
            } footer: {
                Text(L("Sirena only asks for what its features need. Everything stays on this Mac."))
            }
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
                ShortcutRow(title: L("Open Sirena on Home"), defaultsKey: AppDelegate.openHomeShortcutKey,
                            recordingObserver: recordingObserver)
                if hideMenuBarIcon {
                    Text(L("Open Sirena again from Finder or Spotlight to see this window."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sirena")
            }

            AboutSections()
        }
        .formStyle(.grouped)
        .toolbar { BackToHomeButton() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = AXIsProcessTrusted()
            hasScreenRecording = DockController.hasScreenRecordingPermission
        }
    }
}

private extension GeneralPage {
    func permissionRow(_ title: String, _ caption: String, granted: Bool, request: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label(L("Allowed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(L("Allow Access…"), action: request)
            }
        } label: {
            Text(title)
            Text(caption)
        }
    }
}
