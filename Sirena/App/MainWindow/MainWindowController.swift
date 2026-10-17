/// MainWindowController.swift

import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case home
    case module(ModuleID)
    case general
    case about
}

@Observable
final class Router {
    var selection: SidebarItem? = .home
}

/// Asks the page being shown to switch to one of its tabs (used to reach modules
/// embedded as tabs of another page).
@MainActor
@Observable
final class PageNavigator {
    static let shared = PageNavigator()
    var requestedTab: String?
}

final class MainWindowController: NSWindowController, NSWindowDelegate {

    let router = Router()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 820, height: 560)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("SirenaMainWindow")
        window.title = "Sirena"
        self.init(window: window)

        let hosting = NSHostingController(rootView: MainView(router: router))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        // The window size is the user's; pages (some fixed-width AppKit ones) must not resize it.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.setFrameAutosaveName("SirenaMainWindow")
        window.delegate = self
    }

    var isVisible: Bool { window?.isVisible == true }

    /// Shows the window and, while it is open, the Dock icon so Sirena can be switched to like a regular app.
    func present(_ item: SidebarItem? = nil) {
        if case .module(let module)? = item, module.hostPage != module {
            router.selection = .module(module.hostPage)
            PageNavigator.shared.requestedTab = module.hostTab
        } else if let item {
            router.selection = item
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true, window?.frameAutosaveName.isEmpty == false,
           UserDefaults.standard.string(forKey: "NSWindow Frame SirenaMainWindow") == nil {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
