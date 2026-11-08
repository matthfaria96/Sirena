/// SirenaDockSettings.swift
///
/// The Dock page shown inside Sirena's main window. A focused subset of DockDoor's
/// settings: everything else keeps DockDoor's defaults and keeps working unseen.
/// Labels reuse DockDoor's own strings so its translations apply.

import Defaults
import SwiftUI

/// Sirena's own strings on this page (DockDoor's labels keep their own table).
private func SL(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Sirena", bundle: .main)
}

/// A section header that says where it belongs: an icon, the parent topic in small caps
/// above, the topic itself below ("PRÉVIAS DO DOCK" / "Quando aparecem").
public struct SettingsSubheader: View {
    let parent: String?
    let title: String
    let symbol: String

    public init(_ title: String, parent: String? = nil, symbol: String) {
        self.title = title
        self.parent = parent
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                if let parent {
                    Text(parent)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.leading, parent == nil ? 0 : 14)
    }
}

/// ⌘ + right click on a Dock icon quits the app (shown with the Dock clicks).
public struct DockQuitClickToggle: View {
    @Default(.enableCmdRightClickQuit) var enableCmdRightClickQuit
    public init() {}
    public var body: some View {
        Toggle("CMD + Right Click on dock icon to quit app", isOn: $enableCmdRightClickQuit)
    }
}

/// Everything about the Dock previews, as sub-topics of "Prévias do Dock".
public struct SirenaDockSettingsSections: View {
    public init() {}

    public var body: some View {
        PreviewsWhenSection()
        PreviewsContentSection()
        PreviewsButtonsSection()
        PreviewsLookSection()
    }
}

private var previewsParent: String { SL("Dock Previews") }

// MARK: When they show

private struct PreviewsWhenSection: View {
    @Default(.dockPreviewActivationMode) var dockPreviewActivationMode
    @Default(.dockPreviewActivationModifier) var dockPreviewActivationModifier
    @Default(.hoverWindowOpenDelay) var hoverWindowOpenDelay
    @Default(.fadeOutDuration) var fadeOutDuration
    @Default(.previewHoverAction) var previewHoverAction
    @Default(.tapEquivalentInterval) var tapEquivalentInterval

    var body: some View {
        Section {
            TriggerCards(selection: $dockPreviewActivationMode)
            if dockPreviewActivationMode == .modifierClick {
                Picker("Dock Preview Modifier", selection: $dockPreviewActivationModifier) {
                    ForEach(DockPreviewActivationModifier.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
            }
            SliderRow(title: "Preview Window Open Delay", value: $hoverWindowOpenDelay, range: 0 ... 2, step: 0.1, format: "%.1f s")
            SliderRow(title: "Preview Window Fade Out Duration", value: $fadeOutDuration, range: 0 ... 2, step: 0.1, format: "%.1f s")
            Picker("Dock Preview Hover Action", selection: $previewHoverAction) {
                ForEach(PreviewHoverAction.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            if previewHoverAction != .none {
                SliderRow(title: "Preview Hover Action Delay", value: $tapEquivalentInterval,
                          range: 0 ... 2, step: 0.1, format: "%.1f s")
            }
        } header: {
            SettingsSubheader(SL("When they show"), parent: previewsParent, symbol: "cursorarrow.motionlines")
        }
    }
}

/// How the previews are called up, as cards with a picture each.
private struct TriggerCards: View {
    @Binding var selection: DockPreviewActivationMode

    private func symbol(_ mode: DockPreviewActivationMode) -> String {
        switch mode {
        case .hover: "cursorarrow.rays"
        case .middleClick: "computermouse.fill"
        case .modifierClick: "command"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DockPreviewActivationMode.allCases, id: \.self) { mode in
                let selected = selection == mode
                Button { withAnimation(.snappy) { selection = mode } } label: {
                    VStack(spacing: 8) {
                        Image(systemName: symbol(mode))
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .frame(height: 30)
                        Text(mode.localizedName)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .padding(6)
                    .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: What they show

private struct PreviewsContentSection: View {
    @Default(.windowPreviewSortOrder) var windowPreviewSortOrder
    @Default(.includeHiddenWindowsInDockPreview) var includeHiddenWindowsInDockPreview
    @Default(.groupAppInstancesInDock) var groupAppInstancesInDock
    @Default(.enableMediaWidget) var enableMediaWidget
    @Default(.showWindowTitle) var showWindowTitle
    @Default(.windowTitleVisibility) var windowTitleVisibility

    var body: some View {
        Section {
            Picker("Window sort order", selection: $windowPreviewSortOrder) {
                ForEach(WindowPreviewSortOrder.allCases.filter { !$0.isWindowSwitcherOnly }) { order in
                    Text(order.localizedName).tag(order)
                }
            }
            Toggle("Include hidden/minimized windows", isOn: $includeHiddenWindowsInDockPreview)
            Toggle("Show Window Title", isOn: $showWindowTitle)
            if showWindowTitle {
                Picker("Window Title Visibility", selection: $windowTitleVisibility) {
                    ForEach(WindowTitleVisibility.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
            }
            Toggle(isOn: $groupAppInstancesInDock) {
                Text("Group multiple app instances together")
                Text("Show windows from all instances of an app when hovering its dock icon.")
            }
            Toggle(isOn: $enableMediaWidget) {
                Text("Music player in previews")
                Text("Hovering a music app in the Dock also shows its playback controls.")
            }
            if enableMediaWidget {
                MediaWidgetPreview()
            }
        } header: {
            SettingsSubheader(SL("What they show"), parent: previewsParent, symbol: "square.grid.2x2")
        }
    }
}

// MARK: Window buttons

private struct PreviewsButtonsSection: View {
    @Default(.trafficLightButtonsVisibility) var trafficLightButtonsVisibility
    @Default(.enabledTrafficLightButtons) var enabledTrafficLightButtons
    @Default(.trafficLightButtonScale) var trafficLightButtonScale

    var body: some View {
        Section {
            Picker("Traffic Light Buttons Visibility", selection: $trafficLightButtonsVisibility) {
                ForEach(TrafficLightButtonsVisibility.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            if trafficLightButtonsVisibility != .never {
                EnabledButtonsGrid(enabledButtons: $enabledTrafficLightButtons, visibility: $trafficLightButtonsVisibility)
                SliderRow(title: "Button Scale", value: $trafficLightButtonScale,
                          range: 0.75 ... 2.0, step: 0.05, format: "%.2f×")
            }
        } header: {
            SettingsSubheader(SL("Window buttons"), parent: previewsParent, symbol: "circle.grid.3x3.fill")
        }
    }
}

// MARK: Look

private struct PreviewsLookSection: View {
    @Default(.showAnimations) var showAnimations
    @Default(.uniformCardRadius) var uniformCardRadius
    @Default(.raisedWindowLevel) var raisedWindowLevel
    @Default(.previewWidth) var previewWidth
    @Default(.previewHeight) var previewHeight
    @Default(.lockAspectRatio) var lockAspectRatio
    @Default(.bufferFromDock) var bufferFromDock

    var body: some View {
        Section {
            Toggle("Show Animations", isOn: $showAnimations)
            Toggle("Rounded corners", isOn: $uniformCardRadius)
            Toggle(isOn: $raisedWindowLevel) {
                Text("Show preview above app labels")
                Text(SL("The preview covers the app name macOS shows above the Dock icon."))
            }
            SliderRow(title: "Preview Width", value: $previewWidth, range: 100 ... 600, step: 10, format: "%.0f px")
                .onChange(of: previewWidth) { _ in
                    if lockAspectRatio { previewHeight = previewWidth / (16.0 / 10.0) }
                    SharedPreviewWindowCoordinator.activeInstance?.windowSize = getWindowSize()
                }
            SliderRow(title: "Window Buffer from Dock (pixels)", value: $bufferFromDock,
                      range: -100 ... 100, step: 5, format: "%.0f px")
        } header: {
            SettingsSubheader(SL("Look"), parent: previewsParent, symbol: "paintbrush.pointed")
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
                Text(String(format: format, locale: .current, Double(value)))
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

    private func title(_ action: WindowAction) -> String {
        switch action {
        case .quit: String(localized: "Quit")
        case .close: String(localized: "Close")
        case .minimize: String(localized: "Minimize")
        case .maximize: String(localized: "Maximize")
        case .toggleFullScreen: String(localized: "Fullscreen")
        case .openNewWindow: String(localized: "New Window")
        default: String(localized: "Bring to Current Space")
        }
    }

    private func binding(_ action: WindowAction) -> Binding<Bool> {
        Binding(
            get: { enabledButtons.contains(action) },
            set: { isOn in
                if isOn {
                    enabledButtons.insert(action)
                } else {
                    enabledButtons.remove(action)
                    if enabledButtons.isEmpty { visibility = .never }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Enabled Buttons")
                Spacer()
                // Live preview, in the order they show on a window.
                HStack(spacing: 6) {
                    ForEach(TrafficLightStyle.order.filter(enabledButtons.contains), id: \.self) {
                        TrafficLightSwatch(action: $0, size: 15)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .compatGlass(in: Capsule())
                .opacity(enabledButtons.isEmpty ? 0 : 1)
                .animation(.snappy, value: enabledButtons)
            }
            // Three per row, left aligned, in the same order as on a window.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                      alignment: .leading, spacing: 10) {
                ForEach(TrafficLightStyle.order, id: \.self) { action in
                    Toggle(isOn: binding(action)) {
                        HStack(spacing: 8) {
                            TrafficLightSwatch(action: action, size: 14)
                            Text(title(action)).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
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


