/// GreenButtonManager.swift

import Cocoa
import DockKit

class GreenButtonManager {
    private var eventMonitor: ActiveEventMonitor!
    private var windowElement: AccessibilityElement?
    private var buttonFrame: CGRect?

    init() {
        eventMonitor = ActiveEventMonitor(mask: [.leftMouseDown, .leftMouseUp], filterer: filter, handler: { _ in })
        toggleListening()
        Notification.Name.greenButtonOverride.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }

    private func toggleListening() {
        if Defaults.greenButtonOverride.enabled {
            if !eventMonitor.running {
                eventMonitor.start()
            }
        } else {
            eventMonitor.stop()
        }
    }

    /// Runs on the event tap thread. Returning true consumes the event so the
    /// app never sees the click that would put its window into native full screen.
    private func filter(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            // Cached by AccessibilityGuard: a live TCC check per click is too slow for a tap.
            guard AccessibilityGuard.isTrusted else { return false }
            return autoreleasepool { filterMouseDown(event) }
        case .leftMouseUp:
            return filterMouseUp(event)
        default:
            return false
        }
    }

    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Whether the frontmost window under the point belongs to Sirena.
    /// True when the point is over any window of Sirena's, or Sirena is the active app.
    /// Deliberately conservative: an AX hit-test that lands on Sirena is answered in-process
    /// on the tap thread and touches SwiftUI / NSWindow off the main thread — that froze
    /// the app (SwiftUI's update lock left held) and crashed it before. Missing a green-button
    /// click over our own windows costs nothing.
    static func isOwnWindow(at point: CGPoint) -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID { return true }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == ownPID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(point)
        }
    }

    private func filterMouseDown(_ event: NSEvent) -> Bool {
            guard
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                let location = event.cgEvent?.location,
                // Every click on the Mac passes here: only the top-left corner of a window,
                // where its buttons are, is worth asking Accessibility about.
                Self.isInButtonsCorner(event, at: location),
                // Over Sirena's own windows the AX hit-test is answered in-process on this
                // tap thread, which makes SwiftUI rebuild pages off the main thread (crash).
                !Self.isOwnWindow(at: location),
                let element = AccessibilityElement(location),
                let buttonFrame = Self.greenButtonFrame(of: element, at: location),
                let windowElement = element.windowElement
            else {
                return false
            }
            self.windowElement = windowElement
            self.buttonFrame = buttonFrame
            return true
    }

    /// Whether `point` falls in the corner of the clicked window that holds its buttons
    /// (window server only, no Accessibility). An unknown window counts, to be safe.
    private static func isInButtonsCorner(_ event: NSEvent, at point: CGPoint) -> Bool {
        guard let number = event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointer), number > 0,
              let frame = WindowUtil.getWindowFrame(id: CGWindowID(number)) else { return true }
        return point.y - frame.minY <= 60 && point.x - frame.minX <= 140
    }

    /// The green button's frame when `point` is on it. The element under the point is the
    /// button itself up to macOS 26; from macOS 27 it is usually the traffic lights' group,
    /// another group of the window or the window, so the window's own button is checked too.
    private static func greenButtonFrame(of element: AccessibilityElement, at point: CGPoint) -> CGRect? {
        if element.isFullScreenButton == true {
            let frame = element.frame
            return frame == .null ? nil : frame
        }
        guard let frame = element.fullScreenButtonFrame, frame.contains(point) else { return nil }
        return frame
    }

    private func filterMouseUp(_ event: NSEvent) -> Bool {
        guard let windowElement = windowElement, let buttonFrame = buttonFrame else {
            return false
        }
        self.windowElement = nil
        self.buttonFrame = nil
        // Releasing outside the button cancels the click, matching native button behavior
        if let location = event.cgEvent?.location, buttonFrame.contains(location) {
            DispatchQueue.main.async {
                GreenButtonManager.executeAction(windowElement)
            }
        }
        return true
    }

    private static func executeAction(_ windowElement: AccessibilityElement) {
        if let windowId = windowElement.getWindowId(),
           case let windowFrame = windowElement.frame,
           windowFrame != .null,
           let historyAction = WindowManagementModule.windowHistory.lastRectangleActions[windowId],
           historyAction.action == .maximize,
           historyAction.rect == windowFrame {
            WindowAction.restore.postTitleBar(windowElement: windowElement)
            return
        }
        WindowAction.maximize.postTitleBar(windowElement: windowElement)
    }
}
