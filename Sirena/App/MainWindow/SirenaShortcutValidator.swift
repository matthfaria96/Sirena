/// SirenaShortcutValidator.swift
///
/// Every shortcut recorder in Sirena refuses a combination another Sirena feature already
/// uses (window positions included), on top of MASShortcut's system and menu checks.

import AppKit
import MASShortcut

final class SirenaShortcutValidator: MASShortcutValidator {
    /// The key being recorded: its own current value is not a conflict.
    private let ownKey: String

    init(ownKey: String) {
        self.ownKey = ownKey
        super.init()
    }

    override func isShortcutAlreadyTaken(bySystem shortcut: MASShortcut!,
                                         explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        if let shortcut, let owner = Self.sirenaOwner(of: shortcut, except: ownKey) {
            explanation?.pointee = String(format: L("Sirena already uses this shortcut for “%@”."), owner) as NSString
            return true
        }
        return super.isShortcutAlreadyTaken(bySystem: shortcut, explanation: explanation)
    }

    /// Which Sirena shortcut (saved or default) uses the combination, by its readable name.
    static func sirenaOwner(of shortcut: MASShortcut, except ownKey: String) -> String? {
        let transformer = MASDictionaryTransformer()
        // Includes the registered defaults, so unchanged defaults count too.
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key != ownKey {
            guard let dict = value as? [String: Any], dict["keyCode"] != nil,
                  let other = transformer.transformedValue(dict) as? MASShortcut,
                  other.keyCode == shortcut.keyCode,
                  other.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    == shortcut.modifierFlags.intersection(.deviceIndependentFlagsMask) else { continue }
            return displayName(for: key)
        }
        return nil
    }

    private static func displayName(for key: String) -> String {
        if let action = WindowAction.active.first(where: { $0.name == key }) {
            return action.displayName ?? key
        }
        let names: [String: String] = [
            AppDelegate.openHomeShortcutKey: L("Open Sirena on Home"),
            ColorPickerController.pickShortcutKey: ModuleID.colorPicker.title,
            ScreenBrushSettings.toggleShortcutKey: ModuleID.screenBrush.title,
            PomodoroController.toggleShortcutKey: ModuleID.pomodoro.title,
            PomodoroController.skipShortcutKey: ModuleID.pomodoro.title,
            PinWindowSettings.selectShortcutKey: ModuleID.pinWindow.title,
            MirrorController.shortcutKey: ModuleID.mirror.title,
            MenuBarModule.shortcutKey: ModuleID.menuBar.title,
        ]
        if let name = names[key] { return name }
        if key.hasPrefix("textCaptureShortcut") { return ModuleID.textCapture.title }
        if key.hasPrefix("screenCaptureShortcut") { return ModuleID.screenCapture.title }
        if key.hasPrefix("shelf") { return ModuleID.shelf.title }
        if key.hasPrefix("pinWindow") { return ModuleID.pinWindow.title }
        return key
    }
}
