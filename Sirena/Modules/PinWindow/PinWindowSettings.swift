/// PinWindowSettings.swift
///
/// Preferences of Pin Window, the "keep this window on top" feature modeled on Floaty.
/// Written from scratch for Sirena: Floaty is closed source, only its public feature
/// list was used.

import AppKit
import SwiftUI

/// How a pinned window hands control back to the real window under it.
enum PinActivationMode: String, CaseIterable, Identifiable {
    /// Click the pinned window to use it.
    case click
    /// Rest the pointer over the pinned window to use it.
    case hover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return L("Click")
        case .hover: return L("Hover")
        }
    }
}

/// Where the pin control sits on a window that has no traffic lights.
enum PinControlPosition: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return L("Top Left")
        case .topRight: return L("Top Right")
        case .bottomLeft: return L("Bottom Left")
        case .bottomRight: return L("Bottom Right")
        }
    }

    private static let key = "pinWindow.controlPositions"

    /// The position chosen for an app's windows, remembered across launches.
    static func saved(for bundleID: String?) -> PinControlPosition {
        guard let bundleID, let stored = UserDefaults.standard.dictionary(forKey: key)?[bundleID] as? String else { return .topLeft }
        return PinControlPosition(rawValue: stored) ?? .topLeft
    }

    static func save(_ position: PinControlPosition, for bundleID: String?) {
        guard let bundleID else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[bundleID] = position.rawValue
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// Choices offered for "Unpin in", in minutes (0 = never).
enum PinAutoUnpin {
    static let choices = [0, 5, 15, 30, 60, 120]

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: return L("Never")
        case 60: return L("1 hour")
        case 120: return L("2 hours")
        default: return L("\(minutes) minutes")
        }
    }
}

@Observable
final class PinWindowSettings {
    static let shared = PinWindowSettings()

    /// Shortcut keys (MASShortcut, stored by the binder). The binder reaches them
    /// through a key path, so they must not contain dots.
    static let selectShortcutKey = "pinWindowShortcutSelect"
    static let toggleFrontShortcutKey = "pinWindowShortcutToggleFront"
    static let unpinAllShortcutKey = "pinWindowShortcutUnpinAll"

    private let defaults = UserDefaults.standard

    var activationMode: PinActivationMode { didSet { save(activationMode.rawValue, "pinWindow.activationMode") } }
    /// Opacity given to a window when it gets pinned (0.2 … 1).
    var defaultOpacity: Double { didSet { save(defaultOpacity, "pinWindow.defaultOpacity") } }
    var shakeToPin: Bool { didSet { save(shakeToPin, "pinWindow.shakeToPin") } }
    /// Pinned windows stay visible on every Space.
    var allSpaces: Bool { didSet { save(allSpaces, "pinWindow.allSpaces") } }
    /// Minutes after which a new pin removes itself (0 = never).
    var autoUnpinMinutes: Int { didSet { save(autoUnpinMinutes, "pinWindow.autoUnpinMinutes") } }

    private init() {
        activationMode = PinActivationMode(rawValue: defaults.string(forKey: "pinWindow.activationMode") ?? "") ?? .click
        defaultOpacity = defaults.object(forKey: "pinWindow.defaultOpacity") as? Double ?? 1
        shakeToPin = defaults.object(forKey: "pinWindow.shakeToPin") as? Bool ?? false
        allSpaces = defaults.object(forKey: "pinWindow.allSpaces") as? Bool ?? true
        autoUnpinMinutes = defaults.object(forKey: "pinWindow.autoUnpinMinutes") as? Int ?? 0
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .pinWindowSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let pinWindowSettingsChanged = Notification.Name("sirena.pinWindowSettingsChanged")
}
