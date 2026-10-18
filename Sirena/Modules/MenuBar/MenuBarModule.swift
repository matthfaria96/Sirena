/// MenuBarModule.swift
///
/// Hides the menu bar icons of the apps you choose. Its own icon sits at the far left
/// of the app icons: click it to bring the hidden icons back, click again to hide them.
/// Which apps are hidden is picked from a list in Sirena's settings — no ⌘-dragging.
///
/// Hiding uses macOS 27's menu bar visibility restriction through Hidden Bar's native
/// bridge (MIT, © Dwarves Foundation). Sirena itself is never hidden.

import AppKit
import MASShortcut

/// How Sirena's arrow reveals the hidden icons.
enum HiddenIconsStyle: String, CaseIterable, Identifiable {
    /// The icons come back into the menu bar, next to the arrow.
    case expand
    /// A small menu below the arrow lists them; the menu bar stays tidy.
    case menu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expand: return L("Expand beside the arrow")
        case .menu: return L("Show a menu with the icons")
        }
    }
}

@MainActor
@Observable
final class MenuBarModule: NSObject {
    static let shared = MenuBarModule()

    static let autosaveName = "sirena.hider"
    private static let hiddenAppsKey = "hiddenBar.hiddenApps"
    private static let styleKey = "hiddenBar.revealStyle"

    var style: HiddenIconsStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey)
            guard isRunning else { return }
            panel.close()
            // In menu mode the icons always stay tucked away.
            if style == .menu && !isCollapsed && !hiddenApps.isEmpty { collapse() } else { updateIcon() }
        }
    }

    private(set) var isRunning = false
    private(set) var isCollapsed = false

    /// Bundle identifiers of the apps whose icons get hidden.
    var hiddenApps: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenApps).sorted(), forKey: Self.hiddenAppsKey)
            // Apply the new choice right away: hide what was just picked, show what was
            // just removed (collapse() releases everything when nothing is left to hide).
            guard isRunning else { return }
            collapse()
            keepArrowLast()
        }
    }

    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private let visibility: NativeVisibilityProviding = NativeVisibilityBridge()
    @ObservationIgnored private let inventory = AccessibilityMenuBarInventory()
    @ObservationIgnored private var assertion: NativeVisibilityAssertion?
    @ObservationIgnored private var autoHideTimer: Timer?
    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private let panel = HiddenIconsPanel()
    @ObservationIgnored private var revealWatcher: Timer?

    var isAvailable: Bool { visibility.isAvailable }

    /// On macOS 27 the restriction only recognises Sirena's own icons when the app runs
    /// from /Applications; anywhere else it hides them too.
    static var needsApplicationsFolder: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            && !Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static let defaultPreferenceValues: [String: Any] = [
        UserDefaults.Key.isAutoHide: true,
        UserDefaults.Key.numberOfSecondForAutoHide: 10.0
    ]

    private override init() {
        hiddenApps = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenAppsKey) ?? [])
        style = HiddenIconsStyle(rawValue: UserDefaults.standard.string(forKey: Self.styleKey) ?? "") ?? .expand
        super.init()
    }

    // MARK: - Lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        UserDefaults.standard.register(defaults: Self.defaultPreferenceValues)
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)

        arrangeMenuBar { [weak self] _ in
            self?.createItem()
            // Like Hidden Bar, start with the chosen icons tucked away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.collapse() }
        }
        applyGlobalKey()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appsChanged),
                                                          name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    }

    func terminate() {
        panel.close()
        revealWatcher?.invalidate()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        release()
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.shortcutKey)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        isRunning = false
    }

    // MARK: - Hide / show

    func toggle() {
        if style == .menu {
            togglePanel()
        } else {
            isCollapsed ? expand() : collapse()
        }
    }

    /// Hides the chosen apps' icons.
    func collapse() {
        autoHideTimer?.invalidate()
        guard visibility.isAvailable else { return setCollapsed(false) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let toHide = hiddenApps.intersection(running)
        guard !toHide.isEmpty else {
            release()
            return setCollapsed(false)
        }
        // Allowed: every owner of a menu bar icon except the ones chosen to hide — running
        // apps, plus the owners macOS remembers icons for (helpers like Setapp's agent
        // aren't "running applications", and leaving them out hid them by mistake).
        let remembered = Set(Self.menuBarPositions().keys.compactMap(Self.owner(ofPositionKey:)))
        var allowed = running.union(remembered).subtracting(hiddenApps)
        if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
        visibility.activate(allowedSystemItems: Array(0..<64), allowedBundleIdentifiers: Array(allowed)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let newAssertion):
                // Activate the new restriction before dropping the old one: no flash.
                let old = self.assertion
                self.assertion = newAssertion
                old?.invalidate()
                self.setCollapsed(true)
            case .failure(let error):
                NSLog("Sirena menu bar: hiding failed: \(error.localizedDescription)")
                self.release()
                self.setCollapsed(false)
            }
        }
    }

    /// Brings every icon back.
    func expand() {
        // Hidden icons come back after the arrow, not in between the other apps.
        arrangeMenuBar { _ in }
        release()
        setCollapsed(false)
        scheduleAutoHide()
    }

    private func release() {
        assertion?.invalidate()
        assertion = nil
    }

    private func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        updateIcon()
    }

    /// An app launched while hidden is shown, unless it is on the list: re-apply.
    @objc private func appsChanged() {
        if isCollapsed { collapse() }
        // A launched app adds its icon a moment later: keep the arrow last.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.keepArrowLast() }
    }

    /// Puts the arrow back at the end (and the hidden icons beyond it) when the layout
    /// changed, re-creating the arrow only if it has to move.
    func keepArrowLast() {
        guard isRunning else { return }
        arrangeMenuBar { [weak self] arrowMoved in
            guard let self, arrowMoved else { return }
            self.recreateItem()
        }
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard Preferences.isAutoHide, style == .expand else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isCollapsed else { return }
                // Not while the pointer is in the menu bar (the user is using an icon).
                if Self.isMouseInMenuBar { self.scheduleAutoHide() } else { self.collapse() }
            }
        }
    }

    private static var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // MARK: - Shortcut

    /// No dots: MASShortcut reaches it through a key path.
    static let shortcutKey = "hiddenIconsShortcutToggle"

    /// Same shortcut recorder as every other feature (MASShortcut); a shortcut set with
    /// Hidden Bar's old recorder is carried over once.
    func applyGlobalKey() {
        if let old = Preferences.globalKey {
            var modifiers: NSEvent.ModifierFlags = []
            if old.command { modifiers.insert(.command) }
            if old.option { modifiers.insert(.option) }
            if old.control { modifiers.insert(.control) }
            if old.shift { modifiers.insert(.shift) }
            migrateShortcut(to: Self.shortcutKey, keyCode: Int(old.keyCode), modifiers: modifiers)
            UserDefaults.standard.removeObject(forKey: UserDefaults.Key.globalKey)
        }
        MASShortcutBinder.shared()?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: Self.shortcutKey) { [weak self] in self?.toggle() }
    }

    // MARK: - Apps with menu bar icons (for the settings list)

    struct MenuBarApp: Identifiable, Hashable {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
        var id: String { bundleIdentifier }
    }

    /// Apps that currently have menu bar icons, plus the ones already chosen.
    func menuBarApps(_ completion: @escaping ([MenuBarApp]) -> Void) {
        let own = Bundle.main.bundleIdentifier
        let chosen = hiddenApps
        inventory.snapshot { items in
            var bundles = Set(items.compactMap(\.bundleIdentifier))
            bundles.formUnion(chosen)
            bundles.subtract(MenuBarLayoutResolver.systemItemOwners)
            if let own { bundles.remove(own) }
            let apps = bundles.map { bundle -> MenuBarApp in
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                let name = url.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
                    ?? url?.deletingPathExtension().lastPathComponent ?? bundle
                return MenuBarApp(bundleIdentifier: bundle, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
            }
            completion(apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    var needsAccessibility: Bool { !inventory.isAuthorized }

    // MARK: - The icon

    private func createItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel(L("Hidden icons"))
        item.isVisible = true
        statusItem = item
        updateIcon()
    }

    private var hiddenCount: Int {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return hiddenApps.intersection(running).count
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.image = Self.makeImage(collapsed: isCollapsed || style == .menu, count: hiddenCount,
                                      symbol: style == .menu ? (panel.isShown ? "chevron.up" : "chevron.down") : nil)
        button.toolTip = style == .menu
            ? L("Click to see the hidden icons")
            : isCollapsed
            ? L("Click to show the hidden icons")
            : (hiddenApps.isEmpty ? L("Choose which apps to hide in Sirena's settings") : L("Click to hide the chosen icons"))
    }

    /// Collapsed: a filled pill with ‹ (icons expand to the left) and how many apps are hidden.
    /// Expanded: a plain ›, to tuck them away again.
    /// In menu mode the chevron points down (the icons drop down below it).
    private static func makeImage(collapsed: Bool, count: Int, symbol: String? = nil) -> NSImage {
        let chevron = NSImage(systemSymbolName: symbol ?? (collapsed ? "chevron.left" : "chevron.right"), accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        let text = collapsed && count > 0 ? "\(count)" : ""
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let chevronWidth: CGFloat = 8
        let width = collapsed ? 5 + chevronWidth + (text.isEmpty ? 0 : 3 + textSize.width) + 5 : chevronWidth + 10
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = NSRect(x: 0, y: 3, width: rect.width, height: rect.height - 6)
            let operation: NSCompositingOperation = collapsed ? .destinationOut : .sourceOver
            if collapsed {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            }
            var x: CGFloat = collapsed ? 5 : 5
            if let chevron {
                let size = chevron.size
                chevron.draw(in: NSRect(x: x + (chevronWidth - size.width) / 2, y: (rect.height - size.height) / 2,
                                        width: size.width, height: size.height),
                             from: .zero, operation: operation, fraction: 1)
                x += chevronWidth + 3
            }
            if !text.isEmpty {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                (text as NSString).draw(at: NSPoint(x: x, y: (rect.height - textSize.height) / 2),
                                        withAttributes: [.font: font, .foregroundColor: NSColor.black])
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if hiddenApps.isEmpty {
            // Nothing chosen yet: take the user to the list.
            openPage()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: isCollapsed ? L("Show Hidden Icons") : L("Hide Chosen Icons"), action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = !hiddenApps.isEmpty
        menu.addItem(toggleItem)
        let autoHide = NSMenuItem(title: L("Hide Automatically"), action: #selector(menuAutoHide), keyEquivalent: "")
        autoHide.target = self
        autoHide.state = Preferences.isAutoHide ? .on : .off
        menu.addItem(autoHide)
        menu.addItem(.separator())
        let choose = NSMenuItem(title: L("Choose Apps to Hide…"), action: #selector(menuChoose), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        menu.delegate = self
        statusItem.menu = menu
        DispatchQueue.main.async { statusItem.button?.performClick(nil) }
    }

    // MARK: - Menu style

    private var hiddenRunningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier.map(hiddenApps.contains) ?? false }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func togglePanel() {
        if panel.isShown {
            panel.close()
        } else if !panel.closedJustNow, let button = statusItem?.button {
            panel.show(from: button, apps: hiddenRunningApps, onPick: { [weak self] app in
                self?.reveal(app)
            }, onSettings: { [weak self] in
                self?.openPage()
            }, onClose: { [weak self] in
                self?.updateIcon()
            })
        }
        // The arrow flips while the menu is open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.updateIcon() }
    }

    /// Lets the app's icon back into the menu bar, clicks it, and tucks it away again
    /// once its menu is closed and the pointer has left the menu bar.
    /// Opens a hidden app's menu bar icon (sirena://open-hidden-icon?app=<bundle id>).
    func openHiddenIcon(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        reveal(app)
    }

    /// Lets the app's icon back into the menu bar and opens it, then tucks it away again
    /// once its menu is closed and the pointer has left the menu bar.
    private func reveal(_ app: NSRunningApplication) {
        revealWatcher?.invalidate()
        release()
        isCollapsed = false
        updateIcon()
        // Right after the restriction is lifted the menu bar ignores presses on the icon
        // for a moment, so press, check that a menu opened, and try again until it does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openStatusItem(of: app, attemptsLeft: 8)
        }
    }

    private func openStatusItem(of app: NSRunningApplication, attemptsLeft: Int) {
        let pid = app.processIdentifier
        guard !Self.hasOpenMenu(pid) else { return watchRevealedApp(app) }
        guard attemptsLeft > 0, Self.statusItemElement(of: pid) != nil else {
            // No icon to open (or it never answered): at least bring the app forward.
            app.activate()
            return watchRevealedApp(app)
        }
        _ = Self.pressStatusItem(of: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.openStatusItem(of: app, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Presses the app's first menu bar icon through Accessibility, which opens its menu
    /// or popover the same way a click does.
    private static func pressStatusItem(of pid: pid_t) -> Bool {
        guard let item = statusItemElement(of: pid) else { return false }
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        // A press that opens a menu often "times out" because the menu is now tracking:
        // that still counts as opened.
        return result == .success || result == .cannotComplete
    }

    private static func statusItemElement(of pid: pid_t) -> AXUIElement? {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success else { return nil }
        return (children as? [AXUIElement])?.first
    }

    private func watchRevealedApp(_ app: NSRunningApplication) {
        let started = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let inUse = Self.isMouseInMenuBar || Self.hasOpenMenu(app.processIdentifier)
                guard Date().timeIntervalSince(started) > 1.5, !inUse else { return }
                timer.invalidate()
                self.revealWatcher = nil
                if self.style == .menu { self.collapse() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealWatcher = timer
    }

    /// Whether the app shows a menu or popover (any on-screen window taller than the
    /// menu bar besides its normal windows' layer).
    private static func hasOpenMenu(_ pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height > 40
        }
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuAutoHide() { Preferences.isAutoHide.toggle() }
    @objc private func menuChoose() { openPage() }

    // MARK: - Far left placement

    private static let menuBarPreferences = NSHomeDirectory() + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist"

    /// Orders the menu bar so Sirena's arrow is always the last visible icon (furthest
    /// left) and the hidden apps' icons sit beyond it: when they're shown, they appear
    /// after the arrow, never in between the other apps. macOS 27 keeps each item's place
    /// in MenuBarAgent's preferences, as the distance from the right edge (bigger =
    /// further left), and reads it when the item is created.
    private func arrangeMenuBar(then done: @escaping (_ arrowMoved: Bool) -> Void = { _ in }) {
        guard #available(macOS 27, *), inventory.isAuthorized else { return done(false) }
        let hidden = hiddenApps
        inventory.snapshot { items in
            let own = Bundle.main.bundleIdentifier ?? ""
            let present = Set(items.compactMap(\.bundleIdentifier)).subtracting(MenuBarLayoutResolver.systemItemOwners)
                .union(hidden).union([own])
            let positions = Self.menuBarPositions()
            let arrowKey = "status:\(own)::\(Self.autosaveName)"

            func bundle(of key: String) -> String? {
                guard key.hasPrefix("status:"), let end = key.range(of: "::") else { return nil }
                return String(key[key.index(key.startIndex, offsetBy: 7)..<end.lowerBound])
            }

            // Icons that stay visible: every icon not chosen to hide, detected or not. Some
            // apps (Setapp and others) put their icon up from a helper the inventory can't
            // see; leaving them out put the arrow before them, so they got hidden too.
            _ = present
            let visible = positions.filter { key, _ in
                guard key != arrowKey else { return false }
                guard let owner = bundle(of: key) else { return true }
                return !hidden.contains(owner)
            }
            let hiddenItems = positions.filter { key, _ in bundle(of: key).map(hidden.contains) ?? false }
                .sorted { $0.value < $1.value }

            let arrow = ((visible.values.max() ?? 0) + 40).rounded()
            var target = [arrowKey: arrow]
            for (index, item) in hiddenItems.enumerated() {
                target[item.key] = arrow + 40 * Double(index + 1)
            }
            let changed = target.filter { positions[$0.key] != $0.value }
            if !changed.isEmpty {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                task.arguments = ["write", Self.menuBarPreferences, "TrailingItemPreferredPositions", "-dict-add"]
                    + changed.flatMap { [$0.key, "-float", String($0.value)] }
                // Off the main thread: never block the menu bar while defaults writes.
                let moved = positions[arrowKey] != arrow
                task.terminationHandler = { _ in DispatchQueue.main.async { done(moved) } }
                do { try task.run() } catch { done(moved) }
                return
            }
            done(positions[arrowKey] != arrow)
        }
    }

    /// Re-creates the arrow so macOS reads its new place.
    private func recreateItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        createItem()
    }

    /// "status:com.app.id::name" → "com.app.id".
    private static func owner(ofPositionKey key: String) -> String? {
        guard key.hasPrefix("status:"), let end = key.range(of: "::") else { return nil }
        return String(key[key.index(key.startIndex, offsetBy: 7)..<end.lowerBound])
    }

    private static func menuBarPositions() -> [String: Double] {
        guard let data = FileManager.default.contents(atPath: menuBarPreferences),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let positions = plist["TrailingItemPreferredPositions"] as? [String: Any] else { return [:] }
        return positions.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }
}

extension MenuBarModule: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}
