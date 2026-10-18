/// SirenaStatusItem.swift
///
/// Sirena's menu bar icon. A click opens the sound panel (outputs, per-app volume,
/// microphone); a right-click (or ⌃-click) opens a small menu to open or quit Sirena.
/// Features never add icons of their own. (Hiding other apps' icons has its own separate
/// icon, see MenuBarModule.)

import Cocoa

final class SirenaStatusItem: NSObject {
    static let instance = SirenaStatusItem()

    static let autosaveName = "sirena.main"

    private(set) var statusItem: NSStatusItem?
    private var isVisibleObserver: NSKeyValueObservation?

    /// The right-click menu, built fresh every time it opens.
    var menuProvider: (() -> NSMenu)?
    /// What a click shows, in a popover below the icon.
    var panelProvider: (() -> NSViewController)?
    private var popover: NSPopover?

    var button: NSStatusBarButton? { statusItem?.button }

    private override init() {}

    func refreshVisibility() {
        // Sirena lives in the menu bar: its icon is always there.
        Defaults.hideMenuBarIcon.enabled = false
        if let statusItem {
            statusItem.isVisible = true
        } else {
            create()
        }
    }

    func openMenu() {
        if statusItem == nil { create() }
        togglePanel()
    }

    private func create() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        // The orb, drawn as a template so the menu bar tints it (black or white).
        let image = NSImage(named: "TrayOrb")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Sirena"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        isVisibleObserver = item.observe(\.isVisible, options: [.old, .new]) { _, change in
            if change.oldValue == true && change.newValue == false {
                Notification.Name.menuBarIconHidden.post()
                Defaults.hideMenuBarIcon.enabled = true
            }
        }
        item.isVisible = true
        statusItem = item
    }

    private func remove() {
        isVisibleObserver = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel()
        }
    }

    func closePanel() {
        popover?.performClose(nil)
    }

    /// When the popover last closed: the click that closes it (mouse-down) must not
    /// reopen it on mouse-up.
    private var lastClose = Date.distantPast

    private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard Date().timeIntervalSince(lastClose) > 0.3 else { return }
        guard let content = panelProvider?() else { return }
        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = content
        self.popover = popover
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showMenu() {
        guard let statusItem, let menu = menuProvider?() else { return }
        // Attach the menu so macOS places it below the icon and highlights it, then
        // detach it when it closes. Sent on the next run loop pass because this runs
        // inside the button's own action, where performClick would re-enter it.
        menu.delegate = self
        statusItem.menu = menu
        DispatchQueue.main.async {
            statusItem.button?.performClick(nil)
        }
    }
}

extension SirenaStatusItem: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
    }
}

extension SirenaStatusItem: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}
