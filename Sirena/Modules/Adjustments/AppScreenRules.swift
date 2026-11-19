/// AppScreenRules.swift
///
/// Ajustes › Monitores: "this app opens on that display". The rules (one per app) are kept in
/// UserDefaults as JSON; `AppScreenEngine` applies them.

import AppKit

struct AppScreenRule: Codable, Identifiable, Equatable {
    var bundleID: String
    /// The display's hardware UUID (`ScreenIdentity`).
    var screenID: String
    /// Its name when the rule was made, shown while it's not connected.
    var screenName: String
    var mode: AppScreenPlacementMode = .keep
    /// Only the windows that open in the first seconds after the app starts.
    var onlyAtLaunch = false

    var id: String { bundleID }
}

@MainActor
@Observable
final class AppScreenRules {
    static let shared = AppScreenRules()
    static let key = "adjustments.appScreens.rules"

    var rules: [AppScreenRule] {
        didSet {
            guard rules != oldValue else { return }
            if let data = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
            AppScreenEngine.shared.rulesChanged()
        }
    }

    private init() {
        rules = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([AppScreenRule].self, from: $0) } ?? []
    }

    func add(bundleID: String, screen: NSScreen) {
        guard !rules.contains(where: { $0.bundleID == bundleID }) else { return }
        rules.append(AppScreenRule(bundleID: bundleID, screenID: ScreenIdentity.identifier(of: screen),
                                   screenName: screen.localizedName))
    }

    func remove(_ bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
    }

    func update(_ rule: AppScreenRule) {
        guard let index = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) else { return }
        rules[index] = rule
    }
}

/// Displays by hardware UUID: the same display keeps it across reboots and reconnections
/// (CGDirectDisplayID doesn't). Same scheme as DockKit's `NSScreen.uniqueIdentifier`.
enum ScreenIdentity {
    static func identifier(of screen: NSScreen) -> String {
        guard let id = displayID(of: screen) else { return screen.localizedName }
        return identifier(of: id) ?? screen.localizedName
    }

    static func identifier(of display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(withIdentifier identifier: String) -> NSScreen? {
        NSScreen.screens.first { Self.identifier(of: $0) == identifier }
    }
}
