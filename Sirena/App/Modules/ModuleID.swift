/// ModuleID.swift

import SwiftUI

/// Every feature area Sirena offers. Each one is a full app ported into Sirena,
/// with its own page in the main window.
enum ModuleID: String, CaseIterable, Identifiable {
    case windows
    case dock
    case switcher
    case island
    case clipboard
    case menuBar
    case keepAwake
    case mixer
    case mirror
    case pinWindow
    case textCapture
    case tweaks
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return L("Window & Dock")
        case .dock: return L("Dock & Switcher")
        case .switcher: return L("Window Switcher")
        case .island: return L("Dynamic Island")
        case .clipboard: return L("Clipboard")
        case .menuBar: return L("Hidden Icons")
        case .keepAwake: return L("Keep Awake")
        case .mixer: return L("Sound Mixer")
        case .mirror: return L("Mirror")
        case .pinWindow: return L("Pin Window")
        case .textCapture: return L("Text Capture")
        case .tweaks: return L("Tweaks")
        case .shelf: return L("Shelf")
        }
    }

    var summary: String {
        switch self {
        case .windows: return L("Arrange windows, switch between them with ⌘ Tab and see window previews on the Dock.")
        case .dock: return L("See window previews when hovering the Dock and switch between windows with ⌥ Tab.")
        case .switcher: return L("⌘ Tab with live window previews: search, close and quit right from the switcher.")
        case .island: return L("The notch comes alive: music, calendar, timer, notifications and quick controls around the camera.")
        case .clipboard: return L("Keep a searchable history of everything you copy and paste it back anywhere.")
        case .menuBar: return L("Hide menu bar icons you don't need and reveal them with one click.")
        case .keepAwake: return L("Stop your Mac from sleeping or dimming the screen, for as long as you want.")
        case .mixer: return L("The volume of the Mac and of each app, where each one plays, and the microphone.")
        case .mirror: return L("A hand mirror in your menu bar: click it to check how you look before a call.")
        case .pinWindow: return L("Keep any window floating above all the others, with adjustable transparency.")
        case .textCapture: return L("Select any part of the screen and copy its text, QR codes and barcodes, even from images and videos.")
        case .tweaks: return L("Small improvements for the Finder.")
        case .shelf: return L("Start dragging anything and a shelf appears at the screen edge: drop it there, move on, and drag it back out where it needs to go.")
        }
    }

    var symbol: String {
        switch self {
        case .windows: return "macwindow.on.rectangle"
        case .dock: return "dock.rectangle"
        case .switcher: return "rectangle.stack.fill"
        case .island: return "capsule.portrait"
        case .clipboard: return "doc.on.clipboard"
        case .menuBar: return "menubar.rectangle"
        case .keepAwake: return "cup.and.saucer.fill"
        case .mixer: return "slider.vertical.3"
        case .mirror: return "person.crop.circle"
        case .pinWindow: return "pin.fill"
        case .textCapture: return "text.viewfinder"
        case .tweaks: return "wand.and.stars"
        case .shelf: return "tray.and.arrow.down.fill"
        }
    }

    /// A custom template image used instead of the SF Symbol (the camera shutter).
    var imageName: String? { self == .mirror ? "CameraShutter" : nil }

    var tint: Color {
        switch self {
        case .windows: return .blue
        case .dock: return .teal
        case .switcher: return .purple
        case .island: return .gray
        case .clipboard: return .orange
        case .menuBar: return .indigo
        case .keepAwake: return Color(red: 0.55, green: 0.30, blue: 0.10)
        case .mixer: return .purple
        case .mirror: return .pink
        case .pinWindow: return .mint
        case .textCapture: return .green
        case .tweaks: return .red
        case .shelf: return .cyan
        }
    }

    /// The open-source app this module is built from.
    var origin: (name: String, author: String, license: String, url: String) {
        switch self {
        case .windows: return ("Rectangle", "Ryan Hanson", "MIT", "https://github.com/rxhanson/Rectangle")
        case .dock: return ("DockDoor", "Ethan Bills", "GPL-3.0", "https://github.com/ejbills/DockDoor")
        case .switcher: return ("Vorssaint", "Vorssaint", "GPL-3.0", "https://github.com/vorssaint/vorssaint-utils")
        case .island: return ("Vorssaint", "Vorssaint", "GPL-3.0", "https://github.com/vorssaint/vorssaint-utils")
        case .clipboard: return ("Maccy", "Alex Rodionov", "MIT", "https://github.com/p0deje/Maccy")
        case .menuBar: return ("Hidden Bar", "Dwarves Foundation", "MIT", "https://github.com/dwarvesf/hidden")
        case .keepAwake: return ("Caffeine", "Tomas Franzén, Michael Jones, Dominic Rodemer", "MIT", "https://github.com/domzilla/Caffeine")
        case .mixer: return ("Vorssaint", "Vorssaint", "GPL-3.0", "https://github.com/vorssaint/vorssaint-utils")
        case .mirror: return ("Iris", "Ahmet Alp Balkan", "MIT", "https://github.com/ahmetb/Iris")
        // Floaty is closed source: Pin Window is written from scratch after its feature list.
        case .pinWindow: return ("Floaty", L("Inspired by Floaty, written for Sirena"), L("Original"), "https://floatytool.com")
        // TextSniper is closed source: Text Capture is written from scratch after its feature list.
        case .textCapture: return ("TextSniper", L("Inspired by TextSniper, written for Sirena"), L("Original"), "https://textsniper.app")
        // Supercharge is closed source: Tweaks is written from scratch after its feature list.
        case .tweaks: return ("Supercharge", L("Inspired by Supercharge, written for Sirena"), L("Original"), "https://sindresorhus.com/supercharge")
        // Yoink is closed source: Shelf is written from scratch after its feature list.
        case .shelf: return ("Yoink", L("Inspired by Yoink, written for Sirena"), L("Original"), "https://eternalstorms.at/yoink/mac/")
        }
    }

    /// Small tweak-like features live as tabs of the Melhorias page instead of having a
    /// page of their own.
    var hostPage: ModuleID {
        switch self {
        case .dock, .switcher, .tweaks: return .windows
        default: return self
        }
    }

    /// The tab of `hostPage` that shows this module, when it is embedded.
    var hostTab: String? {
        switch self {
        case .switcher: return "windows"
        case .dock: return "dock"
        case .tweaks: return "finder"
        default: return nil
        }
    }

    /// Tools are used now and then (pin a window, check the mirror): always available,
    /// never switched on or off, and listed apart from the background features.
    var isTool: Bool { [.mirror, .pinWindow, .clipboard, .textCapture, .keepAwake, .mixer].contains(self) }

    static var tools: [ModuleID] { allCases.filter(\.isTool) }

    /// Modules with a page (and a sidebar row / Home card) of their own: tools first.
    static var pages: [ModuleID] { tools + featurePages }

    /// Background features with a page of their own.
    static var featurePages: [ModuleID] { allCases.filter { $0.hostPage == $0 && !$0.isTool } }

    private var enabledKey: String { "sirena.module.\(rawValue).enabled" }

    /// Whether the module runs. Read once at launch; changes apply on relaunch
    /// (turning a module on also starts it right away).
    var isEnabled: Bool {
        get { isTool || (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true) }
        nonmutating set {
            guard !isTool else { return }
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}
