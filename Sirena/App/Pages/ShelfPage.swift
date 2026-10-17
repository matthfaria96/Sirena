/// ShelfPage.swift

import SwiftUI
import UniformTypeIdentifiers

struct ShelfPage: View {
    var body: some View {
        ModulePage(module: .shelf, tabs: [
            PageTab("general", L("General")) { ShelfGeneralView() },
            PageTab("items", L("Appearance")) { ShelfItemsView() },
            PageTab("shelf", L("Contents")) { ShelfContentsView() }
        ]) {
            ShelfToggleButton()
        }
    }
}

private struct ShelfToggleButton: View {
    @State private var controller = ShelfController.shared

    var body: some View {
        Button {
            controller.toggle()
        } label: {
            Label(controller.isVisible ? L("Hide Shelf") : L("Show Shelf"), systemImage: "tray")
        }
    }
}

// MARK: - General

private struct ShelfGeneralView: View {
    @State private var settings = ShelfSettings.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ShelfPositionPicker(selection: $settings.position)
                } label: {
                    Text(L("Window Position"))
                    Text(settings.position.title)
                }
                .disabled(settings.showAtCursor)
                .opacity(settings.showAtCursor ? 0.5 : 1)
                Toggle(isOn: $settings.showAtCursor) {
                    Text(L("Show at the mouse pointer"))
                    Text(L("The shelf appears next to the pointer when a drag starts."))
                }
                Toggle(isOn: $settings.showOnlyAtEdge) {
                    Text(L("Show only when dragging to the screen edge"))
                    Text(L("The shelf waits until the drag reaches its edge of the screen."))
                }
                .disabled(settings.showAtCursor)
            } header: {
                Text(L("Appearance"))
            }

            Section {
                Picker(L("Hold to keep the shelf hidden"), selection: $settings.suppressKey) {
                    ForEach(ShelfSuppressKey.allCases) { Text($0.title).tag($0) }
                }
                IgnoredAppsList(apps: $settings.ignoredApps)
            } header: {
                Text(L("When dragging"))
            } footer: {
                Text(L("Dragging in an ignored app never shows the shelf."))
            }

            Section {
                ShortcutRow(title: L("Show / Hide Shelf"), defaultsKey: ShelfSettings.toggleShortcutKey,
                            recordingObserver: recordingObserver)
                ShortcutRow(title: L("Add Clipboard Contents to Shelf"), defaultsKey: ShelfSettings.addClipboardShortcutKey,
                            recordingObserver: recordingObserver)
            } header: {
                Text(L("Keyboard shortcuts"))
            } footer: {
                Text(L("Files and text can also be added from the Services menu of any app (“Adicionar à Prateleira do Sirena”), from the Shortcuts app, or with sirena://shelf-toggle and sirena://shelf-add-clipboard."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct IgnoredAppsList: View {
    @Binding var apps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Ignored Apps"))
            if apps.isEmpty {
                Text(L("None"))
                    .foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.self) { bundleID in
                HStack {
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                    Spacer()
                    Button {
                        apps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button(L("Add App…")) { addApp() }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
    }
}

// MARK: - Items

private struct ShelfItemsView: View {
    @State private var settings = ShelfSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(L("Window Size"), selection: $settings.itemSize) {
                    ForEach(ShelfItemSize.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $settings.showPreviews) {
                    Text(L("Show previews"))
                    Text(L("Identify files by a full Quick Look preview instead of their icon."))
                }
            } header: {
                Text(L("Items"))
            }

            Section {
                Toggle(isOn: $settings.removeAfterDragOut) {
                    Text(L("Remove items after dragging them out"))
                    Text(L("Locked items always stay. Use “Restore Last Removed Files” to bring items back."))
                }
                Toggle(isOn: $settings.resolveAliases) {
                    Text(L("Resolve aliases"))
                    Text(L("Aliases dropped on the shelf are replaced by their original files."))
                }
            } header: {
                Text(L("Behavior"))
            } footer: {
                Text(L("The shelf keeps references to the files you add, it doesn't copy them. Several files dropped together become a Stack: drag them out together, or split it up from its menu."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Contents

private struct ShelfContentsView: View {
    @State private var store = ShelfStore.shared

    var body: some View {
        Form {
            Section {
                if store.items.isEmpty {
                    Text(L("The shelf is empty. Start dragging something, or add the clipboard's contents."))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    HStack {
                        Image(systemName: icon(for: item))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(item.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if item.isLocked {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.toggleLock([item.id])
                        } label: {
                            Image(systemName: item.isLocked ? "lock.open" : "lock")
                        }
                        .buttonStyle(.borderless)
                        .help(item.isLocked ? L("Unlock") : L("Lock"))
                        Button {
                            store.remove([item.id])
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove from Shelf"))
                    }
                }
            } header: {
                Text(L("On the shelf"))
            }

            Section {
                HStack {
                    Button(L("Add from Clipboard")) { ShelfActions.addFromClipboard() }
                    Button(L("Restore Last Removed Files")) { store.restoreLastRemoved() }
                        .disabled(!store.canRestore)
                    Spacer()
                    Button(L("Remove All Files"), role: .destructive) { store.removeAll() }
                        .disabled(store.items.isEmpty)
                }
            } footer: {
                Text(L("Looking for the clipboard history? It lives in the Clipboard feature, which keeps, searches and pins everything you copy."))
            }
        }
        .formStyle(.grouped)
    }

    private func icon(for item: ShelfItem) -> String {
        switch item.content {
        case .files: return item.isStack ? "square.stack.3d.up" : "doc"
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette"
        }
    }
}

/// The six places the shelf can sit, drawn on a little screen: one click per place.
private struct ShelfPositionPicker: View {
    @Binding var selection: ShelfPosition

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .overlay(alignment: .top) {
                Rectangle().fill(.tertiary).frame(height: 6)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
            }
            .overlay {
                HStack {
                    column([.leftTop, .leftCenter, .leftBottom])
                    Spacer()
                    column([.rightTop, .rightCenter, .rightBottom])
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .frame(width: 150, height: 96)
    }

    private func column(_ positions: [ShelfPosition]) -> some View {
        VStack {
            ForEach(Array(positions.enumerated()), id: \.element) { index, position in
                if index > 0 { Spacer(minLength: 0) }
                Button {
                    withAnimation(.snappy) { selection = position }
                } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selection == position ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 16, height: 22)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white.opacity(selection == position ? 0.6 : 0), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(position.title)
                .accessibilityLabel(position.title)
                .accessibilityAddTraits(selection == position ? .isSelected : [])
            }
        }
    }
}
