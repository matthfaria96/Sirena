/// TweaksSettings.swift
///
/// Preferences of Tweaks, the behavior fixes modeled on Supercharge's Tweaks tab.
/// Written from scratch for Sirena: Supercharge is closed source, only its public
/// feature list was used.

import Foundation

/// What clicking the Dock icon of the app already in front does.
enum DockActiveAppClick: String, CaseIterable, Identifiable {
    /// macOS's own behavior: nothing changes.
    case nothing
    case minimizeWindows
    case hideApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nothing: return L("Do Nothing")
        case .minimizeWindows: return L("Minimize Windows")
        case .hideApp: return L("Hide App")
        }
    }
}

@Observable
final class TweaksSettings {
    static let shared = TweaksSettings()

    private let defaults = UserDefaults.standard

    // Apps & Windows
    /// Done by the Windows feature (Rectangle's proven green-button override, which
    /// maximizes and restores like a double-click on the title bar).
    var greenButtonFills: Bool {
        didSet {
            save(greenButtonFills, "tweaks.greenButtonFills")
            Self.applyGreenButton(greenButtonFills)
        }
    }

    static func applyGreenButton(_ enabled: Bool) {
        guard Defaults.greenButtonOverride.enabled != enabled else { return }
        Defaults.greenButtonOverride.enabled = enabled
        Notification.Name.greenButtonOverride.post()
    }

    // Dock
    var dockActiveAppClick: DockActiveAppClick { didSet { save(dockActiveAppClick.rawValue, "tweaks.dockActiveAppClick") } }
    var dockUnminimizeAll: Bool { didSet { save(dockUnminimizeAll, "tweaks.dockUnminimizeAll") } }
    var dockFoldersOpenInFinder: Bool { didSet { save(dockFoldersOpenInFinder, "tweaks.dockFoldersOpenInFinder") } }

    // Finder
    var finderCutAndPaste: Bool { didSet { save(finderCutAndPaste, "tweaks.finderCutAndPaste") } }
    var finderCutSound: Bool { didSet { save(finderCutSound, "tweaks.finderCutSound") } }
    var finderDeleteMovesToTrash: Bool { didSet { save(finderDeleteMovesToTrash, "tweaks.finderDeleteMovesToTrash") } }
    /// ⌘L in a Finder window: an address bar to edit or paste the path (FinderAddressBar).
    var finderAddressBar: Bool { didSet { save(finderAddressBar, "tweaks.finderAddressBar") } }
    /// "Copiar Caminho" in the Finder's right-click menu (Sirena's Finder extension).
    var finderCopyPath: Bool {
        didSet {
            save(finderCopyPath, "tweaks.finderCopyPath")
            FinderCopyPathExtension.setEnabled(finderCopyPath && TweaksController.finderTweaksOn)
        }
    }

    /// Opening a .dmg with an app offers to install it, eject it and trash it (Supercharge).
    var installFromDMG: Bool { didSet { save(installFromDMG, "tweaks.installFromDMG") } }

    private init() {
        greenButtonFills = defaults.object(forKey: "tweaks.greenButtonFills") as? Bool ?? true
        dockActiveAppClick = DockActiveAppClick(rawValue: defaults.string(forKey: "tweaks.dockActiveAppClick") ?? "") ?? .minimizeWindows
        dockUnminimizeAll = defaults.object(forKey: "tweaks.dockUnminimizeAll") as? Bool ?? true
        dockFoldersOpenInFinder = defaults.object(forKey: "tweaks.dockFoldersOpenInFinder") as? Bool ?? true
        finderCutAndPaste = defaults.object(forKey: "tweaks.finderCutAndPaste") as? Bool ?? true
        finderCutSound = defaults.object(forKey: "tweaks.finderCutSound") as? Bool ?? true
        finderDeleteMovesToTrash = defaults.object(forKey: "tweaks.finderDeleteMovesToTrash") as? Bool ?? true
        finderAddressBar = defaults.object(forKey: "tweaks.finderAddressBar") as? Bool ?? true
        finderCopyPath = defaults.object(forKey: "tweaks.finderCopyPath") as? Bool ?? true
        installFromDMG = defaults.object(forKey: "tweaks.installFromDMG") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Sirena's Finder extension (SirenaFinder.appex, inside the app): the system keeps it
/// on or off through PlugInKit, like the switch in System Settings › Login Items & Extensions.
enum FinderCopyPathExtension {
    static let identifier = "com.matheusfaria.Sirena.Finder"

    static func setEnabled(_ enabled: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-e", enabled ? "use" : "ignore", "-i", identifier]
        try? task.run()
    }
}
