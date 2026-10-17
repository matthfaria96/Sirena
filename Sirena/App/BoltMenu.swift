/// BoltMenu.swift
///
/// What Sirena's menu bar icon shows, chosen on Home. Two kinds of things:
/// - Atalhos: programs opened with one click (clipboard history, pin a window, capture text).
/// - Controladores: things adjusted right there (volume, microphone, display brightness,
///   keyboard light, Cafeína, a peek through the camera, the per-app mixer). Volume,
///   microphone, brightness and keyboard light use the controls ported from Vorssaint.

import AppKit
import ClipboardKit
import SoundKit
import SwiftUI

enum BoltMenuItem: String, CaseIterable, Identifiable {
    // Atalhos
    case clipboard, pinWindow, textCapture
    // Controladores
    case volume, microphone, brightness, keyboardLight, keepAwake, mirror, sound

    var id: String { rawValue }

    enum Kind { case shortcut, control }

    var kind: Kind {
        switch self {
        case .clipboard, .pinWindow, .textCapture: return .shortcut
        default: return .control
        }
    }

    static var shortcuts: [BoltMenuItem] { allCases.filter { $0.kind == .shortcut } }
    static var controls: [BoltMenuItem] { allCases.filter { $0.kind == .control } }

    var title: String {
        switch self {
        case .clipboard: return L("Clipboard History")
        case .pinWindow: return ModuleID.pinWindow.title
        case .textCapture: return ModuleID.textCapture.title
        case .volume: return L("Volume")
        case .microphone: return L("Microphone")
        case .brightness: return L("Display Brightness")
        case .keyboardLight: return L("Keyboard Light")
        case .keepAwake: return L("Keep Awake")
        case .mirror: return L("Peek Camera")
        case .sound: return L("Per-App Mixer")
        }
    }

    /// The (i) explanation.
    var detail: String {
        switch self {
        case .clipboard: return L("Opens the list of everything you copied, to paste it again.")
        case .pinWindow: return L("Choose a window to keep floating above all the others.")
        case .textCapture: return L("Select an area of the screen and copy the text in it, even from images and videos.")
        case .volume: return L("The Mac's sound volume, with a click on the speaker to mute.")
        case .microphone: return L("Mutes or unmutes the microphone for every app at once. Green: on; red: muted.")
        case .brightness: return L("Brightness of the built-in display and Apple displays, one slider each.")
        case .keyboardLight: return L("The keyboard backlight, on Macs that have one.")
        case .keepAwake: return L("Keeps the Mac and the display from sleeping, for the time you choose or indefinitely. The time is remembered.")
        case .mirror: return L("Opens the camera below the menu bar for a quick look at yourself. Click it again to close.")
        case .sound: return L("Outputs, volume of each app and the microphone, in detail.")
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return ModuleID.clipboard.symbol
        case .pinWindow: return ModuleID.pinWindow.symbol
        case .textCapture: return ModuleID.textCapture.symbol
        case .volume: return "speaker.wave.2.fill"
        case .microphone: return "mic.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardLight: return "light.max"
        case .keepAwake: return "cup.and.saucer.fill"
        case .mirror: return "camera.fill"
        case .sound: return "slider.vertical.3"
        }
    }

    var tint: Color {
        switch self {
        case .clipboard: return ModuleID.clipboard.tint
        case .pinWindow: return ModuleID.pinWindow.tint
        case .textCapture: return ModuleID.textCapture.tint
        case .volume: return .indigo
        case .microphone: return .red
        case .brightness: return .yellow
        case .keyboardLight: return .orange
        case .keepAwake: return ModuleID.keepAwake.tint
        case .mirror: return ModuleID.mirror.tint
        case .sound: return .purple
        }
    }

    /// The module that has to run for this item to make sense.
    var module: ModuleID? {
        switch self {
        case .clipboard: return .clipboard
        case .pinWindow: return .pinWindow
        case .textCapture: return .textCapture
        case .keepAwake: return .keepAwake
        case .mirror: return .mirror
        default: return nil
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .clipboard: ClipboardController.shared.togglePanel()
        case .pinWindow: PinWindowController.shared.selectWindowToPin()
        case .textCapture: TextCaptureController.shared.capture(.text())
        case .mirror: MirrorController.shared.toggle()
        default: break
        }
    }
}

/// Which items the menu shows (kept in UserDefaults).
@MainActor
@Observable
final class BoltMenuSettings {
    static let shared = BoltMenuSettings()
    private static let key = "boltMenu.items.v2"

    var enabled: Set<BoltMenuItem> {
        didSet { UserDefaults.standard.set(enabled.map(\.rawValue).sorted(), forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key)
        enabled = saved.map { Set($0.compactMap(BoltMenuItem.init)) }
            ?? [.clipboard, .pinWindow, .textCapture, .volume, .microphone, .brightness, .keepAwake, .mirror]
    }

    func isOn(_ item: BoltMenuItem) -> Bool { enabled.contains(item) }

    func set(_ item: BoltMenuItem, _ on: Bool) {
        if on { enabled.insert(item) } else { enabled.remove(item) }
    }

    /// Items to show right now: chosen, and with their feature running.
    var visibleItems: [BoltMenuItem] {
        BoltMenuItem.allCases.filter { item in
            enabled.contains(item) && (item.module.map { ModuleManager.shared.isRunning($0) } ?? true)
        }
    }
}

// MARK: - The popover

struct BoltMenuView: View {
    @State private var settings = BoltMenuSettings.shared
    let close: () -> Void

    var body: some View {
        let visible = settings.visibleItems
        let controls = visible.filter { $0.kind == .control && $0 != .sound }
        let shortcuts = visible.filter { $0.kind == .shortcut }
        VStack(spacing: 0) {
            if !controls.isEmpty {
                VStack(spacing: 10) {
                    ForEach(controls) { item in
                        ControlRow(item: item, close: close)
                    }
                }
                .padding(12)
            }
            if visible.contains(.sound) {
                if !controls.isEmpty { Divider().padding(.horizontal, 12) }
                SoundPanel()
            }
            if !shortcuts.isEmpty {
                if !controls.isEmpty || visible.contains(.sound) { Divider().padding(.horizontal, 12) }
                HStack(spacing: 8) {
                    ForEach(shortcuts) { item in
                        Button {
                            close()
                            item.perform()
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                Text(item.title)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 26, alignment: .top)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.detail)
                    }
                }
                .padding(12)
            }
            if visible.isEmpty {
                ContentUnavailableView(L("Nothing here yet"), systemImage: "circle.hexagongrid",
                                       description: Text(L("Choose what this menu shows on Sirena's Home.")))
                    .frame(width: 320, height: 160)
            }
            Divider().padding(.horizontal, 12)
            OpenHomeButton(close: close)
        }
        .frame(width: 344)
    }
}

// MARK: - Controllers

private struct ControlRow: View {
    let item: BoltMenuItem
    let close: () -> Void
    @ObservedObject private var audio = IslandAudioOutput.shared
    @ObservedObject private var microphone = IslandMicrophone.shared
    @ObservedObject private var brightness = IslandBrightness.shared
    @ObservedObject private var keepAwake = KeepAwakeModule.shared.viewModel
    @State private var mirror = MirrorState.shared
    @AppStorage(PreferenceKeys.defaultDuration) private var defaultDuration = 0

    var body: some View {
        switch item {
        case .volume:
            sliderRow(symbol: audio.systemOutputMuted == true ? "speaker.slash.fill" : item.symbol,
                      value: Binding(get: { audio.systemOutputVolume ?? 0 },
                                     set: { audio.requestOutputAdjustment(volume: $0, muted: false) }),
                      iconAction: { audio.requestOutputAdjustment(muted: !(audio.systemOutputMuted ?? false)) },
                      dimmed: audio.systemOutputMuted == true)
        case .microphone:
            switchRow(isOn: !microphone.isMuted,
                      symbol: microphone.isMuted ? "mic.slash.fill" : "mic.fill",
                      state: microphone.isMuted ? L("Muted") : L("On")) {
                microphone.toggle()
            }
        case .brightness:
            let displays = brightness.displays.filter { $0.method != nil }
            if displays.isEmpty {
                unavailable(L("No display here can change brightness."))
            } else {
                ForEach(displays) { display in
                    sliderRow(symbol: item.symbol,
                              value: Binding(get: { display.brightness },
                                             set: { brightness.setBrightness($0, for: display.id, announces: false) }),
                              caption: displays.count > 1 ? display.name : nil)
                }
            }
        case .keyboardLight:
            if brightness.hasKeyboardLight {
                sliderRow(symbol: item.symbol,
                          value: Binding(get: { Double(brightness.keyboardLightLevel ?? 0) },
                                         set: { brightness.setKeyboardLightLevel(Float($0)) }),
                          iconAction: { brightness.setKeyboardLightEnabled(!(brightness.keyboardLightEnabled ?? false)) },
                          dimmed: brightness.keyboardLightEnabled == false)
                    .onAppear { brightness.refreshKeyboardLight() }
            } else {
                unavailable(L("This Mac has no keyboard light."))
            }
        case .keepAwake:
            HStack(spacing: 10) {
                icon(keepAwake.isActive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12, weight: .medium))
                    Text(keepAwake.isActive ? (keepAwake.formattedTimeRemaining() ?? L("Awake indefinitely")) : L("Mac can sleep"))
                        .font(.system(size: 10))
                        .foregroundStyle(keepAwake.isActive ? .green : .secondary)
                }
                Spacer(minLength: 4)
                Menu {
                    Picker(L("Duration"), selection: $defaultDuration) {
                        ForEach(Self.durations, id: \.minutes) { Text($0.title).tag($0.minutes) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(Self.durations.first { $0.minutes == defaultDuration }?.title ?? L("Indefinitely"))
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("How long Cafeína keeps the Mac awake. Remembered for next time."))
                .onChange(of: defaultDuration) { _, _ in
                    // Already on: restart with the new time.
                    if keepAwake.isActive { keepAwake.activate() }
                }
                Toggle("", isOn: Binding(get: { keepAwake.isActive },
                                         set: { $0 ? keepAwake.activate() : keepAwake.deactivate() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .help(item.detail)
        case .mirror:
            HStack(spacing: 10) {
                icon(mirror.isVisible)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12, weight: .medium))
                    Text(mirror.isVisible ? L("Showing") : L("Quick look at yourself"))
                        .font(.system(size: 10))
                        .foregroundStyle(mirror.isVisible ? .green : .secondary)
                }
                Spacer(minLength: 4)
                Button(mirror.isVisible ? L("Close") : L("Peek")) {
                    close()
                    item.perform()
                }
                .controlSize(.small)
            }
            .help(item.detail)
        default:
            EmptyView()
        }
    }

    static let durations: [(minutes: Int, title: String)] = [
        (15, L("15 minutes")), (30, L("30 minutes")), (60, L("1 hour")), (120, L("2 hours")),
        (300, L("5 hours")), (0, L("Indefinitely"))
    ]

    private func icon(_ on: Bool) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? .white : .secondary)
            .frame(width: 26, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? AnyShapeStyle(item.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            }
    }

    private func sliderRow(symbol: String, value: Binding<Double>, caption: String? = nil,
                           iconAction: (() -> Void)? = nil, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption {
                Text(caption).font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 36)
            }
            HStack(spacing: 10) {
                Button { iconAction?() } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(dimmed ? .secondary : .primary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(iconAction == nil)
                Slider(value: value, in: 0...1)
                    .controlSize(.small)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .help(item.detail)
    }

    private func switchRow(isOn: Bool, symbol: String, state: String, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background((isOn ? Color.green : Color.red).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12, weight: .medium))
                Text(state).font(.system(size: 10)).foregroundStyle(isOn ? .green : .red)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .help(item.detail)
    }

    private func unavailable(_ text: String) -> some View {
        HStack(spacing: 10) {
            icon(false)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct OpenHomeButton: View {
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            close()
            ModuleManager.shared.openPage(.home)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Open Sirena"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L("Settings and turning features on or off"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("⌃⌥S")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

/// Fader's mixer (SoundKit), hosted in the popover.
private struct SoundPanel: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> NSViewController {
        SoundController.shared.makeViewController()
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
