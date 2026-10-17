/// BoltMenu.swift
///
/// What Sirena's ⚡ menu bar icon shows. Chosen on Home (the first section), shown in
/// the popover below the icon: the sound mixer plus quick buttons for the tools.

import AppKit
import ClipboardKit
import SoundKit
import SwiftUI

enum BoltMenuItem: String, CaseIterable, Identifiable {
    case sound, clipboard, keepAwake, mirror, pinWindow, textCapture, shelf, hiddenIcons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: return L("Sound")
        case .clipboard: return L("Clipboard History")
        case .keepAwake: return L("Keep Awake")
        case .mirror: return ModuleID.mirror.title
        case .pinWindow: return ModuleID.pinWindow.title
        case .textCapture: return ModuleID.textCapture.title
        case .shelf: return ModuleID.shelf.title
        case .hiddenIcons: return ModuleID.menuBar.title
        }
    }

    var detail: String {
        switch self {
        case .sound: return L("Outputs, per-app volume and the microphone")
        case .clipboard: return L("Open the history panel")
        case .keepAwake: return L("Turn Cafeína on or off")
        case .mirror: return L("Show or hide the mirror")
        case .pinWindow: return L("Choose a window to pin")
        case .textCapture: return L("Select text on screen")
        case .shelf: return L("Show or hide the shelf")
        case .hiddenIcons: return L("Show or hide the chosen icons")
        }
    }

    var symbol: String {
        switch self {
        case .sound: return "speaker.wave.2.fill"
        case .clipboard: return ModuleID.clipboard.symbol
        case .keepAwake: return "cup.and.saucer.fill"
        case .mirror: return ModuleID.mirror.symbol
        case .pinWindow: return ModuleID.pinWindow.symbol
        case .textCapture: return ModuleID.textCapture.symbol
        case .shelf: return ModuleID.shelf.symbol
        case .hiddenIcons: return "eye.slash"
        }
    }

    var tint: Color {
        switch self {
        case .sound: return .indigo
        case .clipboard: return ModuleID.clipboard.tint
        case .keepAwake: return ModuleID.keepAwake.tint
        case .mirror: return ModuleID.mirror.tint
        case .pinWindow: return ModuleID.pinWindow.tint
        case .textCapture: return ModuleID.textCapture.tint
        case .shelf: return ModuleID.shelf.tint
        case .hiddenIcons: return ModuleID.menuBar.tint
        }
    }

    /// On or off right now, for the items that switch something (nil for one-shot actions).
    @MainActor
    var isOn: Bool? {
        switch self {
        case .keepAwake: return KeepAwakeModule.shared.viewModel.isActive
        case .mirror: return MirrorState.shared.isVisible
        case .shelf: return ShelfController.shared.isVisible
        case .hiddenIcons: return MenuBarModule.shared.isCollapsed
        case .pinWindow: return !PinWindowController.shared.pins.isEmpty
        default: return nil
        }
    }

    /// The state in words, under the button.
    @MainActor
    var stateText: String? {
        guard let isOn else { return nil }
        switch self {
        case .keepAwake: return isOn ? L("Awake") : L("Can sleep")
        case .mirror, .shelf: return isOn ? L("Showing") : L("Hidden")
        case .hiddenIcons: return isOn ? L("Hidden") : L("Showing")
        case .pinWindow:
            let count = PinWindowController.shared.pins.count
            return isOn ? (count == 1 ? L("1 pinned") : L("\(count) pinned")) : L("None pinned")
        default: return nil
        }
    }

    /// The module that has to run for this item to make sense.
    var module: ModuleID? {
        switch self {
        case .sound: return nil
        case .clipboard: return .clipboard
        case .keepAwake: return .keepAwake
        case .mirror: return .mirror
        case .pinWindow: return .pinWindow
        case .textCapture: return .textCapture
        case .shelf: return .shelf
        case .hiddenIcons: return .menuBar
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .sound: break
        case .clipboard: ClipboardController.shared.togglePanel()
        case .keepAwake: KeepAwakeModule.shared.viewModel.toggleActive()
        case .mirror: MirrorController.shared.toggle()
        case .pinWindow: PinWindowController.shared.selectWindowToPin()
        case .textCapture: TextCaptureController.shared.capture(.text())
        case .shelf: ShelfController.shared.toggle()
        case .hiddenIcons: MenuBarModule.shared.toggle()
        }
    }
}

/// Which items the ⚡ menu shows (kept in UserDefaults).
@MainActor
@Observable
final class BoltMenuSettings {
    static let shared = BoltMenuSettings()
    private static let key = "boltMenu.items"

    var enabled: Set<BoltMenuItem> {
        didSet { UserDefaults.standard.set(enabled.map(\.rawValue).sorted(), forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key)
        enabled = saved.map { Set($0.compactMap(BoltMenuItem.init)) }
            ?? [.sound, .clipboard, .keepAwake, .textCapture, .shelf]
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

    private var actions: [BoltMenuItem] { settings.visibleItems.filter { $0 != .sound } }

    var body: some View {
        VStack(spacing: 0) {
            if settings.visibleItems.contains(.sound) {
                SoundPanel()
            }
            if !actions.isEmpty {
                if settings.visibleItems.contains(.sound) { Divider().padding(.horizontal, 12) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(actions) { item in
                        BoltButton(item: item) {
                            // Toggles stay open so the new state shows; actions close it.
                            if item.isOn == nil || item == .mirror { close() }
                            item.perform()
                        }
                    }
                }
                .padding(12)
            }
            if settings.visibleItems.isEmpty {
                ContentUnavailableView(L("Nothing here yet"), systemImage: "bolt",
                                       description: Text(L("Choose what this menu shows on Sirena's Home.")))
                    .frame(width: 320, height: 160)
            }
            Divider().padding(.horizontal, 12)
            // Sirena's Home: turn features on and off and change their settings.
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(HoverHighlight())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(width: 344)
    }
}

/// Fader's mixer (SoundKit), hosted in the popover.
private struct SoundPanel: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> NSViewController {
        SoundController.shared.makeViewController()
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

/// The menu-like highlight under the pointer.
private struct HoverHighlight: View {
    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            .onHover { isHovering = $0 }
    }
}

/// One quick button: colored when what it switches is on, gray when off, with the state
/// in words below (Cafeína "Acordado", Espelho "Aparecendo"…).
private struct BoltButton: View {
    let item: BoltMenuItem
    let action: () -> Void
    @ObservedObject private var keepAwake = KeepAwakeModule.shared.viewModel
    @State private var mirror = MirrorState.shared
    @State private var shelf = ShelfController.shared
    @State private var menuBar = MenuBarModule.shared
    @State private var pins = PinWindowController.shared

    var body: some View {
        // Reading the observed objects keeps the state live while the menu is open.
        _ = (keepAwake.isActive, mirror.isVisible, shelf.isVisible, menuBar.isCollapsed, pins.pins.count)
        let isOn = item.isOn
        let lit = isOn ?? true
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(lit ? .white : .secondary)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(lit ? AnyShapeStyle(item.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    }
                    .overlay(alignment: .topTrailing) {
                        if isOn == true {
                            Circle()
                                .fill(.green)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                                .offset(x: 3, y: -3)
                        }
                    }
                    .animation(.snappy, value: isOn)
                Text(item.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let state = item.stateText {
                    Text(state)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isOn == true ? .green : .secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                } else {
                    Text(" ").font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.detail)
        .accessibilityValue(item.stateText ?? "")
    }
}
