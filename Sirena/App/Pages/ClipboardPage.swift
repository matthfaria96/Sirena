/// ClipboardPage.swift
///
/// The clipboard history itself (search, pin, copy, delete), and its settings on one page.

import ClipboardKit
import SwiftUI

struct ClipboardPage: View {
    var body: some View {
        ModulePage(module: .clipboard, tabs: [
            PageTab("history", L("History")) { ClipboardHistoryView() },
            PageTab("settings", L("Settings")) { SirenaClipboardSettings() }
        ]) {
            Button {
                ClipboardController.shared.togglePanel()
            } label: {
                Label(L("Open Panel"), systemImage: "list.bullet.rectangle")
            }
            .help(L("The floating history panel, also on ⇧⌘C."))
        }
    }
}

private struct ClipboardHistoryView: View {
    @State private var controller = ClipboardController.shared
    @State private var query = ""
    @State private var selection: ObjectIdentifier?
    @State private var confirmsClear = false

    private var entries: [ClipboardEntry] {
        let all = controller.entries
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || ($0.appName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        let entries = entries
        let pinned = entries.filter(\.isPinned)
        let recent = entries.filter { !$0.isPinned }

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search the history"), text: $query)
                    .textFieldStyle(.plain)
                if controller.isPaused {
                    Label(L("Paused"), systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(L("New copies aren't being kept. Resume in Settings."))
                }
                Text(L("\(controller.historyCount) items"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(L("Clear…")) { confirmsClear = true }
                    .controlSize(.small)
                    .disabled(recent.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if entries.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? L("Nothing copied yet") : L("No matches"),
                          systemImage: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? L("Everything you copy shows up here.") : L("Try other words."))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    if !pinned.isEmpty {
                        Section(L("Pinned Items")) {
                            ForEach(pinned) { ClipboardRow(entry: $0).tag($0.id) }
                        }
                    }
                    if !recent.isEmpty {
                        Section(L("Recent")) {
                            ForEach(recent) { ClipboardRow(entry: $0).tag($0.id) }
                        }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
                    if let id = ids.first, let entry = entries.first(where: { $0.id == id }) {
                        Button(L("Copy")) { controller.copy(id) }
                        if entry.kind == .text || entry.kind == .richText {
                            Button(L("Copy Without Formatting")) { controller.copy(id, removeFormatting: true) }
                        }
                        Button(entry.isPinned ? L("Unpin") : L("Pin")) { controller.togglePin(id) }
                        Divider()
                        Button(L("Delete"), role: .destructive) { controller.delete(id) }
                    }
                } primaryAction: { ids in
                    // Double-click (or Return) puts it back on the clipboard.
                    if let id = ids.first { controller.copy(id) }
                }
                .onDeleteCommand {
                    if let selection { controller.delete(selection) }
                }
            }
        }
        .confirmationDialog(L("Clear the clipboard history?"), isPresented: $confirmsClear) {
            Button(L("Clear History"), role: .destructive) { controller.clearHistory() }
        } message: {
            Text(L("Pinned items are kept."))
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    @State private var isHovering = false
    private var controller: ClipboardController { .shared }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            preview
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? (entry.kind == .image ? L("Image") : entry.kind == .file ? L("File") : L("(no text)")) : entry.title)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let app = entry.appName { Text(app) ; Text("·") }
                    Text(entry.lastCopied, format: .relative(presentation: .named))
                    if entry.copies > 1 { Text("· \(entry.copies)×") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isHovering {
                HStack(spacing: 2) {
                    rowButton(L("Copy"), "doc.on.doc") { controller.copy(entry.id) }
                    rowButton(entry.isPinned ? L("Unpin") : L("Pin"), entry.isPinned ? "pin.slash" : "pin") { controller.togglePin(entry.id) }
                    rowButton(L("Delete"), "trash") { controller.delete(entry.id) }
                }
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("Pinned Items"))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if entry.kind == .image, let image = controller.thumbnail(for: entry.id) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let icon = controller.appIcon(for: entry.id) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .bottomTrailing) {
                    if entry.kind != .text {
                        Image(systemName: entry.kind == .file ? "doc.fill" : "textformat")
                            .font(.system(size: 9, weight: .bold))
                            .padding(3)
                            .background(.regularMaterial, in: Circle())
                    }
                }
        } else {
            Image(systemName: entry.kind == .image ? "photo" : entry.kind == .file ? "doc" : "text.alignleft")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func rowButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}
