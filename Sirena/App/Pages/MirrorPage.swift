/// MirrorPage.swift

import AVFoundation
import SwiftUI

struct MirrorPage: View {
    var body: some View {
        ModulePage(module: .mirror, tabs: [
            PageTab("general", L("General")) { MirrorSettingsView() }
        ]) {
            MirrorToggleButton()
        }
    }
}

private struct MirrorToggleButton: View {
    @State private var state = MirrorState.shared

    var body: some View {
        Button {
            MirrorController.shared.toggle()
        } label: {
            Label(state.isVisible ? L("Hide Mirror") : L("Show Mirror"), systemImage: "person.crop.circle")
        }
    }
}

private struct MirrorSettingsView: View {
    @State private var settings = MirrorSettings.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    private let cameras = MirrorCamera.availableCameras()

    var body: some View {
        Form {
            Section {
                Picker(L("Show the mirror"), selection: $settings.displayMode) {
                    ForEach(MirrorDisplayMode.allCases) { Text($0.title).tag($0) }
                }
                Picker(L("Size"), selection: $settings.size) {
                    ForEach(MirrorSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("Shape"), selection: $settings.shape) {
                    ForEach(MirrorShape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("Mirror the image"), isOn: $settings.mirrored)
                Picker(selection: $settings.peekSeconds) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text(L("\($0) seconds")).tag($0) }
                } label: {
                    Text(L("“Peek” from the menu lasts"))
                    Text(L("The camera opens below the menu bar with a countdown and closes by itself."))
                }
                Picker(L("Zoom"), selection: $settings.zoom) {
                    Text("1×").tag(1.0)
                    Text(1.5.formatted(.number) + "×").tag(1.5)
                    Text("2×").tag(2.0)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L("Mirror"))
            }

            Section {
                Picker(L("Camera"), selection: Binding(
                    get: { settings.cameraID ?? "" },
                    set: { id in
                        if let camera = cameras.first(where: { $0.uniqueID == id }) {
                            MirrorCamera.shared.switchTo(camera)
                        } else {
                            settings.cameraID = nil
                        }
                    }
                )) {
                    Text(cameras.isEmpty ? L("No Camera Available") : L("Automatic")).tag("")
                    ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                Toggle(isOn: $settings.showMicrophoneLevel) {
                    Text(L("Show microphone level"))
                    Text(L("Check you can be heard before a call. Asks for microphone access."))
                }
            } header: {
                Text(L("Camera & microphone"))
            }

            Section {
                Toggle(isOn: $settings.snapsEnabled) {
                    Text(L("Snaps"))
                    Text(L("A shutter button on the mirror takes a photo of you."))
                }
                if settings.snapsEnabled {
                    LabeledContent(L("Save to")) {
                        HStack {
                            Text(FileManager.default.displayName(atPath: settings.snapsFolder.path))
                                .foregroundStyle(.secondary)
                            Button(L("Choose…")) { chooseFolder() }
                        }
                    }
                    Toggle(L("Also copy to the clipboard"), isOn: $settings.snapsCopyToClipboard)
                }
            } header: {
                Text(L("Snaps"))
            }

            Section {
                Toggle(isOn: $settings.notchTrigger) {
                    Text(L("Open by resting the pointer on the notch"))
                    Text(L("On Macs without a notch, rest the pointer at the top center of the screen."))
                }
                if settings.notchTrigger {
                    Picker(L("Display"), selection: $settings.triggerDisplay) {
                        ForEach(MirrorTriggerDisplay.allCases) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text(L("Notch"))
            }

            Section {
                ShortcutRow(title: L("Show / hide the mirror"), defaultsKey: MirrorController.shortcutKey,
                            recordingObserver: recordingObserver)
            } header: {
                Text(L("Keyboard shortcut"))
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.snapsFolder
        if panel.runModal() == .OK, let url = panel.url {
            settings.snapsFolder = url
        }
    }
}
