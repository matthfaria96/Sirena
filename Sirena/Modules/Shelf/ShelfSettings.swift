/// ShelfSettings.swift
///
/// Preferences of Shelf, the drag-and-drop shelf modeled on Yoink. Written from scratch
/// for Sirena: Yoink is closed source, only its public feature list was used.

import AppKit
import SwiftUI

/// Where the shelf appears.
enum ShelfPosition: String, CaseIterable, Identifiable {
    case leftTop, leftCenter, leftBottom, rightTop, rightCenter, rightBottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftTop: return L("Top Left Corner")
        case .leftCenter: return L("Middle of the Left Side")
        case .leftBottom: return L("Bottom Left Corner")
        case .rightTop: return L("Top Right Corner")
        case .rightCenter: return L("Middle of the Right Side")
        case .rightBottom: return L("Bottom Right Corner")
        }
    }

    var isLeft: Bool { [.leftTop, .leftCenter, .leftBottom].contains(self) }
}

/// Size of the items on the shelf.
enum ShelfItemSize: String, CaseIterable, Identifiable {
    case smallest, standard, biggest, automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smallest: return L("Smallest")
        case .standard: return L("Default (3 Files)")
        case .biggest: return L("Biggest")
        case .automatic: return L("Adjust Automatically")
        }
    }

    /// Thumbnail side for a shelf holding `count` items.
    func side(for count: Int) -> CGFloat {
        switch self {
        case .smallest: return 48
        case .standard: return 76
        case .biggest: return 112
        case .automatic: return count <= 3 ? 76 : count <= 6 ? 60 : 48
        }
    }
}

/// Key that, held during a drag, keeps the shelf from appearing.
enum ShelfSuppressKey: String, CaseIterable, Identifiable {
    case none, function, shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L("None")
        case .function: return L("fn key")
        case .shift: return L("shift key")
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .none: return nil
        case .function: return .function
        case .shift: return .shift
        }
    }
}

@Observable
final class ShelfSettings {
    static let shared = ShelfSettings()

    /// Shortcut keys (MASShortcut). No dots: the binder reaches them through a key path.
    static let toggleShortcutKey = "shelfShortcutToggle"
    static let addClipboardShortcutKey = "shelfShortcutAddClipboard"

    private let defaults = UserDefaults.standard

    var position: ShelfPosition { didSet { save(position.rawValue, "shelf.position") } }
    /// Show the shelf next to the pointer when a drag starts, instead of at the edge.
    var showAtCursor: Bool { didSet { save(showAtCursor, "shelf.showAtCursor") } }
    /// Only show it once the drag reaches the screen edge it sits on.
    var showOnlyAtEdge: Bool { didSet { save(showOnlyAtEdge, "shelf.showOnlyAtEdge") } }
    var suppressKey: ShelfSuppressKey { didSet { save(suppressKey.rawValue, "shelf.suppressKey") } }
    /// Bundle identifiers of apps in which dragging never shows the shelf.
    var ignoredApps: [String] { didSet { save(ignoredApps, "shelf.ignoredApps") } }
    var itemSize: ShelfItemSize { didSet { save(itemSize.rawValue, "shelf.itemSize") } }
    /// Quick Look previews instead of plain file icons.
    var showPreviews: Bool { didSet { save(showPreviews, "shelf.showPreviews") } }
    /// Dragging an item out of the shelf takes it off the shelf.
    var removeAfterDragOut: Bool { didSet { save(removeAfterDragOut, "shelf.removeAfterDragOut") } }
    /// Aliases dropped on the shelf are replaced by their originals.
    var resolveAliases: Bool { didSet { save(resolveAliases, "shelf.resolveAliases") } }

    private init() {
        position = ShelfPosition(rawValue: defaults.string(forKey: "shelf.position") ?? "") ?? .leftCenter
        showAtCursor = defaults.object(forKey: "shelf.showAtCursor") as? Bool ?? false
        showOnlyAtEdge = defaults.object(forKey: "shelf.showOnlyAtEdge") as? Bool ?? false
        suppressKey = ShelfSuppressKey(rawValue: defaults.string(forKey: "shelf.suppressKey") ?? "") ?? .function
        ignoredApps = defaults.stringArray(forKey: "shelf.ignoredApps") ?? []
        itemSize = ShelfItemSize(rawValue: defaults.string(forKey: "shelf.itemSize") ?? "") ?? .standard
        showPreviews = defaults.object(forKey: "shelf.showPreviews") as? Bool ?? true
        removeAfterDragOut = defaults.object(forKey: "shelf.removeAfterDragOut") as? Bool ?? true
        resolveAliases = defaults.object(forKey: "shelf.resolveAliases") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .shelfSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let shelfSettingsChanged = Notification.Name("sirena.shelfSettingsChanged")
}
