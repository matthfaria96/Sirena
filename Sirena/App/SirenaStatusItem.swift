/// SirenaStatusItem.swift
///
/// Sirena's menu bar icon. A click opens the sound panel (outputs, per-app volume,
/// microphone); a right-click (or ⌃-click) opens a small menu to open or quit Sirena.
/// Features never add icons of their own: hiding other apps' icons lives in this menu too
/// (a button beside Settings, and an item in the right-click menu); its own arrow only shows
/// when asked for, or before macOS 27 (see MenuBarModule).

import Cocoa

final class SirenaStatusItem: NSObject {
    static let instance = SirenaStatusItem()

    static let autosaveName = "sirena.main"

    private(set) var statusItem: NSStatusItem?

    /// The right-click menu, built fresh every time it opens.
    var menuProvider: (() -> NSMenu)?
    /// What a click shows, in a popover below the icon.
    var panelProvider: (() -> NSViewController)?
    private var popover: NSPopover?
    /// Closes the panel on a click in another app (see `watchOutsideClicks`).
    private var outsideClickMonitor: Any?
    /// Closes the panel when another app comes forward without a click (⌘ Tab, the Dock…).
    private var activationObserver: NSObjectProtocol?
    /// The app that was in front when the panel opened (the panel itself activates Sirena).
    private(set) var appBeforePanel: NSRunningApplication?

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

    /// How many other apps' menu bar icons are hidden right now; nil: no badge (Ícones off).
    private var hiddenIcons: Int?

    /// Shows how many menu bar icons are hidden, as a small badge on the orb. Zero shows
    /// too, so the icon keeps its shape; nil takes the badge away.
    func setHiddenIconCount(_ count: Int?) {
        guard count != hiddenIcons else { return }
        hiddenIcons = count
        statusItem?.button?.image = Self.orb(badge: count)
        statusItem?.button?.toolTip = count.map { L("Sirena — \($0) menu bar icons hidden") } ?? "Sirena"
    }

    /// The orb, drawn as a template so the menu bar tints it (black or white). With hidden
    /// icons, their number sits on its lower right corner in a small pill, cut out of the orb
    /// with a thin gap, its digits cut out of the pill: one colour, like the system's icons.
    private static func orb(badge: Int?) -> NSImage? {
        guard let source = NSImage(named: "TrayOrb") else { return nil }
        let side: CGFloat = 18
        guard let badge else {
            let image = source.copy() as? NSImage
            image?.size = NSSize(width: side, height: side)
            image?.isTemplate = true
            return image
        }
        let text = badge > 99 ? "99+" : "\(badge)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
        let textSize = text.size(withAttributes: [.font: font])
        let pillHeight: CGFloat = 10
        let pillWidth = max(pillHeight, (textSize.width + 5).rounded())
        let width = max(side, side - 5 + pillWidth)
        let image = NSImage(size: NSSize(width: width, height: side), flipped: false) { _ in
            source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            let pill = NSRect(x: width - pillWidth, y: 0, width: pillWidth, height: pillHeight)
            let context = NSGraphicsContext.current
            context?.compositingOperation = .destinationOut
            let gap = pill.insetBy(dx: -1.5, dy: -1.5)
            NSBezierPath(roundedRect: gap, xRadius: gap.height / 2, yRadius: gap.height / 2).fill()
            context?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            context?.compositingOperation = .destinationOut
            text.draw(at: NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2 + 0.25),
                      withAttributes: [.font: font, .foregroundColor: NSColor.black])
            context?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }

    private func create() {
        // Variable: the orb grows a little when it carries the hidden icons' count.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        item.button?.image = Self.orb(badge: hiddenIcons)
        item.button?.toolTip = "Sirena"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.isVisible = true
        statusItem = item
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
        // Opening the panel brings Sirena forward: remember who was in front, to paste there.
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            appBeforePanel = front
        }
        MainActor.assumeIsolated { SirenaActivation.activateForTool() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        watchOutsideClicks()
    }

    /// A transient popover only closes when Sirena loses focus, and opening it doesn't always
    /// bring Sirena forward (activation is cooperative since macOS 14): until something in the
    /// panel was clicked, a click in another app left it open. A global monitor sees clicks in
    /// other apps only (no Accessibility needed, no event tap), so Sirena's own windows — the
    /// drawing canvas, the history, a menu opened from the panel — never close it.
    private func watchOutsideClicks() {
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let self, let app, app != .current, let popover = self.popover, popover.isShown else { return }
                popover.performClose(nil)
            }
        }
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            popover.performClose(nil)
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
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
        stopWatchingOutsideClicks()
        // Let the menu's views go: the mixer would otherwise keep re-rendering offscreen.
        popover?.contentViewController = nil
    }
}

extension SirenaStatusItem: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}
