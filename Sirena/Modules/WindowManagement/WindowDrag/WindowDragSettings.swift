/// WindowDragSettings.swift
///
/// Janelas › Arrastar de qualquer lugar: hold a key and drag anywhere on a window to move it,
/// drag with the right button to resize it from the nearest corner, double-click to maximize.
/// Ported from AnyDrag (Xueshi Qiao, GPL-3.0, https://github.com/XueshiQiao/AnyDrag).
///
/// The tap reads a snapshot (`WindowDragSnapshot.current`), refreshed on the main thread when
/// a default changes: never UserDefaults or AppKit state from the tap thread per event.

import AppKit

/// The key held to move or resize.
enum WindowDragModifier: Int, CaseIterable, Identifiable {
    case controlCommand = 0
    case option = 1
    case controlOption = 2
    case optionCommand = 3
    case controlOptionCommand = 4

    var id: Int { rawValue }

    var flags: CGEventFlags {
        switch self {
        case .controlCommand: return [.maskControl, .maskCommand]
        case .option: return [.maskAlternate]
        case .controlOption: return [.maskControl, .maskAlternate]
        case .optionCommand: return [.maskAlternate, .maskCommand]
        case .controlOptionCommand: return [.maskControl, .maskAlternate, .maskCommand]
        }
    }

    var symbol: String {
        switch self {
        case .controlCommand: return "⌃⌘"
        case .option: return "⌥"
        case .controlOption: return "⌃⌥"
        case .optionCommand: return "⌥⌘"
        case .controlOptionCommand: return "⌃⌥⌘"
        }
    }
}

enum WindowDragSettings {
    static let enabledKey = "windowDrag.enabled"
    static let modifierKey = "windowDrag.modifier"
    static let resizeKey = "windowDrag.resize"
    static let maximizeKey = "windowDrag.doubleClickMaximize"
    static let bottomRightKey = "windowDrag.bottomRightOnly"
    static let excludedKey = "windowDrag.excludedApps"

    static let enabledDefault = false
    /// ⌃⌘: ⌥-drag already means something in many apps (column selection in editors,
    /// duplicating in the Finder and design apps); ⌃⌘-drag means nothing almost anywhere.
    static let modifierDefault = WindowDragModifier.controlCommand
    static let resizeDefault = true
    static let maximizeDefault = true
    static let bottomRightDefault = false
}

/// What the tap needs, copied on the main thread.
struct WindowDragSnapshot {
    var enabled = WindowDragSettings.enabledDefault
    var modifier = WindowDragSettings.modifierDefault
    var resize = WindowDragSettings.resizeDefault
    var maximize = WindowDragSettings.maximizeDefault
    var bottomRightOnly = WindowDragSettings.bottomRightDefault
    var excluded: Set<String> = []

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = WindowDragSnapshot()

    static var current: WindowDragSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    static func refresh() {
        let defaults = UserDefaults.standard
        var snapshot = WindowDragSnapshot()
        snapshot.enabled = defaults.object(forKey: WindowDragSettings.enabledKey) as? Bool ?? WindowDragSettings.enabledDefault
        snapshot.modifier = (defaults.object(forKey: WindowDragSettings.modifierKey) as? Int)
            .flatMap(WindowDragModifier.init(rawValue:)) ?? WindowDragSettings.modifierDefault
        snapshot.resize = defaults.object(forKey: WindowDragSettings.resizeKey) as? Bool ?? WindowDragSettings.resizeDefault
        snapshot.maximize = defaults.object(forKey: WindowDragSettings.maximizeKey) as? Bool ?? WindowDragSettings.maximizeDefault
        snapshot.bottomRightOnly = defaults.object(forKey: WindowDragSettings.bottomRightKey) as? Bool ?? WindowDragSettings.bottomRightDefault
        snapshot.excluded = Set(defaults.stringArray(forKey: WindowDragSettings.excludedKey) ?? [])
        lock.lock()
        stored = snapshot
        lock.unlock()
    }
}
