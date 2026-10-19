/// ModuleID.swift

import SwiftUI

/// Every feature area Sirena offers. Each one is a full app ported into Sirena,
/// with its own page in the main window.
enum ModuleID: String, CaseIterable, Identifiable {
    case windows
    case dock
    case switcher
    case clipboard
    case menuBar
    case keepAwake
    case displayOff
    case mixer
    case mirror
    case pinWindow
    case textCapture
    case tweaks
    case shelf
    case island
    case screenCapture
    case pomodoro
    case colorPicker
    case screenBrush

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
        case .displayOff: return L("Turn Off Display")
        case .mixer: return L("Sound Mixer")
        case .mirror: return L("Mirror")
        case .pinWindow: return L("Pin Window")
        case .textCapture: return L("Text Capture")
        case .tweaks: return L("Tweaks")
        case .shelf: return L("Shelf")
        case .screenCapture: return L("Screen Capture")
        case .pomodoro: return L("Pomodoro")
        case .colorPicker: return L("Color Picker")
        case .screenBrush: return L("Freehand Drawing")
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
        case .displayOff: return L("Turn the screen off with one click, after a short countdown you can cancel.")
        case .mixer: return L("The volume of the Mac and of each app, where each one plays, and the microphone.")
        case .mirror: return L("A hand mirror in your menu bar: click it to check how you look before a call.")
        case .pinWindow: return L("Keep any window floating above all the others, with adjustable transparency.")
        case .textCapture: return L("Select any part of the screen and copy its text, QR codes and barcodes, even from images and videos.")
        case .tweaks: return L("Small improvements for the Finder.")
        case .shelf: return L("Start dragging anything and a shelf appears at the screen edge: drop it there, move on, and drag it back out where it needs to go.")
        case .screenCapture: return L("A custom shortcut to Apple's Screenshot app: take an area or the whole screen, or record either, starting right in the mode you pick.")
        case .pomodoro: return L("A focus timer: work in sessions, take short and long breaks, and keep track of your day.")
        case .colorPicker: return L("Pick any color on the screen and keep a library of colors in every format.")
        case .screenBrush: return L("Draw, highlight and point on top of everything on the screen, for presentations and calls.")
        }
    }

    var symbol: String {
        switch self {
        case .windows: return "rectangle.split.2x2.fill"
        case .dock: return "dock.rectangle"
        case .switcher: return "rectangle.stack.fill"
        case .island: return "capsule.portrait.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .menuBar: return "eye.slash.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .displayOff: return "display"
        case .mixer: return "slider.vertical.3"
        case .mirror: return "person.crop.circle"
        case .pinWindow: return "pin.fill"
        case .textCapture: return "doc.text.viewfinder"
        case .tweaks: return "wand.and.stars"
        case .shelf: return "tray.and.arrow.down.fill"
        case .screenCapture: return "camera.fill"
        case .pomodoro: return "timer"
        case .colorPicker: return "eyedropper.halffull"
        case .screenBrush: return "pencil.tip.crop.circle.fill"
        }
    }

    /// One short, direct line about what it does, for its card on Home.
    var tagline: String {
        switch self {
        case .windows, .dock, .switcher, .tweaks: return L("Arrange windows, ⌘ Tab with previews, the Dock and the Finder.")
        case .menuBar: return L("Hides the menu bar icons you don't need.")
        case .shelf: return L("A shelf at the screen edge to park files while dragging.")
        case .island: return L("The notch becomes a panel with music, calendar and controls.")
        default: return summary
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
        case .displayOff: return Color(red: 0.24, green: 0.40, blue: 0.62)
        case .mixer: return .purple
        case .mirror: return .pink
        case .pinWindow: return Color(red: 0.0, green: 0.52, blue: 0.42)
        case .textCapture: return .green
        case .tweaks: return .red
        case .shelf: return Color(red: 0.05, green: 0.42, blue: 0.78)
        case .screenCapture: return Color(red: 0.36, green: 0.38, blue: 0.45)
        case .pomodoro: return .red
        case .colorPicker: return Color(red: 0.0, green: 0.42, blue: 0.55)
        case .screenBrush: return .yellow
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
        case .displayOff: return ("pmset", L("Built on macOS's power management"), L("Original"), "https://ss64.com/mac/pmset.html")
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
        // Flow, Pastel and ScreenBrush are closed source: written from scratch after their feature lists.
        case .screenCapture: return ("Screenshot", L("Built on macOS's Screenshot tool"), L("Original"), "https://support.apple.com/102646")
        case .pomodoro: return ("Flow", L("Inspired by Flow, written for Sirena"), L("Original"), "https://flowapp.info")
        case .colorPicker: return ("Pastel", L("Inspired by Pastel, written for Sirena"), L("Original"), "https://pastelapp.io")
        case .screenBrush: return ("ScreenBrush", L("Inspired by ScreenBrush, written for Sirena"), L("Original"), "https://imagestudiopro.com")
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
    var isTool: Bool { [.mirror, .pinWindow, .clipboard, .textCapture, .keepAwake, .displayOff, .mixer, .screenCapture, .pomodoro, .colorPicker, .screenBrush].contains(self) }

    static var tools: [ModuleID] { allCases.filter(\.isTool) }

    /// Modules with a page (and a sidebar row / Home card) of their own: tools first.
    static var pages: [ModuleID] { tools + featurePages }

    /// Background features with a page of their own.
    static var featurePages: [ModuleID] { allCases.filter { $0.hostPage == $0 && !$0.isTool } }

    /// The Dynamic Island starts off until the user turns it on.
    private var isOnByDefault: Bool { self != .island }

    private var enabledKey: String { "sirena.module.\(rawValue).enabled" }

    /// Whether the module runs. Read once at launch; changes apply on relaunch
    /// (turning a module on also starts it right away).
    var isEnabled: Bool {
        get { isTool || (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? isOnByDefault) }
        nonmutating set {
            guard !isTool else { return }
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}
