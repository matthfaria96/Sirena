/// WindowDragStrategies.swift
///
/// The trick that makes it as smooth as a real title bar (from AnyDrag, Xueshi Qiao, GPL-3.0):
/// nothing moves the window frame by frame through Accessibility. The held-key press is
/// swallowed; on the first drag event it is sent again as a press on the window's title bar
/// (move) or just inside its nearest corner (resize), and every following drag/up is shifted by
/// the same offset. The window server then moves or resizes the window itself, exactly as if
/// the title bar or the corner had been grabbed by hand: no per-frame IPC at all.
///
/// Rectangle's snap areas and Sirena's snap layouts watch the drag like any other title-bar
/// drag, so they work during a held-key move too.
///
/// Everything here runs on the tap thread and makes no Accessibility call: bringing the
/// window forward runs elsewhere (`WindowDragEngine.bringForward`), and the press waits until
/// the window is really in front at the press point (`coveringPID`), at most 250 ms.

import AppKit

/// Moves: the press goes to the title bar.
final class TitleBarDragStrategy {
    private(set) var isActive = false
    private(set) var didDrag = false
    private(set) var pressSent = false
    private var offset = CGPoint.zero
    private var dragPoint = CGPoint.zero
    private var windowID: CGWindowID = 0
    private var pid: pid_t = 0
    private var deadline: TimeInterval = 0

    /// How long the press waits for the window to come forward before going out anyway.
    static let startupGrace: TimeInterval = 0.25
    /// Below the window's top edge: inside the title bar on every stock window, above the
    /// traffic lights. One point more on macOS 27, whose top edge is a resize zone.
    static let titleBarOffset: CGFloat = {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 4 : 3
    }()
    /// ⌃ turns a press into a secondary click and ⌘ on a title bar opens the path menu:
    /// neither may reach the synthesized press.
    static let flagsToStrip: CGEventFlags = [.maskControl, .maskCommand]

    func begin(pid: pid_t, windowID: CGWindowID, windowFrame: CGRect, cursor: CGPoint) {
        dragPoint = CGPoint(x: cursor.x.rounded(), y: (windowFrame.minY + Self.titleBarOffset).rounded())
        offset = CGPoint(x: 0, y: dragPoint.y - cursor.y)
        self.windowID = windowID
        self.pid = pid
        deadline = ProcessInfo.processInfo.systemUptime + Self.startupGrace
        isActive = true
        didDrag = false
        pressSent = false
    }

    func dragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        didDrag = true
        event.flags = event.flags.subtracting(Self.flagsToStrip)
        if !pressSent {
            // Hold the press while another app still covers the title bar (the window is
            // being brought forward); past the grace period it goes out regardless.
            if let coverer = Self.coveringPID(of: windowID, at: dragPoint), coverer != pid,
               ProcessInfo.processInfo.systemUptime < deadline {
                return nil
            }
            pressSent = true
            event.type = .leftMouseDown
            // A move is never a double click on the title bar (that would zoom instead).
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.location = dragPoint
            return Unmanaged.passUnretained(event)
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        let point = event.location
        event.location = CGPoint(x: (point.x + offset.x).rounded(), y: (point.y + offset.y).rounded())
        return Unmanaged.passUnretained(event)
    }

    /// The release, shifted like the drags; nil when no press went out (the engine decides).
    func released(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        defer { reset() }
        guard pressSent else { return nil }
        event.flags = event.flags.subtracting(Self.flagsToStrip)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        let point = event.location
        event.location = CGPoint(x: (point.x + offset.x).rounded(), y: (point.y + offset.y).rounded())
        return Unmanaged.passUnretained(event)
    }

    func reset() {
        isActive = false
        didDrag = false
        pressSent = false
        windowID = 0
        pid = 0
    }

    /// The owner of the front-most normal window above `windowID` at `point`, or nil when the
    /// window itself shows there. Window server only, no Accessibility.
    static func coveringPID(of windowID: CGWindowID, at point: CGPoint) -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], windowID)
            as? [[CFString: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowLayer] as? Int) == 0,
                  (window[kCGWindowAlpha] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point) else { continue }
            return window[kCGWindowOwnerPID] as? pid_t ?? 0
        }
        return nil
    }
}

enum WindowDragCorner {
    case topLeft, topRight, bottomLeft, bottomRight

    /// The corner of the quarter of the window the cursor is in.
    static func nearest(to cursor: CGPoint, in frame: CGRect) -> WindowDragCorner {
        let left = cursor.x < frame.midX
        let top = cursor.y < frame.midY
        switch (top, left) {
        case (true, true): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    /// `inset` inside the corner: in the window server's resize zone, inside the rounded shape.
    func anchor(in frame: CGRect, inset: CGFloat) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: frame.minX + inset, y: frame.minY + inset)
        case .topRight: return CGPoint(x: frame.maxX - inset, y: frame.minY + inset)
        case .bottomLeft: return CGPoint(x: frame.minX + inset, y: frame.maxY - inset)
        case .bottomRight: return CGPoint(x: frame.maxX - inset, y: frame.maxY - inset)
        }
    }
}

/// Resizes: the press goes just inside the nearest corner; right-button events become
/// left-button ones for the window server.
final class CornerResizeStrategy {
    private(set) var isActive = false
    private(set) var didDrag = false
    private(set) var pressSent = false
    /// AppKit's live resize measures from the first drag after the press that moves at all,
    /// not from the press: that drag goes 1 pt from the press point, toward the motion, so the
    /// distance covered while the press waited isn't lost.
    private var settleNext = false
    private var cursorAtBegin = CGPoint.zero
    private var offset = CGPoint.zero
    private var dragPoint = CGPoint.zero
    private var windowID: CGWindowID = 0
    private var pid: pid_t = 0
    private var deadline: TimeInterval = 0

    static let cornerInset: CGFloat = 5
    /// ⌥ would resize both sides at once, ⌃ makes a secondary click, ⌘ is left alone by
    /// nothing useful here: all three go.
    static let flagsToStrip: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate]

    func begin(pid: pid_t, windowID: CGWindowID, windowFrame: CGRect, cursor: CGPoint, bottomRightOnly: Bool) {
        let corner = bottomRightOnly ? .bottomRight : WindowDragCorner.nearest(to: cursor, in: windowFrame)
        dragPoint = corner.anchor(in: windowFrame, inset: Self.cornerInset)
        offset = CGPoint(x: dragPoint.x - cursor.x, y: dragPoint.y - cursor.y)
        cursorAtBegin = cursor
        self.windowID = windowID
        self.pid = pid
        deadline = ProcessInfo.processInfo.systemUptime + TitleBarDragStrategy.startupGrace
        isActive = true
        didDrag = false
        pressSent = false
    }

    func dragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        didDrag = true
        event.flags = event.flags.subtracting(Self.flagsToStrip)
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        if !pressSent {
            if let coverer = TitleBarDragStrategy.coveringPID(of: windowID, at: dragPoint), coverer != pid,
               ProcessInfo.processInfo.systemUptime < deadline {
                return nil
            }
            pressSent = true
            settleNext = true
            event.type = .leftMouseDown
            event.location = dragPoint
            return Unmanaged.passUnretained(event)
        }
        event.type = .leftMouseDragged
        let point = event.location
        if settleNext {
            let dx = (point.x - cursorAtBegin.x).rounded(), dy = (point.y - cursorAtBegin.y).rounded()
            event.location = CGPoint(x: dragPoint.x + (dx > 0 ? 1 : dx < 0 ? -1 : 0),
                                     y: dragPoint.y + (dy > 0 ? 1 : dy < 0 ? -1 : 0))
            if dx != 0 || dy != 0 { settleNext = false }
            return Unmanaged.passUnretained(event)
        }
        event.location = CGPoint(x: (point.x + offset.x).rounded(), y: (point.y + offset.y).rounded())
        return Unmanaged.passUnretained(event)
    }

    func released(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        defer { reset() }
        guard pressSent else { return nil }
        event.type = .leftMouseUp
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.flags = event.flags.subtracting(Self.flagsToStrip)
        let point = event.location
        event.location = CGPoint(x: (point.x + offset.x).rounded(), y: (point.y + offset.y).rounded())
        return Unmanaged.passUnretained(event)
    }

    func reset() {
        isActive = false
        didDrag = false
        pressSent = false
        settleNext = false
        windowID = 0
        pid = 0
    }
}
