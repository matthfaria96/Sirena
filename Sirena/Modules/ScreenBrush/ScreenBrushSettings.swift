/// ScreenBrushSettings.swift
///
/// Preferences of Desenho Livre (UserDefaults, keys prefixed `screenBrush.`).

import Foundation

@MainActor
@Observable
final class ScreenBrushSettings {
    static let shared = ScreenBrushSettings()

    /// No dots: the shortcut binder reaches the key through a key path.
    static let toggleShortcutKey = "screenBrushShortcutToggle"

    enum ScreenshotAction: String, CaseIterable, Identifiable {
        case copy, save, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .copy: return L("Copy to Clipboard")
            case .save: return L("Save to Screenshots")
            case .both: return L("Copy and Save to Screenshots")
            }
        }
    }

    /// What a screenshot takes: an area the user picks (like ⇧⌘4) or the whole screen.
    enum ScreenshotArea: String, CaseIterable, Identifiable {
        case selection, fullScreen
        var id: String { rawValue }
        var title: String {
            switch self {
            case .selection: return L("Selected area")
            case .fullScreen: return L("Whole screen")
            }
        }
    }

    private let defaults = UserDefaults.standard

    var tool: BrushTool { didSet { defaults.set(tool.rawValue, forKey: "screenBrush.tool") } }
    var colorIndex: Int { didSet { defaults.set(colorIndex, forKey: "screenBrush.color") } }
    var width: Double { didSet { defaults.set(width, forKey: "screenBrush.width") } }
    var fillShapes: Bool { didSet { defaults.set(fillShapes, forKey: "screenBrush.fillShapes") } }
    /// Keep the drawing when leaving drawing mode, to show it again next time.
    var keepStrokes: Bool { didSet { defaults.set(keepStrokes, forKey: "screenBrush.keepStrokes") } }
    /// Draw on every display, or only on the one with the pointer.
    var allScreens: Bool { didSet { defaults.set(allScreens, forKey: "screenBrush.allScreens") } }
    var showToolbar: Bool { didSet { defaults.set(showToolbar, forKey: "screenBrush.showToolbar") } }
    /// Seconds a laser stroke stays before fading.
    var laserDelay: Double { didSet { defaults.set(laserDelay, forKey: "screenBrush.laserDelay") } }
    var spotlightRadius: Double { didSet { defaults.set(spotlightRadius, forKey: "screenBrush.spotlightRadius") } }
    var screenshotAction: ScreenshotAction { didSet { defaults.set(screenshotAction.rawValue, forKey: "screenBrush.screenshotAction") } }
    var screenshotArea: ScreenshotArea { didSet { defaults.set(screenshotArea.rawValue, forKey: "screenBrush.screenshotArea") } }

    private init() {
        let d = UserDefaults.standard
        tool = BrushTool(rawValue: d.string(forKey: "screenBrush.tool") ?? "").flatMap { BrushTool.available.contains($0) ? $0 : nil } ?? .pen
        colorIndex = d.object(forKey: "screenBrush.color") as? Int ?? 0
        width = d.object(forKey: "screenBrush.width") as? Double ?? 4
        fillShapes = d.bool(forKey: "screenBrush.fillShapes")
        keepStrokes = d.bool(forKey: "screenBrush.keepStrokes")
        allScreens = d.object(forKey: "screenBrush.allScreens") as? Bool ?? true
        showToolbar = d.object(forKey: "screenBrush.showToolbar") as? Bool ?? true
        laserDelay = d.object(forKey: "screenBrush.laserDelay") as? Double ?? 1.5
        spotlightRadius = d.object(forKey: "screenBrush.spotlightRadius") as? Double ?? 140
        screenshotAction = ScreenshotAction(rawValue: d.string(forKey: "screenBrush.screenshotAction") ?? "") ?? .both
        screenshotArea = ScreenshotArea(rawValue: d.string(forKey: "screenBrush.screenshotArea") ?? "") ?? .selection
    }
}
