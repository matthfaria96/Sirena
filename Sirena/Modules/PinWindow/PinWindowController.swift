/// PinWindowController.swift
///
/// Pin Window, modeled on Floaty: keeps any window of any app above all the others,
/// with adjustable opacity. Several windows can be pinned at once.

import AppKit
import Carbon.HIToolbox
import MASShortcut
import ScreenCaptureKit

@MainActor
@Observable
final class PinWindowController {
    static let shared = PinWindowController()

    /// Pinned windows, oldest first (the newest one is on top).
    private(set) var pins: [PinnedWindow] = []
    /// Windows being pinned right now (waiting for ScreenCaptureKit).
    private(set) var pending: Set<CGWindowID> = []
    private(set) var isRunning = false

    @ObservationIgnored private let picker = WindowPicker()
    @ObservationIgnored private let shake = ShakeDetector()
    @ObservationIgnored private var tracker: Timer?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var openPage: () -> Void = {}

    private var settings: PinWindowSettings { .shared }

    private init() {}

    // MARK: - Module lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage

        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.registerDefaultShortcuts([
            PinWindowSettings.selectShortcutKey: MASShortcut(keyCode: kVK_ANSI_P, modifierFlags: [.control, .option, .command])
        ])
        binder?.bindShortcut(withDefaultsKey: PinWindowSettings.selectShortcutKey) { [weak self] in self?.selectWindowToPin() }
        binder?.bindShortcut(withDefaultsKey: PinWindowSettings.toggleFrontShortcutKey) { [weak self] in self?.toggleFrontWindow() }
        binder?.bindShortcut(withDefaultsKey: PinWindowSettings.unpinAllShortcutKey) { [weak self] in self?.unpinAll() }

        shake.onShake = { [weak self] window in self?.toggle(window) }
        shake.isEnabled = settings.shakeToPin

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .pinWindowSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.applicationActivated(pid) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                for pin in self.pins where pin.pid == pid { self.unpin(pin.id) }
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pins.forEach { $0.poll() } }
        })
    }

    func terminate() {
        unpinAll()
        shake.isEnabled = false
        picker.cancel()
        let binder = MASShortcutBinder.shared()
        for key in [PinWindowSettings.selectShortcutKey, PinWindowSettings.toggleFrontShortcutKey, PinWindowSettings.unpinAllShortcutKey] {
            binder?.breakBinding(withDefaultsKey: key)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        isRunning = false
    }

    private func settingsChanged() {
        shake.isEnabled = settings.shakeToPin
        pins.forEach { $0.applySettings() }
        // The tracker's pace depends on the activation mode.
        if tracker != nil {
            stopTracking()
            startTracking()
        }
    }

    // MARK: - Permissions

    var hasAccessibility: Bool { PinAX.isTrusted }
    var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccessibility() {
        PinAX.requestTrust()
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            openPrivacySettings("Privacy_ScreenCapture")
        }
    }

    func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Screen Recording is required (the pinned copy is a capture of the window);
    /// Accessibility is asked for too, it lets the copy follow and activate the window.
    private static var askedForAccessibility = false

    private func ensurePermissions() -> Bool {
        // Ask the system for Accessibility once per session, not on every pin.
        if !hasAccessibility && !Self.askedForAccessibility {
            Self.askedForAccessibility = true
            requestAccessibility()
        }
        guard hasScreenRecording else {
            // A single explanation with a way to fix it (no system prompt + Settings + alert).
            let alert = NSAlert()
            alert.messageText = L("Pin Window needs Screen Recording")
            alert.informativeText = L("Allow Sirena in System Settings › Privacy & Security › Screen & System Audio Recording, then restart Sirena.")
            alert.addButton(withTitle: L("Open System Settings"))
            alert.addButton(withTitle: L("Cancel"))
            SirenaActivation.activateForTool()
            if alert.runModal() == .alertFirstButtonReturn {
                openPrivacySettings("Privacy_ScreenCapture")
            }
            return false
        }
        return true
    }

    // MARK: - Pinning

    func isPinned(_ id: CGWindowID) -> Bool {
        pins.contains { $0.id == id }
    }

    func pin(for id: CGWindowID) -> PinnedWindow? {
        pins.first { $0.id == id }
    }

    func toggle(_ window: PinnableWindow) {
        if isPinned(window.id) {
            unpin(window.id)
        } else {
            pin(window)
        }
    }

    func pin(_ window: PinnableWindow) {
        guard isRunning, !isPinned(window.id), !pending.contains(window.id), ensurePermissions() else { return }
        pending.insert(window.id)
        Task {
            defer { pending.remove(window.id) }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                    throw PinError.windowGone
                }
                let pin = PinnedWindow(window: window, opacity: settings.defaultOpacity)
                pin.onUnpin = { [weak self] pin in self?.unpin(pin.id) }
                try await pin.start(scWindow)
                // The module may have been turned off, or the window closed, meanwhile.
                guard isRunning, WindowList.window(id: window.id) != nil else {
                    pin.stop()
                    return
                }
                pin.scheduleUnpin(minutes: settings.autoUnpinMinutes)
                pins.append(pin)
                startTracking()
            } catch {
                presentError(error)
            }
        }
    }

    func unpin(_ id: CGWindowID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        let pin = pins.remove(at: index)
        pin.onUnpin = nil
        pin.stop()
        if pins.isEmpty { stopTracking() }
    }

    func unpinAll() {
        for pin in pins { unpin(pin.id) }
    }

    /// "Click a window to select it for pinning".
    func selectWindowToPin() {
        guard isRunning else { return }
        if picker.isActive {
            picker.cancel()
            return
        }
        picker.begin(isPinned: { [weak self] in self?.isPinned($0) ?? false }) { [weak self] window in
            if let window { self?.toggle(window) }
        }
    }

    /// Pins the focused window of the front-most app, or unpins it if it is pinned.
    func toggleFrontWindow() {
        guard isRunning else { return }
        if !hasAccessibility {
            requestAccessibility()
            return
        }
        guard let id = PinAX.frontWindowID() else { NSSound.beep(); return }
        if isPinned(id) {
            unpin(id)
        } else if let window = WindowList.window(id: id)?.window {
            pin(window)
        }
    }

    /// The window the front-most app has focused, if pinning it makes sense.
    var frontWindow: PinnableWindow? {
        PinAX.frontWindowID().flatMap { WindowList.window(id: $0)?.window }
    }

    // MARK: - Hover, click and tracking

    private func applicationActivated(_ pid: pid_t?) {
        for pin in pins where pin.isPassingThrough && pin.pid != pid {
            pin.restoreAfterFocusLoss()
        }
    }

    private func startTracking() {
        guard tracker == nil else { return }
        // Hover mode follows the pointer closely; click mode only needs the 0.5 s check
        // of where the windows are.
        let hover = settings.activationMode == .hover
        let timer = Timer(timeInterval: hover ? 0.05 : 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        timer.tolerance = hover ? 0.01 : 0.1
        RunLoop.main.add(timer, forMode: .common)
        tracker = timer
    }

    private func stopTracking() {
        tracker?.invalidate()
        tracker = nil
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let buttonsDown = NSEvent.pressedMouseButtons != 0
        // Only the top-most pin under the pointer counts as hovered.
        let hovered = pins.last { $0.cocoaFrame.contains(mouse) }

        for pin in pins {
            let inside = pin === hovered
            guard settings.activationMode == .hover else {
                pin.hoverStart = nil
                continue
            }
            if !inside {
                pin.hoverArmed = true
                pin.hoverStart = nil
                if pin.isPassingThrough && !buttonsDown { pin.restore() }
            } else if !pin.isPassingThrough && pin.hoverArmed && !buttonsDown && !pin.controlFrame.contains(mouse) {
                let start = pin.hoverStart ?? Date()
                pin.hoverStart = start
                if Date().timeIntervalSince(start) > 0.15 { pin.activateRealWindow() }
            }
        }

        tick += 1
        if settings.activationMode != .hover || tick % 10 == 0 {
            pins.forEach { $0.poll() }
        }
    }

    // MARK: - Errors

    private enum PinError: LocalizedError {
        case windowGone

        var errorDescription: String? {
            L("This window can't be captured. It may have closed or be on another Space.")
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Couldn't pin the window")
        alert.informativeText = error.localizedDescription
        SirenaActivation.activateForTool()
        alert.runModal()
    }
}
