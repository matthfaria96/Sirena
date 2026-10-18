/// ScreenCapturePage.swift

import SwiftUI

struct ScreenCapturePage: View {
    var body: some View {
        ModulePage(module: .screenCapture, tabs: [
            PageTab("general", L("General")) { ScreenCaptureSettingsView() },
            PageTab("shortcuts", L("Shortcuts")) { ScreenCaptureShortcutsView() }
        ]) {
            Menu {
                ForEach(ScreenCaptureAction.allCases) { action in
                    Button { ScreenCaptureController.shared.run(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } label: {
                Label(L("Capture"), systemImage: "camera.fill")
            } primaryAction: {
                ScreenCaptureController.shared.run(.area)
            }
        }
    }
}

private struct ScreenCaptureSettingsView: View {
    @State private var controller = ScreenCaptureController.shared

    var body: some View {
        Form {
            Section {
                ForEach(ScreenCaptureAction.allCases) { action in
                    LabeledContent {
                        Button(L("Start")) { controller.run(action) }
                            .disabled(!controller.isRunning)
                    } label: {
                        Label {
                            Text(action.title)
                            Text(action.detail)
                        } icon: {
                            Image(systemName: action.symbol).foregroundStyle(ModuleID.screenCapture.tint)
                        }
                    }
                }
            } header: {
                Text(L("Capture"))
            } footer: {
                Text(L("Uses macOS's own Screenshot tool, starting directly in the mode you pick."))
            }

            Section {
                Toggle(isOn: $controller.copiesScreenshots) {
                    Text(L("Copy screenshots to the clipboard"))
                    Text(L("Instead of saving a file."))
                }
                Toggle(L("Include the pointer in full-screen screenshots"), isOn: $controller.showsCursor)
                Toggle(L("Open in Preview or QuickTime afterwards"), isOn: $controller.opensAfterCapture)
                LabeledContent(L("Saved to")) {
                    Text(ScreenCaptureController.saveFolder.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button(L("Show")) { NSWorkspace.shared.open(ScreenCaptureController.saveFolder) }
                }
            } header: {
                Text(L("Screenshots"))
            }

            Section {
                Toggle(L("Show clicks"), isOn: $controller.showsClicks)
                Toggle(isOn: $controller.recordsMicrophone) {
                    Text(L("Record the microphone"))
                    Text(L("Uses the default input."))
                }
            } header: {
                Text(L("Recordings"))
            } footer: {
                Text(L("Stop a recording from the red button at the top of the screen, or the Capture button in the ⚡ menu."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScreenCaptureShortcutsView: View {
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                ForEach(ScreenCaptureAction.allCases) { action in
                    ShortcutRow(title: action.title, defaultsKey: action.shortcutKey, recordingObserver: recordingObserver)
                }
            } footer: {
                Text(L("Optional: macOS keeps ⇧⌘3, ⇧⌘4 and ⇧⌘5."))
            }
        }
        .formStyle(.grouped)
    }
}
