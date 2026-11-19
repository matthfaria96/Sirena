/// DockPreferences.swift
///
/// Ajustes › Dock: the Dock's own preferences (`com.apple.dock`), read and written through
/// CFPreferences, then the Dock is restarted so it reads them again. Spacers are tiles in
/// `persistent-apps`; behaviour options are plain keys. Before the first change Sirena saves a
/// copy of the whole domain (`defaults export`), which "Restore" puts back.

import AppKit
import OSLog

/// One tile on the apps side of the Dock, in its order.
struct DockTile: Identifiable, Equatable {
    enum Kind: Equatable { case app, spacer, smallSpacer, other }

    /// Its index in `persistent-apps` (stable until the next reload).
    let id: Int
    let kind: Kind
    let label: String
    let path: String?

    var isSpacer: Bool { kind == .spacer || kind == .smallSpacer }
}

/// A Dock option Sirena offers, stored by the Dock itself.
enum DockOption: String, CaseIterable, Identifiable {
    case autohide
    case instantReveal
    case staticOnly
    case showHidden
    case showRecents
    case launchAnimation
    case lockContents
    case lockSize

    var id: String { rawValue }

    var key: String {
        switch self {
        case .autohide: return "autohide"
        case .instantReveal: return "autohide-delay"
        case .staticOnly: return "static-only"
        case .showHidden: return "showhidden"
        case .showRecents: return "show-recents"
        case .launchAnimation: return "launchanim"
        case .lockContents: return "contents-immutable"
        case .lockSize: return "size-immutable"
        }
    }

    /// What macOS does when the key was never written.
    var macOSDefault: Bool {
        switch self {
        case .showRecents, .launchAnimation: return true
        default: return false
        }
    }
}

/// How fast the hidden Dock slides in and out (`autohide-time-modifier`).
enum DockAnimationSpeed: String, CaseIterable, Identifiable {
    case normal, fast, instant
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return L("Normal")
        case .fast: return L("Fast")
        case .instant: return L("Instant")
        }
    }

    /// nil: the key is removed (macOS's own speed).
    var value: Double? {
        switch self {
        case .normal: return nil
        case .fast: return 0.15
        case .instant: return 0
        }
    }
}

@MainActor
@Observable
final class DockPreferences {
    static let shared = DockPreferences()

    private static let domain = "com.apple.dock" as CFString
    private static let spacerType = "spacer-tile"
    private static let smallSpacerType = "small-spacer-tile"
    private static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "Adjustments")

    private(set) var tiles: [DockTile] = []
    /// Bumped on every write, so views reading options refresh.
    private(set) var revision = 0
    private(set) var backupDate: Date?

    private var restartWork: DispatchWorkItem?

    private init() {
        backupDate = Self.backupDateOnDisk()
    }

    var spacerCount: Int { tiles.filter(\.isSpacer).count }

    // MARK: - Reading

    /// Reads the apps side of the Dock again (the user may have moved things since).
    func reload() {
        CFPreferencesAppSynchronize(Self.domain)
        let raw = Self.persistentApps()
        tiles = raw.enumerated().map { index, tile in
            let type = tile["tile-type"] as? String
            let data = tile["tile-data"] as? [String: Any] ?? [:]
            let label = data["file-label"] as? String ?? ""
            let url = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String
            let path = url.flatMap { URL(string: $0)?.path }
            let kind: DockTile.Kind
            switch type {
            case Self.spacerType: kind = .spacer
            case Self.smallSpacerType: kind = .smallSpacer
            case "file-tile": kind = .app
            default: kind = .other
            }
            return DockTile(id: index, kind: kind, label: label, path: path)
        }
    }

    func isOn(_ option: DockOption) -> Bool {
        _ = revision
        if option == .instantReveal {
            return (Self.value("autohide-delay") as? NSNumber)?.doubleValue == 0
        }
        return (Self.value(option.key) as? NSNumber)?.boolValue ?? option.macOSDefault
    }

    var animationSpeed: DockAnimationSpeed {
        _ = revision
        guard let value = (Self.value("autohide-time-modifier") as? NSNumber)?.doubleValue else { return .normal }
        if value == 0 { return .instant }
        return value < 0.4 ? .fast : .normal
    }

    // MARK: - Writing

    func set(_ option: DockOption, _ on: Bool) {
        if option == .instantReveal {
            write(["autohide-delay": on ? NSNumber(value: 0.0) : nil])
        } else {
            // Back to macOS's default: remove the key instead of writing it.
            write([option.key: on == option.macOSDefault ? nil : NSNumber(value: on)])
        }
    }

    func setAnimationSpeed(_ speed: DockAnimationSpeed) {
        write(["autohide-time-modifier": speed.value.map { NSNumber(value: $0) }])
    }

    /// Puts a spacer right before the tile at `index` (at the end when `index` is past it).
    func insertSpacer(small: Bool, at index: Int) {
        reload()
        var apps = Self.persistentApps()
        let tile: [String: Any] = ["tile-data": [String: Any](), "tile-type": small ? Self.smallSpacerType : Self.spacerType]
        apps.insert(tile, at: min(max(index, 0), apps.count))
        write(["persistent-apps": apps])
    }

    func removeSpacer(at index: Int) {
        reload()
        var apps = Self.persistentApps()
        guard apps.indices.contains(index),
              let type = apps[index]["tile-type"] as? String,
              type == Self.spacerType || type == Self.smallSpacerType else { return }
        apps.remove(at: index)
        write(["persistent-apps": apps])
    }

    func removeAllSpacers() {
        reload()
        let apps = Self.persistentApps().filter {
            let type = $0["tile-type"] as? String
            return type != Self.spacerType && type != Self.smallSpacerType
        }
        write(["persistent-apps": apps])
    }

    private func write(_ values: [String: Any?]) {
        // Screenshots for the site never touch the real Dock.
        guard !Showcase.isActive else { return }
        ensureBackup()
        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFPropertyList }, Self.domain)
        }
        CFPreferencesAppSynchronize(Self.domain)
        revision += 1
        reload()
        scheduleDockRestart()
    }

    /// Several changes in a row restart the Dock once.
    private func scheduleDockRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { Self.restartDock() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private nonisolated static func restartDock() {
        DispatchQueue.global(qos: .userInitiated).async {
            run("/usr/bin/killall", ["Dock"])
        }
    }

    // MARK: - Backup

    private static var backupURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("Sirena", isDirectory: true).appendingPathComponent("Dock backup.plist")
    }

    private static func backupDateOnDisk() -> Date? {
        guard let url = backupURL else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The first change keeps a copy of the Dock as it was.
    private func ensureBackup() {
        guard backupDate == nil else { return }
        saveBackup()
    }

    /// Replaces the copy with the Dock as it is now.
    func saveBackup() {
        guard let url = Self.backupURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        CFPreferencesAppSynchronize(Self.domain)
        if Self.run("/usr/bin/defaults", ["export", "com.apple.dock", url.path]) {
            backupDate = Self.backupDateOnDisk()
            Self.log.notice("Dock preferences saved")
        }
    }

    /// Puts the saved copy back and restarts the Dock.
    func restoreBackup() {
        guard !Showcase.isActive, let url = Self.backupURL, FileManager.default.fileExists(atPath: url.path) else { return }
        if Self.run("/usr/bin/defaults", ["import", "com.apple.dock", url.path]) {
            CFPreferencesAppSynchronize(Self.domain)
            revision += 1
            reload()
            scheduleDockRestart()
            Self.log.notice("Dock preferences restored")
        }
    }

    // MARK: - Helpers

    private static func persistentApps() -> [[String: Any]] {
        value("persistent-apps") as? [[String: Any]] ?? []
    }

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
