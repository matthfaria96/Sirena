/// BoltMenu.swift
///
/// What Sirena's menu bar icon shows, chosen on Home. Two kinds of things:
/// - Atalhos: programs opened with one click (clipboard history, pin a window, capture text).
/// - Controladores: things adjusted right there (volume, microphone, display brightness,
///   Cafeína, a peek through the camera, the per-app mixer). Volume,
///   microphone and brightness use the controls ported from Vorssaint.

import AppKit
import ClipboardKit
import SoundKit
import SwiftUI

enum BoltMenuItem: String, CaseIterable, Identifiable {
    // Atalhos
    case clipboard, pinWindow, textCapture, mirror
    // Controladores
    case keepAwake, volume, microphone, brightness, sound

    var id: String { rawValue }

    enum Kind { case shortcut, control }

    var kind: Kind {
        switch self {
        case .clipboard, .pinWindow, .textCapture, .mirror: return .shortcut
        default: return .control
        }
    }

    static var shortcuts: [BoltMenuItem] { allCases.filter { $0.kind == .shortcut } }
    static var controls: [BoltMenuItem] { allCases.filter { $0.kind == .control } }

    var title: String {
        switch self {
        case .clipboard: return L("History")
        case .pinWindow: return ModuleID.pinWindow.title
        case .textCapture: return ModuleID.textCapture.title
        case .volume: return L("Volume")
        case .microphone: return L("Microphone")
        case .brightness: return L("Display Brightness")
        case .keepAwake: return L("Keep Display On")
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
        VStack(spacing: 12) {
            if !shortcuts.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(shortcuts) { item in
                        ShortcutButton(item: item) {
                            close()
                            item.perform()
                        }
                    }
                }
                Divider()
            }
            ForEach(controls) { item in
                ControlRow(item: item, close: close)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
            }
            if visible.contains(.sound) {
                SoundPanel()
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            if visible.isEmpty {
                ContentUnavailableView(L("Nothing here yet"), systemImage: "circle.hexagongrid",
                                       description: Text(L("Choose what this menu shows on Sirena's Home.")))
                    .frame(height: 140)
            }
            HStack(spacing: 10) {
                FooterButton(title: L("Settings"), symbol: "gearshape", tint: nil) {
                    close()
                    ModuleManager.shared.openPage(.home)
                }
                .help(L("Opens Sirena on Home (⌃⌥S)"))
                FooterButton(title: L("Quit"), symbol: "power", tint: .red) {
                    NSApp.terminate(nil)
                }
                .help(L("Quits Sirena"))
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 344)
    }
}

/// A shortcut at the top: a quiet rounded square with the icon, the name below.
private struct ShortcutButton: View {
    let item: BoltMenuItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if item == .mirror {
                        Image("CameraShutter").resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: item.symbol).font(.system(size: 16, weight: .regular))
                    }
                }
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.14 : 0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8))
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.detail)
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let tint: Color?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((tint ?? .primary).opacity(isHovering ? 0.22 : (tint == nil ? 0.07 : 0.14))))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((tint ?? .primary).opacity(0.25), lineWidth: 0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
        case .keepAwake:
            HStack(spacing: 10) {
                icon(keepAwake.isActive)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(item.title).font(.system(size: 12, weight: .medium))
                        InfoButton(item.detail).controlSize(.mini)
                    }
                    Text(keepAwake.isActive ? (keepAwake.formattedTimeRemaining() ?? L("Awake indefinitely")) : L("Sleep allowed"))
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

/// Fader's mixer (SoundKit), hosted in the popover.
private struct SoundPanel: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> NSViewController {
        SoundController.shared.makeViewController()
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
