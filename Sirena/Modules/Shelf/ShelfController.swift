/// ShelfController.swift
///
/// Shelf, modeled on Yoink: start dragging anything and a shelf appears at the edge of
/// the screen. Drop it there, go wherever it needs to go, and drag it back out. The
/// shelf stays while it holds something and goes away once it's empty.

import AppKit
import MASShortcut

@MainActor
@Observable
final class ShelfController {
    static let shared = ShelfController()

    private(set) var isRunning = false
    private(set) var isVisible = false
    /// A drag is over the shelf (highlights it).
    var isDropTargeted = false
    /// The content is shown (drives the SwiftUI entrance/exit animation).
    var isPresented = false
    /// 0 … 1: how close a drag in progress is to the shelf (it grows and glows).
    var dragProximity: Double = 0
    /// Shown empty for a drag: the shelf waits as a slim glowing edge and opens up as the
    /// drag comes closer, so it's clear where to let go.
    var isPeeking = false
    /// The shelf's own menu is open: a Continuity Camera import goes to the shelf, not
    /// to Text Capture (both use the same system mechanism, answered by AppDelegate).
    @ObservationIgnored var importsToShelf = false

    @ObservationIgnored let panel = ShelfPanel()
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let services = ShelfServices()
    @ObservationIgnored private var openPage: () -> Void = {}

    /// Drag pasteboard state when the mouse went down: a change means content is being dragged.
    @ObservationIgnored private var dragChangeCount = 0
    @ObservationIgnored private var dragHandled = false
    @ObservationIgnored private var shownForDrag = false
    @ObservationIgnored private var dragEndTimer: Timer?
    /// Screen and (in "at cursor" mode) the point the shelf was placed at.
    @ObservationIgnored private var anchorScreen: NSScreen?
    @ObservationIgnored private var anchorPoint: CGPoint?
    @ObservationIgnored private var isTrackingItems = false

    private var settings: ShelfSettings { .shared }
    private var store: ShelfStore { .shared }

    private init() {}

    // MARK: - Module lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseDown() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseDragged() }
            }
        ].compactMap { $0 }

        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.bindShortcut(withDefaultsKey: ShelfSettings.toggleShortcutKey) { [weak self] in self?.toggle() }
        binder?.bindShortcut(withDefaultsKey: ShelfSettings.addClipboardShortcutKey) { ShelfActions.addFromClipboard() }

        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        observers.append(NotificationCenter.default.addObserver(forName: .shelfSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                ShelfThumbnails.shared.clear()
                self?.relayout(animated: true)
            }
        })
        if !isTrackingItems {
            isTrackingItems = true
            trackItems()
        }
        if !store.items.isEmpty { show() }
    }

    func terminate() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for key in [ShelfSettings.toggleShortcutKey, ShelfSettings.addClipboardShortcutKey] {
            MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: key)
        }
        dragEndTimer?.invalidate()
        panel.orderOut(nil)
        isVisible = false
        isRunning = false
    }

    func openSettings() {
        openPage()
    }

    // MARK: - Showing

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Shows the shelf at its edge, or next to `point` (Cocoa screen coordinates).
    func show(near point: CGPoint? = nil) {
        guard isRunning else { return }
        let mouse = NSEvent.mouseLocation
        anchorScreen = NSScreen.screens.first { $0.frame.contains(point ?? mouse) } ?? NSScreen.main
        anchorPoint = point
        if !shownForDrag || !store.items.isEmpty || point != nil { isPeeking = false }
        let target = targetFrame()
        if !isVisible {
            // Slide in from the edge (or fade in next to the cursor).
            var start = target
            if point == nil {
                start.origin.x += settings.position.isLeft ? -target.width - 20 : target.width + 20
            }
            panel.setFrame(start, display: false)
            panel.alphaValue = point == nil ? 1 : 0
            panel.orderFrontRegardless()
            isVisible = true
        }
        isPresented = true
        NSAnimationContext.runAnimationGroup { context in
            // A little overshoot, like a spring settling against the edge.
            context.duration = Self.reduceMotion ? 0.15 : 0.42
            context.timingFunction = Self.reduceMotion
                ? CAMediaTimingFunction(name: .easeOut)
                : CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        shownForDrag = false
        isPeeking = false
        isPresented = false
        dragProximity = 0
        var end = panel.frame
        if anchorPoint == nil {
            end.origin.x += settings.position.isLeft ? -end.width - 20 : end.width + 20
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.8, 0.4)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = anchorPoint == nil ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func targetFrame() -> CGRect {
        guard let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first else { return panel.frame }
        let visible = screen.visibleFrame
        let side = settings.itemSize.side(for: store.items.count)
        let size = ShelfLayout.size(itemCount: store.items.count, side: side, maxHeight: visible.height * 0.85)

        if let point = anchorPoint {
            // Next to the pointer, on the side with room, kept on screen.
            var x = point.x + 28
            if x + size.width > visible.maxX { x = point.x - 28 - size.width }
            let y = min(max(point.y - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8)
            return CGRect(x: max(x, visible.minX + 8), y: y, width: size.width, height: size.height)
        }
        // Flush against the screen edge: the panel's transparent margin goes off screen,
        // so the glass itself touches the edge.
        let x = settings.position.isLeft
            ? screen.frame.minX - ShelfLayout.margin
            : screen.frame.maxX - size.width + ShelfLayout.margin
        let y: CGFloat
        switch settings.position {
        case .leftTop, .rightTop: y = visible.maxY - size.height - 8
        case .leftBottom, .rightBottom: y = visible.minY + 8
        default: y = visible.midY - size.height / 2
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func relayout(animated: Bool) {
        guard isVisible else { return }
        let target = targetFrame()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// Resizes with the content, and goes away once the last item is dragged out.
    private func trackItems() {
        withObservationTracking {
            _ = store.items.count
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                if !self.store.items.isEmpty { self.isPeeking = false }
                self.relayout(animated: true)
                if self.store.items.isEmpty, !self.shownForDrag, !self.isDropTargeted {
                    self.hide()
                }
                self.trackItems()
            }
        }
    }

    // MARK: - Drag detection

    private func mouseDown() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragHandled = false
    }

    private func mouseDragged() {
        guard isRunning, !dragHandled, NSPasteboard(name: .drag).changeCount != dragChangeCount else { return }
        // Something (not a window or a selection) is being dragged.
        if let flag = settings.suppressKey.flag, NSEvent.modifierFlags.contains(flag) {
            dragHandled = true
            return
        }
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, settings.ignoredApps.contains(app) {
            dragHandled = true
            return
        }
        let mouse = NSEvent.mouseLocation
        if settings.showOnlyAtEdge && !settings.showAtCursor {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
            let atEdge = settings.position.isLeft ? mouse.x <= screen.frame.minX + 3 : mouse.x >= screen.frame.maxX - 4
            guard atEdge else { return } // keep watching this drag
        }
        dragHandled = true
        if !isVisible {
            shownForDrag = true
            isPeeking = store.items.isEmpty && !settings.showAtCursor
            show(near: settings.showAtCursor ? mouse : nil)
        } else if store.items.isEmpty {
            shownForDrag = true
        }
        watchDragEnd()
    }

    /// Global monitors don't always see the mouse-up that ends another app's drag, so
    /// watch the button state instead.
    private func watchDragEnd() {
        dragEndTimer?.invalidate()
        // 60 Hz while a drag is in progress: the shelf reacts to the pointer approaching.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                guard NSEvent.pressedMouseButtons & 1 == 0 else {
                    self.updateProximity()
                    return
                }
                timer.invalidate()
                self.dragEndTimer = nil
                self.dragProximity = 0
                self.dragEnded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragEndTimer = timer
    }

    private func updateProximity() {
        guard isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let dx = max(frame.minX - mouse.x, 0, mouse.x - frame.maxX)
        let dy = max(frame.minY - mouse.y, 0, mouse.y - frame.maxY)
        let proximity = max(0, 1 - hypot(dx, dy) / (isPeeking ? 340 : 260))
        if abs(proximity - dragProximity) > 0.02 { dragProximity = proximity }
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func dragEnded() {
        guard shownForDrag else { return }
        shownForDrag = false
        // Let a drop on the shelf land before deciding it stayed empty.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.store.items.isEmpty, !self.isDropTargeted else { return }
            self.hide()
        }
    }
}

/// "Add to Sirena Shelf" in the Services menu (declared in Info.plist).
final class ShelfServices: NSObject {
    @objc func addToShelf(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        MainActor.assumeIsolated {
            guard ModuleManager.shared.isRunning(.shelf) else {
                error.pointee = L("Shelf is turned off in Sirena.") as NSString
                return
            }
            if ShelfStore.shared.add(from: pasteboard) {
                ShelfController.shared.show()
            } else {
                error.pointee = L("Nothing on the pasteboard could be added to the shelf.") as NSString
            }
        }
    }
}
