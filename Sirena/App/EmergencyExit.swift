/// EmergencyExit.swift
///
/// ⌃⌥⇧⌘⎋ quits Sirena from any app: a way out if a feature ever misbehaves (0.5.2 froze the
/// Mac when Accessibility was revoked). Every event tap is switched off first, then Sirena quits
/// normally so the modules put things back; if quitting hangs, it leaves anyway after 2 s.
/// Not ⌃⌥⇧⌘Q: missing ⌃ there gives ⌥⇧⌘Q, which logs out without asking. Missing keys here
/// give at worst ⌥⌘⎋, the Force Quit window. The shortcut is fixed so it is always known.

import AppKit
import DockKit
import MASShortcut

@MainActor
enum EmergencyExit {
    static let keyCode = 53 // kVK_Escape
    static let modifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let symbols = "⌃⌥⇧⌘⎋"

    static func register() {
        let shortcut = MASShortcut(keyCode: keyCode, modifierFlags: modifiers)
        MASShortcutMonitor.shared().register(shortcut) { run() }
    }

    static func run() {
        AccessibilityGuard.shared.disableAllTaps()
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 2) { exit(0) }
        NSApp.terminate(nil)
    }

    /// Whether a shortcut someone is recording is this one (it can't be given to anything else).
    nonisolated static func matches(_ shortcut: MASShortcut) -> Bool {
        shortcut.keyCode == keyCode
            && shortcut.modifierFlags.intersection(.deviceIndependentFlagsMask)
                == modifiers.intersection(.deviceIndependentFlagsMask)
    }
}
