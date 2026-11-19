/// SettingsShortcuts.swift
///
/// Ajustes › Permissões and Ajustes › Sistema: one click to the System Settings pane people
/// actually look for. Sirena can't grant permissions (only macOS asks the user); it opens the
/// exact list where an app is switched on.
///
/// Panes are addressed by their extension's bundle id (System Settings, macOS 13+); privacy
/// lists by their `Privacy_…` anchor. Check them on the oldest supported macOS when adding one:
/// `ls /System/Library/ExtensionKit/Extensions` lists the panes of the Mac at hand.

import AppKit

struct SettingsShortcut: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let url: String
    /// Opened as an app instead (Passwords).
    var appBundleID: String?

    func open() {
        if let appBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

enum SettingsShortcuts {
    private static func privacy(_ anchor: String) -> String {
        "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }

    private static func pane(_ id: String) -> String {
        "x-apple.systempreferences:\(id)"
    }

    /// Privacy & Security, list by list: what each permission lets an app do.
    static var permissions: [SettingsShortcut] {
        [
            SettingsShortcut(id: "accessibility", title: L("Accessibility"),
                             detail: L("Control the Mac: move windows, read the screen's buttons, press keys."),
                             symbol: "accessibility", url: privacy("Privacy_Accessibility")),
            SettingsShortcut(id: "screen", title: L("Screen & System Audio Recording"),
                             detail: L("See and record what is on the screen: screenshots, sharing in calls, previews."),
                             symbol: "rectangle.dashed.badge.record", url: privacy("Privacy_ScreenCapture")),
            SettingsShortcut(id: "disk", title: L("Full Disk Access"),
                             detail: L("Read every file, including Mail, Messages and other apps' data."),
                             symbol: "internaldrive", url: privacy("Privacy_AllFiles")),
            SettingsShortcut(id: "input", title: L("Input Monitoring"),
                             detail: L("Watch the keyboard and mouse even when the app is in the background."),
                             symbol: "keyboard", url: privacy("Privacy_ListenEvent")),
            SettingsShortcut(id: "automation", title: L("Automation"),
                             detail: L("Control other apps, like Finder, Music or Safari."),
                             symbol: "gearshape.2", url: privacy("Privacy_Automation")),
            SettingsShortcut(id: "files", title: L("Files & Folders"),
                             detail: L("Desktop, Documents, Downloads and external drives."),
                             symbol: "folder", url: privacy("Privacy_FilesAndFolders")),
            SettingsShortcut(id: "camera", title: L("Camera"), detail: L("Use the camera."),
                             symbol: "camera", url: privacy("Privacy_Camera")),
            SettingsShortcut(id: "microphone", title: L("Microphone"), detail: L("Use the microphone."),
                             symbol: "mic", url: privacy("Privacy_Microphone")),
            SettingsShortcut(id: "location", title: L("Location Services"), detail: L("Know where the Mac is."),
                             symbol: "location", url: privacy("Privacy_LocationServices")),
            SettingsShortcut(id: "bluetooth", title: L("Bluetooth"), detail: L("Find and connect to Bluetooth devices."),
                             symbol: "wave.3.right", url: privacy("Privacy_Bluetooth")),
            SettingsShortcut(id: "contacts", title: L("Contacts"), detail: L("Read and change your contacts."),
                             symbol: "person.crop.circle", url: privacy("Privacy_Contacts")),
            SettingsShortcut(id: "calendars", title: L("Calendars"), detail: L("Read and change your events."),
                             symbol: "calendar", url: privacy("Privacy_Calendars")),
            SettingsShortcut(id: "reminders", title: L("Reminders"), detail: L("Read and change your reminders."),
                             symbol: "checklist", url: privacy("Privacy_Reminders")),
            SettingsShortcut(id: "photos", title: L("Photos"), detail: L("See your photo library."),
                             symbol: "photo.on.rectangle", url: privacy("Privacy_Photos")),
            SettingsShortcut(id: "appManagement", title: L("App Management"),
                             detail: L("Update or delete other apps (installers and updaters)."),
                             symbol: "square.and.arrow.down.on.square", url: privacy("Privacy_AppBundles")),
            SettingsShortcut(id: "developerTools", title: L("Developer Tools"),
                             detail: L("Run software that doesn't meet the system's security policy (Terminal, editors)."),
                             symbol: "hammer", url: privacy("Privacy_DevTools")),
            SettingsShortcut(id: "privacy", title: L("Privacy & Security"),
                             detail: L("Every list, plus “Open Anyway” for an app macOS blocked."),
                             symbol: "hand.raised", url: pane("com.apple.settings.PrivacySecurity.extension"))
        ]
    }

    /// The settings people actually use, grouped.
    static var system: [(title: String, items: [SettingsShortcut])] {
        [
            (L("Connections"), [
                SettingsShortcut(id: "wifi", title: L("Wi-Fi"), detail: "", symbol: "wifi", url: pane("com.apple.wifi-settings-extension")),
                SettingsShortcut(id: "bt", title: L("Bluetooth"), detail: "", symbol: "wave.3.right", url: pane("com.apple.BluetoothSettings")),
                SettingsShortcut(id: "network", title: L("Network"), detail: "", symbol: "network", url: pane("com.apple.Network-Settings.extension")),
                SettingsShortcut(id: "sharing", title: L("Sharing"), detail: "", symbol: "person.2", url: pane("com.apple.Sharing-Settings.extension")),
                SettingsShortcut(id: "airdrop", title: L("AirDrop & Handoff"), detail: "", symbol: "airplayaudio", url: pane("com.apple.AirDrop-Handoff-Settings.extension")),
                SettingsShortcut(id: "printers", title: L("Printers & Scanners"), detail: "", symbol: "printer", url: pane("com.apple.Print-Scan-Settings.extension"))
            ]),
            (L("Passwords & Security"), [
                SettingsShortcut(id: "passwords", title: L("Passwords"), detail: "", symbol: "key", url: "", appBundleID: "com.apple.Passwords"),
                SettingsShortcut(id: "touchid", title: L("Touch ID & Password"), detail: "", symbol: "touchid", url: pane("com.apple.Touch-ID-Settings.extension")),
                SettingsShortcut(id: "lock", title: L("Lock Screen"), detail: "", symbol: "lock", url: pane("com.apple.Lock-Screen-Settings.extension")),
                SettingsShortcut(id: "users", title: L("Users & Groups"), detail: "", symbol: "person.crop.circle", url: pane("com.apple.Users-Groups-Settings.extension")),
                SettingsShortcut(id: "loginItems", title: L("Login Items"), detail: "", symbol: "power", url: pane("com.apple.LoginItems-Settings.extension"))
            ]),
            (L("Screen & Sound"), [
                SettingsShortcut(id: "displays", title: L("Displays"), detail: "", symbol: "display", url: pane("com.apple.Displays-Settings.extension")),
                SettingsShortcut(id: "sound", title: L("Sound"), detail: "", symbol: "speaker.wave.2", url: pane("com.apple.Sound-Settings.extension")),
                SettingsShortcut(id: "desktopDock", title: L("Desktop & Dock"), detail: "", symbol: "dock.rectangle", url: pane("com.apple.Desktop-Settings.extension")),
                SettingsShortcut(id: "wallpaper", title: L("Wallpaper"), detail: "", symbol: "photo", url: pane("com.apple.Wallpaper-Settings.extension")),
                SettingsShortcut(id: "appearance", title: L("Appearance"), detail: "", symbol: "circle.lefthalf.filled", url: pane("com.apple.Appearance-Settings.extension")),
                SettingsShortcut(id: "notifications", title: L("Notifications"), detail: "", symbol: "bell.badge", url: pane("com.apple.Notifications-Settings.extension")),
                SettingsShortcut(id: "focus", title: L("Focus"), detail: "", symbol: "moon", url: pane("com.apple.Focus-Settings.extension"))
            ]),
            (L("Input"), [
                SettingsShortcut(id: "keyboard", title: L("Keyboard"), detail: "", symbol: "keyboard", url: pane("com.apple.Keyboard-Settings.extension")),
                SettingsShortcut(id: "trackpad", title: L("Trackpad"), detail: "", symbol: "rectangle.and.hand.point.up.left", url: pane("com.apple.Trackpad-Settings.extension")),
                SettingsShortcut(id: "mouse", title: L("Mouse"), detail: "", symbol: "computermouse", url: pane("com.apple.Mouse-Settings.extension")),
                SettingsShortcut(id: "a11y", title: L("Accessibility"), detail: "", symbol: "accessibility", url: pane("com.apple.Accessibility-Settings.extension"))
            ]),
            (L("This Mac"), [
                SettingsShortcut(id: "update", title: L("Software Update"), detail: "", symbol: "arrow.triangle.2.circlepath", url: pane("com.apple.Software-Update-Settings.extension")),
                SettingsShortcut(id: "storage", title: L("Storage"), detail: "", symbol: "internaldrive", url: pane("com.apple.settings.Storage")),
                SettingsShortcut(id: "battery", title: L("Battery & Energy"), detail: "", symbol: "battery.75percent", url: pane("com.apple.Battery-Settings.extension")),
                SettingsShortcut(id: "timeMachine", title: L("Time Machine"), detail: "", symbol: "clock.arrow.circlepath", url: pane("com.apple.Time-Machine-Settings.extension")),
                SettingsShortcut(id: "dateTime", title: L("Date & Time"), detail: "", symbol: "clock", url: pane("com.apple.Date-Time-Settings.extension")),
                SettingsShortcut(id: "language", title: L("Language & Region"), detail: "", symbol: "globe", url: pane("com.apple.Localization-Settings.extension"))
            ])
        ]
    }
}
