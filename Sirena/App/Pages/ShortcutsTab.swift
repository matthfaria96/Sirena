/// ShortcutsTab.swift
///
/// The Atalhos tab of Janela e Dock: every window action and switcher shortcut in one
/// searchable list. Rows only draw text; the recorder (an AppKit view) is created when a
/// shortcut is clicked, in a popover. Dozens of live recorders in one Form were what
/// made the old lists slow and jumpy.

import MASShortcut
import SwiftUI

struct ShortcutsTab: View {
    /// One instance: each AppSettingsViewModel registers notification observers.
    private static let sharedSettings = AppSettingsViewModel()

    @State private var manager = ModuleManager.shared
    @State private var settings = ShortcutsTab.sharedSettings
    @State private var recordingObserver = ShortcutRecordingObserver()
    @State private var query = ""
    /// The one shortcut being recorded right now.
    @State private var editingKey: String?

    private static let groups: [(title: String, actions: [WindowAction])] = [
        (L("Halves"), [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf]),
        (L("Corners"), [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        (L("Size and Position"), [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore]),
        (L("Displays"), [.nextDisplay, .previousDisplay]),
        (L("Thirds"), [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
        (L("Fourths"), [.firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths, .lastThreeFourths]),
        (L("Sixths"), [.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]),
        (L("Move"), [.moveLeft, .moveRight, .moveUp, .moveDown]),
        (L("Tile and width"), [.tileRows, .tileColumns, .largerWidth, .smallerWidth]),
        (L("Vertical thirds"), [.topVerticalThird, .middleVerticalThird, .bottomVerticalThird, .topVerticalTwoThirds, .bottomVerticalTwoThirds]),
        (L("Eighths"), [.topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
                        .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth]),
        (L("Other grids"), [.topLeftNinth, .topLeftTwelfth, .topLeftSixteenth])
    ]

    private func name(_ action: WindowAction) -> String {
        action.settingsDisplayName ?? action.displayName ?? action.name
    }

    private var filteredGroups: [(title: String, actions: [WindowAction])] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return Self.groups }
        return Self.groups.compactMap { group in
            if group.title.localizedCaseInsensitiveContains(text) { return group }
            let actions = group.actions.filter { name($0).localizedCaseInsensitiveContains(text) }
            return actions.isEmpty ? nil : (group.title, actions)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if query.isEmpty, manager.isEnabled(.switcher) {
                    SwitcherShortcutsSection()
                }

                if manager.isEnabled(.windows) {
                    // Three blocks, each a two-column grid: halves and corners, size and
                    // displays, then the finer grids (thirds through the other grids).
                    ForEach(Self.blocks, id: \.self) { titles in
                        let groups = filteredGroups.filter { titles.contains($0.title) }
                        if !groups.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(groups, id: \.title) { group in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(group.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            grid(group.actions)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if query.isEmpty {
                        Section {
                            Toggle(isOn: $settings.allowAnyShortcut) {
                                Text(L("Remove keyboard shortcut restrictions"))
                                Text(L("Lets you record any key combination, even ones macOS or the menus of the front app already use."))
                            }
                            HStack {
                                Button {
                                    settings.restoreDefaults()
                                } label: {
                                    Label(L("Restore Default Shortcuts"), systemImage: "arrow.counterclockwise")
                                }
                                Spacer()
                                Button {
                                    settings.importConfig()
                                } label: {
                                    Label(L("Import…"), systemImage: "square.and.arrow.down")
                                }
                                Button {
                                    settings.exportConfig()
                                } label: {
                                    Label(L("Export…"), systemImage: "square.and.arrow.up")
                                }
                            }
                        } footer: {
                            Text(L("Restoring also resets the snap areas. Import and export use a JSON file with every window setting."))
                        }
                    }
                } else if query.isEmpty {
                    Section {
                        Text(L("Turn on “Arrange windows” in the Windows tab to use window shortcuts."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text(L("Search shortcuts")))
        .onChange(of: query) { _, _ in editingKey = nil }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.configImported)) { _ in labelsVersion += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .switcherShortcutRecordingStarted)) { _ in editingKey = nil }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.changeDefaults)) { _ in labelsVersion += 1 }
    }

    @State private var labelsVersion = 0

    private static let blocks: [[String]] = [
        [L("Halves"), L("Corners")],
        [L("Size and Position"), L("Displays")],
        [L("Thirds"), L("Fourths"), L("Sixths"), L("Move"), L("Tile and width"),
         L("Vertical thirds"), L("Eighths"), L("Other grids")]
    ]

    /// Two columns. A plain Grid: rows only hold text, so it stays light.
    private func grid(_ actions: [WindowAction]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            ForEach(Array(stride(from: 0, to: actions.count, by: 2)), id: \.self) { start in
                GridRow {
                    row(actions[start])
                    if start + 1 < actions.count {
                        row(actions[start + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func row(_ action: WindowAction) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: action.image)
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 14)
            Text(name(action))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(name(action))
            Spacer(minLength: 4)
            if let options = Self.options[action] {
                ActionOptionsButton(content: options)
                    .frame(width: 18, height: 18)
            }
            ShortcutChip(action: action, recordingObserver: recordingObserver, editingKey: $editingKey, labelsVersion: labelsVersion)
        }
        .frame(maxWidth: .infinity)
    }

    /// Actions with extra settings in a popover (Rectangle's gear buttons).
    private static let options: [WindowAction: () -> NSView] = [
        .largerWidth: { WidthSettingsView() },
        .tileRows: { TileSettingsView() }
    ]
}

/// A shortcut shown as text. Clicking it swaps in the recorder (an AppKit view), already
/// listening; once a shortcut is recorded, cleared or cancelled it turns back into text.
/// Only one recorder exists at a time.
private struct ShortcutChip: View {
    let action: WindowAction
    let recordingObserver: ShortcutRecordingObserver
    @Binding var editingKey: String?
    /// Bumped when restoring or importing rewrites every shortcut.
    let labelsVersion: Int

    private var defaultsKey: String { action.name }

    var body: some View {
        if editingKey == defaultsKey {
            MASShortcutViewRepresentable(
                defaultsKey: defaultsKey,
                validator: Defaults.allowAnyShortcut.enabled ? PassthroughShortcutValidator() : SirenaShortcutValidator(ownKey: defaultsKey),
                recordingObserver: recordingObserver,
                recordsMouseButtons: true,
                startsRecording: true,
                onRecordingChange: { recording in
                    if !recording, editingKey == defaultsKey { editingKey = nil }
                }
            )
            .frame(width: 130, height: 22)
            .help(L("Type the new shortcut. Esc cancels, ⌫ removes it."))
            .onAppear { NotificationCenter.default.post(name: .windowActionShortcutRecordingStarted, object: nil) }
        } else {
            let label = Self.label(for: action)
            Button {
                editingKey = defaultsKey
            } label: {
                Text(label ?? L("Record Shortcut"))
                    .font(.callout)
                    .foregroundStyle(label == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 118)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 130, alignment: .trailing)
        }
    }

    /// The saved shortcut as text ("⌃⌥←", or a mouse button), nil when there's none.
    static func label(for action: WindowAction) -> String? {
        let shortcut: MASShortcut?
        if let stored = UserDefaults.standard.object(forKey: action.name) {
            // MASDictionaryTransformer: transformedValue is dictionary → shortcut ({} = none).
            shortcut = MASDictionaryTransformer().transformedValue(stored) as? MASShortcut
        } else {
            // Defaults are registered only once Accessibility is allowed: show them anyway.
            let fallback = Defaults.alternateDefaultShortcuts.enabled ? action.alternateDefault : action.spectacleDefault
            shortcut = fallback.map { MASShortcut(keyCode: $0.keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: $0.modifierFlags)) }
        }
        guard let shortcut else { return nil }
        let text = MouseButtonShortcut.displayable(shortcut).description
        return text.isEmpty ? nil : text
    }
}

/// Rectangle's gear button that opens an action's settings in a popover.
private struct ActionOptionsButton: NSViewRepresentable {
    let content: () -> NSView

    func makeNSView(context: Context) -> PopoverButton {
        let button = PopoverButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.image = NSImage(systemSymbolName: "gear", accessibilityDescription: L("Options"))
        button.contentView = content()
        return button
    }

    func updateNSView(_ nsView: PopoverButton, context: Context) {}
}

extension Notification.Name {
    /// A window action's recorder appeared: a switcher recorder stops.
    static let windowActionShortcutRecordingStarted = Notification.Name("sirena.windowActionShortcutRecordingStarted")
}
