/// FinderSync.swift
///
/// Sirena's additions to the Finder: "Copiar Caminho" in the right-click menu of files and
/// folders, and a toolbar button (added through View › Customize Toolbar) whose menu opens
/// Sirena's address bar over the window (the same bar as ⌘L) or copies the folder's path.
/// Turned on or off from Sirena (Melhorias › Finder).

import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Everywhere: every folder of every volume.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: Toolbar button

    override var toolbarItemName: String { "Sirena" }
    override var toolbarItemToolTip: String { "Editar o caminho desta janela (⌘L)" }
    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "point.topleft.down.to.point.bottomright.curvepath",
                            accessibilityDescription: "Caminho") ?? NSImage()
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        if menuKind == .toolbarItemMenu {
            let edit = NSMenuItem(title: "Editar Caminho…", action: #selector(editPath(_:)), keyEquivalent: "l")
            edit.keyEquivalentModifierMask = .command
            edit.image = Self.menuIcon("character.cursor.ibeam")
            menu.addItem(edit)
            let copy = NSMenuItem(title: "Copiar Caminho desta Pasta", action: #selector(copyPath(_:)), keyEquivalent: "")
            copy.image = Self.menuIcon("square.and.arrow.up")
            menu.addItem(copy)
            return menu
        }
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return menu }
        let item = NSMenuItem(title: "Copiar Caminho", action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = Self.menuIcon("square.and.arrow.up")
        menu.addItem(item)
        return menu
    }

    /// Finder draws extension icons as given (it doesn't tint template images), so the
    /// symbol is drawn in the menu's text color for the current appearance: white in Dark
    /// Mode, black in Light Mode, at the size and weight of the Finder's own icons.
    private static func menuIcon(_ symbol: String) -> NSImage? {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            || UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let color: NSColor = dark ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0, alpha: 0.85)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copiar Caminho")?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = false
        return image
    }

    /// Sirena lays its address bar over the front Finder window (without coming forward).
    @objc func editPath(_ sender: AnyObject?) {
        guard let url = URL(string: "sirena://finder-address") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    /// Copies the selected items' paths (one per line), or the open folder's.
    @objc func copyPath(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let folder = controller.targetedURL() { urls = [folder] }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
}
