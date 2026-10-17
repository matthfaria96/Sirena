/// PinnedWindow.swift
///
/// One pinned window: a live copy of it floating above every other window, kept on top
/// of the real one. Using the copy (click or hover, see PinActivationMode) hides it and
/// brings the real window forward; the copy comes back when the real window loses focus.

import AppKit
import ApplicationServices
import ScreenCaptureKit

@MainActor
@Observable
final class PinnedWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String?
    private(set) var title: String

    var opacity: Double {
        didSet { applyVisibility() }
    }

    /// When the window unpins itself, if scheduled.
    private(set) var unpinDate: Date?

    /// The real window is in front and in use; the copy is hidden.
    private(set) var isPassingThrough = false

    /// Frame in Core Graphics global coordinates.
    @ObservationIgnored private(set) var frame: CGRect
    @ObservationIgnored private var isMinimized = false
    /// Where the window's traffic lights are, relative to its top-left corner.
    @ObservationIgnored private var trafficLightsOffset: CGRect? {
        didSet { hasTrafficLights = trafficLightsOffset != nil }
    }
    /// Whether the control sits on the window's traffic lights; otherwise `controlPosition` places it.
    private(set) var hasTrafficLights = false
    /// Corner for the control on a window without traffic lights, saved per app.
    var controlPosition: PinControlPosition {
        didSet {
            PinControlPosition.save(controlPosition, for: bundleID)
            layoutControl()
        }
    }
    /// Hover activation waits until the pointer has left the window once, so a window
    /// restored while the pointer is still over it doesn't jump straight back.
    @ObservationIgnored var hoverArmed = true
    @ObservationIgnored var hoverStart: Date?

    @ObservationIgnored private let mirror = PinMirrorPanel()
    @ObservationIgnored private let control = PinControlPanel()
    @ObservationIgnored private let capture = PinCapture()
    @ObservationIgnored private var axWindow: AXUIElement?
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var unpinTimer: Timer?

    /// Asks the controller to unpin this window.
    @ObservationIgnored var onUnpin: ((PinnedWindow) -> Void)?

    private var settings: PinWindowSettings { .shared }

    var displayName: String { title.isEmpty ? appName : title }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }

    /// Frame in Cocoa screen coordinates.
    var cocoaFrame: CGRect { PinGeometry.cocoaRect(fromCG: frame) }
    /// The pin control over the traffic lights, in Cocoa screen coordinates.
    var controlFrame: CGRect { control.frame }

    init(window: PinnableWindow, opacity: Double) {
        id = window.id
        pid = window.pid
        appName = window.appName
        bundleID = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier
        controlPosition = PinControlPosition.saved(for: bundleID)
        title = window.title
        frame = window.frame
        self.opacity = opacity
        mirror.onActivate = { [weak self] in self?.activateRealWindow() }
        control.onClick = { [weak self] view in self?.showMenu(from: view) }
    }

    // MARK: - Lifecycle

    func start(_ scWindow: SCWindow) async throws {
        axWindow = PinAX.window(id: id, pid: pid)
        if let axWindow, let axFrame = PinAX.frame(of: axWindow) {
            frame = axFrame
        }
        capture.onFrame = { [weak self] surface in
            self?.mirror.contentLayer.contents = surface
        }
        capture.onStop = { [weak self] _ in
            // Sleep, locking the screen or a display change stop the stream: start it
            // again while the window is still there, and only unpin if that fails.
            Task { @MainActor [weak self] in await self?.restartCapture() }
        }
        try await capture.start(window: scWindow, pixelSize: pixelSize)
        installObserver()
        measureTrafficLights()
        applySettings()
        applyFrame()
        applyVisibility()
    }

    func stop() {
        unpinTimer?.invalidate()
        unpinTimer = nil
        capture.stop()
        removeObserver()
        mirror.orderOut(nil)
        control.orderOut(nil)
        mirror.contentLayer.contents = nil
    }

    // MARK: - Settings & layout

    func applySettings() {
        let behavior: NSWindow.CollectionBehavior = settings.allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        mirror.collectionBehavior = behavior
        control.collectionBehavior = behavior
    }

    @ObservationIgnored private var restartAttempts = 0

    private func restartCapture() async {
        guard restartAttempts < 5 else { onUnpin?(self); return }
        restartAttempts += 1
        try? await Task.sleep(for: .seconds(1))
        guard WindowList.window(id: id) != nil,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
              let scWindow = content.windows.first(where: { $0.windowID == id }) else {
            onUnpin?(self)
            return
        }
        capture.stop()
        capture.onFrame = { [weak self] surface in self?.mirror.contentLayer.contents = surface }
        capture.onStop = { [weak self] _ in
            Task { @MainActor [weak self] in await self?.restartCapture() }
        }
        do {
            try await capture.start(window: scWindow, pixelSize: pixelSize)
            restartAttempts = 0
        } catch {
            onUnpin?(self)
        }
    }

    private var pixelSize: CGSize {
        let frame = cocoaFrame
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = lhs.frame.intersection(frame), b = rhs.frame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }

    @ObservationIgnored private var resizeWork: DispatchWorkItem?

    private func applyFrame() {
        mirror.setFrame(cocoaFrame, display: true)
        layoutControl()
        // During a live resize the window reports dozens of sizes a second: reconfigure the
        // capture once it settles.
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.capture.resize(to: self.pixelSize)
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Finds the traffic lights through Accessibility. They keep their place relative to
    /// the window's top-left corner, so this only runs when pinning and on resize.
    private func measureTrafficLights() {
        guard let axWindow, let lights = PinAX.trafficLightsFrame(of: axWindow) else { return }
        trafficLightsOffset = lights.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// Lays the pin control over the traffic lights (or where they usually are).
    private func layoutControl() {
        let height: CGFloat = 24
        // Core Graphics frame (y down).
        let cgRect: CGRect
        if let lights = trafficLightsOffset {
            let width = max(lights.width + 14, 60)
            cgRect = CGRect(x: frame.minX + lights.midX - width / 2, y: frame.minY + lights.midY - height / 2,
                            width: width, height: height)
        } else {
            let width: CGFloat = 60
            let inset: CGFloat = 10
            let x = controlPosition == .topLeft || controlPosition == .bottomLeft
                ? frame.minX + inset : frame.maxX - width - inset
            let y = controlPosition == .topLeft || controlPosition == .topRight
                ? frame.minY + inset : frame.maxY - height - inset
            cgRect = CGRect(x: x, y: y, width: width, height: height)
        }
        control.setFrame(PinGeometry.cocoaRect(fromCG: cgRect), display: true)
    }

    /// The control stays over the traffic lights whether the window is in use or not;
    /// it only goes away while the window is minimized.
    private func applyVisibility() {
        let hidden = isPassingThrough || isMinimized
        mirror.alphaValue = hidden ? 0 : opacity
        mirror.ignoresMouseEvents = hidden
        if !hidden {
            mirror.orderFrontRegardless()
        }
        if isMinimized {
            control.orderOut(nil)
        } else {
            control.orderFrontRegardless()
        }
    }

    // MARK: - Handing over to the real window

    func activateRealWindow() {
        if axWindow == nil { axWindow = PinAX.window(id: id, pid: pid) }
        isPassingThrough = true
        hoverStart = nil
        applyVisibility()
        PinAX.activate(window: axWindow, pid: pid)
    }

    /// Puts the floating copy back on top.
    func restore() {
        guard isPassingThrough else { return }
        isPassingThrough = false
        applyVisibility()
    }

    /// Checks the real window still exists and where it is. Used as a fallback to the
    /// Accessibility notifications, which some apps don't send.
    func poll() {
        guard let (window, _) = WindowList.window(id: id) else {
            onUnpin?(self)
            return
        }
        if !window.title.isEmpty, window.title != title { title = window.title }
        if let axWindow {
            setMinimized(PinAX.isMinimized(axWindow))
        }
        if window.frame != frame {
            let resized = window.frame.size != frame.size
            frame = window.frame
            if resized { measureTrafficLights() }
            applyFrame()
        }
    }

    private func setMinimized(_ minimized: Bool) {
        guard minimized != isMinimized else { return }
        isMinimized = minimized
        applyVisibility()
    }

    // MARK: - Auto unpin

    func scheduleUnpin(minutes: Int) {
        unpinTimer?.invalidate()
        unpinTimer = nil
        guard minutes > 0 else {
            unpinDate = nil
            return
        }
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        unpinDate = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onUnpin?(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        unpinTimer = timer
    }

    // MARK: - Pin control menu

    private func showMenu(from view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(PinMenuItem(L("Unpin"), symbol: "pin.slash.fill") { [weak self] in
            guard let self else { return }
            self.onUnpin?(self)
        })
        menu.addItem(.separator())

        let window = axWindow ?? PinAX.window(id: id, pid: pid)
        let minimize = PinMenuItem(L("Minimize"), image: TrafficLightIcon.minimize.image) { [weak self] in
            guard let self, let window else { return }
            PinAX.minimize(window)
            self.setMinimized(true)
        }
        let maximize = PinMenuItem(L("Maximize"), image: TrafficLightIcon.zoom.image) { [weak self] in
            guard let self, let window else { return }
            PinAX.maximize(window, currentFrame: self.frame)
        }
        let close = PinMenuItem(L("Close"), image: TrafficLightIcon.close.image) { [weak self] in
            guard let self, let window else { return }
            self.onUnpin?(self)
            PinAX.close(window)
        }
        for item in [minimize, maximize, close] {
            item.isEnabled = window != nil
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }

    // MARK: - Accessibility notifications

    private static let windowNotifications = [
        kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification
    ]
    private static let appNotifications = [kAXFocusedWindowChangedNotification, kAXApplicationDeactivatedNotification]

    private func installObserver() {
        guard let axWindow else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, pinAXCallback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(created, axWindow, name as CFString, refcon)
        }
        let app = AXUIElementCreateApplication(pid)
        for name in Self.appNotifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func removeObserver() {
        guard let observer else { return }
        if let axWindow {
            for name in Self.windowNotifications {
                AXObserverRemoveNotification(observer, axWindow, name as CFString)
            }
        }
        let app = AXUIElementCreateApplication(pid)
        for name in Self.appNotifications {
            AXObserverRemoveNotification(observer, app, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
    }

    fileprivate func handleAccessibility(_ notification: String) {
        switch notification {
        case kAXMovedNotification, kAXResizedNotification:
            if let axWindow, let axFrame = PinAX.frame(of: axWindow), axFrame != frame {
                let resized = axFrame.size != frame.size
                frame = axFrame
                if resized { measureTrafficLights() }
                applyFrame()
            }
        case kAXUIElementDestroyedNotification:
            onUnpin?(self)
        case kAXWindowMiniaturizedNotification:
            setMinimized(true)
        case kAXWindowDeminiaturizedNotification:
            setMinimized(false)
        case kAXTitleChangedNotification:
            if let (window, _) = WindowList.window(id: id), !window.title.isEmpty { title = window.title }
        case kAXFocusedWindowChangedNotification:
            if isPassingThrough, PinAX.focusedWindowID(pid: pid) != id { restoreAfterFocusLoss() }
        case kAXApplicationDeactivatedNotification:
            if isPassingThrough { restoreAfterFocusLoss() }
        default:
            break
        }
    }

    /// The real window lost focus: put the copy back, and don't let hover activate it
    /// again until the pointer has left it.
    func restoreAfterFocusLoss() {
        let pointerInside = cocoaFrame.contains(NSEvent.mouseLocation)
        if pointerInside { hoverArmed = false }
        restore()
    }
}

private func pinAXCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let pin = Unmanaged<PinnedWindow>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        pin.handleAccessibility(name)
    }
}
