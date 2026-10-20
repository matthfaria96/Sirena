/// ShelfActions.swift
///
/// Everything you can do with shelf items, and the menus that offer it.

import AppKit
import UniformTypeIdentifiers

@MainActor
enum ShelfActions {
    private static var store: ShelfStore { .shared }

    // MARK: - Pasteboard

    /// What a drag or copy of the item carries.
    static func pasteboardWriters(for item: ShelfItem) -> [NSPasteboardWriting] {
        switch item.content {
        case .files: return item.urls.map { $0 as NSURL }
        case .text(let text): return [text as NSString]
        case .link(let url): return [url as NSURL]
        case .color: return [item.nsColor].compactMap { $0 }
        }
    }

    static func copy(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.flatMap(pasteboardWriters))
    }

    static func copyPaths(_ items: [ShelfItem]) {
        let paths = items.flatMap(\.urls).map(\.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    static func copyColor(_ item: ShelfItem, format: String) {
        guard let color = item.nsColor, let hex = item.hexColor else { return }
        let value: String
        switch format {
        case "RGB":
            value = "rgb(\(Int(color.redComponent * 255)), \(Int(color.greenComponent * 255)), \(Int(color.blueComponent * 255)))"
        case "HSL":
            value = "hsl(\(Int(color.hueComponent * 360)), \(Int(color.saturationComponent * 100))%, \(Int(color.brightnessComponent * 100))%)"
        default:
            value = hex
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// Puts whatever is on the clipboard on the shelf.
    static func addFromClipboard() {
        if !store.add(from: .general) { NSSound.beep() }
        ShelfController.shared.show()
    }

    // MARK: - Opening

    static func open(_ items: [ShelfItem]) {
        for item in items {
            switch item.content {
            case .files: item.urls.forEach { NSWorkspace.shared.open($0) }
            case .link(let url): NSWorkspace.shared.open(url)
            case .text, .color: copy([item])
            }
        }
    }

    static func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func showInFinder(_ items: [ShelfItem]) {
        let urls = items.flatMap(\.urls)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    // MARK: - Files

    static func copyFiles(_ items: [ShelfItem], move: Bool) {
        let urls = items.flatMap(\.urls)
        guard !urls.isEmpty, let folder = chooseFolder(prompt: move ? L("Move") : L("Copy")) else { return }
        for url in urls {
            let destination = uniqueURL(folder.appendingPathComponent(url.lastPathComponent))
            do {
                if move {
                    try FileManager.default.moveItem(at: url, to: destination)
                    store.replaceURL(url, with: destination)
                } else {
                    try FileManager.default.copyItem(at: url, to: destination)
                }
            } catch {
                present(error)
            }
        }
    }

    static func rename(_ item: ShelfItem) {
        guard item.urls.count == 1, let url = item.urls.first else { return }
        let alert = NSAlert()
        alert.messageText = L("Rename")
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        SirenaActivation.activateForTool()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            store.replaceURL(url, with: destination)
            ShelfThumbnails.shared.clear()
        } catch {
            present(error)
        }
    }

    private static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        SirenaActivation.activateForTool()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var number = 2
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            number += 1
        }
        return candidate
    }

    private static func present(_ error: Error) {
        let alert = NSAlert(error: error)
        SirenaActivation.activateForTool()
        alert.runModal()
    }

    // MARK: - Sharing

    private static func shareItems(_ items: [ShelfItem]) -> [Any] {
        items.flatMap { item -> [Any] in
            switch item.content {
            case .files: return item.urls
            case .text(let text): return [text]
            case .link(let url): return [url]
            case .color: return [item.hexColor ?? ""]
            }
        }
    }

    static func shareMenu(for items: [ShelfItem]) -> NSMenu {
        let menu = NSMenu()
        let shared = shareItems(items)
        for service in NSSharingService.sharingServices(forItems: shared) {
            let entry = PinMenuItem(service.title, image: service.image) { service.perform(withItems: shared) }
            menu.addItem(entry)
        }
        return menu
    }

    static func mail(_ items: [ShelfItem]) {
        NSSharingService(named: .composeEmail)?.perform(withItems: shareItems(items))
    }

    // MARK: - Menus

    /// Right-click menu for the selected items.
    static func itemMenu(for items: [ShelfItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let ids = Set(items.map(\.id))
        let urls = items.flatMap(\.urls)
        let single = items.count == 1 ? items.first : nil

        menu.addItem(PinMenuItem(L("Quick Look"), symbol: "eye") {
            (ShelfController.shared.panel.contentView as? ShelfContentView)?.toggleQuickLook()
        })
        menu.addItem(PinMenuItem(L("Open"), symbol: "arrow.up.forward.app") { open(items) })
        if let first = urls.first {
            let openWith = PinMenuItem(L("Open With"), symbol: "app.badge") {}
            let apps = NSMenu()
            for app in NSWorkspace.shared.urlsForApplications(toOpen: first).prefix(15) {
                let name = FileManager.default.displayName(atPath: app.path)
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icon.size = NSSize(width: 16, height: 16)
                apps.addItem(PinMenuItem(name, image: icon) { open(urls, with: app) })
            }
            openWith.submenu = apps
            menu.addItem(openWith)
            menu.addItem(PinMenuItem(L("Show in Finder"), symbol: "folder") { showInFinder(items) })
        }
        menu.addItem(.separator())

        menu.addItem(PinMenuItem(L("Copy"), symbol: "doc.on.doc") { copy(items) })
        if !urls.isEmpty {
            menu.addItem(PinMenuItem(L("Copy all Filepaths"), symbol: "text.page") { copyPaths(items) })
            menu.addItem(PinMenuItem(L("Copy to…"), symbol: "folder.badge.plus") { copyFiles(items, move: false) })
            menu.addItem(PinMenuItem(L("Move to…"), symbol: "folder") { copyFiles(items, move: true) })
            if let single, single.urls.count == 1 {
                menu.addItem(PinMenuItem(L("Rename…"), symbol: "pencil") { rename(single) })
            }
        }
        if let single, single.nsColor != nil {
            let values = PinMenuItem(L("Copy Color Values"), symbol: "eyedropper") {}
            let formats = NSMenu()
            for format in ["HEX", "RGB", "HSL"] {
                formats.addItem(PinMenuItem(format) { copyColor(single, format: format) })
            }
            values.submenu = formats
            menu.addItem(values)
        }
        menu.addItem(.separator())

        let share = PinMenuItem(L("Share"), symbol: "square.and.arrow.up") {}
        share.submenu = shareMenu(for: items)
        menu.addItem(share)
        menu.addItem(PinMenuItem(L("Mail…"), symbol: "envelope") { mail(items) })
        menu.addItem(.separator())

        let locked = items.allSatisfy(\.isLocked)
        menu.addItem(PinMenuItem(locked ? L("Unlock") : L("Lock"), symbol: locked ? "lock.open" : "lock") {
            store.toggleLock(ids)
        })
        if let single, single.isStack {
            menu.addItem(PinMenuItem(L("Split up Stack"), symbol: "square.stack.3d.down.right") { store.split(single.id) })
        }
        if items.filter({ !$0.urls.isEmpty }).count > 1 {
            menu.addItem(PinMenuItem(L("Merge Selected Items to a Stack"), symbol: "square.stack.3d.up") { store.mergeToStack(ids) })
        }
        menu.addItem(.separator())
        menu.addItem(PinMenuItem(L("Remove from Shelf"), symbol: "xmark") { store.remove(ids) })
        return menu
    }

    /// The shelf's own menu ("…" in its header, and the Sirena menu).
    static func shelfMenu(includeShowHide: Bool = false, inSirenaMenu: Bool = false) -> NSMenu {
        // In the Sirena menu, "Import from iPhone" belongs to Text Capture only.
        let offersImport = !includeShowHide && !inSirenaMenu
        let menu = NSMenu()
        menu.autoenablesItems = false
        if includeShowHide {
            let controller = ShelfController.shared
            menu.addItem(PinMenuItem(controller.isVisible ? L("Hide Shelf") : L("Show Shelf"), symbol: "tray") {
                controller.toggle()
            })
            menu.addItem(.separator())
        }
        menu.addItem(PinMenuItem(L("Add from Clipboard"), symbol: "doc.on.clipboard") { addFromClipboard() })
        if offersImport {
            let importItem = NSMenuItem(title: L("Add Photo from iPhone…"), action: nil, keyEquivalent: "")
            importItem.identifier = NSMenuItem.importFromDeviceIdentifier
            menu.addItem(importItem)
        }
        menu.addItem(.separator())

        let merge = PinMenuItem(L("Merge all Items to a Stack"), symbol: "square.stack.3d.up") { store.mergeAllToStack() }
        merge.isEnabled = store.items.filter { !$0.urls.isEmpty }.count > 1
        menu.addItem(merge)
        let restore = PinMenuItem(L("Restore Last Removed Files"), symbol: "arrow.uturn.backward") { store.restoreLastRemoved() }
        restore.isEnabled = store.canRestore
        menu.addItem(restore)
        menu.addItem(.separator())

        let removeAll = PinMenuItem(L("Remove All Files"), symbol: "trash") { store.removeAll() }
        removeAll.isEnabled = !store.items.isEmpty
        menu.addItem(removeAll)
        if store.items.contains(where: \.isLocked) {
            menu.addItem(PinMenuItem(L("Also Remove Locked Files"), symbol: "lock.slash") { store.removeAll(includingLocked: true) })
        }
        if !includeShowHide && !inSirenaMenu {
            menu.addItem(.separator())
            menu.addItem(PinMenuItem(L("Settings…"), symbol: "gearshape") { ShelfController.shared.openSettings() })
        }
        return menu
    }
}
