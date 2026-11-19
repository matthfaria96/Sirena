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
    /// False while the window is closed: the pages (and their timers) are torn down.
    var isWindowOpen = true
}

/// Asks the page being shown to switch to one of its tabs (used to reach modules
/// embedded as tabs of another page).
@MainActor
@Observable
final class PageNavigator {
    static let shared = PageNavigator()
    var requestedTab: String?
}

/// Brings Sirena forward for a tool (the ⚡ menu, an overlay, an alert) without the main
/// window. Activating an app raises all its windows, so a main window left open behind other
/// apps popped up on every Pin Window or Text Capture; it only shows when asked for
/// (Configurações, ⌃⌥S, "Open Sirena…").
@MainActor
enum SirenaActivation {
    static var closeIdleMainWindow: () -> Void = {}

    static func activateForTool() {
        closeIdleMainWindow()
        NSApp.activate()
    }
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
        router.isWindowOpen = true
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closes the window unless the user is working in it right now.
    func closeIfIdle() {
        guard let window, window.isVisible else { return }
        if NSApp.isActive, window.isKeyWindow { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        router.isWindowOpen = false
        // An update window still up keeps the Dock icon; Sparkle's session end hides it.
        guard !AppUpdater.shared.isShowingUpdate else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
