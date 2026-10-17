/// WindowManagementModule.swift
///
/// Window management for Sirena, ported from Rectangle (MIT, © Ryan Hanson).
/// Owns every Rectangle manager and the window-action part of the status menu,
/// which used to live in Rectangle's AppDelegate.

import Cocoa
import os.log

final class WindowManagementModule: NSObject {

    static let windowHistory = WindowHistory()

    private let accessibilityAuthorization = AccessibilityAuthorization()

    private var shortcutManager: ShortcutManager!
    private var windowManager: WindowManager!
    private var applicationToggle: ApplicationToggle!
    private var windowCalculationFactory: WindowCalculationFactory!
    private var snappingManager: SnappingManager!
    private var stackBadgeManager: StackBadgeManager!
    private var titleBarManager: TitleBarManager!
    private var greenButtonManager: GreenButtonManager!

    private var prevActiveAppObservation: NSKeyValueObservation?
    private var prevActiveApp: NSRunningApplication?

    /// The status menu the module inserts its items into, starting at index 0.
    private weak var mainStatusMenu: NSMenu!
    private var ignoreMenuItem: NSMenuItem!
    private var additionalSizeMenuItems: [NSMenuItem] = []
    private var dynamicMenuItemCount: Int = 0

    private(set) var isTrusted = false

    /// Called once accessibility access is granted (immediately if it already was).
    var onTrusted: (() -> Void)?

    // MARK: - Lifecycle

    func start(menu: NSMenu) {
        mainStatusMenu = menu
        menu.delegate = self
        Defaults.loadFromSupportDir()
        migrateShowEighthsInMenu()
        checkVersion()
        checkLaunchOnLogin()

        let alreadyTrusted = accessibilityAuthorization.checkAccessibility {
            WelcomeView.show()
            self.checkForConflictingApps()
            self.accessibilityTrusted()
        }

        if alreadyTrusted {
            accessibilityTrusted()
        }

        addWindowActionMenuItems()

        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .showAdditionalSizesInMenuChanged, object: nil)

        Notification.Name.configImported.onPost(using: { _ in
            SirenaStatusItem.instance.refreshVisibility()
            guard self.isTrusted else { return }
            self.applicationToggle.reloadFromDefaults()
            self.shortcutManager.reloadFromDefaults()
            self.snappingManager.reloadFromDefaults()
            self.initializeTodo(false)
        })

        Notification.Name.todoMenuToggled.onPost(using: { _ in
            guard self.isTrusted else { return }
            self.initializeTodo(false)
        })

        prevActiveAppObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: .old) { _, change in
            self.prevActiveApp = change.oldValue ?? nil
        }
    }

    func requestAuthorization() {
        accessibilityAuthorization.checkAccessibility {
            self.accessibilityTrusted()
        }
        accessibilityAuthorization.showAuthorizationWindow()
    }

    private func accessibilityTrusted() {
        guard !isTrusted else { return }
        isTrusted = true
        windowCalculationFactory = WindowCalculationFactory()
        windowManager = WindowManager()
        shortcutManager = ShortcutManager(windowManager: windowManager)
        applicationToggle = ApplicationToggle(shortcutManager: shortcutManager)
        snappingManager = SnappingManager()
        stackBadgeManager = StackBadgeManager()
        titleBarManager = TitleBarManager()
        greenButtonManager = GreenButtonManager()
        initializeTodo()
        checkForProblematicApps()
        MacTilingDefaults.checkForBuiltInTiling(skipIfAlreadyNotified: true)
        onTrusted?()
    }

    private func checkVersion() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let lastVersion = Defaults.lastVersion.value,
           let intLastVersion = Int(lastVersion) {
            if intLastVersion < 46 {
                MASShortcutMigration.migrate()
            }
            if intLastVersion < 64 {
                SnapAreaModel.instance.migrate()
            }
        } else {
            Defaults.installVersion.value = currentVersion
            Defaults.allowAnyShortcut.enabled = true
        }
        MASShortcutMigration.syncRenamedSideShortcutAliases()

        Defaults.lastVersion.value = currentVersion
    }

    private func checkLaunchOnLogin() {
        if Defaults.launchOnLogin.enabled, !LaunchOnLogin.isEnabled {
            LaunchOnLogin.isEnabled = true
        }
    }

    private func migrateShowEighthsInMenu() {
        let oldKey = "showEighthsInMenu"
        let oldValue = UserDefaults.standard.integer(forKey: oldKey)
        if oldValue != 0 && Defaults.showAdditionalSizesInMenu.notSet {
            Defaults.showAdditionalSizesInMenu.enabled = (oldValue == 1)
        }
    }

    private func checkForConflictingApps() {
        let conflictingAppsIds: [String: String] = [
            "com.knollsoft.Rectangle": "Rectangle",
            "com.knollsoft.Hookshot": "Rectangle Pro",
            "com.divisiblebyzero.Spectacle": "Spectacle",
            "com.crowdcafe.windowmagnet": "Magnet",
            "com.hegenberg.BetterSnapTool": "BetterSnapTool",
            "com.manytricks.Moom": "Moom"
        ]

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier else { continue }
            if let conflictingAppName = conflictingAppsIds[bundleId] {
                AlertUtil.oneButtonAlert(question: "Potential window manager conflict: \(conflictingAppName)", text: "Since \(conflictingAppName) might have some overlapping behavior with Sirena, it's recommended that you either disable or quit \(conflictingAppName).")
                break
            }
        }
    }

    /// certain applications have issues with the click listening done by the drag to snap feature
    private func checkForProblematicApps() {
        guard !Defaults.windowSnapping.userDisabled, !Defaults.notifiedOfProblemApps.enabled else { return }

        let problemBundleIds: [String] = [
            "com.mathworks.matlab",
            "com.live2d.cubism.CECubismEditorApp",
            "com.aquafold.datastudio.DataStudio",
            "com.adobe.illustrator",
            "com.adobe.AfterEffects"
        ]

        // these apps are java based with dynamic bundleIds
        let problemJavaAppNames: [String] = [
            "thinkorswim",
            "Trader Workstation"
        ]

        var problemBundles: [Bundle] = problemBundleIds.compactMap { bundleId in
            if applicationToggle.isDisabled(bundleId: bundleId) { return nil }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return Bundle(url: url)
            }
            return nil
        }

        let runningApps = NSWorkspace.shared.runningApplications

        for name in problemJavaAppNames {
            if let runningApp = runningApps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }),
               let bundleId = runningApp.bundleIdentifier,
               let appURL = runningApp.bundleURL,
               let bundle = Bundle(url: appURL) {

                if !applicationToggle.isDisabled(bundleId: bundleId),
                   bundleId.starts(with: "com.install4j") {
                    problemBundles.append(bundle)
                }
            }
        }

        let displayNames = problemBundles.compactMap { $0.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String }
        let displayNameString = displayNames.joined(separator: "\n")

        if !problemBundles.isEmpty {
            AlertUtil.oneButtonAlert(question: "Known issues with installed applications", text: "\(displayNameString)\n\nThese applications have issues with the drag to screen edge to snap functionality in Sirena.\n\nYou can either ignore the applications using the menu item in Sirena, or disable drag to screen edge snapping in Sirena settings.")
            Defaults.notifiedOfProblemApps.enabled = true
        }
    }

    @objc private func ignoreFrontMostApp(_ sender: NSMenuItem) {
        if sender.state == .on {
            applicationToggle.enableApp()
        } else {
            applicationToggle.disableApp()
        }
    }
}

// MARK: - Status menu

extension WindowManagementModule: NSMenuDelegate {

    /// Called by the app's status menu delegate before the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        if menu != mainStatusMenu {
            updateWindowActionMenuItems(menu: menu)
            updateTodoModeMenuItems(menu: menu)
            return
        }

        guard ignoreMenuItem != nil else { return }

        if isTrusted, let frontAppName = ApplicationToggle.frontAppName {
            let ignoreString = String(localized: "Ignore frontmost.app")
            ignoreMenuItem.title = ignoreString.replacingOccurrences(of: "frontmost.app", with: frontAppName)
            ignoreMenuItem.state = ApplicationToggle.shortcutsDisabled ? .on : .off
            ignoreMenuItem.isHidden = false
        } else {
            ignoreMenuItem.isHidden = true
        }

        updateWindowActionMenuItems(menu: menu)
        updateTodoModeMenuItems(menu: menu)
    }

    private func updateWindowActionMenuItems(menu: NSMenu) {
        let frontmostWindow = isTrusted ? AccessibilityElement.getFrontWindowElement() : nil
        let screenCount = NSScreen.screens.count
        let isPortrait = NSScreen.main?.frame.isLandscape == false

        for menuItem in menu.items {
            guard let windowAction = menuItem.representedObject as? WindowAction else { continue }

            menuItem.image = windowAction.image.copy() as? NSImage
            menuItem.image?.size = NSSize(width: 18, height: 12)

            if isPortrait && windowAction.classification == .thirds {
                menuItem.image = menuItem.image?.rotated(by: 270)
                menuItem.image?.isTemplate = true
            }

            if isTrusted, !ApplicationToggle.shortcutsDisabled {
                if let fullKeyEquivalent = shortcutManager.getKeyEquivalent(action: windowAction),
                   let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
                    menuItem.keyEquivalent = keyEquivalent
                    menuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
                }
            }
            if frontmostWindow == nil {
                menuItem.isEnabled = false
            }
            if windowAction == .nextDisplay || windowAction == .previousDisplay {
                menuItem.isHidden = screenCount == 1 || Defaults.combinedDisplayMode.userEnabled
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        for menuItem in menu.items where menuItem.representedObject is WindowAction || TodoItem.tags.contains(menuItem.tag) {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags()
            menuItem.isEnabled = true
        }
    }

    @objc private func executeMenuWindowAction(sender: NSMenuItem) {
        guard let windowAction = sender.representedObject as? WindowAction else { return }
        windowAction.postMenu()
    }

    private func addWindowActionMenuItems(showAdditional: Bool = Defaults.showAdditionalSizesInMenu.userEnabled,
                                          showAllActions: Bool = Defaults.showAllActionsInMenu.userEnabled) {
        let additionalSizeCategories: Set<WindowActionCategory> = [.eighths, .ninths, .twelfths, .sixteenths, .tiling]
        let submenuOnlyWhenAdditional: Set<WindowActionCategory> = [.thirds, .size]
        var menuIndex = 0
        var categoryMenus: [CategoryMenu] = []
        for action in WindowAction.active {
            guard !action.excludedFromMenu, let displayName = action.displayName else { continue }
            let newMenuItem = NSMenuItem(title: displayName, action: #selector(executeMenuWindowAction), keyEquivalent: "")
            newMenuItem.target = self
            newMenuItem.representedObject = action
            if #available(macOS 27.0, *) {
                newMenuItem.preferredImageVisibility = .visible
            }
            if !showAllActions, let category = action.category {
                // When additional sizes are off, keep Thirds and Size as flat items
                if submenuOnlyWhenAdditional.contains(category) && !showAdditional {
                    // Fall through to flat item handling below
                } else {
                    if menuIndex != 0 && action.firstInGroup {
                        let menu = NSMenu(title: category.displayName)
                        menu.autoenablesItems = false
                        categoryMenus.append(CategoryMenu(menu: menu, category: category))
                    }
                    categoryMenus.last?.menu.addItem(newMenuItem)
                    continue
                }
            }

            // Flat item - suppress extra separator for almostMaximize when Size is not a submenu
            let showSeparator = action.firstInGroup && !(action == .almostMaximize && !showAdditional)
            if menuIndex != 0 && showSeparator {
                mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
                menuIndex += 1
            }
            mainStatusMenu.insertItem(newMenuItem, at: menuIndex)
            menuIndex += 1
        }

        if !categoryMenus.isEmpty {
            mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
            menuIndex += 1

            let sortedCategoryMenus = categoryMenus.sorted { $0.category.menuOrder < $1.category.menuOrder }
            for categoryMenu in sortedCategoryMenus {
                categoryMenu.menu.delegate = self
                let menuMenuItem = NSMenuItem(title: categoryMenu.category.displayName, action: nil, keyEquivalent: "")
                if additionalSizeCategories.contains(categoryMenu.category) {
                    menuMenuItem.isHidden = !showAdditional
                    additionalSizeMenuItems.append(menuMenuItem)
                }
                mainStatusMenu.insertItem(menuMenuItem, at: menuIndex)
                mainStatusMenu.setSubmenu(categoryMenu.menu, for: menuMenuItem)
                menuIndex += 1
            }
        }

        mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
        menuIndex += 1

        let todoItemCount = addTodoModeMenuItems(startingIndex: menuIndex)
        menuIndex += todoItemCount

        ignoreMenuItem = NSMenuItem(title: String(localized: "Ignore frontmost.app"), action: #selector(ignoreFrontMostApp), keyEquivalent: "")
        ignoreMenuItem.target = self
        mainStatusMenu.insertItem(ignoreMenuItem, at: menuIndex)
        menuIndex += 1

        dynamicMenuItemCount = menuIndex
    }

    @objc private func rebuildMenu() {
        for _ in 0..<dynamicMenuItemCount {
            mainStatusMenu.removeItem(at: 0)
        }
        dynamicMenuItemCount = 0
        additionalSizeMenuItems.removeAll()
        addWindowActionMenuItems()
    }

    private struct CategoryMenu {
        let menu: NSMenu
        let category: WindowActionCategory
    }
}

// MARK: - Todo mode

extension WindowManagementModule {
    private func initializeTodo(_ bringToFront: Bool = true) {
        showHideTodoMenuItems()
        TodoManager.registerUnregisterToggleShortcut()
        TodoManager.registerUnregisterReflowShortcut()
        TodoManager.moveAllIfNeeded(bringToFront)
    }

    enum TodoItem {
        case mode, app, reflow, separator, window

        var tag: Int {
            switch self {
            case .mode: return 101
            case .app: return 102
            case .reflow: return 103
            case .separator: return 104
            case .window: return 105
            }
        }

        static let tags = [101, 102, 103, 104, 105]
    }

    /// Returns the number of items inserted.
    private func addTodoModeMenuItems(startingIndex: Int) -> Int {
        var menuIndex = startingIndex

        let todoModeMenuItem = NSMenuItem(title: String(localized: "Enable Todo Mode"), action: #selector(toggleTodoMode), keyEquivalent: "")
        todoModeMenuItem.tag = TodoItem.mode.tag
        todoModeMenuItem.target = self
        mainStatusMenu.insertItem(todoModeMenuItem, at: menuIndex)
        menuIndex += 1

        let todoAppMenuItem = NSMenuItem(title: String(localized: "Use frontmost.app as Todo App"), action: #selector(setTodoApp), keyEquivalent: "")
        todoAppMenuItem.tag = TodoItem.app.tag
        todoAppMenuItem.target = self
        mainStatusMenu.insertItem(todoAppMenuItem, at: menuIndex)
        menuIndex += 1

        let todoWindowMenuItem = NSMenuItem(title: String(localized: "Use as Todo Window"), action: #selector(setTodoWindow), keyEquivalent: "")
        todoWindowMenuItem.tag = TodoItem.window.tag
        todoWindowMenuItem.target = self
        mainStatusMenu.insertItem(todoWindowMenuItem, at: menuIndex)
        menuIndex += 1

        let todoReflowItem = NSMenuItem(title: String(localized: "Reflow Todo"), action: #selector(todoReflow), keyEquivalent: "")
        todoReflowItem.tag = TodoItem.reflow.tag
        todoReflowItem.target = self
        mainStatusMenu.insertItem(todoReflowItem, at: menuIndex)
        menuIndex += 1

        let separator = NSMenuItem.separator()
        separator.tag = TodoItem.separator.tag
        mainStatusMenu.insertItem(separator, at: menuIndex)
        menuIndex += 1

        showHideTodoMenuItems()
        return menuIndex - startingIndex
    }

    private func showHideTodoMenuItems() {
        for item in mainStatusMenu.items where TodoItem.tags.contains(item.tag) {
            item.isHidden = !Defaults.todo.userEnabled
        }
    }

    @objc private func toggleTodoMode(_ sender: NSMenuItem) {
        TodoManager.setTodoMode(sender.state == .off)
    }

    @objc private func setTodoApp(_ sender: NSMenuItem) {
        applicationToggle.setTodoApp()
        TodoManager.moveAllIfNeeded()
    }

    @objc private func todoReflow(_ sender: NSMenuItem) {
        TodoManager.moveAll()
    }

    @objc private func setTodoWindow(_ sender: NSMenuItem) {
        TodoManager.resetTodoWindow()
        TodoManager.moveAllIfNeeded()
    }

    private func updateTodoModeMenuItems(menu: NSMenu) {
        guard isTrusted,
              Defaults.todo.userEnabled,
              let todoAppMenuItem = menu.item(withTag: TodoItem.app.tag),
              let todoModeMenuItem = menu.item(withTag: TodoItem.mode.tag),
              let todoReflowMenuItem = menu.item(withTag: TodoItem.reflow.tag),
              let todoWindowMenuItem = menu.item(withTag: TodoItem.window.tag)
        else {
            return
        }

        if let frontAppName = ApplicationToggle.frontAppName {
            let appString = String(localized: "Use frontmost.app as Todo App")
            todoAppMenuItem.title = appString.replacingOccurrences(of: "frontmost.app", with: frontAppName)
            todoAppMenuItem.isEnabled = !applicationToggle.todoAppIsActive()
            todoAppMenuItem.state = applicationToggle.todoAppIsActive() ? .on : .off
            todoAppMenuItem.isHidden = false
        } else {
            todoAppMenuItem.isHidden = true
        }

        todoModeMenuItem.state = Defaults.todoMode.enabled ? .on : .off

        if let fullKeyEquivalent = TodoManager.getToggleKeyDisplay(),
           let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
            todoModeMenuItem.keyEquivalent = keyEquivalent
            todoModeMenuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
        }

        if let fullKeyEquivalent = TodoManager.getReflowKeyDisplay(),
           let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
            todoReflowMenuItem.keyEquivalent = keyEquivalent
            todoReflowMenuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
        }

        todoReflowMenuItem.isEnabled = Defaults.todoMode.enabled

        todoWindowMenuItem.isHidden = !applicationToggle.todoAppIsActive() || TodoManager.isTodoWindowFront()
    }
}

// MARK: - URL scheme (sirena://execute-action?name=left-half)

extension WindowManagementModule {
    func handle(urls: [URL]) {
        let triggeringApp = NSWorkspace.shared.frontmostApplication

        if triggeringApp == NSRunningApplication.current {
            prevActiveApp?.activate()
        }
        DispatchQueue.main.async {

            func getUrlName(_ name: String) -> String {
                return name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
            }

            func extractBundleIdParameter(fromComponents components: URLComponents) -> String? {
                (components.queryItems?.first { $0.name == "app-bundle-id" })?.value ?? ApplicationToggle.frontAppId
            }

            func isValidParameter(bundleId: String?) -> Bool {
                let isValid = bundleId?.isEmpty != true
                if !isValid {
                    Logger.log("Received an empty app-bundle-id parameter. Either pass a valid app bundle id or remove the parameter.")
                }
                return isValid
            }

            func confirmExecuteTask(action: String, bundleId: String) -> Bool {
                if triggeringApp == NSRunningApplication.current {
                    return true
                }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Allow Sirena URL action?")
                alert.informativeText = String(localized: "An external source asked Sirena to perform \"\(action)\" on app bundle id \"\(bundleId)\". Allow?")
                alert.addButton(withTitle: String(localized: "Allow"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertFirstButtonReturn
            }

            guard self.isTrusted else { return }

            for url in urls {
                guard
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                    components.path.isEmpty
                else {
                    continue
                }

                let name = (components.queryItems?.first { $0.name == "name" })?.value
                switch (components.host, name) {
                case ("execute-action", _):
                    let action = (WindowAction.active.first { windowAction in
                        if let aliasName = windowAction.aliasName, getUrlName(aliasName) == name {
                            return true
                        }
                        return getUrlName(windowAction.name) == name
                    })
                    action?.postUrl()
                case ("execute-task", "ignore-app"):
                    let bundleId = extractBundleIdParameter(fromComponents: components)
                    guard isValidParameter(bundleId: bundleId), let bundleId else { continue }
                    guard confirmExecuteTask(action: "ignore-app", bundleId: bundleId) else { continue }
                    self.applicationToggle.disableApp(appBundleId: bundleId)
                case ("execute-task", "unignore-app"):
                    let bundleId = extractBundleIdParameter(fromComponents: components)
                    guard isValidParameter(bundleId: bundleId), let bundleId else { continue }
                    guard confirmExecuteTask(action: "unignore-app", bundleId: bundleId) else { continue }
                    self.applicationToggle.enableApp(appBundleId: bundleId)
                default:
                    continue
                }
            }
        }
    }
}
