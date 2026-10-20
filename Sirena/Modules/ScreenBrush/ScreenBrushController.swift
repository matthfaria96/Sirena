/// ScreenBrushController.swift
///
/// Desenho Livre: draw, highlight and point on top of everything. Written from scratch
/// for Sirena; ScreenBrush (closed source) only inspired the feature list.

import SwiftUI
import Carbon.HIToolbox
import MASShortcut
import ScreenCaptureKit

/// Entry point of the module (Sirena contract: start, terminate, status, quick action).
@MainActor
@Observable
final class ScreenBrushController {
    static let shared = ScreenBrushController()
    private(set) var isRunning = false
    private(set) var isDrawing = false
    let document = BrushDocument()

    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private var overlays: [CGDirectDisplayID: BrushOverlayPanel] = [:]
    @ObservationIgnored private var clickThroughMonitor: Any?
    @ObservationIgnored private var escapeMonitor: Any?
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var toolbar: BrushToolbarPanel?
    @ObservationIgnored private var laserTimer: Timer?
    @ObservationIgnored private var screensObserver: NSObjectProtocol?

    private var settings: ScreenBrushSettings { .shared }

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        document.onChange = { [weak self] change in self?.overlays.values.forEach { $0.canvas.handle(change) } }

        let binder = MASShortcutBinder.shared()
        binder?.registerDefaultShortcuts([
            ScreenBrushSettings.toggleShortcutKey: MASShortcut(keyCode: kVK_ANSI_D, modifierFlags: [.control, .option, .command])
        ])
        binder?.bindShortcut(withDefaultsKey: ScreenBrushSettings.toggleShortcutKey) { [weak self] in
            self?.quickAction()
        }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDrawing else { return }
                self.rebuildOverlays()
            }
        }
    }

    func terminate() {
        guard isRunning else { return }
        stopDrawing()
        document.reset()
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: ScreenBrushSettings.toggleShortcutKey)
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        screensObserver = nil
        toolbar = nil
        isRunning = false
    }

    /// Whether it is doing something right now (Home's check).
    var isActive: Bool { isDrawing }
    /// One live status line for Home.
    var statusText: String {
        if isDrawing { return L("Drawing — Esc to leave") }
        let stored = UserDefaults.standard.dictionary(forKey: ScreenBrushSettings.toggleShortcutKey)
        let shortcut = stored.flatMap { MASDictionaryTransformer().transformedValue($0) as? MASShortcut }
        if let shortcut { return L("Ready — \(shortcut.modifierFlagsString + (shortcut.keyCodeString ?? "")) to draw") }
        return L("Ready")
    }
    /// The main action, from Home, the sidebar card and the ⚡ menu.
    func quickAction() {
        isDrawing ? stopDrawing() : startDrawing()
    }

    // MARK: Drawing mode

    func startDrawing() {
        guard isRunning, !isDrawing else { return }
        if !settings.keepStrokes { document.reset() }
        isDrawing = true
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        rebuildOverlays()
        // macOS may refuse to bring a background app forward (cooperative activation);
        // then the overlay never gets the keyboard, so Esc is also watched globally below.
        SirenaActivation.activateForTool()
        focusOverlayUnderMouse()
        NSCursor.crosshair.set()
        startLaserTimer()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in ScreenBrushController.shared.escapePressed() }
        }
    }

    /// Esc: cancels picking an area first; a second Esc leaves drawing mode.
    func escapePressed() {
        if areaSelector.isSelecting { areaSelector.cancel() } else { stopDrawing() }
    }

    func stopDrawing() {
        guard isDrawing else { return }
        areaSelector.cancel()
        overlays.values.forEach { $0.canvas.commitText() }
        isDrawing = false
        removeClickThroughMonitor()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        toolbar?.orderOut(nil)
        toolbar?.alphaValue = 1
        laserTimer?.invalidate()
        laserTimer = nil
        if !settings.keepStrokes { document.reset() } else { document.current = nil; document.clickThrough = false }
        NSCursor.arrow.set()
        previousApp?.activate()
        previousApp = nil
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func rebuildOverlays() {
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        let screens = settings.allScreens ? NSScreen.screens : [screenWithMouse()].compactMap { $0 }
        for screen in screens {
            let panel = BrushOverlayPanel(screen: screen, document: document)
            panel.ignoresMouseEvents = document.clickThrough
            panel.orderFrontRegardless()
            overlays[panel.displayID] = panel
        }
        if isDrawing { focusOverlayUnderMouse() }
    }

    /// Keyboard to the overlay under the pointer, toolbar onto that screen.
    private func focusOverlayUnderMouse() {
        guard let screen = screenWithMouse() else { return }
        overlays[screen.displayID]?.makeKeyAndOrderFront(nil)
        if settings.showToolbar {
            let panel = toolbar ?? BrushToolbarPanel(document: document)
            toolbar = panel
            // Hidden while a screenshot is taken: never come back invisible.
            panel.alphaValue = 1
            panel.place(on: screen)
            panel.orderFrontRegardless()
        }
    }

    func startLaserTimer() {
        guard laserTimer == nil, isDrawing else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let delay = self.settings.laserDelay
                if !self.document.tickLasers(delay: delay) {
                    self.laserTimer?.invalidate()
                    self.laserTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        laserTimer = timer
    }

    func cycleBackground() {
        let all = BrushBackground.allCases
        let index = all.firstIndex(of: document.background) ?? 0
        document.background = all[(index + 1) % all.count]
    }

    func toggleClickThrough() {
        document.clickThrough.toggle()
        overlays.values.forEach { $0.ignoresMouseEvents = document.clickThrough }
        NSCursor.arrow.set()
        removeClickThroughMonitor()
        if document.clickThrough {
            // Other apps get the keyboard now: still listen for G (Esc is watched while drawing).
            clickThroughMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
                Task { @MainActor in
                    let controller = ScreenBrushController.shared
                    if keyCode == UInt16(kVK_ANSI_G), plain { controller.toggleClickThrough() }
                }
            }
        } else {
            focusOverlayUnderMouse()
        }
    }

    private func removeClickThroughMonitor() {
        if let clickThroughMonitor { NSEvent.removeMonitor(clickThroughMonitor) }
        clickThroughMonitor = nil
    }

    // MARK: Keys

    /// Keys while drawing. Returns false when the key isn't ours.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == UInt16(kVK_Escape) { escapePressed(); return true }
        if flags.contains(.command) {
            switch event.keyCode {
            case UInt16(kVK_ANSI_Z): flags.contains(.shift) ? document.redo() : document.undo()
            case UInt16(kVK_Delete): document.clear()
            case UInt16(kVK_ANSI_S): takeScreenshot()
            case UInt16(kVK_ANSI_C): takeScreenshot(forcing: .copy)
            default: return false
            }
            return true
        }
        guard let c = chars.first else { return false }
        if let digit = c.wholeNumberValue, digit >= 1, digit <= BrushTool.available.count {
            settings.tool = BrushTool.available[digit - 1]
            return true
        }
        if let tool = BrushTool.available.first(where: { $0.key == c }) { settings.tool = tool; return true }
        switch c {
        case "[": settings.width = max(1, settings.width - 1)
        case "]": settings.width = min(24, settings.width + 1)
        case "c": settings.colorIndex = (settings.colorIndex + 1) % BrushPalette.colors.count
        default: return false
        }
        return true
    }

    // MARK: Screenshot

    /// The same shutter sound as macOS screenshots.
    private static let shutter = NSSound(contentsOfFile:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true) ?? NSSound(named: "Tink")

    private let areaSelector = ScreenBrushAreaSelector()

    /// A screenshot of the screen with the drawing. By default the user picks an area first
    /// (like ⇧⌘4); `area` and `action` override the settings for one shot.
    func takeScreenshot(area: ScreenBrushSettings.ScreenshotArea? = nil,
                        forcing action: ScreenBrushSettings.ScreenshotAction? = nil) {
        guard isDrawing, !areaSelector.isSelecting, let screen = screenWithMouse() else { return }
        let action = action ?? settings.screenshotAction
        switch area ?? settings.screenshotArea {
        case .fullScreen:
            shoot(screen.frame, action: action)
        case .selection:
            toolbar?.alphaValue = 0
            areaSelector.begin { [weak self] rect in
                guard let self else { return }
                guard let rect else {
                    self.toolbar?.alphaValue = 1
                    return
                }
                self.shoot(rect, action: action)
            }
        }
    }

    /// Captures `rect` (global AppKit coordinates) once the toolbar and the selection are gone.
    private func shoot(_ rect: CGRect, action: ScreenBrushSettings.ScreenshotAction) {
        toolbar?.alphaValue = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            let image = await self.capture(rect)
            self.toolbar?.alphaValue = 1
            guard let image else { NSSound.beep(); return }
            self.deliver(image, action: action)
        }
    }

    private func capture(_ rect: CGRect) async -> NSImage? {
        if CGPreflightScreenCaptureAccess() {
            // ScreenCaptureKit wants a top-left origin measured from the primary display.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
            let topLeft = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
            if let cg = try? await SCScreenshotManager.compatCaptureImage(in: topLeft) {
                return NSImage(cgImage: cg, size: rect.size)
            }
        }
        return drawingOnly(in: rect)
    }

    /// Without Screen Recording: only the drawing layer, cropped to `rect`.
    private func drawingOnly(in rect: CGRect) -> NSImage? {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) }
        guard let screen, let canvas = overlays[screen.displayID]?.canvas ?? overlays.values.first?.canvas,
              let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let local = rect.intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let scale = CGFloat(rep.pixelsWide) / canvas.bounds.width
        // The bitmap's rows start at the top: flip the y of the crop.
        let pixels = CGRect(x: local.minX * scale, y: (canvas.bounds.height - local.maxY) * scale,
                            width: local.width * scale, height: local.height * scale).integral
        guard let full = rep.cgImage, let cropped = full.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: cropped, size: local.size)
    }

    private func deliver(_ image: NSImage, action: ScreenBrushSettings.ScreenshotAction) {
        guard let png = Self.pngData(image) else { NSSound.beep(); return }
        var ok = true
        if action != .save {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            // PNG and TIFF, so every app finds a type it pastes.
            ok = pasteboard.setData(png, forType: .png) && (image.tiffRepresentation.map { pasteboard.setData($0, forType: .tiff) } ?? true)
        }
        if action != .copy {
            do {
                try png.write(to: try Self.screenshotsFolder().appending(path: Self.fileName()))
            } catch {
                NSLog("Sirena Freehand Drawing: saving the screenshot failed: \(error.localizedDescription)")
                ok = false
            }
        }
        if ok { Self.shutter?.play() } else { NSSound.beep() }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Pictures › Screenshots, created when missing.
    static func screenshotsFolder() throws -> URL {
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = pictures.appending(path: "Screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "Desenho Livre 2026-10-19 às 19.04.39.png", in local time like macOS's own screenshots.
    private static func fileName() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: now)
        return "\(L("Freehand Drawing")) \(L("\(day) at \(time)")).png"
    }


    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
