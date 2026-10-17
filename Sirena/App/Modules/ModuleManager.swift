/// ModuleManager.swift

import AppKit
import DockKit
import ClipboardKit

/// Starts the enabled modules and tracks what needs a relaunch.
@MainActor
@Observable
final class ModuleManager {
    static let shared = ModuleManager()

    /// Modules turned off while running; they stop for good on the next launch.
    private(set) var pendingRestart: Set<ModuleID> = []

    private(set) var running: Set<ModuleID> = []

    /// Set by the app delegate: opens the main window on a page.
    var openPage: (SidebarItem) -> Void = { _ in }
    var isMainWindowVisible: () -> Bool = { false }

    func startEnabledModules(windowManagement: WindowManagementModule, windowsMenu: NSMenu) {
        for module in ModuleID.allCases where module.isEnabled {
            start(module, windowManagement: windowManagement, windowsMenu: windowsMenu)
        }
        // The Dock and window tweaks don't depend on Melhorias (which is only the Finder now).
        start(.tweaks, windowManagement: windowManagement, windowsMenu: windowsMenu)
    }

    func isRunning(_ module: ModuleID) -> Bool {
        running.contains(module)
    }

    /// Bumped on every switch, so views reading `isEnabled` refresh (the flag itself
    /// lives in UserDefaults).
    private var switchChanges = 0

    func isEnabled(_ module: ModuleID) -> Bool {
        _ = switchChanges
        return module.isEnabled
    }

    func setEnabled(_ module: ModuleID, _ enabled: Bool) {
        module.isEnabled = enabled
        switchChanges += 1
        if enabled {
            pendingRestart.remove(module)
            let delegate = AppDelegate.instance
            start(module, windowManagement: delegate.windowManagement, windowsMenu: delegate.windowsMenu)
            if module == .tweaks { TweaksController.shared.applyFinderSwitch() }
        } else if module == .switcher, running.contains(module) {
            // Give ⌘ Tab back to macOS right away, no restart needed.
            WindowSwitcherController.shared.terminate()
            running.remove(module)
        } else if module == .tweaks {
            TweaksController.shared.applyFinderSwitch()
        } else if module == .island, running.contains(module) {
            IslandController.shared.terminate()
            running.remove(module)
        } else if running.contains(module) {
            pendingRestart.insert(module)
        }
    }

    private func start(_ module: ModuleID, windowManagement: WindowManagementModule, windowsMenu: NSMenu) {
        guard !running.contains(module) else { return }
        let open = { [weak self] in self?.openPage(.module(module)) ?? () }
        switch module {
        case .windows:
            windowManagement.start(menu: windowsMenu)
        case .dock:
            DockModule.start(openPage: open)
        case .switcher:
            WindowSwitcherController.shared.start()
        case .island:
            IslandController.openSettingsHandler = open
            IslandController.shared.start()
        case .clipboard:
            ClipboardModule.start(openPage: open)
        case .menuBar:
            MenuBarModule.shared.start(openPage: open)
        case .keepAwake:
            KeepAwakeModule.shared.start()
        case .mirror:
            MirrorController.shared.start(openSettings: open)
        case .pinWindow:
            PinWindowController.shared.start(openPage: open)
        case .textCapture:
            TextCaptureController.shared.start(openPage: open)
        case .tweaks:
            TweaksController.shared.start()
        case .shelf:
            ShelfController.shared.start(openPage: open)
        }
        running.insert(module)
    }

    func terminate() {
        if running.contains(.clipboard) { ClipboardModule.terminate() }
        if running.contains(.dock) { DockModule.terminate() }
        if running.contains(.switcher) { WindowSwitcherController.shared.terminate() }
        if running.contains(.island) { IslandController.shared.terminate() }
        if running.contains(.keepAwake) { KeepAwakeModule.shared.terminate() }
        if running.contains(.mirror) { MirrorController.shared.terminate() }
        if running.contains(.pinWindow) { PinWindowController.shared.terminate() }
        if running.contains(.textCapture) { TextCaptureController.shared.terminate() }
        if running.contains(.tweaks) { TweaksController.shared.terminate() }
        if running.contains(.shelf) { ShelfController.shared.terminate() }
        if running.contains(.menuBar) { MenuBarModule.shared.terminate() }
    }

    /// Quits and reopens Sirena.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
