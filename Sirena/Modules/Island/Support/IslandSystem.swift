// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena: Space topology (from SpaceWindowBridge.swift) and grid
// keyboard navigation (from QuickToolsSupport.swift), as the island uses them.

import AppKit

enum IslandSpaces {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    struct Topology {
        struct DisplayInfo {
            let displayID: CGDirectDisplayID?
            let spaces: [UInt64]
            let fullscreenSpaces: Set<UInt64>
            let currentSpace: UInt64?
        }

        /// With separate Spaces, only the island's display controls visibility.
        /// A shared Space applies to every display even if its UUID is absent.
        func isFullscreen(on displayID: CGDirectDisplayID, separateSpaces: Bool) -> Bool {
            let candidates = separateSpaces ? displays.filter { $0.displayID == displayID } : displays
            return candidates.contains { display in
                display.currentSpace.map { display.fullscreenSpaces.contains($0) } == true
            }
        }

        /// Displays in order.
        let displays: [DisplayInfo]
        /// Space ids in left-to-right order, one row per display.
        var orderedSpacesPerDisplay: [[UInt64]] { displays.map(\.spaces) }
        /// The Space currently showing on each display.
        var visibleSpaces: Set<UInt64> { Set(displays.compactMap(\.currentSpace)) }
        /// Native fullscreen Spaces. Managed-display dictionaries use type 4
        /// for these and type 0 for ordinary desktops on current macOS.
        var fullscreenSpaces: Set<UInt64> {
            displays.reduce(into: []) { $0.formUnion($1.fullscreenSpaces) }
        }
    }

    /// Captures AppKit's display identity while the caller is on main. The
    /// resulting values are safe to carry to window-enumeration workers.
    static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
        var map: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                  let uuidStr = CFUUIDCreateString(nil, uuid) as String?
            else { continue }
            map[uuidStr] = screenNum
        }
        return map
    }

    /// Main-thread callers can keep using the AppKit-backed display mapping.
    static func topology() -> Topology? {
        topology(displayIDsByUUID: displayIDsByUUID())
    }

    /// Resolves Space topology using display values captured by the caller.
    /// This overload does not access AppKit and is safe for worker queues.
    static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return nil }

        var displays: [Topology.DisplayInfo] = []
        for display in displayDicts {
            let spaceDictionaries = display["Spaces"] as? [[String: Any]] ?? []
            let row = spaceDictionaries
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            guard !row.isEmpty else { continue }
            let fullscreenSpaces = Set(spaceDictionaries.compactMap { space -> UInt64? in
                guard (space["type"] as? NSNumber)?.intValue == 4 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            })
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let uuidStr = display["Display Identifier"] as? String
            let displayID = uuidStr.flatMap { displayIDsByUUID[$0] }
            displays.append(Topology.DisplayInfo(displayID: displayID,
                                                 spaces: row,
                                                 fullscreenSpaces: fullscreenSpaces,
                                                 currentSpace: current?.uint64Value))
        }
        guard !displays.isEmpty else { return nil }
        return Topology(displays: displays)
    }
}

enum NotchGridDirection {
    case up, down, left, right
}

/// Which way a grid fills: row by row with a fixed column count, or column by
/// column with a fixed row count, as a rail in the island does.
enum NotchGridFlow: Equatable {
    case rows(columns: Int)
    case columns(rows: Int)
}

enum NotchGrid {
    /// Keyboard navigation over a row-major grid: arrows move by one cell,
    /// clamped to the existing items, never wrapping from one edge to the other.
    static func index(after index: Int, count: Int, columns: Int, direction: NotchGridDirection) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        let candidate: Int
        switch direction {
        case .left: candidate = current - 1
        case .right: candidate = current + 1
        case .up: candidate = current - columns
        case .down: candidate = current + columns
        }
        guard candidate >= 0, candidate < count else { return current }
        if direction == .left, current % columns == 0 { return current }
        if direction == .right, current % columns == columns - 1 { return current }
        return candidate
    }

    /// A column-major rail is the row-major walk with the axes swapped.
    static func index(after index: Int, count: Int, flow: NotchGridFlow, direction: NotchGridDirection) -> Int {
        switch flow {
        case .rows(let columns):
            return Self.index(after: index, count: count, columns: columns, direction: direction)
        case .columns(let rows):
            let transposed: NotchGridDirection
            switch direction {
            case .up: transposed = .left
            case .down: transposed = .right
            case .left: transposed = .up
            case .right: transposed = .down
            }
            return Self.index(after: index, count: count, columns: max(1, rows), direction: transposed)
        }
    }
}
