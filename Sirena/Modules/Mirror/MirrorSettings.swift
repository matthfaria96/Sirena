/// MirrorSettings.swift
///
/// Preferences of the camera mirror. The mirror works like a hand mirror kept in the
/// menu bar: click the icon and your camera drops down below it.

import AppKit
import SwiftUI

enum MirrorDisplayMode: String, CaseIterable, Identifiable {
    /// Drops down below the menu bar icon and closes when you click elsewhere.
    case popover
    /// A floating window that stays where you put it, above other windows.
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popover: return L("Below the menu bar icon")
        case .window: return L("Floating window")
        }
    }
}

enum MirrorSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return L("Small")
        case .medium: return L("Medium")
        case .large: return L("Large")
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 260
        case .medium: return 360
        case .large: return 500
        }
    }
}

enum MirrorShape: String, CaseIterable, Identifiable {
    case rounded, circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return L("Rectangle")
        case .circle: return L("Circle")
        }
    }
}

enum MirrorTriggerDisplay: String, CaseIterable, Identifiable {
    case main, mouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return L("Main display")
        case .mouse: return L("Display with the pointer")
        }
    }
}

/// Menu bar icon styles (SF Symbols).
enum MirrorIconStyle: String, CaseIterable, Identifiable {
    case aperture = "camera.aperture"
    case webcam = "web.camera"
    case person = "person.crop.circle"
    case face = "face.smiling"
    case eye = "eye"
    case camera = "camera"
    case video = "video"
    case viewfinder = "viewfinder"
    case hand = "hand.raised"
    case sparkles = "sparkles"
    case circle = "circle.circle"

    var id: String { rawValue }
}

@Observable
final class MirrorSettings {
    static let shared = MirrorSettings()

    private let defaults = UserDefaults.standard

    var displayMode: MirrorDisplayMode { didSet { save(displayMode.rawValue, "mirror.displayMode") } }
    var size: MirrorSize { didSet { save(size.rawValue, "mirror.size") } }
    var shape: MirrorShape { didSet { save(shape.rawValue, "mirror.shape") } }
    var mirrored: Bool { didSet { save(mirrored, "mirror.mirrored") } }
    var zoom: Double { didSet { save(zoom, "mirror.zoom") } }
    var iconStyle: MirrorIconStyle { didSet { save(iconStyle.rawValue, "mirror.iconStyle") } }
    var snapsEnabled: Bool { didSet { save(snapsEnabled, "mirror.snapsEnabled") } }
    var snapsCopyToClipboard: Bool { didSet { save(snapsCopyToClipboard, "mirror.snapsCopyToClipboard") } }
    var snapsFolder: URL { didSet { save(snapsFolder.path, "mirror.snapsFolder") } }
    var notchTrigger: Bool { didSet { save(notchTrigger, "mirror.notchTrigger") } }
    var triggerDisplay: MirrorTriggerDisplay { didSet { save(triggerDisplay.rawValue, "mirror.triggerDisplay") } }
    var showMicrophoneLevel: Bool { didSet { save(showMicrophoneLevel, "mirror.showMicrophoneLevel") } }
    var cameraID: String? { didSet { defaults.set(cameraID, forKey: "mirror.cameraID") } }

    private init() {
        displayMode = MirrorDisplayMode(rawValue: defaults.string(forKey: "mirror.displayMode") ?? "") ?? .popover
        size = MirrorSize(rawValue: defaults.string(forKey: "mirror.size") ?? "") ?? .medium
        shape = MirrorShape(rawValue: defaults.string(forKey: "mirror.shape") ?? "") ?? .rounded
        mirrored = defaults.object(forKey: "mirror.mirrored") as? Bool ?? true
        zoom = defaults.object(forKey: "mirror.zoom") as? Double ?? 1
        iconStyle = MirrorIconStyle(rawValue: defaults.string(forKey: "mirror.iconStyle") ?? "") ?? .aperture
        snapsEnabled = defaults.object(forKey: "mirror.snapsEnabled") as? Bool ?? true
        snapsCopyToClipboard = defaults.object(forKey: "mirror.snapsCopyToClipboard") as? Bool ?? false
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        snapsFolder = defaults.string(forKey: "mirror.snapsFolder").map { URL(fileURLWithPath: $0) } ?? pictures
        notchTrigger = defaults.object(forKey: "mirror.notchTrigger") as? Bool ?? false
        triggerDisplay = MirrorTriggerDisplay(rawValue: defaults.string(forKey: "mirror.triggerDisplay") ?? "") ?? .mouse
        showMicrophoneLevel = defaults.object(forKey: "mirror.showMicrophoneLevel") as? Bool ?? false
        cameraID = defaults.string(forKey: "mirror.cameraID")
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .mirrorSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let mirrorSettingsChanged = Notification.Name("sirena.mirrorSettingsChanged")
}
