/// MenuHistoryPanel.swift
///
/// Histórico inside the menu bar panel: the last copies with a preview of what each one is
/// (image, color, link, files, code), a bigger preview when the pointer rests on one, search,
/// drag out, and click to copy or paste (⌥-click does the other one). How many items, the
/// previews and what a click does are set on the Clipboard page.

import AppKit
import ClipboardKit
import SwiftUI

struct InlineHistoryPanel: View {
    let closeMenu: () -> Void
    @State private var controller = ClipboardController.shared
    @AppStorage(ClipboardMenuSettings.countKey) private var count = ClipboardMenuSettings.defaultCount
    @AppStorage(ClipboardMenuSettings.previewsKey) private var showsPreviews = true
    @AppStorage(ClipboardMenuSettings.clickPastesKey) private var clickPastes = false
    @State private var query = ""
    @State private var copied: ObjectIdentifier?
    /// Clearing asks for a second click.
    @State private var confirmsClear = false

    var body: some View {
        let all = controller.entries
        let entries = Array(filtered(all).prefix(max(count, 1)))
        VStack(alignment: .leading, spacing: 2) {
            if !all.isEmpty {
                searchField
                    .padding(.bottom, 4)
            }
            if all.isEmpty {
                Label(L("Nothing copied yet"), systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if entries.isEmpty {
                Label(L("No matches"), systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry,
                               isCopied: copied == entry.id,
                               showsPreview: showsPreviews,
                               clickPastes: clickPastes,
                               activate: { paste, plain in activate(entry, paste: paste, plain: plain) })
                }
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 8) {
                footerButton(L("Open History"), symbol: "list.bullet.rectangle", tint: .accentColor) {
                    closeMenu()
                    ModuleManager.shared.openPage(.module(.clipboard))
                    PageNavigator.shared.requestedTab = "history"
                }
                footerButton(confirmsClear ? L("Click to Confirm") : L("Clear History"),
                             symbol: confirmsClear ? "exclamationmark.triangle.fill" : "trash", tint: .red) {
                    if confirmsClear {
                        controller.clearHistory()
                        withAnimation(.snappy) { confirmsClear = false }
                    } else {
                        withAnimation(.snappy) { confirmsClear = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.easeOut) { confirmsClear = false }
                        }
                    }
                }
                .disabled(all.isEmpty)
                .help(L("Removes every copy except the pinned ones"))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(L("Search copies"), text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func filtered(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.localizedStandardContains(text)
                || (entry.preview.caption?.localizedStandardContains(text) ?? false)
                || (entry.appName?.localizedStandardContains(text) ?? false)
        }
    }

    /// Copies, or pastes into the app that was in front before the menu opened.
    private func activate(_ entry: ClipboardEntry, paste: Bool, plain: Bool) {
        guard paste else {
            controller.copy(entry.id, removeFormatting: plain)
            withAnimation(.snappy) { copied = entry.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                if copied == entry.id { withAnimation(.easeOut) { copied = nil } }
            }
            return
        }
        let target = SirenaStatusItem.instance.appBeforePanel
        closeMenu()
        target?.activate()
        // ⌘V goes to whoever is in front: give the app a moment to come forward.
        let id = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            ClipboardController.shared.paste(id, removeFormatting: plain)
        }
    }

    /// Native Liquid Glass buttons, full-size text so they read at a glance.
    private func footerButton(_ title: String, symbol: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .compatGlassButtonStyle()
        .controlSize(.large)
        .tint(tint == .accentColor ? nil : tint)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: ClipboardEntry
    let isCopied: Bool
    let showsPreview: Bool
    let clickPastes: Bool
    /// (paste, without formatting)
    let activate: (Bool, Bool) -> Void
    @State private var isHovering = false
    @State private var showsDetail = false
    @State private var hoverTask: Task<Void, Never>?
    private var controller: ClipboardController { .shared }

    var body: some View {
        Button {
            // ⌥-click does the opposite of the chosen click.
            activate(clickPastes != NSEvent.modifierFlags.contains(.option), false)
        } label: {
            HStack(spacing: 9) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(showsPreview && entry.preview == .text ? 2 : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    if showsPreview {
                        subtitle
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if isHovering {
                    Image(systemName: clickPastes ? "arrow.down.doc" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, showsPreview ? 4 : 5)
            .background(isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .onDisappear { hoverTask?.cancel() }
        .onAppear { controller.loadThumbnail(for: entry.id) }
        .popover(isPresented: $showsDetail, arrowEdge: .leading) {
            ClipPreviewDetail(entry: entry,
                              thumbnail: controller.cachedThumbnail(for: entry.id),
                              fullText: controller.fullText(for: entry.id))
        }
        .onDrag {
            hoverTask?.cancel()
            showsDetail = false
            return controller.itemProvider(for: entry.id) ?? NSItemProvider()
        }
        .contextMenu { menu }
        .help(clickPastes ? L("Click to paste, ⌥-click to copy") : L("Click to copy, ⌥-click to paste"))
        .accessibilityLabel(entry.title)
    }

    @ViewBuilder
    private var leading: some View {
        if showsPreview {
            ClipPreviewTile(preview: entry.preview,
                            thumbnail: controller.cachedThumbnail(for: entry.id),
                            appIcon: controller.appIcon(for: entry.id),
                            size: 30)
        } else if let icon = controller.appIcon(for: entry.id) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }

    private var title: String {
        switch entry.preview {
        case .files(let urls):
            return urls.map(\.lastPathComponent).joined(separator: ", ")
        case .image:
            return entry.title.isEmpty ? L("Image") : entry.title
        default:
            let text = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? L("(empty)") : text
        }
    }

    private var subtitle: Text {
        var parts: [String] = []
        // The caption adds what the title doesn't say (an image's kind, a link's site), never a repeat.
        if let caption = entry.preview.caption, entry.preview != .image || !entry.title.isEmpty,
           caption.caseInsensitiveCompare(title) != .orderedSame {
            parts.append(caption)
        }
        if let app = entry.appName, !app.isEmpty { parts.append(app) }
        let prefix = parts.isEmpty ? "" : parts.joined(separator: " · ") + " · "
        return Text(prefix) + Text(entry.lastCopied, format: .relative(presentation: .named))
    }

    @ViewBuilder
    private var menu: some View {
        if clickPastes {
            Button(L("Copy")) { activate(false, false) }
        } else {
            Button(L("Paste")) { activate(true, false) }
        }
        Button(L("Paste Without Formatting")) { activate(true, true) }
        Divider()
        Button(entry.isPinned ? L("Unpin") : L("Pin")) { controller.togglePin(entry.id) }
        Button(L("Delete"), role: .destructive) { controller.delete(entry.id) }
    }

    /// The bigger preview shows after the pointer rests on the row for a moment.
    private func hover(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        guard hovering, showsPreview else {
            showsDetail = false
            return
        }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            if !Task.isCancelled { showsDetail = true }
        }
    }
}
