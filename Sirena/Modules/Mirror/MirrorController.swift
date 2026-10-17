/// MirrorController.swift
///
/// Sirena's camera mirror. Click the menu bar icon and the camera drops down below it,
/// like a hand mirror; click anywhere else and it goes away. It can also live in a
/// floating window, open when the pointer rests on the notch, take Snaps (photos)
/// and show the microphone level. The global shortcut comes from Iris (MIT).

import AVFoundation
import AppKit
import MASShortcut

/// Observable mirror state for SwiftUI (the controller itself is an NSObject).
@MainActor
@Observable
final class MirrorState {
    static let shared = MirrorState()
    var isVisible = false
    /// Seconds left of a peek from the menu (nil when not peeking).
    var peekRemaining: Int?
}

@MainActor
final class MirrorController: NSObject {
    static let shared = MirrorController()
    /// No dots: MASShortcut reaches it through a key path.
    static let shortcutKey = "mirrorShortcutToggle"

    private let settings = MirrorSettings.shared
    /// Sirena's single menu bar item: the mirror drops down below it.
    private var anchorButton: NSStatusBarButton? { SirenaStatusItem.instance.button }
    private var started = false
    private lazy var panel = MirrorPanel()

    private var outsideClickMonitor: Any?
    private var notchMonitors: [Any] = []
    private var dwellTimer: Timer?
    private var leaveTimer: Timer?
    private var openedFromNotch = false

    var onOpenSettings: (() -> Void)?

    private(set) var isVisible = false {
        didSet { MirrorState.shared.isVisible = isVisible }
    }
    var isRunning: Bool { started }

    // MARK: - Lifecycle

    func start(openSettings: @escaping () -> Void) {
        guard !started else { return }
        started = true
        onOpenSettings = openSettings

        // Same shortcut recorder as every other feature (MASShortcut); a shortcut set with
        // Iris's old recorder is carried over once.
        let preferences = PreferencesManager.shared
        if preferences.toggleHotkeyEnabled {
            migrateShortcut(to: Self.shortcutKey, keyCode: Int(preferences.toggleHotkeyKeyCode),
                            modifiers: NSEvent.ModifierFlags(rawValue: preferences.toggleHotkeyModifiers))
            preferences.toggleHotkeyEnabled = false
        }
        MASShortcutBinder.shared()?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: Self.shortcutKey) { [weak self] in self?.toggle() }

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .mirrorSettingsChanged, object: nil)
        updateNotchTrigger()
    }

    func terminate() {
        hide()
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.shortcutKey)
    }

    @objc private func settingsChanged() {
        updateNotchTrigger()
        if isVisible {
            layoutPanel(animated: true)
            settings.showMicrophoneLevel ? MirrorAudioMeter.shared.start() : MirrorAudioMeter.shared.stop()
        }
    }

    // MARK: - Show / hide

    func toggle() {
        openedFromNotch = false
        (isVisible || showTask != nil) ? hide() : show()
    }

    private var peekTimer: Timer?

    /// "Espiar" from the menu: the camera drops down below the menu bar for a few
    /// seconds (10 unless changed on its page) with a countdown, then goes away.
    func peek() {
        if isVisible || showTask != nil { hide(); return }
        openedFromNotch = false
        show { [weak self] in self?.startPeekCountdown() }
    }

    private func startPeekCountdown() {
        let state = MirrorState.shared
        state.peekRemaining = settings.peekSeconds
        peekTimer?.invalidate()
        peekTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, let left = state.peekRemaining else {
                    timer.invalidate(); state.peekRemaining = nil; return
                }
                if left <= 1 {
                    timer.invalidate()
                    state.peekRemaining = nil
                    self.hide()
                } else {
                    state.peekRemaining = left - 1
                }
            }
        }
    }

    /// The camera starting (and, the first time, asking for access) before showing.
    private var showTask: Task<Void, Never>?

    func show(onShown: (() -> Void)? = nil) {
        guard showTask == nil else { return }
        showTask = Task { @MainActor in
            defer { showTask = nil }
            do {
                try await MirrorCamera.shared.start()
            } catch {
                presentError(error)
                return
            }
            guard !Task.isCancelled else {
                MirrorCamera.shared.stop()
                return
            }
            isVisible = true
            onShown?()
            layoutPanel(animated: false)
            let target = panel.frame
            let dropsDown = settings.displayMode == .popover || openedFromNotch
            if dropsDown {
                // Unrolls downward from the menu bar, like a curtain, for a quick look.
                var start = target
                start.size.height = 24
                start.origin.y = target.maxY - start.height
                panel.setFrame(start, display: false)
            }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = dropsDown ? 0.32 : 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.1, 0.35, 1)
                self.panel.animator().alphaValue = 1
                if dropsDown { self.panel.animator().setFrame(target, display: true) }
            }, completionHandler: nil)
            if settings.showMicrophoneLevel { MirrorAudioMeter.shared.start() }
            installOutsideClickMonitor()
        }
    }

    func hide() {
        if let showTask, !isVisible {
            // Still starting: don't appear at all.
            showTask.cancel()
            self.showTask = nil
            return
        }
        guard isVisible else { return }
        peekTimer?.invalidate()
        peekTimer = nil
        MirrorState.shared.peekRemaining = nil
        isVisible = false
        openedFromNotch = false
        removeOutsideClickMonitor()
        if settings.displayMode == .window {
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "mirror.windowOrigin")
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            MirrorCamera.shared.stop()
            MirrorAudioMeter.shared.stop()
        })
    }

    func toggleDisplayMode() {
        settings.displayMode = settings.displayMode == .popover ? .window : .popover
        if isVisible {
            layoutPanel(animated: true)
            installOutsideClickMonitor()
        }
    }

    func openSettings() {
        if settings.displayMode == .popover { hide() }
        onOpenSettings?()
    }

    // MARK: - Layout

    private var panelSize: NSSize {
        let width = settings.size.width
        return NSSize(width: width, height: settings.shape == .circle ? width : (width * 0.75).rounded())
    }

    private func layoutPanel(animated: Bool) {
        let size = panelSize
        var origin: NSPoint

        switch (settings.displayMode, openedFromNotch) {
        case (_, true):
            guard let screen = triggerScreen() else { return }
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8)
        case (.popover, false):
            if let buttonFrame = anchorButton?.window?.frame {
                origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 6)
            } else {
                let screen = NSScreen.main ?? NSScreen.screens[0]
                origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 12, y: screen.visibleFrame.maxY - size.height - 8)
            }
        case (.window, false):
            if let saved = UserDefaults.standard.string(forKey: "mirror.windowOrigin") {
                origin = NSPointFromString(saved)
            } else {
                let screen = NSScreen.main ?? NSScreen.screens[0]
                origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 24, y: screen.visibleFrame.maxY - size.height - 24)
            }
        }

        var frame = NSRect(origin: origin, size: size)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }

        let isWindow = settings.displayMode == .window && !openedFromNotch
        panel.isMovableByWindowBackground = isWindow
        panel.level = isWindow ? .floating : .statusBar
        panel.setFrame(frame, display: true, animate: animated)
    }

    // MARK: - Closing when clicking elsewhere (popover mode)

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        guard settings.displayMode == .popover || openedFromNotch else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            // On macOS 26+ clicks on our own status item also reach global monitors;
            // the status item's own action toggles the mirror, so leave those alone.
            if let buttonFrame = self.anchorButton?.window?.frame,
               buttonFrame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) {
                return
            }
            self.hide()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    // MARK: - Notch trigger

    private func updateNotchTrigger() {
        notchMonitors.forEach { NSEvent.removeMonitor($0) }
        notchMonitors = []
        guard settings.notchTrigger else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in self?.pointerMoved() }) {
            notchMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) {
            notchMonitors.append(local)
        }
    }

    private func triggerScreen() -> NSScreen? {
        switch settings.triggerDisplay {
        case .main:
            return NSScreen.screens.first ?? NSScreen.main
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        }
    }

    /// The notch on Macs that have one, otherwise a strip at the top center of the screen.
    private func triggerRect(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            return NSRect(x: left.maxX, y: frame.maxY - screen.safeAreaInsets.top, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        }
        return NSRect(x: frame.midX - 110, y: frame.maxY - 4, width: 220, height: 4)
    }

    private func pointerMoved() {
        let mouse = NSEvent.mouseLocation
        guard let screen = triggerScreen() else { return }
        let trigger = triggerRect(on: screen)
        let inTrigger = trigger.insetBy(dx: 0, dy: -1).contains(mouse)

        if isVisible {
            guard openedFromNotch else { return }
            let keepArea = panel.frame.union(trigger).insetBy(dx: -30, dy: -30)
            if keepArea.contains(mouse) {
                leaveTimer?.invalidate()
                leaveTimer = nil
            } else if leaveTimer == nil {
                leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.leaveTimer = nil
                    self?.hide()
                }
            }
            return
        }

        if inTrigger {
            guard dwellTimer == nil else { return }
            dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.dwellTimer = nil
                if let screen = self.triggerScreen(),
                   self.triggerRect(on: screen).insetBy(dx: 0, dy: -1).contains(NSEvent.mouseLocation) {
                    self.openedFromNotch = true
                    self.show()
                }
            }
        } else {
            dwellTimer?.invalidate()
            dwellTimer = nil
        }
    }

    // MARK: - Snaps

    func takeSnap() {
        MirrorCamera.shared.capturePhoto { [weak self] image in
            guard let self, var image else { return }
            if self.settings.mirrored { image = image.flippedHorizontally() }
            NotificationCenter.default.post(name: .mirrorDidSnap, object: nil)
            NSSound(named: "Tink")?.play()

            if self.settings.snapsCopyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            guard let tiff = image.tiffRepresentation,
                  let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
            else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
            let url = self.settings.snapsFolder.appendingPathComponent("Snap \(formatter.string(from: Date())).jpg")
            try? jpeg.write(to: url)
        }
    }

    private func presentError(_ error: Error) {
        presentError(error.localizedDescription)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L("Camera Access Required")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension NSImage {
    func flippedHorizontally() -> NSImage {
        let flipped = NSImage(size: size)
        flipped.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: size.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()
        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
        flipped.unlockFocus()
        return flipped
    }
}
