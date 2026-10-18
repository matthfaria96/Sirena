/// MixerPage.swift
///
/// Mixer de som: settings first, like every other page (control style, options),
/// then the sound itself as standard macOS rows — output, microphone, each app.
/// The menu bar keeps its own compact version.

import AppKit
import SwiftUI

struct MixerPage: View {
    var body: some View {
        ModulePage(module: .mixer, tabs: [
            PageTab("mixer", L("Mixer")) { MixerSettingsForm() }
        ])
    }
}

private struct MixerSettingsForm: View {
    @ObservedObject private var mixer = SirenaAppVolumeMixer.shared
    @ObservedObject private var input = SirenaMixerInputManager.shared
    @AppStorage(SirenaMixerDefaultsKey.glassSliders) private var glass = true
    @AppStorage(SirenaMixerDefaultsKey.mixerHideInactiveApps) private var hideInactive = false
    @AppStorage(SirenaMixerDefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect) private var lowerOnDisconnect = true
    @AppStorage(SirenaMixerDefaultsKey.mixerHeadphonesDisconnectVolumePercent) private var disconnectPercent = 25

    var body: some View {
        Form {
            Section {
                Picker(selection: $glass) {
                    Text(L("Glass")).tag(true)
                    Text(L("Basic")).tag(false)
                } label: {
                    Text(L("Control style"))
                    Text(L("How the volume sliders look in the menu bar menu."))
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L("Appearance"))
            }

            Section {
                Toggle(isOn: $hideInactive) {
                    Text(L("Hide apps that aren't playing"))
                    Text(L("Only apps making sound right now appear in the list."))
                }
                Toggle(isOn: $lowerOnDisconnect) {
                    Text(L("Lower the volume when headphones disconnect"))
                    Text(L("So the sound doesn't blast through the speakers when you unplug or the Bluetooth drops."))
                }
                if lowerOnDisconnect {
                    Picker(L("Lower to"), selection: $disconnectPercent) {
                        ForEach([0, 10, 25, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }
                }
            } header: {
                Text(L("Options"))
            }

            Section {
                Picker(L("Play sound on"), selection: Binding(
                    get: { mixer.currentOutputDeviceUID ?? "" },
                    set: { if !$0.isEmpty { mixer.setUniversalOutputDeviceUID($0) } })) {
                    ForEach(mixer.outputDevices.filter(\.canBeDefaultOutput)) { Text($0.name).tag($0.uid) }
                }
                if let volume = mixer.systemOutputVolume {
                    VolumeRow(title: L("Volume"), symbol: "speaker.wave.2.fill", value: volume, maximum: 1) {
                        mixer.setCurrentOutputVolume($0)
                    }
                }
                Picker(L("System sounds on"), selection: Binding(
                    get: { mixer.currentSystemSoundOutputDeviceUID ?? "" },
                    set: { if !$0.isEmpty { mixer.setSystemSoundOutputDeviceUID($0) } })) {
                    ForEach(mixer.outputDevices.filter(\.canBeDefaultSystemOutput)) { Text($0.name).tag($0.uid) }
                }
            } header: {
                Text(L("Output"))
            }

            Section {
                Picker(L("Microphone"), selection: Binding(
                    get: { input.preferredInputDeviceUID ?? "" },
                    set: { input.setPreferredInputDeviceUID($0.isEmpty ? nil : $0) })) {
                    Text(L("System default")).tag("")
                    ForEach(input.inputDevices) { Text($0.name).tag($0.uid) }
                }
                if let volume = input.inputVolume {
                    VolumeRow(title: L("Input volume"), symbol: "mic.fill", value: volume, maximum: 1) {
                        input.setInputVolume($0)
                    }
                }
            } header: {
                Text(L("Microphone"))
            }

            Section {
                let apps = mixer.apps.filter { !hideInactive || $0.isPlaying }
                if mixer.needsPermission {
                    LabeledContent {
                        Button(L("Allow…")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        Text(L("Audio access needed"))
                        Text(L("Needed to change each app's volume."))
                    }
                } else if apps.isEmpty {
                    Text(L("Apps playing sound show up here."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(apps) { app in
                        AppVolumeRow(app: app)
                    }
                }
            } header: {
                Text(L("Volume of each app"))
            } footer: {
                Text(L("Up to 200%. Above 100% the sound is boosted."))
            }
        }
        .formStyle(.grouped)
        .onAppear { SirenaMixer.shared.start() }
    }
}

/// A standard row: name and symbol, a slider, the percent.
private struct VolumeRow: View {
    let title: String
    let symbol: String
    let value: Double
    let maximum: Double
    let set: (Double) -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: set), in: 0...maximum)
                    .frame(minWidth: 180)
                Text("\(Int((value * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

private struct AppVolumeRow: View {
    let app: SirenaMixerApp
    private var mixer: SirenaAppVolumeMixer { .shared }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                if app.isBypassed {
                    Text(L("Managed by the app")).foregroundStyle(.secondary)
                } else {
                    Slider(value: Binding(get: { app.volume }, set: { mixer.setVolume($0, for: app) }),
                           in: 0...SirenaAppVolumeMixer.maxVolume)
                        .frame(minWidth: 180)
                        .tint(app.volume > 1 ? .orange : nil)
                    Text("\(Int((app.volume * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(app.volume > 1 ? .orange : .secondary)
                        .frame(width: 44, alignment: .trailing)
                    Button {
                        mixer.toggleMute(app)
                    } label: {
                        Image(systemName: app.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(app.volume <= 0.001 ? L("Unmute") : L("Mute"))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSRunningApplication(processIdentifier: app.ownerPid)?.icon ?? NSImage())
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                if app.isPlaying {
                    Circle().fill(.green).frame(width: 6, height: 6)
                        .help(L("Playing now"))
                }
            }
        }
    }
}
