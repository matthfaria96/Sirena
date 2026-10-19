/// LegacyMenuBarHider.swift
///
/// Hiding for macOS versions before 27, which lack the native menu bar visibility
/// restriction. Uses the classic Hidden Bar technique (MIT, © Dwarves Foundation):
/// a separator status item sits just left of Sirena's arrow, and stretching it to a
/// huge length pushes every icon on its left off the screen.
///
/// Since Sirena hides by app instead of by position, the chosen apps' icons are first
/// ⌘-dragged (synthetic events, needs Accessibility) to the left of the separator, and
/// any icon that must stay visible is dragged to the right of it.

import AppKit
import ApplicationServices

@MainActor
final class LegacyMenuBarHider {
    static let separatorAutosaveName = "sirena.hider.separator"

    /// Forces the legacy technique on any macOS, to test it without an older Mac:
    /// `defaults write <bundle id> hiddenBar.forceLegacy -bool YES`.
    static let forceLegacyKey = "hiddenBar.forceLegacy"

    /// Whether this Mac needs the legacy technique.
    static var isNeeded: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
            || UserDefaults.standard.bool(forKey: forceLegacyKey)
    }

    private static let collapsedLength: CGFloat = 10_000
    private static let expandedLength: CGFloat = 1
    private static let dragStepDelay: TimeInterval = 0.08
    /// Time for the menu bar to lay icons out again after the separator shrinks.
    private static let settleDelay: TimeInterval = 0.4
    /// Safety net: never drag forever if an icon refuses to move.
    private static let maxDrags = 30

    private var separator: NSStatusItem?
    private(set) var isCollapsed = false

    // MARK: - Lifecycle

    /// Creates the separator. Call right after Sirena's arrow exists so macOS places
    /// the separator on its left.
    func install() {
        guard separator == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        item.autosaveName = Self.separatorAutosaveName
        item.button?.image = nil
        item.button?.title = ""
        item.button?.setAccessibilityLabel(L("Hidden icons"))
        item.isVisible = true
        separator = item
    }

    func uninstall() {
        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        separator = nil
        isCollapsed = false
    }

    // MARK: - Hide / show

    /// Moves the chosen apps' icons left of the separator, the rest right of it, then
    /// stretches the separator so everything on its left leaves the screen.
    func collapse(hiding bundleIDs: Set<String>, arrow: NSStatusItem?, completion: @escaping (Bool) -> Void) {
        guard let separator, AXIsProcessTrusted() else { return completion(false) }
        // Back to a thin separator first: positions are only meaningful when visible.
        separator.length = Self.expandedLength
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self else { return completion(false) }
            self.moveIcons(hiding: bundleIDs, arrow: arrow) { [weak self] in
                guard let self, let separator = self.separator else { return completion(false) }
                separator.length = Self.collapsedLength
                self.isCollapsed = true
                completion(true)
            }
        }
    }

    func expand() {
        separator?.length = Self.expandedLength
        isCollapsed = false
    }

    // MARK: - Planning

    private struct Move {
        let from: CGPoint
        let to: CGPoint
    }

    /// Screen frame (top-left origin, like Accessibility and CGEvent) of a status item.
    private static func frame(of item: NSStatusItem?) -> CGRect? {
        guard let window = item?.button?.window, let screen = window.screen ?? NSScreen.screens.first else { return nil }
        let frame = window.frame
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func plannedMoves(hiding bundleIDs: Set<String>, separator: NSStatusItem, arrow: NSStatusItem?) -> [Move] {
        guard let separatorFrame = frame(of: separator) else { return [] }
        let arrowFrame = frame(of: arrow)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let y = separatorFrame.midY
        // Dropping on the left edge of the separator puts the icon before it; on the
        // right edge of the arrow, after it.
        let hideTarget = CGPoint(x: separatorFrame.minX + 1, y: y)
        let showTarget = CGPoint(x: (arrowFrame?.maxX ?? separatorFrame.maxX) - 1, y: y)

        return NSWorkspace.shared.runningApplications.compactMap { app -> [Move]? in
            guard app.processIdentifier != ownPID, let bundleID = app.bundleIdentifier else { return nil }
            let shouldHide = bundleIDs.contains(bundleID)
            return statusItemFrames(of: app.processIdentifier).compactMap { itemFrame in
                let isLeft = itemFrame.midX < separatorFrame.minX
                guard shouldHide != isLeft else { return nil }
                let center = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
                return Move(from: center, to: shouldHide ? hideTarget : showTarget)
            }
        }.flatMap { $0 }
    }

    private static func statusItemFrames(of pid: pid_t) -> [CGRect] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(unsafeDowncast(bar, to: AXUIElement.self), kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap(axFrame)
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position)
        AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    // MARK: - ⌘-drag

    /// Drags one icon at a time and re-reads the positions after each drag, since every
    /// move shifts the icons around it.
    private func moveIcons(hiding bundleIDs: Set<String>, arrow: NSStatusItem?, completion: @escaping () -> Void) {
        let originalMouse = CGEvent(source: nil)?.location
        func finish() {
            if let originalMouse { CGWarpMouseCursorPosition(originalMouse) }
            completion()
        }
        func step(_ dragsLeft: Int) {
            guard let separator = self.separator, dragsLeft > 0,
                  let move = Self.plannedMoves(hiding: bundleIDs, separator: separator, arrow: arrow).first else { return finish() }
            Self.commandDrag(move)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dragStepDelay * 3) { step(dragsLeft - 1) }
        }
        step(Self.maxDrags)
    }

    private static func commandDrag(_ move: Move) {
        let source = CGEventSource(stateID: .hidSystemState)
        let events: [(CGEventType, CGPoint)] = [
            (.leftMouseDown, move.from),
            (.leftMouseDragged, CGPoint(x: (move.from.x + move.to.x) / 2, y: move.from.y)),
            (.leftMouseDragged, move.to),
            (.leftMouseUp, move.to),
        ]
        for (type, point) in events {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: dragStepDelay)
        }
    }
}
