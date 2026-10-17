/// AppDelegate.swift

import ClipboardKit
import SoundKit
import MASShortcut
import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static var instance: AppDelegate {
        NSApp.delegate as! AppDelegate
    }

    let windowManagement = WindowManagementModule()
    /// Rectangle's window actions, shown as the "Windows" submenu of the Sirena menu.
    let windowsMenu = NSMenu()

    private let statusItem = SirenaStatusItem.instance
    private lazy var mainWindowController = MainWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        windowsMenu.autoenablesItems = false
        statusItem.menuProvider = { [weak self] in self?.makeSirenaMenu() ?? NSMenu() }
        statusItem.panelProvider = {
            let controller = NSHostingController(rootView: BoltMenuView { SirenaStatusItem.instance.closePanel() })
            controller.sizingOptions = [.preferredContentSize]
            return controller
        }
        SoundController.shared.start()
        statusItem.refreshVisibility()

        // A crashed run may have left macOS's ⌘ Tab turned off: give it back first.
        WindowSwitcherController.recoverSystemShortcuts()

        let modules = ModuleManager.shared
        modules.openPage = { [weak self] item in self?.mainWindowController.present(item) }
        modules.isMainWindowVisible = { [weak self] in self?.mainWindowController.isVisible ?? false }
        modules.startEnabledModules(windowManagement: windowManagement, windowsMenu: windowsMenu)

        // Debug helpers: SIRENA_OPEN_SETTINGS=1 opens the main window,
        // SIRENA_OPEN_PAGE=<module id|general|about> opens it on a page.
        let environment = ProcessInfo.processInfo.environment
        if let page = environment["SIRENA_OPEN_PAGE"] {
            let item: SidebarItem = ModuleID(rawValue: page).map { .module($0) }
                ?? (page == "general" ? .general : page == "about" ? .about : .home)
            mainWindowController.present(item)
        } else if environment["SIRENA_OPEN_SETTINGS"] == "1" {
            openMainWindow(self)
        }
        if environment["SIRENA_SHOW_MIRROR"] == "1" {
            MirrorController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SoundController.shared.stop()
        ModuleManager.shared.terminate()
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        Notification.Name.appWillBecomeActive.post()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Defaults.relaunchOpensMenu.enabled {
            statusItem.openMenu()
        } else {
            openMainWindow(sender)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // sirena://capture-text, sirena://read-code: Text Capture from Shortcuts or scripts.
        let capture = TextCaptureController.shared
        var others: [URL] = []
        for url in urls {
            switch url.host {
            case "capture-text": capture.capture(.text())
            case "capture-last": capture.captureLastSelection()
            case "read-code": capture.capture(.code)
            case "capture-translate": capture.capture(.text(translate: true))
            case "open-hidden-icon":
                let bundle = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "app" }?.value
                if let bundle { MenuBarModule.shared.openHiddenIcon(bundleID: bundle) }
            case "sound": SirenaStatusItem.instance.openMenu()
            case "hidden-icons-show": MenuBarModule.shared.expand()
            case "hidden-icons-hide": MenuBarModule.shared.collapse()
            case "shelf-toggle": ShelfController.shared.toggle()
            case "shelf-add-clipboard": ShelfActions.addFromClipboard()
            default: others.append(url)
            }
        }
        if !others.isEmpty { windowManagement.handle(urls: others) }
    }

    // MARK: - The Sirena menu

    /// Everything Sirena does, behind its single menu bar item. Built on every open so
    /// each line shows the current state (Caffeine on/off, mirror shown, …).
    /// Right-click menu of Sirena's icon. Everything else moved to the sound panel and
    /// the main window; this menu is being rebuilt from the sound panel up.
    private func makeSirenaMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(L("Open Sirena…"), symbol: "macwindow", #selector(openMainWindow), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Sirena"), symbol: nil, #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        return menu
    }


    private func header(_ module: ModuleID) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: module.title)
        }
        let header = NSMenuItem(title: module.title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return header
    }

    private func item(_ title: String, symbol: String?, _ action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if #available(macOS 27.0, *) {
                item.preferredImageVisibility = .visible
            }
        }
        return item
    }

    // MARK: - Actions






    @objc private func takeSnap() {
        MirrorController.shared.takeSnap()
    }

    @objc private func selectWindowToPin() {
        PinWindowController.shared.selectWindowToPin()
    }





    @objc private func captureLastSelection() {
        TextCaptureController.shared.captureLastSelection()
    }







    @objc private func stopSpeaking() {
        TextCaptureController.shared.stopSpeaking()
    }



    @objc func openMainWindow(_ sender: Any?) {
        mainWindowController.present()
    }

    @objc func openSettings(_ sender: Any?) {
        mainWindowController.present(.general)
    }

    @objc func showAbout(_ sender: Any?) {
        mainWindowController.present(.about)
    }

    @objc func viewLogging(_ sender: Any?) {
        Logger.showLogging(sender: sender)
    }

    @objc func authorizeAccessibility(_ sender: Any?) {
        windowManagement.requestAuthorization()
    }
}

// MARK: - Continuity Camera

/// "Import from iPhone" in the Sirena menu: macOS fills that item with the nearby
/// iPhones and iPads, and hands the photo or scan back here for Text Capture to read.
extension AppDelegate: @MainActor NSServicesMenuRequestor {
    @objc func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        guard sendType == nil, let returnType, NSImage.imageTypes.contains(returnType.rawValue),
              ModuleManager.shared.isRunning(.textCapture) || ShelfController.shared.importsToShelf else { return nil }
        return self
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        if ShelfController.shared.importsToShelf {
            ShelfController.shared.importsToShelf = false
            return ShelfStore.shared.add(from: pasteboard)
        }
        guard let image = NSImage(pasteboard: pasteboard) else { return false }
        TextCaptureController.shared.handleImportedImage(image)
        return true
    }
}
