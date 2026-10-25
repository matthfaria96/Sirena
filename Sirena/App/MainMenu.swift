/// MainMenu.swift
///
/// Sirena is a menu bar app, but its windows still need a main menu so standard
/// key equivalents (copy, paste, close, …) work in text fields and the settings window.

import Cocoa

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("About Sirena"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        let updates = appMenu.addItem(withTitle: L("Check for Updates…"), action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = AppUpdater.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Settings…"), action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide Sirena"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("Quit Sirena"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, title: "Sirena", to: mainMenu)

        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, title: editMenu.title, to: mainMenu)

        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(windowMenu, title: windowMenu.title, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
