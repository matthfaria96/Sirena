// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint (shims for the Sirena port)

import AppKit
import ApplicationServices
import CoreGraphics

enum SwitcherDefaultsKey {
    static let switcherEnabled = "switcherEnabled"
    static let switcherTakeOverSystemShortcuts = "switcherTakeOverSystemShortcuts"
    static let switcherNativeHotkeysSuppressed = "switcherNativeHotkeysSuppressed"
    static let systemShortcutsSuppressed = "switcherSystemShortcutsSuppressed"
    static let systemShortcutTakeOverKeys = "switcherSystemShortcutTakeOverKeys"
    static let switcherShortcut = "switcherShortcut"
    static let switcherWindowShortcut = "switcherWindowShortcut"
    static let switcherIconRowMode = "switcherIconRowMode"
    static let switcherSimpleMode = "switcherSimpleMode"
    static let switcherMergeTabs = "switcherMergeTabs"
    static let switcherWindowlessApps = "switcherWindowlessApps"
    static let switcherMinimizedPlacement = "switcherMinimizedPlacement"
    static let switcherTreatHiddenAppsLikeMinimized = "switcherTreatHiddenAppsLikeMinimized"
    static let switcherShowFullscreenWindows = "switcherShowFullscreenWindows"
    static let switcherAppRules = "switcherAppRules"
    static let switcherCurrentSpaceOnly = "switcherCurrentSpaceOnly"
    static let switcherSearchPinEnabled = "switcherSearchPinEnabled"
    static let switcherShowShortcutHints = "switcherShowShortcutHints"
    static let switcherAppearanceDelay = "switcherAppearanceDelay"
    static let switcherInstantSelection = "switcherInstantSelection"
    static let switcherScreenPlacement = "switcherScreenPlacement"
    static let switcherCurrentDisplayOnly = "switcherCurrentDisplayOnly"
    static let switcherMaxColumns = "switcherMaxColumns"
    static let minimalWindowPreviews = "switcherMinimalPreviews"
    static let dockPreviewCurrentSpaceOnly = "switcherDockPreviewCurrentSpaceOnly"
    static let switcherPreviewSize = "switcherPreviewSize"
    static let switcherPreviewExcludedApps = "switcherPreviewExcludedApps"
    static let switcherLiquidGlass = "switcherLiquidGlass"
}

enum SwitcherDefaults {
    static let finderBundleIdentifier = "com.apple.finder"
    static let allowedPreviewSizes = ["small", "normal", "large", "xlarge"]

    static func sanitizedBundleIdentifierList(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIDs {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id.lowercased()).inserted else { continue }
            result.append(id)
        }
        return result
    }

    static func registerSwitcherDefaults() {
        UserDefaults.standard.register(defaults: [
            SwitcherDefaultsKey.switcherEnabled: true,
            SwitcherDefaultsKey.switcherTakeOverSystemShortcuts: true,
            SwitcherDefaultsKey.switcherShortcut: SwitcherGlobalShortcut.switcherDefault.storageValue,
            SwitcherDefaultsKey.switcherWindowShortcut: SwitcherGlobalShortcut.switcherWindowDefault.storageValue,
            SwitcherDefaultsKey.switcherIconRowMode: false,
            SwitcherDefaultsKey.switcherSimpleMode: false,
            SwitcherDefaultsKey.switcherMergeTabs: false,
            SwitcherDefaultsKey.switcherWindowlessApps: SwitcherWindowlessApps.fallback.rawValue,
            SwitcherDefaultsKey.switcherMinimizedPlacement: SwitcherWindowSwitchMinimizedPlacement.normal.rawValue,
            SwitcherDefaultsKey.switcherTreatHiddenAppsLikeMinimized: true,
            SwitcherDefaultsKey.switcherShowFullscreenWindows: true,
            SwitcherDefaultsKey.switcherAppRules: [String: String](),
            SwitcherDefaultsKey.switcherCurrentSpaceOnly: false,
            SwitcherDefaultsKey.switcherSearchPinEnabled: false,
            SwitcherDefaultsKey.switcherShowShortcutHints: true,
            SwitcherDefaultsKey.switcherAppearanceDelay: SwitcherSupport.defaultAppearanceDelayMilliseconds,
            SwitcherDefaultsKey.switcherInstantSelection: false,
            SwitcherDefaultsKey.switcherScreenPlacement: SwitcherScreenPlacement.fallback.rawValue,
            SwitcherDefaultsKey.switcherCurrentDisplayOnly: false,
            SwitcherDefaultsKey.switcherMaxColumns: 0,
            SwitcherDefaultsKey.minimalWindowPreviews: false,
            SwitcherDefaultsKey.dockPreviewCurrentSpaceOnly: false,
            SwitcherDefaultsKey.switcherPreviewSize: "normal",
            SwitcherDefaultsKey.switcherPreviewExcludedApps: [String](),
            SwitcherDefaultsKey.switcherLiquidGlass: true,
        ])
    }
}

enum SwitcherPreviewSizing {
    static func sanitized(_ value: String) -> String {
        SwitcherDefaults.allowedPreviewSizes.contains(value) ? value : "normal"
    }

    static func scale(for value: String) -> CGFloat {
        switch sanitized(value) {
        case "small": return 0.75
        case "large": return 1.4
        case "xlarge": return 1.8
        default: return 1.0
        }
    }

    static var switcherScale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: SwitcherDefaultsKey.switcherPreviewSize) ?? "normal")
    }
}

final class SwitcherPermissions {
    static let shared = SwitcherPermissions()
    var accessibility: Bool { AXIsProcessTrusted() }
    var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
}

/// Vorssaint gates each service on its feature being installed; in Sirena the
/// switcher is available exactly while `WindowSwitcherController` is running.
enum SwitcherAppFeature {
    case switcher, windowLayout

    private static let lock = NSLock()
    nonisolated(unsafe) private static var switcherRunning = false

    static func setSwitcherRunning(_ running: Bool) {
        lock.withLock { switcherRunning = running }
    }

    var isAvailable: Bool {
        switch self {
        case .switcher: return Self.lock.withLock { Self.switcherRunning }
        case .windowLayout: return false
        }
    }
}

enum SwitcherQuitProtectionShortcut { case quit, close }

final class SwitcherQuitProtectionService {
    static let shared = SwitcherQuitProtectionService()
    struct SelectionConfirmation {
        let intervalMilliseconds: Double
        let showsFeedback: Bool
    }
    func selectionConfirmation(for shortcut: SwitcherQuitProtectionShortcut,
                               bundleIdentifier: String?) -> SelectionConfirmation? { nil }
    func showSelectionHUD(for shortcut: SwitcherQuitProtectionShortcut, on screen: NSScreen?) {}
    func hideSelectionHUD() {}
}

extension NSScreen {
    var switcherDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class SwitcherL10n: ObservableObject {
    static let shared = SwitcherL10n()
    struct Strings {
        var dockPreviewCloseWindow: String { L("Close window") }
        var panelHiddenItem: String { L("Hidden") }
        var switcherNoOpenWindow: String { L("No open window") }
        var switcherNoWindows: String { L("No open windows") }
        var switcherOtherDesktop: String { L("Other desktop") }
        var switcherSearchPin: String { L("Pin search with S") }
        var switcherShortcutHintApps: String { L("Apps") }
        var switcherShortcutHintWindows: String { L("Windows") }
    }
    var s: Strings { Strings() }
}
