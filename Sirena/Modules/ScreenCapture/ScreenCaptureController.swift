/// ScreenCaptureController.swift
///
/// Captura de Tela: a shortcut to macOS's own screenshot tool (`/usr/sbin/screencapture`)
/// that starts straight in the chosen mode — an area, the whole screen, or a recording of
/// either — instead of opening the ⇧⌘5 toolbar first. Files go where macOS saves screenshots.

import AppKit
import Carbon.HIToolbox
import MASShortcut

enum ScreenCaptureAction: String, CaseIterable, Identifiable {
    case area, screen, recordArea, recordScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return L("Area")
        case .screen: return L("Screen")
        case .recordArea: return L("Record Area")
        case .recordScreen: return L("Record Screen")
        }
    }

    var detail: String {
        switch self {
        case .area: return L("Select part of the screen or a window (space switches)")
        case .screen: return L("The whole screen under the pointer")
        case .recordArea: return L("Drag the area to record, then stop from the red button")
        case .recordScreen: return L("Records the screen under the pointer until you stop")
        }
    }

    var symbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .screen: return "display"
        case .recordArea: return "rectangle.dashed.badge.record"
        case .recordScreen: return "record.circle"
        }
    }

    var isRecording: Bool { self == .recordArea || self == .recordScreen }

    /// No dots: MASShortcut reaches it through a key path.
    var shortcutKey: String { "screenCaptureShortcut_\(rawValue)" }
}

@MainActor
@Observable
final class ScreenCaptureController {
    static let shared = ScreenCaptureController()

    private(set) var isRunning = false
    /// While a recording runs: when it started (for the timer on the stop button).
    private(set) var recordingStart: Date?
    private(set) var lastFile: URL?

    var showsCursor: Bool { didSet { save(showsCursor, "showsCursor") } }
    var showsClicks: Bool { didSet { save(showsClicks, "showsClicks") } }
    var recordsMicrophone: Bool { didSet { save(recordsMicrophone, "recordsMicrophone") } }
    var opensAfterCapture: Bool { didSet { save(opensAfterCapture, "opensAfterCapture") } }
    var copiesScreenshots: Bool { didSet { save(copiesScreenshots, "copiesScreenshots") } }

    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private let selector = AreaSelector()
    @ObservationIgnored private var recorder: Process?
    @ObservationIgnored private let stopPanel = RecordingStopPanel()

    private init() {
        let d = UserDefaults.standard
        showsCursor = d.object(forKey: "screenCapture.showsCursor") as? Bool ?? false
        showsClicks = d.object(forKey: "screenCapture.showsClicks") as? Bool ?? true
        recordsMicrophone = d.object(forKey: "screenCapture.recordsMicrophone") as? Bool ?? false
        opensAfterCapture = d.object(forKey: "screenCapture.opensAfterCapture") as? Bool ?? false
        copiesScreenshots = d.object(forKey: "screenCapture.copiesScreenshots") as? Bool ?? false
    }

    private func save(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: "screenCapture.\(key)")
    }

    // MARK: Lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        let binder = MASShortcutBinder.shared()
        for action in ScreenCaptureAction.allCases {
            binder?.bindShortcut(withDefaultsKey: action.shortcutKey) { [weak self] in self?.run(action) }
        }
    }

    func terminate() {
        guard isRunning else { return }
        stopRecording()
        selector.cancel()
        for action in ScreenCaptureAction.allCases {
            MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: action.shortcutKey)
        }
        isRunning = false
    }

    // MARK: Status (Home)

    var isRecording: Bool { recordingStart != nil }
    var isActive: Bool { isRecording }

    var statusText: String {
        if isRecording { return L("Recording — click Capture to stop") }
        if let lastFile { return String(format: L("Last: %@"), lastFile.deletingPathExtension().lastPathComponent) }
        return L("Ready — screenshots and recordings")
    }

    /// The ⚡ menu opens its options inline; from Home the default is an area screenshot.
    func quickAction() {
        isRecording ? stopRecording() : run(.area)
    }

    // MARK: Actions

    func run(_ action: ScreenCaptureAction) {
        guard isRunning else { return }
        if isRecording { return stopRecording() }
        // Let the menu that started us close before the screen is captured.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            switch action {
            case .area: self.screenshot(interactive: true)
            case .screen: self.screenshot(interactive: false)
            case .recordScreen: self.record(rect: nil)
            case .recordArea:
                self.selector.begin(hint: L("Drag the area to record · Esc cancels"), toggles: []) { [weak self] rect in
                    guard let rect, rect.width >= 8, rect.height >= 8 else { return }
                    self?.record(rect: rect)
                }
            }
        }
    }

    private func screenshot(interactive: Bool) {
        let url = Self.nextFile(prefix: L("Screenshot"), ext: "png")
        var args: [String] = []
        if interactive {
            // Apple's Screenshot toolbar (photo or video, area, window or screen), always in
            // selection mode so it never opens on Visual Intelligence's text highlighting.
            args += ["-i", "-U", "-Jselection"]
        } else {
            args.append("-D\(Self.displayIndexUnderMouse())")
            if showsCursor { args.append("-C") }
        }
        if copiesScreenshots {
            args.append("-c")
        } else {
            if opensAfterCapture { args.append("-P") }
            args.append(url.path)
        }
        launch(args) { [weak self] in
            guard let self, !self.copiesScreenshots else { return }
            if FileManager.default.fileExists(atPath: url.path) { self.lastFile = url }
        }
    }

    private func record(rect: CGRect?) {
        let url = Self.nextFile(prefix: L("Screen Recording"), ext: "mov")
        var args = ["-v"]
        if let rect {
            args.append("-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
        } else {
            args.append("-D\(Self.displayIndexUnderMouse())")
        }
        if showsClicks { args.append("-k") }
        if recordsMicrophone { args.append("-g") }
        if opensAfterCapture { args.append("-P") }
        args.append(url.path)
        let process = launch(args) { [weak self] in
            guard let self else { return }
            self.recorder = nil
            self.recordingStart = nil
            self.stopPanel.close()
            if FileManager.default.fileExists(atPath: url.path) {
                self.lastFile = url
                CaptureToast.shared.show(title: L("Recording saved"), detail: url.lastPathComponent, symbol: "record.circle")
            }
        }
        guard let process else { return }
        recorder = process
        recordingStart = Date()
        stopPanel.show(on: Self.screenUnderMouse) { [weak self] in self?.stopRecording() }
    }

    func stopRecording() {
        guard let recorder, recorder.isRunning else { return }
        // screencapture finishes the movie on SIGINT, like ^C in Terminal.
        recorder.interrupt()
    }

    func revealLastFile() {
        guard let lastFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastFile])
    }

    @discardableResult
    private func launch(_ args: [String], done: @escaping @MainActor () -> Void) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in Task { @MainActor in done() } }
        do {
            try process.run()
            return process
        } catch {
            NSSound.beep()
            return nil
        }
    }

    // MARK: Files and screens

    /// Where macOS saves screenshots (Screenshot app › Options), the Desktop by default.
    static var saveFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Desktop")
    }

    /// Named like macOS does: "Captura de Tela 2026-10-18 às 10.15.40.png".
    private static func nextFile(prefix: String, ext: String) -> URL {
        let date = Date()
        let day = date.formatted(.iso8601.year().month().day())
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: ":", with: ".")
        return saveFolder.appending(path: "\(prefix) \(day) \(L("at")) \(time).\(ext)")
    }

    private static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// screencapture numbers displays from 1 in NSScreen order (1 = main).
    private static func displayIndexUnderMouse() -> Int {
        guard let screen = screenUnderMouse, let index = NSScreen.screens.firstIndex(of: screen) else { return 1 }
        return index + 1
    }
}

// MARK: - Stop button

/// A small floating pill at the top of the screen while recording: red dot, time, stop.
@MainActor
private final class RecordingStopPanel {
    private var panel: NSPanel?
    private var timer: Timer?

    func show(on screen: NSScreen?, stop: @escaping () -> Void) {
        close()
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let dot = NSImageView(image: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil) ?? NSImage())
        dot.contentTintColor = .systemRed
        let button = NSButton(title: L("Stop"), target: nil, action: nil)
        button.bezelStyle = .glass
        button.controlSize = .small
        let handler = StopTarget(stop)
        button.target = handler
        button.action = #selector(StopTarget.fire)
        let stack = NSStackView(views: [dot, label, button])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)

        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = stack

        let size = NSSize(width: 150, height: 36)
        let frame = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 10)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Keep the recording free of Sirena's own button.
        panel.sharingType = .none
        panel.contentView = glass
        objc_setAssociatedObject(panel, "stopTarget", handler, .OBJC_ASSOCIATION_RETAIN)
        panel.orderFrontRegardless()
        self.panel = panel

        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let seconds = Int(Date().timeIntervalSince(start))
            MainActor.assumeIsolated { label.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60) }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private final class StopTarget: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
