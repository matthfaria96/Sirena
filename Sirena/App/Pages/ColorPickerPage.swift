/// ColorPickerPage.swift

import SwiftUI

struct ColorPickerPage: View {
    var body: some View {
        ModulePage(module: .colorPicker, tabs: [
            PageTab("colors", L("Colors")) { ColorHistoryView() },
            PageTab("palettes", L("Palettes")) { PalettesView() },
            PageTab("settings", L("Settings")) { ColorSettingsView() }
        ]) {
            Button { ColorPickerController.shared.pick() } label: {
                Label(L("Pick Color"), systemImage: "eyedropper.halffull")
            }
            .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Swatch

private struct Swatch: View {
    let color: SavedColor
    var size: CGFloat = 64
    var showLabel = true
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                    if copied || hovering {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(color.isLight ? Color.black.opacity(0.7) : Color.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(hovering ? 1.04 : 1)
            if showLabel {
                Text(color.displayName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: size + 16)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onTapGesture {
            ColorPickerController.shared.copy(color)
            withAnimation(.snappy) { copied = true }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation { copied = false }
        }
        .help(color.string(ColorPickerController.shared.format))
        .accessibilityElement()
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(.isButton)
    }
}

/// "Copy as" submenu shared by every swatch context menu.
private struct CopyAsMenu: View {
    let color: SavedColor
    var body: some View {
        Menu(L("Copy as")) {
            ForEach(ColorFormat.allCases) { format in
                Button("\(format.title)  —  \(color.string(format))") {
                    ColorPickerController.shared.copy(color, as: format)
                }
            }
        }
    }
}

private let gridColumns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

// MARK: - Colors (history)

private struct ColorHistoryView: View {
    @State private var controller = ColorPickerController.shared

    var body: some View {
        if controller.history.isEmpty {
            ContentUnavailableView {
                Label(L("No colors yet"), systemImage: "eyedropper")
            } description: {
                Text(L("Pick a color anywhere on screen. It's copied and kept here."))
            } actions: {
                Button(L("Pick Color")) { controller.pick() }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                if let latest = controller.history.first { latestCard(latest) }
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(controller.history) { color in
                        Swatch(color: color)
                            .contextMenu {
                                Button(L("Copy")) { controller.copy(color) }
                                CopyAsMenu(color: color)
                                if !controller.palettes.isEmpty {
                                    Menu(L("Add to Palette")) {
                                        ForEach(controller.palettes) { p in
                                            Button(p.name) { controller.add(color, toPalette: p.id) }
                                        }
                                    }
                                }
                                Divider()
                                Button(L("Delete"), role: .destructive) { controller.removeFromHistory(color) }
                            }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(String(format: L("%lld colors"), controller.history.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Save as Palette")) { controller.newPalette(colors: controller.history) }
                    Button(L("Clear"), role: .destructive) { controller.clearHistory() }
                }
                .controlSize(.small)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func latestCard(_ color: SavedColor) -> some View {
        HStack(spacing: 16) {
            Swatch(color: color, size: 72, showLabel: false)
            VStack(alignment: .leading, spacing: 4) {
                ForEach([ColorFormat.hex, .rgb, .hsl, .cmyk], id: \.self) { f in
                    HStack {
                        Text(f.title).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Text(color.string(f)).font(.body.monospaced()).textSelection(.enabled)
                    }
                    .font(.callout)
                }
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding([.horizontal, .top], 20)
    }
}

// MARK: - Palettes

private struct PalettesView: View {
    @State private var controller = ColorPickerController.shared
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var addingTo: UUID?
    @State private var hexText = ""
    @State private var renamingColor: (color: SavedColor, palette: UUID)?

    var body: some View {
        Group {
            if controller.palettes.isEmpty {
                ContentUnavailableView {
                    Label(L("No palettes"), systemImage: "swatchpalette")
                } description: {
                    Text(L("Group colors into named palettes and export them as JSON, CSS or text."))
                } actions: {
                    Button(L("New Palette")) { controller.newPalette() }.buttonStyle(.glassProminent)
                    Button(L("Import…")) { controller.importPalette() }
                }
            } else {
                Form {
                    ForEach(controller.palettes) { palette in
                        Section { paletteBody(palette) } header: { paletteHeader(palette) }
                    }
                }
                .formStyle(.grouped)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        Button(L("Import…")) { controller.importPalette() }
                        Button(L("New Palette")) { controller.newPalette() }
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
        .alert(L("Rename Palette"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Name"), text: $renameText)
            Button(L("Rename")) { if let id = renaming { controller.renamePalette(id, to: renameText) }; renaming = nil }
            Button(L("Cancel"), role: .cancel) { renaming = nil }
        }
        .alert(L("Rename Color"), isPresented: Binding(get: { renamingColor != nil }, set: { if !$0 { renamingColor = nil } })) {
            TextField(renamingColor?.color.hex ?? L("Name"), text: $renameText)
            Button(L("Rename")) {
                if let target = renamingColor { controller.renameColor(target.color, inPalette: target.palette, to: renameText) }
                renamingColor = nil
            }
            Button(L("Cancel"), role: .cancel) { renamingColor = nil }
        }
        .alert(L("Add Color"), isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
            TextField("#3A7BFF", text: $hexText)
            Button(L("Add")) { if let id = addingTo { controller.addHex(hexText, toPalette: id) }; addingTo = nil }
            Button(L("Cancel"), role: .cancel) { addingTo = nil }
        } message: {
            Text(L("Type a HEX color."))
        }
    }

    private func paletteHeader(_ palette: ColorPalette) -> some View {
        HStack {
            Text(palette.name)
            Text(String(format: L("%lld colors"), palette.colors.count)).foregroundStyle(.tertiary)
            Spacer()
            Menu {
                Button(L("Add HEX Color…")) { hexText = ""; addingTo = palette.id }
                if let last = controller.history.first {
                    Button(String(format: L("Add Last Picked (%@)"), last.hex)) { controller.add(last, toPalette: palette.id) }
                }
                Divider()
                Button(L("Rename…")) { renameText = palette.name; renaming = palette.id }
                Menu(L("Copy as")) {
                    ForEach(PaletteExportFormat.allCases) { f in Button(f.title) { controller.copyExport(palette, as: f) } }
                }
                Menu(L("Export")) {
                    ForEach(PaletteExportFormat.allCases) { f in Button(f.title + "…") { controller.export(palette, as: f) } }
                }
                Divider()
                Button(L("Delete Palette"), role: .destructive) { controller.deletePalette(palette.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func paletteBody(_ palette: ColorPalette) -> some View {
        if palette.colors.isEmpty {
            Text(L("Empty. Add a HEX color or pick one with this palette set as the destination in Settings."))
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(palette.colors) { color in
                    Swatch(color: color)
                        .contextMenu {
                            Button(L("Copy")) { controller.copy(color) }
                            CopyAsMenu(color: color)
                            Button(L("Rename…")) { renameText = color.name ?? ""; renamingColor = (color, palette.id) }
                            Divider()
                            Button(L("Remove from Palette"), role: .destructive) { controller.remove(color, fromPalette: palette.id) }
                        }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Settings

private struct ColorSettingsView: View {
    @State private var controller = ColorPickerController.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                Picker(L("Copy format"), selection: $controller.format) {
                    ForEach(ColorFormat.allCases) { f in Text(f.title).tag(f) }
                }
                LabeledContent(L("Example")) {
                    Text(SavedColor(red: 0.227, green: 0.482, blue: 1).string(controller.format))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                Toggle(L("Copy to clipboard after picking"), isOn: $controller.copyAfterPick)
                Toggle(L("Play a sound when picking"), isOn: $controller.playSound)
                Toggle(L("Show confirmation toast"), isOn: $controller.showToast)
            } header: {
                Text(L("Picking"))
            }

            Section {
                Picker(L("Also add picked colors to"), selection: $controller.autoAddPaletteID) {
                    Text(L("History only")).tag(UUID?.none)
                    ForEach(controller.palettes) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
                Stepper(value: $controller.historyLimit, in: 10...500, step: 10) {
                    LabeledContent(L("Keep in history"), value: String(format: L("%lld colors"), controller.historyLimit))
                }
            } header: {
                Text(L("Collections"))
            }

            Section {
                ShortcutRow(title: L("Pick a color"), defaultsKey: ColorPickerController.pickShortcutKey,
                            recordingObserver: recordingObserver)
            } header: {
                Text(L("Keyboard shortcuts"))
            }
        }
        .formStyle(.grouped)
    }
}
