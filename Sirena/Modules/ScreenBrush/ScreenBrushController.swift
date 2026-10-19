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
        NSApp.activate(ignoringOtherApps: true)
        focusOverlayUnderMouse()
        NSCursor.crosshair.set()
        startLaserTimer()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in ScreenBrushController.shared.stopDrawing() }
        }
    }

    func stopDrawing() {
        guard isDrawing else { return }
        overlays.values.forEach { $0.canvas.commitText() }
        isDrawing = false
        removeClickThroughMonitor()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        toolbar?.orderOut(nil)
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
        if event.keyCode == UInt16(kVK_Escape) { stopDrawing(); return true }
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

    func takeScreenshot(forcing action: ScreenBrushSettings.ScreenshotAction? = nil) {
        guard isDrawing, let screen = screenWithMouse() else { return }
        let action = action ?? settings.screenshotAction
        toolbar?.alphaValue = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            let image = await self.capture(screen)
            self.toolbar?.alphaValue = 1
            guard let image else { NSSound.beep(); return }
            self.deliver(image, action: action)
        }
    }

    private func capture(_ screen: NSScreen) async -> NSImage? {
        if CGPreflightScreenCaptureAccess() {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let f = screen.frame
            let rect = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            if let cg = try? await SCScreenshotManager.compatCaptureImage(in: rect) {
                return NSImage(cgImage: cg, size: f.size)
            }
        }
        // No Screen Recording: only the drawing layer.
        guard let canvas = overlays[screen.displayID]?.canvas ?? overlays.values.first?.canvas,
              let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let image = NSImage(size: canvas.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func deliver(_ image: NSImage, action: ScreenBrushSettings.ScreenshotAction) {
        var ok = true
        if action != .save {
            NSPasteboard.general.clearContents()
            ok = NSPasteboard.general.writeObjects([image])
        }
        if action != .copy {
            do {
                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
                      let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                else { throw CocoaError(.fileWriteUnknown) }
                let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                    .replacingOccurrences(of: ":", with: ".")
                try png.write(to: pictures.appending(path: "\(L("Freehand Drawing")) \(stamp).png"))
            } catch {
                ok = false
            }
        }
        if ok { Self.shutter?.play() } else { NSSound.beep() }
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
