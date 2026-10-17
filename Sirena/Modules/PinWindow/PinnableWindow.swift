/// PinnableWindow.swift
///
/// Finding the windows of other apps: the list Pin Window offers, the window under the
/// pointer, and the Accessibility element behind a window.

import AppKit
import ApplicationServices

/// A window of another app that can be pinned.
struct PinnableWindow: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    /// Global display coordinates, origin at the top left of the main display (as
    /// Core Graphics and Accessibility use them).
    let frame: CGRect

    var displayName: String {
        title.isEmpty ? appName : title
    }

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    /// The screen showing most of the window.
    var screen: NSScreen? {
        let cocoa = PinGeometry.cocoaRect(fromCG: frame)
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(cocoa).area < rhs.frame.intersection(cocoa).area
        }
    }
}

enum PinGeometry {
    /// Converts between Core Graphics global coordinates (top-left origin, y down) and
    /// Cocoa screen coordinates (bottom-left origin, y up). The flip is its own inverse.
    static func cocoaRect(fromCG rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgPoint(fromCocoa point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }
}

extension CGRect {
    fileprivate var area: CGFloat { isNull ? 0 : width * height }
}

enum WindowList {
    /// Owners whose layer-0 windows are system furniture, never something to pin.
    private static let ignoredOwners: Set<String> = ["Window Server", "Dock", "Control Center", "Notification Center"]

    /// Normal windows of other apps currently on screen, front to back.
    static func onScreen() -> [PinnableWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap(window(from:))
    }

    /// The window with this ID, wherever it is (also off screen), or nil once it closed.
    static func window(id: CGWindowID) -> (window: PinnableWindow, isOnScreen: Bool)? {
        guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let entry = info.first, let window = window(from: entry) else { return nil }
        return (window, entry[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    /// The front-most window under a point given in Cocoa screen coordinates.
    static func window(atCocoaPoint point: CGPoint, in windows: [PinnableWindow]? = nil) -> PinnableWindow? {
        let cgPoint = PinGeometry.cgPoint(fromCocoa: point)
        return (windows ?? onScreen()).first { $0.frame.contains(cgPoint) }
    }

    private static func window(from entry: [String: Any]) -> PinnableWindow? {
        guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
              let id = entry[kCGWindowNumber as String] as? CGWindowID,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              pid != ProcessInfo.processInfo.processIdentifier,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width >= 80, bounds.height >= 60,
              (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
        let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
        guard !ignoredOwners.contains(owner) else { return nil }
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? owner
        return PinnableWindow(id: id, pid: pid, appName: appName,
                              title: entry[kCGWindowName as String] as? String ?? "",
                              frame: bounds)
    }
}

/// Accessibility access to other apps' windows.
enum PinAX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    static func window(id: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { windowID(of: $0) == id }
    }

    /// The focused window of the front-most app, if it belongs to another app.
    static func frontWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return focusedWindowID(pid: app.processIdentifier)
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return windowID(of: value as! AXUIElement)
    }

    /// Frame in Core Graphics global coordinates.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// The window's close, minimize and zoom buttons, in Core Graphics global coordinates.
    static func trafficLightsFrame(of window: AXUIElement) -> CGRect? {
        let attributes = [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute]
        let frames = attributes.compactMap { attribute -> CGRect? in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return frame(of: value as! AXUIElement)
        }
        return frames.isEmpty ? nil : frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    }

    static func minimize(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// Presses the window's close button, so the app can ask to save first.
    static func close(_ window: AXUIElement) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString)
    }

    /// Fills the visible area of the screen showing most of the window (the Dock and the
    /// menu bar stay visible), like Option-clicking the green button.
    static func maximize(_ window: AXUIElement, currentFrame: CGRect) {
        guard let target = visibleFrame(for: currentFrame) else { return }
        setFrame(of: window, to: target)
    }

    /// The visible area (without the Dock and menu bar) of the screen showing most of a
    /// window, both in Core Graphics global coordinates.
    static func visibleFrame(for frame: CGRect) -> CGRect? {
        let cocoa = PinGeometry.cocoaRect(fromCG: frame)
        guard let screen = NSScreen.screens.max(by: {
            $0.frame.intersection(cocoa).width * $0.frame.intersection(cocoa).height
                < $1.frame.intersection(cocoa).width * $1.frame.intersection(cocoa).height
        }) else { return nil }
        return PinGeometry.cocoaRect(fromCG: screen.visibleFrame)
    }

    /// Moves and resizes a window; the frame is in Core Graphics global coordinates.
    static func setFrame(of window: AXUIElement, to frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Position, size, position: some apps clamp the size to the space left at the old position.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Brings the real window to the front and makes its app active.
    static func activate(window: AXUIElement?, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        if AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) != .success {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        if let window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }
}
