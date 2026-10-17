/// FinderSync.swift
///
/// Sirena's only addition to the Finder: "Copiar Caminho" in the right-click menu of
/// files and folders. Turned on or off from Sirena (Melhorias › Finder).

import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Everywhere: every folder of every volume.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
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
