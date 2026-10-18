// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; Sirena port.

import AppKit
import SwiftUI

/// Per-app volume sliders, the mixer macOS never shipped. Shows every app
/// holding an audio connection (a green dot marks the ones playing right now).
/// 100% is untouched passthrough; below it attenuates and above it (up to 200%)
/// boosts, with the slider and percentage turning amber in the boost range.
struct SirenaMixerView: View {
    @ObservedObject private var mixer = SirenaAppVolumeMixer.shared
    @ObservedObject private var inputManager = SirenaMixerInputManager.shared
    @AppStorage(SirenaMixerDefaultsKey.mixerAppArrangement)
    private var arrangementValue = ""
    @AppStorage(SirenaMixerDefaultsKey.mixerHideInactiveApps)
    private var hideInactiveApps = false
    @State private var optionsExpanded = false
    @State private var normalSliderTint = Color(nsColor: .controlAccentColor)
    @State private var accentRevision = 0
    @State private var lastResolvedAccent: NSColor?
    @State private var editingVolumeID: String?
    @State private var draggingAppID: String?
    @State private var dropTarget: SirenaMixerAppDropTarget?
    /// Shows Vorssaint's section title ("MIXER DE VOLUME") above the card.
    var showsTitle = false
    /// Width that fits Sirena's menu bar popover.
    var width: CGFloat? = 320
    /// The menu bar version: one volume row, expanding into two tabs (Saída, Microfone).
    var compact = false
    @State private var expanded = false
    @State private var tab = Tab.output

    private enum Tab: Hashable { case output, input }

    init(showsTitle: Bool = false, width: CGFloat? = 320, compact: Bool = false) {
        self.showsTitle = showsTitle
        self.width = width
        self.compact = compact
    }

    /// Sirena always uses the Liquid Glass sliders (no setting).
    private var glassEnabled: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(SirenaMixerStrings.section.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
            }
            if compact {
                compactControls
            } else {
                mixerControls.sirenaMixerCard()
            }
        }
        .frame(width: width)
        .onReceive(NSApplication.shared.publisher(for: \.effectiveAppearance, options: [.new])) { _ in
            refreshSliderTint()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSSystemColorsDidChangeNotification"))) { _ in
            refreshSliderTint()
        }
        .onAppear {
            // The engine starts with the first panel that shows it and keeps
            // running, so saved volumes keep applying while the panel is closed.
            SirenaMixer.shared.start()
            refreshSliderTint()
        }
    }

    private var mixerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            audioDevicesSection

            if SirenaAppVolumeMixer.isSupported, (!visibleApps.isEmpty || mixer.needsPermission) {
                Divider()
            }

            if !SirenaAppVolumeMixer.isSupported {
                emptyLabel(SirenaMixerStrings.unavailable)
            } else if mixer.needsPermission {
                permissionHint
            } else if visibleApps.isEmpty {
                emptyLabel(SirenaMixerStrings.empty)
            } else {
                mixerRows
            }

            Divider()
            optionsDisclosure
        }
    }

    // MARK: Compact (menu bar)

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Collapsed: just the Mac's volume, and a chevron to open the rest.
            HStack(spacing: 10) {
                Image(systemName: (mixer.systemOutputMuted == true || (mixer.systemOutputVolume ?? 0) <= 0.001)
                      ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .glassEffect(.regular.tint(Color.purple.opacity(0.25)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                if let volume = mixer.systemOutputVolume {
                    SirenaMixerVolumeSlider(value: systemOutputVolumeBinding, normalTint: normalSliderTint, boostTint: normalSliderTint,
                                            isBoosting: false, accentRevision: accentRevision, glassEnabled: glassEnabled,
                                            maximum: 1, accessibilityLabel: SirenaMixerStrings.systemOutputTitle)
                    Text("\(SirenaMixerRoutingSupport.displayPercent(forVolume: volume))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                } else {
                    Text(SirenaMixerStrings.outputUnavailable).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(expanded ? "Recolher" : "Saída, microfone e volume de cada app")
                .accessibilityLabel(expanded ? "Recolher o mixer" : "Expandir o mixer")
            }

            if expanded {
                Picker("", selection: $tab) {
                    Text("Saída").tag(Tab.output)
                    Text("Microfone").tag(Tab.input)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    if tab == .output {
                        VStack(alignment: .leading, spacing: 8) {
                            universalOutputPicker
                            systemSoundOutputPicker
                            if SirenaAppVolumeMixer.isSupported {
                                Divider()
                                if mixer.needsPermission {
                                    permissionHint
                                } else if visibleApps.isEmpty {
                                    emptyLabel(SirenaMixerStrings.empty)
                                } else {
                                    mixerRows
                                }
                            }
                        }
                    } else {
                        microphonePicker
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var audioDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            universalOutputPicker
            systemSoundOutputPicker
            microphonePicker
            if let outputSwitchError = mixer.outputSwitchError {
                inputMessage(String(format: SirenaMixerStrings.systemOutputErrorFormat, outputSwitchError),
                             systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(SirenaMixerStrings.options)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                SirenaMixerOptionsControls()
                    .padding(.leading, 19)
            }
        }
    }

    private var universalOutputPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label {
                    Text(SirenaMixerStrings.systemOutputTitle)
                        .font(.system(size: 11.5, weight: .medium))
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Picker(SirenaMixerStrings.systemOutputTooltip, selection: universalOutputSelectionBinding) {
                    if mixer.currentOutputDeviceUID == nil {
                        Text(SirenaMixerStrings.outputUnavailable)
                            .tag(SirenaMixerRoutingSupport.systemDefaultSelectionID)
                    }
                    ForEach(universalOutputDevices) { device in
                        Text(outputDeviceTitle(device))
                            .tag(device.uid)
                    }
                    if let selected = mixer.currentOutputDeviceUID,
                       !universalOutputDevices.contains(where: { $0.uid == selected }) {
                        Text(SirenaMixerStrings.outputUnavailable)
                            .tag(selected)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 164)
                .disabled(universalOutputDevices.isEmpty)
                .help(SirenaMixerStrings.systemOutputTooltip)
            }

            if let volume = mixer.systemOutputVolume {
                HStack(spacing: 8) {
                    Image(systemName: mixer.systemOutputMuted == true || volume <= 0.001
                          ? "speaker.slash.fill"
                          : "speaker.wave.2.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    SirenaMixerVolumeSlider(value: systemOutputVolumeBinding,
                                      normalTint: normalSliderTint,
                                      boostTint: normalSliderTint,
                                      isBoosting: false,
                                      accentRevision: accentRevision,
                                      glassEnabled: glassEnabled,
                                      maximum: 1,
                                      accessibilityLabel: SirenaMixerStrings.systemOutputTitle)

                    SirenaMixerEditablePercent(currentPercent: SirenaMixerRoutingSupport.displayPercent(forVolume: volume),
                                          maximumPercent: 100,
                                          width: 36,
                                          editorID: "system-output",
                                          editingID: $editingVolumeID,
                                          accessibilityLabel: SirenaMixerStrings.systemOutputTitle) {
                        Text("\(SirenaMixerRoutingSupport.displayPercent(forVolume: volume))%")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } onCommit: {
                        setSystemOutputVolume($0)
                    }
                }
            }

            if universalOutputDevices.isEmpty {
                inputMessage(SirenaMixerStrings.systemOutputNoDevices, systemImage: "speaker.slash")
            }
        }
    }

    private var systemSoundOutputPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label {
                    Text(SirenaMixerStrings.soundEffectsOutputTitle)
                        .font(.system(size: 11.5, weight: .medium))
                } icon: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Picker(SirenaMixerStrings.soundEffectsOutputTooltip,
                       selection: systemSoundOutputSelectionBinding) {
                    if mixer.currentSystemSoundOutputDeviceUID == nil {
                        Text(SirenaMixerStrings.outputUnavailable)
                            .tag(SirenaMixerRoutingSupport.systemDefaultSelectionID)
                    }
                    ForEach(systemSoundOutputDevices) { device in
                        Text(systemSoundOutputDeviceTitle(device))
                            .tag(device.uid)
                    }
                    if let selected = mixer.currentSystemSoundOutputDeviceUID,
                       !systemSoundOutputDevices.contains(where: { $0.uid == selected }) {
                        Text(SirenaMixerStrings.outputUnavailable)
                            .tag(selected)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 164)
                .disabled(systemSoundOutputDevices.isEmpty)
                .help(SirenaMixerStrings.soundEffectsOutputTooltip)
            }

            if systemSoundOutputDevices.isEmpty {
                inputMessage(SirenaMixerStrings.systemOutputNoDevices, systemImage: "bell.slash")
            }
        }
    }

    private var universalOutputDevices: [SirenaMixerOutputDevice] {
        mixer.outputDevices.filter(\.canBeDefaultOutput)
    }

    private var systemSoundOutputDevices: [SirenaMixerOutputDevice] {
        mixer.outputDevices.filter(\.canBeDefaultSystemOutput)
    }

    private var universalOutputSelectionBinding: Binding<String> {
        Binding(
            get: { mixer.currentOutputDeviceUID ?? SirenaMixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                guard selection != SirenaMixerRoutingSupport.systemDefaultSelectionID else { return }
                mixer.setUniversalOutputDeviceUID(selection)
            }
        )
    }

    private func setSystemOutputVolume(_ value: Double) {
        mixer.setCurrentOutputVolume(value)
    }

    private var systemOutputVolumeBinding: Binding<Double> {
        Binding(
            get: { mixer.systemOutputVolume ?? 0 },
            set: { setSystemOutputVolume($0) }
        )
    }

    private var systemSoundOutputSelectionBinding: Binding<String> {
        Binding(
            get: {
                mixer.currentSystemSoundOutputDeviceUID
                    ?? SirenaMixerRoutingSupport.systemDefaultSelectionID
            },
            set: { selection in
                guard selection != SirenaMixerRoutingSupport.systemDefaultSelectionID else { return }
                mixer.setSystemSoundOutputDeviceUID(selection)
            }
        )
    }

    private var microphonePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label {
                    Text(SirenaMixerStrings.inputTitle)
                        .font(.system(size: 11.5, weight: .medium))
                } icon: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 16)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Picker(SirenaMixerStrings.inputTooltip, selection: inputSelectionBinding) {
                    Text(SirenaMixerStrings.outputDefault)
                        .tag(SirenaMixerRoutingSupport.systemDefaultSelectionID)
                    ForEach(inputManager.inputDevices) { device in
                        Text(inputDeviceTitle(device))
                            .tag(device.uid)
                    }
                    if !false,
                       let selected = inputManager.preferredInputDeviceUID,
                       inputManager.preferredUnavailable {
                        Text(SirenaMixerStrings.inputUnavailable)
                            .tag(selected)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 164)
                .disabled(inputManager.inputDevices.isEmpty)
                .help(SirenaMixerStrings.inputTooltip)
            }

            if let volume = inputManager.inputVolume {
                HStack(spacing: 8) {
                    Image(systemName: volume <= 0.001 ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    SirenaMixerVolumeSlider(value: inputVolumeBinding,
                                      normalTint: normalSliderTint,
                                      boostTint: normalSliderTint,
                                      isBoosting: false,
                                      accentRevision: accentRevision,
                                      glassEnabled: glassEnabled,
                                      maximum: 1,
                                      accessibilityLabel: SirenaMixerStrings.inputTitle)

                    SirenaMixerEditablePercent(currentPercent: SirenaMixerRoutingSupport.displayPercent(forVolume: volume),
                                          maximumPercent: 100,
                                          width: 36,
                                          editorID: "microphone-input",
                                          editingID: $editingVolumeID,
                                          accessibilityLabel: SirenaMixerStrings.inputTitle) {
                        Text("\(SirenaMixerRoutingSupport.displayPercent(forVolume: volume))%")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } onCommit: {
                        inputManager.setInputVolume($0)
                    }
                }
            }

            if inputManager.inputDevices.isEmpty {
                inputMessage(SirenaMixerStrings.inputNoDevices, systemImage: "mic.slash")
            } else if !false, inputManager.preferredUnavailable {
                inputMessage(SirenaMixerStrings.inputFallback, systemImage: "mic.badge.xmark")
            } else if let lastError = inputManager.lastError {
                inputMessage(String(format: SirenaMixerStrings.inputErrorFormat, lastError),
                             systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var inputSelectionBinding: Binding<String> {
        Binding(
            get: {
                return SirenaMixerRoutingSupport.selectedInputDeviceUID(
                    preferredUID: inputManager.preferredInputDeviceUID,
                    currentUID: inputManager.currentInputDeviceUID,
                    priorityIsActive: false)
                    ?? SirenaMixerRoutingSupport.systemDefaultSelectionID
            },
            set: { selection in
                if false {
                    guard selection != SirenaMixerRoutingSupport.systemDefaultSelectionID else { return }
                    inputManager.setCurrentInputDeviceUID(selection)
                } else {
                    inputManager.setPreferredInputDeviceUID(
                        selection == SirenaMixerRoutingSupport.systemDefaultSelectionID ? nil : selection)
                }
            }
        )
    }

    private var inputVolumeBinding: Binding<Double> {
        Binding(
            get: { inputManager.inputVolume ?? 0 },
            set: { inputManager.setInputVolume($0) }
        )
    }

    private var arrangement: SirenaMixerAppArrangement { SirenaMixerAppArrangement(rawValue: arrangementValue) }

    private var visibleApps: [SirenaMixerApp] {
        arrangement.ordered(mixer.apps, identity: { $0.persistenceID }).filter { app in
            SirenaMixerRoutingSupport.shouldShowApp(isPlaying: app.isPlaying,
                                              volume: app.volume,
                                              selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                              hideInactiveApps: hideInactiveApps)
        }
    }

    private func inputDeviceTitle(_ device: SirenaMixerInputDevice) -> String {
        device.isDefault ? "\(device.name) (\(SirenaMixerStrings.outputCurrent))" : device.name
    }

    private func outputDeviceTitle(_ device: SirenaMixerOutputDevice) -> String {
        device.isDefault ? "\(device.name) (\(SirenaMixerStrings.outputCurrent))" : device.name
    }

    private func systemSoundOutputDeviceTitle(_ device: SirenaMixerOutputDevice) -> String {
        device.uid == mixer.currentSystemSoundOutputDeviceUID
            ? "\(device.name) (\(SirenaMixerStrings.outputCurrent))"
            : device.name
    }

    private func inputMessage(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var mixerRows: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), glassEnabled {
            GlassEffectContainer(spacing: 8) {
                rowList
            }
        } else {
            rowList
        }
#else
        rowList
#endif
    }

    @ViewBuilder
    private var rowList: some View {
        ForEach(visibleApps) { app in
            SirenaMixerRow(app: app,
                     normalTint: normalSliderTint,
                     accentRevision: accentRevision,
                     glassEnabled: glassEnabled,
                     editingVolumeID: $editingVolumeID,
                     isPinned: arrangement.isPinned(app.persistenceID),
                     togglePin: { updateArrangement { $0.togglePin(app.persistenceID ?? "") } },
                     moveUp: moveAction(for: app, offset: -1),
                     moveDown: moveAction(for: app, offset: 1))
                .modifier(SirenaMixerAppReorderModifier(
                    id: app.persistenceID,
                    icon: SirenaMixerResponsibleProcess.icon(for: app.ownerPid, pointSize: 32),
                    draggingID: $draggingAppID,
                    target: $dropTarget,
                    dragChanged: { _ in },
                    canMove: { source, target in
                        let ids = visibleApps.compactMap(\.persistenceID)
                        return ids.contains(source) && ids.contains(target)
                            && arrangement.isPinned(source) == arrangement.isPinned(target)
                    },
                    move: { source, target, after in
                        updateArrangement {
                            $0.move(source, to: target, after: after,
                                    visibleIDs: visibleApps.compactMap(\.persistenceID))
                        }
                    }))
                .help(SirenaMixerStrings.arrange)
        }
    }

    private func updateArrangement(_ change: (inout SirenaMixerAppArrangement) -> Void) {
        var updated = arrangement
        change(&updated)
        arrangementValue = updated.rawValue
    }

    private func moveAction(for app: SirenaMixerApp, offset: Int) -> (() -> Void)? {
        let ids = visibleApps.compactMap(\.persistenceID)
        guard let id = app.persistenceID,
              arrangement.neighbor(of: id, offset: offset, visibleIDs: ids) != nil else { return nil }
        return {
            updateArrangement {
                $0.move(id, offset: offset, visibleIDs: visibleApps.compactMap(\.persistenceID))
            }
        }
    }

    /// Appearance KVO and the system-colors notification can fire in bursts
    /// without the accent actually changing, and every revision bump re-renders
    /// (and, before macOS 26, recreates) every slider row — so compare the
    /// accent resolved against the current appearance and only then re-tint.
    /// When the accent cannot be resolved this fails open (always re-tints),
    /// never closed: eating a real accent change would leave stale sliders.
    private func refreshSliderTint() {
        var resolved: NSColor?
        NSApplication.shared.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        if let resolved, let last = lastResolvedAccent, resolved == last { return }
        lastResolvedAccent = resolved
        normalSliderTint = Color(nsColor: .controlAccentColor)
        accentRevision += 1
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SirenaMixerStrings.permissionBody)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(SirenaMixerStrings.permissionOpenSettings) {
                SirenaMixer.shared.openAudioCaptureSettings()
            }
            .controlSize(.small)
        }
    }
}

/// The options under the routing, shared with the island's mixer page so
/// both surfaces offer the same switches: idle rows, the headphone guard, the
/// precise roller, the output switcher and the hidden apps.
struct SirenaMixerOptionsControls: View {
    @ObservedObject private var mixer = SirenaAppVolumeMixer.shared
    @AppStorage(SirenaMixerDefaultsKey.mixerHideInactiveApps)
    private var hideInactiveApps = false
    @AppStorage(SirenaMixerDefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect)
    private var lowerOnHeadphonesDisconnect = false
    @AppStorage(SirenaMixerDefaultsKey.mixerHeadphonesDisconnectVolumePercent)
    private var headphonesDisconnectVolumePercent = SirenaMixerDefaults.defaultMixerHeadphonesDisconnectVolumePercent
    @State private var showListChooser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if SirenaAppVolumeMixer.isSupported {
                inactiveAppsVisibilityToggle
            }
            headphoneDisconnectProtectionToggle
            if SirenaAppVolumeMixer.isSupported, !listChoices.isEmpty {
                listVisibilityFooter
            }
        }
    }

    private func inputMessage(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headphoneDisconnectProtectionToggle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(SirenaMixerStrings.lowerOnHeadphonesDisconnect,
                   isOn: $lowerOnHeadphonesDisconnect)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))

            Text(SirenaMixerStrings.lowerOnHeadphonesDisconnectCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if lowerOnHeadphonesDisconnect {
                HStack(spacing: 8) {
                    Stepper(value: headphonesDisconnectVolumeBinding,
                            in: SirenaMixerDefaults.minimumMixerHeadphonesDisconnectVolumePercent...100,
                            step: 5) {
                        Text(SirenaMixerStrings.headphonesDisconnectVolume)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .controlSize(.small)
                    Spacer(minLength: 6)
                    Text("\(headphonesDisconnectDisplayPercent)%")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var headphonesDisconnectVolumeBinding: Binding<Int> {
        Binding(
            get: { SirenaMixerDefaults.sanitizedMixerHeadphonesDisconnectVolumePercent(headphonesDisconnectVolumePercent) },
            set: { headphonesDisconnectVolumePercent = SirenaMixerDefaults.sanitizedMixerHeadphonesDisconnectVolumePercent($0) }
        )
    }

    private var headphonesDisconnectDisplayPercent: Int {
        SirenaMixerDefaults.sanitizedMixerHeadphonesDisconnectVolumePercent(headphonesDisconnectVolumePercent)
    }

    private struct MixerListChoice: Identifiable {
        let id: String
        let name: String
        let isListed: Bool
        /// A row with nothing stable to remember it by cannot be hidden; it
        /// still shows here so the menu mirrors the list.
        let canToggle: Bool
    }

    private var listChoices: [MixerListChoice] {
        // The hidden list updates the moment a box is unchecked, while the
        // visible rows only change when the next HAL refresh lands. Keyed by
        // persistence id with the hidden entry winning, a just-hidden app
        // shows up once (unchecked) instead of twice during that gap.
        var seen = Set<String>()
        var choices = mixer.hiddenApps.map { hidden -> MixerListChoice in
            seen.insert(hidden.id)
            return MixerListChoice(id: hidden.id, name: hidden.name, isListed: false, canToggle: true)
        }
        for app in mixer.apps {
            let id = app.persistenceID ?? app.id
            guard seen.insert(id).inserted else { continue }
            choices.append(MixerListChoice(id: id, name: app.name,
                                           isListed: true, canToggle: app.persistenceID != nil))
        }
        choices.sort {
            SirenaMixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        return choices
    }

    /// Which apps the list shows (issue #300): the row reads how many are
    /// hidden and opens a check per app, right in the panel so several can be
    /// checked or unchecked in one go. Hidden apps stay here even while they
    /// are not running, so they can always be brought back.
    private var listVisibilityFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showListChooser.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(SirenaMixerStrings.visibleApps)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(mixer.hiddenApps.isEmpty
                         ? SirenaMixerStrings.allShown
                         : "\(SirenaMixerStrings.hiddenCountLabel): \(mixer.hiddenApps.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showListChooser ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SirenaMixerStrings.visibleApps)
            .accessibilityValue(mixer.hiddenApps.isEmpty
                                ? SirenaMixerStrings.allShown
                                : "\(SirenaMixerStrings.hiddenCountLabel): \(mixer.hiddenApps.count)")

            if showListChooser {
                ForEach(listChoices) { choice in
                    Toggle(isOn: listedBinding(for: choice)) {
                        Text(choice.name)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(!choice.canToggle)
                }
            }
        }
    }

    private func listedBinding(for choice: MixerListChoice) -> Binding<Bool> {
        Binding(
            get: { choice.isListed },
            set: { listed in
                if listed {
                    mixer.showInList(id: choice.id)
                } else if let app = mixer.apps.first(where: { ($0.persistenceID ?? $0.id) == choice.id }) {
                    mixer.hideFromList(app)
                }
            }
        )
    }

    private var inactiveAppsVisibilityToggle: some View {
        let label = SirenaMixerStrings.hideInactiveApps
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Toggle(label, isOn: $hideInactiveApps)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(label)
        }
    }
}

private struct SirenaMixerRow: View {
    @ObservedObject private var mixer = SirenaAppVolumeMixer.shared
    @Environment(\.colorScheme) private var colorScheme
    let app: SirenaMixerApp
    let normalTint: Color
    let accentRevision: Int
    let glassEnabled: Bool
    @Binding var editingVolumeID: String?
    let isPinned: Bool
    let togglePin: () -> Void
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    private var arrangementStrings: SirenaMixerStrings.Type { SirenaMixerStrings.self }

    /// Warm accent to flag the boost range, darkened in Light Mode for contrast.
    private var boostColor: Color { SirenaMixerColor.orange(for: colorScheme) }
    /// Tie the visual state to the displayed percentage, so "amber" and ">100%"
    /// always agree and the reset hides exactly when the row reads 100%.
    private var isBoosting: Bool { (app.volume * 100).rounded() > 100 }
    private var isAtUnity: Bool { (app.volume * 100).rounded() == 100 }

    /// SoundSource-sized icon spanning the row's two lines (issue #166); the
    /// bitmap must be requested at this size or the upscale looks blurry.
    private static let iconPointSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: SirenaMixerResponsibleProcess.icon(for: app.ownerPid,
                                                       pointSize: Self.iconPointSize))
                    .resizable()
                    .frame(width: Self.iconPointSize, height: Self.iconPointSize)
                if app.isPlaying {
                    Circle()
                        .fill(SirenaMixerColor.green(for: colorScheme))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.2))
                        .offset(x: -1, y: -1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(arrangementStrings.pin)
                    }
                    Spacer(minLength: 4)

                    if app.persistenceID != nil {
                        Menu { arrangementActions } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(isPinned ? arrangementStrings.unpin : arrangementStrings.pin)
                        .accessibilityLabel("\(isPinned ? arrangementStrings.unpin : arrangementStrings.pin): \(app.name)")
                    }
                    if !app.isBypassed {
                        outputPicker
                    }
                }

                if app.isBypassed {
                    // Zoom and pro audio apps are listed but never tapped
                    // (issue #177): the row explains itself instead of the
                    // app silently missing from the mixer.
                    Text(SirenaMixerStrings.bypassedCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        SirenaMixerVolumeSlider(value: volumeBinding,
                                          normalTint: normalTint,
                                          boostTint: boostColor,
                                          isBoosting: isBoosting,
                                          accentRevision: accentRevision,
                                          glassEnabled: glassEnabled,
                                          maximum: SirenaAppVolumeMixer.maxVolume,
                                          accessibilityLabel: app.name)

                        SirenaMixerEditablePercent(currentPercent: SirenaMixerRoutingSupport.displayPercent(forVolume: app.volume),
                                              maximumPercent: Int(SirenaAppVolumeMixer.maxVolume * 100),
                                              width: 42,
                                              editorID: "app:\(app.id)",
                                              editingID: $editingVolumeID,
                                              accessibilityLabel: app.name) {
                            HStack(spacing: 2) {
                                if isBoosting {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(boostColor)
                                }
                                Text("\(SirenaMixerRoutingSupport.displayPercent(forVolume: app.volume))%")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(isBoosting ? boostColor : Color.secondary)
                            }
                        } onCommit: {
                            mixer.setVolume($0, for: app)
                        }

                        Button {
                            mixer.setVolume(1, for: app)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(isBoosting ? boostColor : Color.secondary)
                                .frame(width: 14)
                        }
                        .buttonStyle(.plain)
                        .help(SirenaMixerStrings.resetTooltip)
                        .opacity(isAtUnity ? 0 : 1)
                        .disabled(isAtUnity)

                        Button {
                            mixer.toggleMute(app)
                        } label: {
                            Image(systemName: app.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(app.volume <= 0.001
                                                 ? SirenaMixerColor.red(for: colorScheme)
                                                 : Color.secondary)
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                    }

                    if app.outputDeviceUnavailable {
                        Label(SirenaMixerStrings.outputFallback, systemImage: "speaker.badge.exclamationmark")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: Text(arrangementStrings.moveUp)) { moveUp?() }
        .accessibilityAction(named: Text(arrangementStrings.moveDown)) { moveDown?() }
        .contextMenu {
            if app.persistenceID != nil {
                arrangementActions
                Divider()
                Button(SirenaMixerStrings.hideFromList) {
                    mixer.hideFromList(app)
                }
            }
        }
    }

    @ViewBuilder
    private var arrangementActions: some View {
        Button(action: togglePin) {
            Label(isPinned ? arrangementStrings.unpin : arrangementStrings.pin,
                  systemImage: isPinned ? "pin.slash" : "pin")
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { app.volume },
            set: { mixer.setVolume($0, for: app) }
        )
    }

    private var outputPicker: some View {
        Picker(SirenaMixerStrings.outputTooltip, selection: outputSelectionBinding) {
            Text(SirenaMixerStrings.outputDefault)
                .tag(SirenaMixerRoutingSupport.systemDefaultSelectionID)
            ForEach(mixer.outputDevices) { device in
                Text(outputDeviceTitle(device))
                    .tag(device.uid)
            }
            if let selected = app.selectedOutputDeviceUID,
               SirenaMixerRoutingSupport.needsUnavailableOutputRow(selectedUID: selected,
                                                             isUnavailable: app.outputDeviceUnavailable,
                                                             listedUIDs: mixer.outputDevices.map(\.uid)) {
                Text(SirenaMixerStrings.outputUnavailable)
                    .tag(selected)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 112)
        .help(SirenaMixerStrings.outputTooltip)
    }

    private var outputSelectionBinding: Binding<String> {
        Binding(
            get: { app.selectedOutputDeviceUID ?? SirenaMixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                mixer.setOutputDeviceUID(selection == SirenaMixerRoutingSupport.systemDefaultSelectionID ? nil : selection,
                                         for: app)
            }
        )
    }

    private func outputDeviceTitle(_ device: SirenaMixerOutputDevice) -> String {
        device.isDefault ? "\(device.name) (\(SirenaMixerStrings.outputCurrent))" : device.name
    }
}

/// The percentage keeps its compact read-only appearance until clicked, then
/// becomes a selected text field so the next keystroke replaces the old value.
struct SirenaMixerEditablePercent<Label: View>: View {
    let currentPercent: Int
    let maximumPercent: Int
    let width: CGFloat
    var height: CGFloat = 18
    let editorID: String
    @Binding var editingID: String?
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label
    let onCommit: (Double) -> Void

    @State private var draft = ""

    private var isEditing: Bool { editingID == editorID }

    var body: some View {
        ZStack {
            HStack(spacing: 1) {
                SirenaMixerPercentField(text: $draft,
                                            isActive: isEditing,
                                            accessibilityLabel: accessibilityLabel,
                                            onSubmit: commit,
                                            onCancel: cancel)
                Text("%")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 3)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
            )
            .opacity(isEditing ? 1 : 0)
            .allowsHitTesting(isEditing)
            .accessibilityHidden(!isEditing)

            Button(action: beginEditing) {
                label()
                    .frame(width: width, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEditing ? 0 : 1)
            .allowsHitTesting(!isEditing)
            .accessibilityLabel("\(accessibilityLabel) \(currentPercent)%")
            .accessibilityHidden(isEditing)
        }
        .frame(width: width, alignment: .trailing)
    }

    private func beginEditing() {
        draft = String(currentPercent)
        editingID = editorID
    }

    @discardableResult
    private func commit() -> Bool {
        guard let volume = SirenaMixerRoutingSupport.volumeFraction(
            fromPercentageText: draft,
            maximumPercent: maximumPercent
        ) else {
            NSSound.beep()
            return false
        }
        onCommit(volume)
        editingID = nil
        return true
    }

    private func cancel() {
        if isEditing { editingID = nil }
    }
}

/// A native field is used because an NSPopover can attach its SwiftUI backing
/// view after a FocusState request has already fired. The field retries when it
/// joins the window, then owns Return, Escape and loss-of-focus behavior.
private struct SirenaMixerPercentField: NSViewRepresentable {
    @Binding var text: String
    let isActive: Bool
    let accessibilityLabel: String
    let onSubmit: () -> Bool
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text,
                    isActive: isActive,
                    onSubmit: onSubmit,
                    onCancel: onCancel)
    }

    func makeNSView(context: Context) -> SirenaMixerPercentNativeTextField {
        let field = SirenaMixerPercentNativeTextField()
        field.delegate = context.coordinator
        context.coordinator.field = field
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = .systemFont(ofSize: 10.5, weight: .medium)
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.isEnabled = isActive
        field.isHidden = !isActive
        field.setAccessibilityLabel(accessibilityLabel)
        field.didAttachToWindow = { [weak field, weak coordinator = context.coordinator] in
            guard let field else { return }
            coordinator?.focusIfNeeded(field)
        }
        return field
    }

    func updateNSView(_ field: SirenaMixerPercentNativeTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        field.setAccessibilityLabel(accessibilityLabel)
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.setActive(isActive, field: field)
    }

    static func dismantleNSView(_ field: SirenaMixerPercentNativeTextField,
                                coordinator: Coordinator) {
        coordinator.stopMonitoringEscape()
        field.didAttachToWindow = nil
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        private var isActive: Bool
        var onSubmit: () -> Bool
        var onCancel: () -> Void
        weak var field: SirenaMixerPercentNativeTextField?
        private var didFocus = false
        private var isFinishing = false
        private var escapeMonitor: Any?

        init(text: Binding<String>,
             isActive: Bool,
             onSubmit: @escaping () -> Bool,
             onCancel: @escaping () -> Void) {
            self.text = text
            self.isActive = isActive
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            super.init()
            if isActive { startMonitoringEscape() }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard isActive, didFocus, !isFinishing,
                  let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            isFinishing = true
            if !onSubmit() { onCancel() }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                text.wrappedValue = (control as? NSTextField)?.stringValue ?? text.wrappedValue
                if onSubmit() { isFinishing = true }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                finish(onCancel)
                return true
            }
            return false
        }

        func focusIfNeeded(_ field: SirenaMixerPercentNativeTextField) {
            guard isActive, !didFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.isActive, !self.didFocus else { return }
                if field.focusAndSelectAll() { self.didFocus = true }
            }
        }

        func setActive(_ active: Bool, field: SirenaMixerPercentNativeTextField) {
            if active != isActive {
                isActive = active
                didFocus = false
                isFinishing = false
                if active {
                    field.isHidden = false
                    field.isEnabled = true
                    startMonitoringEscape()
                } else {
                    stopMonitoringEscape()
                    field.isEnabled = false
                    field.isHidden = true
                }
            }
            if active { focusIfNeeded(field) }
        }

        private func startMonitoringEscape() {
            guard escapeMonitor == nil else { return }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // The monitor sees the whole app; Escape in another window,
                // such as Settings, stays there.
                guard let self, self.isActive, event.keyCode == 53,
                      let window = self.field?.window, event.window === window else { return event }
                // While an input method is composing, Esc belongs to it and
                // drops the candidate; the next one cancels the level.
                if (window.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
                self.finish(self.onCancel)
                return nil
            }
        }

        func stopMonitoringEscape() {
            guard let escapeMonitor else { return }
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        private func finish(_ action: () -> Void) {
            guard !isFinishing else { return }
            isFinishing = true
            action()
        }
    }
}

private struct SirenaMixerVolumeSlider: View {
    @Binding var value: Double
    let normalTint: Color
    let boostTint: Color
    let isBoosting: Bool
    let accentRevision: Int
    let glassEnabled: Bool
    let maximum: Double
    let accessibilityLabel: String

    private var activeTint: Color { isBoosting ? boostTint : normalTint }
    private var percentage: Int { SirenaMixerRoutingSupport.displayPercent(forVolume: value) }

    var body: some View {
        Group {
#if compiler(>=6.2)
            if #available(macOS 26.0, *), glassEnabled {
                SirenaMixerGlassSlider(value: $value,
                                       tint: activeTint,
                                       isBoosting: isBoosting,
                                       maximum: maximum,
                                       accessibilityLabel: accessibilityLabel)
            } else {
                nativeSlider
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue("\(percentage)%")
            }
#else
            nativeSlider
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(percentage)%")
#endif
        }
    }

    private var nativeSlider: some View {
        Slider(value: $value, in: 0...maximum)
            .controlSize(.small)
            // Pass an explicit accent (not nil) for the normal state: on the
            // macOS slider, tint(nil) does not reliably clear a previously
            // applied colour, so the bar would stay amber after leaving boost.
            .tint(activeTint)
            .id(accentRevision)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct SirenaMixerGlassSlider: View {
    @Binding var value: Double
    let tint: Color
    let isBoosting: Bool
    let maximum: Double
    let accessibilityLabel: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private let knobWidth: CGFloat = 24
    private let knobHeight: CGFloat = 15
    private let trackHeight: CGFloat = 5

    private var progress: CGFloat {
        let clamped = min(max(value, 0), maximum)
        return CGFloat(clamped / maximum)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, knobWidth)
            let amount = progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(trackOpacity))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(trackHeight, width * amount), height: trackHeight)
                    .shadow(color: tint.opacity(0.18), radius: 3)

                knob
                    .frame(width: knobWidth, height: knobHeight)
                    .offset(x: (width - knobWidth) * amount)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.16), value: amount)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: knobHeight)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(SirenaMixerRoutingSupport.displayPercent(forVolume: value))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(maximum, value + 0.05)
            case .decrement:
                value = max(0, value - 0.05)
            @unknown default:
                break
            }
        }
    }

    private var trackOpacity: Double {
        colorScheme == .light ? 0.11 : 0.16
    }

    private var knob: some View {
        ZStack {
            knobFill
            Capsule()
                .strokeBorder(tint.opacity(isBoosting ? 0.55 : 0.36), lineWidth: isBoosting ? 1.1 : 0.8)
            Capsule()
                .fill(
                    LinearGradient(colors: [
                        Color.white.opacity(colorScheme == .light ? 0.48 : 0.28),
                        Color.white.opacity(0.06)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .blendMode(.screen)
                .padding(1)
        }
        .shadow(color: tint.opacity(isBoosting ? 0.24 : 0.16), radius: 3, x: 0, y: 0)
        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.08 : 0.18), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var knobFill: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Capsule().fill(tint.opacity(colorScheme == .light ? 0.10 : 0.16)))
        } else {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(isBoosting ? 0.18 : 0.10)).interactive(), in: Capsule())
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        let travel = max(width - knobWidth, 1)
        let normalized = min(max((x - knobWidth / 2) / travel, 0), 1)
        value = Double(normalized) * maximum
    }
}
#endif
