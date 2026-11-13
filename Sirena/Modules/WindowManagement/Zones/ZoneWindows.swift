/// ZoneWindows.swift
///
/// The open windows the snap layouts offer (Snap Assist, "Trocar app"): the list the ⌘ Tab
/// switcher builds (`SwitcherWindowEnumerator`: the window server checked against
/// Accessibility, so leftover surfaces stay out and windows their apps describe oddly stay
/// in), for the visible desktops, with the minimized windows and those of hidden apps.
/// Built off the main thread: an app that is slow to answer delays the list, never the
/// pointer.

import AppKit

/// A window Snap Assist can put in a zone.
struct ZoneWindow: Identifiable, Equatable {
    enum State: Equatable {
        /// On screen, on the display being filled.
        case here
        /// On screen, on another display (its name).
        case otherDisplay(String)
        case minimized
        /// Its app is hidden (⌘H, or a Dock click in "Tudo junto pelo Dock").
        case hidden
    }

    let id: CGWindowID
    /// The app it belongs to (icon, name).
    let pid: pid_t
    /// The process that owns the window (a helper, in a few apps).
    let ownerPID: pid_t
    let title: String
    let appName: String
    /// Where the window server has it (top-left origin).
    let frame: CGRect
    let state: State

    /// What the cards and the screen reader call it.
    var label: String { title.isEmpty ? appName : title }

    var isOnScreen: Bool {
        switch state {
        case .here, .otherDisplay: return true
        case .minimized, .hidden: return false
        }
    }
}

enum ZoneWindows {
    private static let queue = DispatchQueue(label: "com.matheusfaria.Sirena.zones.windows", qos: .userInitiated)

    /// The windows that could go into a zone of `screen`, most recently used first. Sirena's
    /// own windows and full screen ones are left out. `completion` runs on the main thread.
    @MainActor
    static func list(for screen: NSScreen, completion: @escaping @MainActor ([ZoneWindow]) -> Void) {
        let snapshot = SwitcherWindowEnumerator.snapshot()
        let here = ZoneController.key(for: screen)
        let displays = NSScreen.screens.map {
            (key: ZoneController.key(for: $0), name: $0.localizedName, frame: $0.frame.screenFlipped)
        }
        queue.async {
            let own = ProcessInfo.processInfo.processIdentifier
            var windows: [ZoneWindow] = []
            for item in SwitcherWindowEnumerator.listSnappableWindows(snapshot: snapshot) {
                guard let id = item.windowID, item.pid != own, item.windowOwnerPID != own else { continue }
                let state: ZoneWindow.State
                if item.isMinimized {
                    state = .minimized
                } else if item.isAppHidden {
                    state = .hidden
                } else if item.isOnScreen {
                    // The switcher's flag also covers a window that merely fills a display:
                    // only one in its own full screen space is out of reach.
                    if item.isFullscreen, isNativeFullScreen(id, ownerPID: item.windowOwnerPID) { continue }
                    let display = ZoneGeometry.display(of: item.frame, in: displays.map(\.frame)).map { displays[$0] }
                    state = display.map { $0.key == here ? .here : .otherDisplay($0.name) } ?? .here
                } else {
                    // Neither shown, minimized nor hidden: a tab behind another, a window in
                    // the middle of closing. Nothing to put in a zone.
                    continue
                }
                windows.append(ZoneWindow(id: id, pid: item.pid, ownerPID: item.windowOwnerPID,
                                          title: item.title, appName: item.appName, frame: item.frame, state: state))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(windows) }
            }
        }
    }

    private static func isNativeFullScreen(_ id: CGWindowID, ownerPID: pid_t) -> Bool {
        let app = AccessibilityElement(ownerPID)
        app.setMessagingTimeout(0.25)
        guard let window = app.windowElements?.first(where: { $0.windowId == id }) else { return false }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window.axElement, "AXFullScreen" as CFString, &value) == .success
            && (value as? Bool) == true
    }
}
