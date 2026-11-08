/// Showcase.swift
///
/// SIRENA_SHOWCASE=1: screenshots for witchmymac.com, taken from a renamed copy (see CLAUDE.md).
/// Nothing is started: no module, event tap, mixer, updater, menu bar icon or onboarding, and no
/// permission is ever asked. Pages show the permissions as granted, so they read like a Mac that
/// went through onboarding, and the clipboard history gets fictional entries.
/// - SIRENA_OPEN_PAGE=<module id|general|about|home> (and SIRENA_OPEN_TAB) picks the page.
/// - SIRENA_SHOW_PANEL=1 shows the menu bar panel in a popover instead of the window;
///   SIRENA_PANEL_INLINE=clipboard|pomodoro|screenCapture opens one of its inline panels.
/// - SIRENA_SHOWCASE_SCREEN=left puts everything on the leftmost display.

import AppKit
import ClipboardKit
import SwiftUI

@MainActor
enum Showcase {
    nonisolated static let isActive = ProcessInfo.processInfo.environment["SIRENA_SHOWCASE"] == "1"

    /// Permission state as the pages show it.
    nonisolated static func accessibilityShown() -> Bool { isActive || AXIsProcessTrusted() }
    nonisolated static func screenRecordingShown() -> Bool { isActive || CGPreflightScreenCaptureAccess() }

    private static var anchor: NSWindow?
    private static var popover: NSPopover?

    static func start(mainWindow: MainWindowController) {
        let environment = ProcessInfo.processInfo.environment
        Task {
            await ClipboardController.shared.loadShowcaseHistory(demoClipboard, images: [(demoImage(), "com.apple.Preview", 4)])
            if environment["SIRENA_SHOW_PANEL"] == "1" {
                showPanel(inline: environment["SIRENA_PANEL_INLINE"].flatMap(BoltMenuItem.init(rawValue:)))
            } else {
                let page = environment["SIRENA_OPEN_PAGE"] ?? "home"
                let item: SidebarItem = ModuleID(rawValue: page).map { .module($0) }
                    ?? (page == "general" ? .general : page == "about" ? .about : .home)
                mainWindow.present(item)
                if let window = mainWindow.window, let screen { center(window, on: screen) }
            }
        }
    }

    /// The leftmost display when asked for, else the main one.
    private static var screen: NSScreen? {
        guard ProcessInfo.processInfo.environment["SIRENA_SHOWCASE_SCREEN"] == "left" else { return NSScreen.main }
        return NSScreen.screens.min { $0.frame.minX < $1.frame.minX }
    }

    private static func center(_ window: NSWindow, on screen: NSScreen) {
        let area = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
    }

    /// The panel of Sirena's menu bar icon, hanging from an invisible anchor near the top of the screen.
    private static func showPanel(inline: BoltMenuItem?) {
        guard let screen else { return }
        BoltMenuSettings.shared.openInline = inline
        let area = screen.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: area.midX, y: area.maxY - 4, width: 2, height: 2),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        anchor = window

        let controller = NSHostingController(rootView: BoltMenuView {})
        controller.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = controller
        if let view = window.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        self.popover = popover
    }

    /// A made-up picture for the clipboard history: a soft gradient with a few shapes.
    private static func demoImage() -> Data {
        let size = NSSize(width: 640, height: 400)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1),
                                NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1)])?
                .draw(in: rect, angle: -35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 70, y: 210, width: 120, height: 120)).fill()
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: 240, y: 90, width: 330, height: 60), xRadius: 30, yRadius: 30).fill()
            NSBezierPath(roundedRect: NSRect(x: 240, y: 180, width: 250, height: 36), xRadius: 18, yRadius: 18).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }

    /// Fictional copies: (text, source app bundle id, minutes ago, pinned).
    private static let demoClipboard: [(text: String, app: String, minutesAgo: Double, pinned: Bool)] = [
        ("Meeting notes: launch review moved to Thursday, 3 PM", "com.apple.Notes", 2, false),
        ("https://example.com/design/brand-guide", "com.apple.Safari", 6, false),
        ("#8B5CF6", "com.apple.TextEdit", 11, false),
        ("brew install --cask sirena-demo", "com.apple.Terminal", 18, false),
        ("Thanks for the update! I'll send the final mockups by Friday.", "com.apple.mail", 27, false),
        ("1600 Example Avenue, Springfield", "com.apple.Notes", 45, false),
        ("func greet(_ name: String) -> String {\n    let greeting = \"Hello, \\(name)\"\n    return greeting\n}", "com.apple.dt.Xcode", 63, false),
        ("Quarterly report – final.pdf", "com.apple.finder", 90, false),
        ("hello@example.com", "com.apple.mail", 240, true)
    ]
}
