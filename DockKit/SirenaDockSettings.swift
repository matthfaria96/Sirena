/// SirenaDockSettings.swift
///
/// The Dock page shown inside Sirena's main window. A focused subset of DockDoor's
/// settings: everything else keeps DockDoor's defaults and keeps working unseen.
/// Labels reuse DockDoor's own strings so its translations apply.

import Defaults
import SwiftUI

/// DockDoor's Dock previews and their look, as sections for a grouped Form on Sirena's
/// "Janela e Dock" page. DockDoor's own window switcher is gone: Sirena's switcher
/// (from Vorssaint) does ⌘ Tab.
public struct SirenaDockSettingsSections: View {
    public init() {}

    public var body: some View {
        DockPreviewsPage()
        DockAppearancePage()
    }
}

// MARK: - Dock previews

private struct DockPreviewsPage: View {
    @Default(.windowPreviewSortOrder) var windowPreviewSortOrder
    @Default(.includeHiddenWindowsInDockPreview) var includeHiddenWindowsInDockPreview
    @Default(.groupAppInstancesInDock) var groupAppInstancesInDock
    @Default(.dockPreviewActivationMode) var dockPreviewActivationMode
    @Default(.dockPreviewActivationModifier) var dockPreviewActivationModifier
    @Default(.previewHoverAction) var previewHoverAction
    @Default(.tapEquivalentInterval) var tapEquivalentInterval
    @Default(.enableCmdRightClickQuit) var enableCmdRightClickQuit
    @Default(.bufferFromDock) var bufferFromDock
    @Default(.dockPreviewControlPosition) var dockPreviewControlPosition
    @Default(.showWindowTitle) var showWindowTitle
    @Default(.windowTitleVisibility) var windowTitleVisibility
    @Default(.trafficLightButtonsVisibility) var trafficLightButtonsVisibility
    @Default(.enabledTrafficLightButtons) var enabledTrafficLightButtons
    @Default(.trafficLightButtonScale) var trafficLightButtonScale
    @Default(.showMassActionButtons) var showMassActionButtons

    var body: some View {
        Group {
                Section("Window Display") {
                    Picker("Window sort order", selection: $windowPreviewSortOrder) {
                        ForEach(WindowPreviewSortOrder.allCases.filter { !$0.isWindowSwitcherOnly }) { order in
                            Text(order.localizedName).tag(order)
                        }
                    }
                    Toggle("Include hidden/minimized windows", isOn: $includeHiddenWindowsInDockPreview)
                    Toggle(isOn: $groupAppInstancesInDock) {
                        Text("Group multiple app instances together")
                        Text("Show windows from all instances of an app when hovering its dock icon.")
                    }
                }

                Section("Dock Interaction") {
                    Picker("Dock Preview Trigger", selection: $dockPreviewActivationMode) {
                        ForEach(DockPreviewActivationMode.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                    if dockPreviewActivationMode == .modifierClick {
                        Picker("Dock Preview Modifier", selection: $dockPreviewActivationModifier) {
                            ForEach(DockPreviewActivationModifier.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                        }
                    }
                    Picker("Dock Preview Hover Action", selection: $previewHoverAction) {
                        ForEach(PreviewHoverAction.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                    SliderRow(title: "Preview Hover Action Delay", value: $tapEquivalentInterval,
                              range: 0 ... 2, step: 0.1, format: "%.1f s")
                        .disabled(previewHoverAction == .none)
                    Toggle("CMD + Right Click on dock icon to quit app", isOn: $enableCmdRightClickQuit)
                    SliderRow(title: "Window Buffer from Dock (pixels)", value: $bufferFromDock,
                              range: -100 ... 100, step: 5, format: "%.0f px")
                }

                Section("Dock Preview Toolbar") {
                    Toggle("Show Window Title", isOn: $showWindowTitle)
                    if showWindowTitle {
                        Picker("Window Title Visibility", selection: $windowTitleVisibility) {
                            ForEach(WindowTitleVisibility.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                        }
                    }
                }

                Section("Traffic Light Buttons in Previews") {
                    Picker("Traffic Light Buttons Visibility", selection: $trafficLightButtonsVisibility) {
                        ForEach(TrafficLightButtonsVisibility.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                    if trafficLightButtonsVisibility != .never {
                        EnabledButtonsGrid(enabledButtons: $enabledTrafficLightButtons, visibility: $trafficLightButtonsVisibility)
                        SliderRow(title: "Button Scale", value: $trafficLightButtonScale,
                                  range: 0.75 ... 2.0, step: 0.05, format: "%.2f×")
                    }
                }
        }
    }
}

// MARK: - Appearance (simple)

private struct DockAppearancePage: View {
    @Default(.showAnimations) var showAnimations
    @Default(.uniformCardRadius) var uniformCardRadius
    @Default(.showMinimizedHiddenLabels) var showMinimizedHiddenLabels
    @Default(.raisedWindowLevel) var raisedWindowLevel
    @Default(.previewWidth) var previewWidth
    @Default(.previewHeight) var previewHeight
    @Default(.lockAspectRatio) var lockAspectRatio
    @Default(.hoverWindowOpenDelay) var hoverWindowOpenDelay
    @Default(.fadeOutDuration) var fadeOutDuration

    var body: some View {
        Group {
            Section("General Appearance") {
                Toggle("Show Animations", isOn: $showAnimations)
                Toggle("Rounded corners", isOn: $uniformCardRadius)
                Toggle("Show preview above app labels", isOn: $raisedWindowLevel)
            }

            Section("Window Size") {
                SliderRow(title: "Preview Width", value: $previewWidth, range: 100 ... 600, step: 10, format: "%.0f px")
                    .onChange(of: previewWidth) { _ in
                        if lockAspectRatio { previewHeight = previewWidth / (16.0 / 10.0) }
                        SharedPreviewWindowCoordinator.activeInstance?.windowSize = getWindowSize()
                    }
            }

            Section("Advanced") {
                SliderRow(title: "Preview Window Open Delay", value: $hoverWindowOpenDelay, range: 0 ... 2, step: 0.1, format: "%.1f s")
                SliderRow(title: "Preview Window Fade Out Duration", value: $fadeOutDuration, range: 0 ... 2, step: 0.1, format: "%.1f s")
            }
        }
    }
}

// MARK: - Shared rows

private struct SliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: LocalizedStringKey
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let format: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .frame(maxWidth: 240)
                Text(String(format: format, Double(value)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

private struct EnabledButtonsGrid: View {
    @Binding var enabledButtons: Set<WindowAction>
    @Binding var visibility: TrafficLightButtonsVisibility

    private let buttons: [(WindowAction, String)] = [
        (.quit, String(localized: "Quit")),
        (.close, String(localized: "Close")),
        (.minimize, String(localized: "Minimize")),
        (.toggleFullScreen, String(localized: "Fullscreen")),
        (.maximize, String(localized: "Maximize")),
        (.bringToCurrentSpace, String(localized: "Bring to Current Space")),
        (.openNewWindow, String(localized: "New Window"))
    ]

    var body: some View {
        LabeledContent("Enabled Buttons") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(buttons, id: \.0) { action, label in
                    Toggle(label, isOn: Binding(
                        get: { enabledButtons.contains(action) },
                        set: { isOn in
                            if isOn {
                                enabledButtons.insert(action)
                            } else {
                                enabledButtons.remove(action)
                                if enabledButtons.isEmpty { visibility = .never }
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: 340)
        }
    }
}

// MARK: - Sirena: DockDoor's window switcher stays off

/// ⌘ Tab and ⌥ Tab belong to Sirena's own switcher (ported from Vorssaint): DockDoor's
/// switcher is never turned on, and any shortcut it had is cleared.
enum SirenaSwitcherShortcuts {
    static func applyDefaultOnce() {
        Defaults[.enableWindowSwitcher] = false
        Defaults[.alternateKeybindKey] = 0
        Defaults[.alternateKeybindModifierFlags] = 0
        // Sirena shows only the Dock previews, so they're always on while the feature is.
        Defaults[.enableDockPreviews] = true
        // Sirena's preview look: no app-name bubble on top, each card's buttons and title
        // in a header above the window, and minimized windows never swap their buttons
        // for a "Minimized" label.
        Defaults[.showAppName] = false
        Defaults[.useEmbeddedDockPreviewElements] = false
        Defaults[.dockPreviewControlPosition] = .topLeading
        Defaults[.showMinimizedHiddenLabels] = false
        Defaults[.disableDockStyleTitles] = true
        Defaults[.disableDockStyleTrafficLights] = true
    }
}

// MARK: - Sirena: how many of the page's options are on (Home's radial chart)

public enum SirenaDockStats {
    public static var options: (on: Int, total: Int) {
        let flags: [Bool] = [
            Defaults[.enableDockPreviews], Defaults[.includeHiddenWindowsInDockPreview], Defaults[.groupAppInstancesInDock],
            Defaults[.enableCmdRightClickQuit], Defaults[.showWindowTitle], Defaults[.showMassActionButtons],
            Defaults[.showAnimations],
            Defaults[.uniformCardRadius], Defaults[.lockAspectRatio]
        ]
        return (flags.filter { $0 }.count, flags.count)
    }
}
