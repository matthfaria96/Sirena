/// ColorPickerController.swift
///
/// Color Picker: pick any color on screen with the system magnifier (no Screen Recording
/// needed), copy it in the preferred format, keep a history and named palettes.

import AppKit
import Carbon.HIToolbox
import MASShortcut
import SwiftUI

@MainActor
@Observable
final class ColorPickerController {
    static let shared = ColorPickerController()

    static let pickShortcutKey = "colorPickerShortcutPick"
    private static let historyFile = "history.json"
    private static let palettesFile = "palettes.json"

    private(set) var isRunning = false
    private(set) var isPicking = false
    private(set) var history: [SavedColor] = []
    private(set) var palettes: [ColorPalette] = []
    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private var sampler: NSColorSampler?

    // MARK: Settings (UserDefaults, `colorPicker.` prefix)

    var format: ColorFormat {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: "colorPicker.format") }
    }
    var copyAfterPick: Bool {
        didSet { UserDefaults.standard.set(copyAfterPick, forKey: "colorPicker.copyAfterPick") }
    }
    var playSound: Bool {
        didSet { UserDefaults.standard.set(playSound, forKey: "colorPicker.playSound") }
    }
    var showToast: Bool {
        didSet { UserDefaults.standard.set(showToast, forKey: "colorPicker.showToast") }
    }
    var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "colorPicker.historyLimit"); trimHistory(); saveHistory() }
    }
    /// Palette that receives every picked color (nil = history only).
    var autoAddPaletteID: UUID? {
        didSet { UserDefaults.standard.set(autoAddPaletteID?.uuidString, forKey: "colorPicker.autoAddPalette") }
    }

    private init() {
        let d = UserDefaults.standard
        format = d.string(forKey: "colorPicker.format").flatMap(ColorFormat.init(rawValue:)) ?? .hex
        copyAfterPick = d.object(forKey: "colorPicker.copyAfterPick") as? Bool ?? true
        showToast = d.object(forKey: "colorPicker.showToast") as? Bool ?? true
        playSound = d.object(forKey: "colorPicker.playSound") as? Bool ?? true
        historyLimit = d.object(forKey: "colorPicker.historyLimit") as? Int ?? 60
        autoAddPaletteID = d.string(forKey: "colorPicker.autoAddPalette").flatMap(UUID.init(uuidString:))
        history = ColorStore.load([SavedColor].self, file: Self.historyFile) ?? []
        palettes = ColorStore.load([ColorPalette].self, file: Self.palettesFile) ?? []
    }

    // MARK: Module lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.registerDefaultShortcuts([
            Self.pickShortcutKey: MASShortcut(keyCode: kVK_ANSI_C, modifierFlags: [.control, .option, .command])
        ])
        binder?.bindShortcut(withDefaultsKey: Self.pickShortcutKey) { [weak self] in self?.pick() }
    }

    func terminate() {
        guard isRunning else { return }
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.pickShortcutKey)
        isRunning = false
    }

    var isActive: Bool { isPicking }

    var statusText: String {
        if isPicking { return L("Picking a color…") }
        if let last = history.first { return String(format: L("Last: %@"), last.hex) }
        if let shortcut = pickShortcutDescription { return String(format: L("Ready — %@ to pick"), shortcut) }
        return L("Ready")
    }

    /// The recorded shortcut as text (e.g. "⌃⌥⌘C"), nil when none is set.
    var pickShortcutDescription: String? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.pickShortcutKey),
              let shortcut = MASDictionaryTransformer().transformedValue(dict) as? MASShortcut else { return nil }
        return shortcut.modifierFlagsString + (shortcut.keyCodeString ?? "")
    }

    func quickAction() { pick() }

    // MARK: Picking

    func pick() {
        guard isRunning, !isPicking else { return }
        isPicking = true
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { picked in
            let saved = picked.flatMap(SavedColor.init(nsColor:))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPicking = false
                self.sampler = nil
                if let saved { self.didPick(saved) }
            }
        }
    }

    private func didPick(_ color: SavedColor) {
        // A short click-like confirmation, like the system eyedropper.
        if playSound { NSSound(named: "Tink")?.play() }
        addToHistory(color)
        if let id = autoAddPaletteID, palettes.contains(where: { $0.id == id }) {
            add(color, toPalette: id)
        }
        if copyAfterPick { copy(color, as: format, toast: false) }
        if showToast {
            CaptureToast.shared.show(title: copyAfterPick ? L("Color copied") : L("Color picked"),
                                     detail: color.string(format), symbol: "eyedropper.halffull")
        }
    }

    // MARK: Clipboard

    func copy(_ color: SavedColor, as format: ColorFormat? = nil, toast: Bool = true) {
        let text = color.string(format ?? self.format)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if toast && showToast {
            CaptureToast.shared.show(title: L("Color copied"), detail: text, symbol: "doc.on.doc")
        }
    }

    // MARK: History

    func addToHistory(_ color: SavedColor) {
        history.removeAll { $0.hex == color.hex && $0.alpha == color.alpha }
        history.insert(color, at: 0)
        trimHistory()
        saveHistory()
    }

    func removeFromHistory(_ color: SavedColor) {
        history.removeAll { $0.id == color.id }
        saveHistory()
    }

    func clearHistory() { history.removeAll(); saveHistory() }

    private func trimHistory() {
        if history.count > max(historyLimit, 1) { history = Array(history.prefix(max(historyLimit, 1))) }
    }

    private func saveHistory() { ColorStore.save(history, file: Self.historyFile) }

    // MARK: Palettes

    @discardableResult
    func newPalette(named name: String? = nil, colors: [SavedColor] = []) -> ColorPalette {
        let palette = ColorPalette(name: name ?? String(format: L("Palette %lld"), palettes.count + 1),
                                   colors: colors.map { var c = $0; c.id = UUID(); return c })
        palettes.append(palette)
        savePalettes()
        return palette
    }

    func renamePalette(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = palettes.firstIndex(where: { $0.id == id }) else { return }
        palettes[i].name = trimmed
        savePalettes()
    }

    func deletePalette(_ id: UUID) {
        palettes.removeAll { $0.id == id }
        if autoAddPaletteID == id { autoAddPaletteID = nil }
        savePalettes()
    }

    func add(_ color: SavedColor, toPalette id: UUID) {
        guard let i = palettes.firstIndex(where: { $0.id == id }) else { return }
        guard !palettes[i].colors.contains(where: { $0.hex == color.hex && $0.alpha == color.alpha }) else { return }
        var copy = color
        copy.id = UUID()
        palettes[i].colors.append(copy)
        savePalettes()
    }

    func remove(_ color: SavedColor, fromPalette id: UUID) {
        guard let i = palettes.firstIndex(where: { $0.id == id }) else { return }
        palettes[i].colors.removeAll { $0.id == color.id }
        savePalettes()
    }

    func renameColor(_ color: SavedColor, inPalette id: UUID, to name: String) {
        guard let i = palettes.firstIndex(where: { $0.id == id }),
              let j = palettes[i].colors.firstIndex(where: { $0.id == color.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        palettes[i].colors[j].name = trimmed.isEmpty ? nil : trimmed
        savePalettes()
    }

    /// Adds a color typed as HEX to a palette; returns false when it can't be parsed.
    @discardableResult
    func addHex(_ hex: String, toPalette id: UUID) -> Bool {
        guard let color = SavedColor(hex: hex) else { return false }
        add(color, toPalette: id)
        return true
    }

    func export(_ palette: ColorPalette, as format: PaletteExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(palette.name).\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try format.render(palette).write(to: url, atomically: true, encoding: .utf8)
            CaptureToast.shared.show(title: L("Palette exported"), detail: url.lastPathComponent, symbol: "square.and.arrow.up")
        } catch {
            showError(L("Couldn't export the palette"), error.localizedDescription)
        }
    }

    func copyExport(_ palette: ColorPalette, as format: PaletteExportFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(format.render(palette), forType: .string)
        if showToast { CaptureToast.shared.show(title: L("Palette copied"), detail: palette.name, symbol: "swatchpalette") }
    }

    /// Imports a JSON palette exported by Sirena or a text file with one HEX per line.
    func importPalette() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { showError(L("Couldn't import the palette"), error.localizedDescription); return }
        let name = url.deletingPathExtension().lastPathComponent
        struct Item: Decodable { let name: String?; let hex: String; let alpha: Double? }
        struct In: Decodable { let name: String?; let colors: [Item] }
        if let data = text.data(using: .utf8), let parsed = try? JSONDecoder().decode(In.self, from: data) {
            let colors = parsed.colors.compactMap { item -> SavedColor? in
                guard var c = SavedColor(hex: item.hex) else { return nil }
                if let a = item.alpha { c.alpha = a }
                c.name = item.name == item.hex ? nil : item.name
                return c
            }
            newPalette(named: parsed.name ?? name, colors: colors)
        } else {
            let colors = text.components(separatedBy: .newlines).compactMap { SavedColor(hex: $0) }
            guard !colors.isEmpty else {
                showError(L("Couldn't import the palette"), L("The file has no HEX colors."))
                return
            }
            newPalette(named: name, colors: colors)
        }
    }

    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func savePalettes() { ColorStore.save(palettes, file: Self.palettesFile) }
}
