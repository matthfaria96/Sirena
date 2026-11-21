/// ScreenCaptureController.swift
///
/// Captura de Tela: Sirena's own screenshot tool, in the spirit of Lightshot. One key
/// freezes the screen; drag over an area (or click a window, or the desktop for the whole
/// screen), mark it up, then copy it, save it, or record that area or window.
///
/// The key is ⇧⌘4 by default, taken from macOS while Sirena runs (System Settings keeps it
/// and gets it back on quit, through the same take-over the ⌘ Tab switcher uses), and Print
/// Screen on PC keyboards (F13). The frozen screen and the recordings come from
/// ScreenCaptureKit, so the tool needs Screen Recording.

import AppKit
import Carbon.HIToolbox
import MASShortcut
import os
import ScreenCaptureKit

/// What Return and a double click do with the selection.
enum CapturePrimaryAction: String, CaseIterable, Identifiable {
    case copy, save, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return L("Copy")
        case .save: return L("Save")
        case .both: return L("Copy and Save")
        }
    }
}

/// Where screenshots and recordings are saved.
enum ScreenCaptureDestination: String, CaseIterable, Identifiable {
    case desktop, screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return L("Desktop")
        case .screenshots: return L("Pictures › Screenshots")
        }
    }

    var folder: URL {
        let fm = FileManager.default
        switch self {
        case .desktop:
            return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Desktop")
        case .screenshots:
            let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Pictures")
            let folder = pictures.appending(path: "Screenshots", directoryHint: .isDirectory)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }
}

@MainActor
@Observable
final class ScreenCaptureController {
    static let shared = ScreenCaptureController()

    /// No dots: MASShortcut reaches it through a key path.
    nonisolated static let shortcutKey = "screenCaptureShortcut_capture"
    /// Print Screen on PC keyboards reaches the Mac as F13.
    static let printScreenShortcut = MASShortcut(keyCode: kVK_F13, modifierFlags: [])
    /// macOS's own screenshot keys (System Settings › Keyboard › Screenshots): ⇧⌘3, ⌃⇧⌘3,
    /// ⇧⌘4, ⌃⇧⌘4 and ⇧⌘5. Only these are ever taken over, and only the one the shortcut uses.
    /// Logitech keyboards' camera key (F8 without fn on the MX Mechanical Mini) sends ⇧⌘4.
    nonisolated static let macScreenshotHotKeys: Set<Int32> = [28, 29, 30, 31, 184]
    private static let takeoverSource = "screenCapture"
    private static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "ScreenCapture")

    private(set) var isRunning = false
    /// While a recording runs: when it started.
    private(set) var recordingStart: Date?
    private(set) var lastFile: URL?
    /// True while the shortcut is one of macOS's screenshot keys, held by Sirena.
    private(set) var holdsMacShortcut = false

    var printScreen: Bool { didSet { save(printScreen, "printScreen"); bindPrintScreen() } }
    var primaryAction: CapturePrimaryAction {
        didSet { UserDefaults.standard.set(primaryAction.rawValue, forKey: "screenCapture.primaryAction") }
    }
    /// Saving also copies (the old "copy screenshots" switch).
    var copiesWhenSaving: Bool { didSet { save(copiesWhenSaving, "copiesScreenshots") } }
    var opensAfterCapture: Bool { didSet { save(opensAfterCapture, "opensAfterCapture") } }
    var detectsWindows: Bool { didSet { save(detectsWindows, "detectsWindows") } }
    var showsLoupe: Bool { didSet { save(showsLoupe, "showsLoupe") } }
    var includesPointer: Bool { didSet { save(includesPointer, "includesPointer") } }
    var showsClicks: Bool { didSet { save(showsClicks, "showsClicks") } }
    var recordsMicrophone: Bool { didSet { save(recordsMicrophone, "recordsMicrophone") } }
    var recordsSystemAudio: Bool { didSet { save(recordsSystemAudio, "recordsSystemAudio") } }
    var destination: ScreenCaptureDestination {
        didSet { UserDefaults.standard.set(destination.rawValue, forKey: "screenCapture.destination") }
    }
    /// The marks' color and thickness, kept between captures.
    var colorIndex: Int { didSet { UserDefaults.standard.set(colorIndex, forKey: "screenCapture.color") } }
    var width: Double { didSet { UserDefaults.standard.set(width, forKey: "screenCapture.width") } }

    @ObservationIgnored private var openPage: () -> Void = {}
    @ObservationIgnored private var session: CaptureSession?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var recorder: CaptureRecorder?
    @ObservationIgnored private var fallbackRecorder: Process?
    @ObservationIgnored private var discardsRecording = false
    /// The display being recorded: the saved card shows there.
    @ObservationIgnored private var recordingDisplay: CGDirectDisplayID?
    @ObservationIgnored private let stopPanel = RecordingStopPanel()
    @ObservationIgnored private let framePanel = RecordingFramePanel()
    @ObservationIgnored private var printScreenBound = false
    @ObservationIgnored private var heldShortcut: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The last app other than Sirena that came forward.
    @ObservationIgnored private var lastOtherApp: NSRunningApplication?

    private init() {
        let d = UserDefaults.standard
        printScreen = d.object(forKey: "screenCapture.printScreen") as? Bool ?? true
        primaryAction = CapturePrimaryAction(rawValue: d.string(forKey: "screenCapture.primaryAction") ?? "") ?? .copy
        copiesWhenSaving = d.object(forKey: "screenCapture.copiesScreenshots") as? Bool ?? true
        opensAfterCapture = d.object(forKey: "screenCapture.opensAfterCapture") as? Bool ?? false
        detectsWindows = d.object(forKey: "screenCapture.detectsWindows") as? Bool ?? true
        showsLoupe = d.object(forKey: "screenCapture.showsLoupe") as? Bool ?? true
        includesPointer = d.object(forKey: "screenCapture.includesPointer") as? Bool ?? false
        showsClicks = d.object(forKey: "screenCapture.showsClicks") as? Bool ?? true
        recordsMicrophone = d.object(forKey: "screenCapture.recordsMicrophone") as? Bool ?? false
        recordsSystemAudio = d.object(forKey: "screenCapture.recordsSystemAudio") as? Bool ?? false
        destination = ScreenCaptureDestination(rawValue: d.string(forKey: "screenCapture.destination") ?? "") ?? .screenshots
        colorIndex = d.object(forKey: "screenCapture.color") as? Int ?? 0
        width = d.object(forKey: "screenCapture.width") as? Double ?? 4
    }

    private func save(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: "screenCapture.\(key)")
    }

    // MARK: Lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage
        Self.migrateShortcutOnce()
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: Self.shortcutKey) { [weak self] in
            Self.log.notice("Capture opened by its shortcut \(Self.shortcutText ?? "", privacy: .public)")
            self?.capture()
        }
        bindPrintScreen()
        syncMacShortcut()
        let center = NotificationCenter.default
        // The recorder on the page, or another Mac's settings sync: follow the stored shortcut.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ScreenCaptureController.shared.syncMacShortcut()
                ScreenCaptureController.shared.bindPrintScreen()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                           object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { ScreenCaptureController.shared.lastOtherApp = app }
        })
        // Wake can hand macOS's screenshot keys back: take them again.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                           object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                ScreenCaptureController.shared.syncMacShortcut(force: true)
            }
        })
    }

    func terminate() {
        guard isRunning else { return }
        session?.finish(.cancel)
        stopRecording()
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.shortcutKey)
        isRunning = false
        bindPrintScreen()
        syncMacShortcut()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    /// ⇧⌘4 once for everyone; whoever had an area shortcut keeps it. Later the shortcut is
    /// the user's, cleared included.
    private static func migrateShortcutOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "screenCapture.shortcutV3") else { return }
        d.set(true, forKey: "screenCapture.shortcutV3")
        if d.object(forKey: shortcutKey) == nil, let area = d.object(forKey: "screenCaptureShortcut_area") {
            d.set(area, forKey: shortcutKey)
        }
        migrateShortcut(to: shortcutKey, keyCode: kVK_ANSI_4, modifiers: [.shift, .command])
        for old in ["area", "screen", "recordArea", "recordScreen"] { d.removeObject(forKey: "screenCaptureShortcut_\(old)") }
    }

    // MARK: Shortcut

    static var currentShortcut: MASShortcut? {
        UserDefaults.standard.dictionary(forKey: shortcutKey)
            .flatMap { MASDictionaryTransformer().transformedValue($0) as? MASShortcut }
    }

    /// "⇧⌘4", or nil when there is no shortcut.
    static var shortcutText: String? {
        currentShortcut.map { $0.modifierFlagsString + ($0.keyCodeString ?? "") }
    }

    static func setShortcut(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        guard let stored = MASDictionaryTransformer().reverseTransformedValue(MASShortcut(keyCode: keyCode, modifierFlags: modifiers)) else { return }
        UserDefaults.standard.set(stored, forKey: shortcutKey)
    }

    /// Whether a combination is one of macOS's screenshot keys (the recorder accepts those
    /// for this shortcut: Sirena takes them over).
    nonisolated static func isMacScreenshotShortcut(_ shortcut: MASShortcut) -> Bool {
        guard let entries = SwitcherSymbolicHotKeys.entries(for: macScreenshotHotKeys) else { return false }
        return !SwitcherSystemShortcutTakeoverSupport.ids(matching: switcherShortcut(shortcut), in: entries).isEmpty
    }

    nonisolated private static func switcherShortcut(_ shortcut: MASShortcut) -> SwitcherGlobalShortcut {
        let flags = CGEventFlags(rawValue: UInt64(shortcut.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
        return SwitcherGlobalShortcut(keyCode: Int64(shortcut.keyCode), modifiers: SwitcherGlobalShortcutModifiers(cgFlags: flags))
    }

    /// Takes macOS's screenshot key the shortcut uses (⇧⌘4 by default) while Sirena runs,
    /// and gives it back as soon as the shortcut changes or the tool stops.
    func syncMacShortcut(force: Bool = false) {
        let shortcut = isRunning ? Self.currentShortcut : nil
        let key = shortcut.map { "\($0.keyCode):\($0.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)" }
        guard force || key != heldShortcut else { return }
        heldShortcut = key
        var ids: Set<Int32> = []
        if let shortcut, let entries = SwitcherSymbolicHotKeys.entries(for: Self.macScreenshotHotKeys) {
            ids = SwitcherSystemShortcutTakeoverSupport.ids(matching: Self.switcherShortcut(shortcut), in: entries)
        }
        SwitcherSystemShortcutTakeover.setWanted(ids, for: Self.takeoverSource)
        if holdsMacShortcut != !ids.isEmpty { holdsMacShortcut = !ids.isEmpty }
    }

    func bindPrintScreen() {
        // Already the main shortcut: one binding is enough.
        let isMain = Self.currentShortcut.map { $0.keyCode == kVK_F13 && $0.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty } ?? false
        let wanted = isRunning && printScreen && !isMain
        guard wanted != printScreenBound, let monitor = MASShortcutMonitor.shared() else { return }
        if wanted {
            printScreenBound = monitor.register(Self.printScreenShortcut, withAction: {
                Task { @MainActor in
                    Self.log.notice("Capture opened by Print Screen (F13)")
                    ScreenCaptureController.shared.capture()
                }
            })
        } else {
            monitor.unregisterShortcut(Self.printScreenShortcut)
            printScreenBound = false
        }
    }

    // MARK: Status (Home)

    var isRecording: Bool { recordingStart != nil }
    var isActive: Bool { isRecording }

    var statusText: String {
        if isRecording { return L("Recording — click Capture to stop") }
        if let lastFile { return String(format: L("Last: %@"), lastFile.deletingPathExtension().lastPathComponent) }
        if let shortcut = Self.shortcutText { return String(format: L("Ready — %@ to capture"), shortcut) }
        return L("Ready — screenshots and recordings")
    }

    /// The ⚡ menu, Home and the page: stop a recording, or start a capture once the menu is gone.
    func quickAction() {
        if isRecording { return stopRecording() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.capture() }
    }

    // MARK: Capture

    /// The key: a new capture, or the end of the one on screen (or of a recording).
    func capture() {
        guard isRunning else { return }
        if isRecording { return stopRecording() }
        if let session { return session.finish(.cancel) }
        guard !isStarting else { return }
        guard CGPreflightScreenCaptureAccess() else { return askForScreenRecording() }
        isStarting = true
        // Before anything of Sirena's shows: the windows and the screen as they are now.
        // Keyboard back afterwards to the app in front, or, when Sirena is only in front
        // because of its menu, to the app used before it.
        let front = NSWorkspace.shared.frontmostApplication
        let isSirena = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let previous = !isSirena ? front : NSApp.keyWindow != nil ? nil : lastOtherApp
        let windows = detectsWindows ? CaptureSnapshot.windows() : []
        Task { @MainActor in
            let frames = await CaptureSnapshot.freeze(includingPointer: includesPointer)
            isStarting = false
            guard isRunning, session == nil else { return }
            guard !frames.isEmpty else { return askForScreenRecording() }
            let session = CaptureSession(frames: frames, windows: windows, previousApp: previous)
            session.onFinish = { result in
                let controller = ScreenCaptureController.shared
                controller.session = nil
                if let result { controller.handle(result) }
            }
            self.session = session
            session.show()
        }
    }

    private func askForScreenRecording() {
        // macOS shows its own prompt the first time; after that the setting has to be opened.
        if !CGRequestScreenCaptureAccess() {
            CaptureToast.shared.show(title: L("Screen Recording needed"),
                                     detail: L("Screen Capture freezes the screen to select from it."),
                                     symbol: "rectangle.dashed.badge.record",
                                     note: L("Click to open the setting, then capture again."), duration: 6) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func handle(_ result: CaptureSession.Result) {
        switch result.outcome {
        case .cancel:
            break
        case .copy:
            guard let image = result.image else { return NSSound.beep() }
            deliver(image, size: result.selection.size, copy: true, save: false, display: result.displayID)
        case .save:
            guard let image = result.image else { return NSSound.beep() }
            deliver(image, size: result.selection.size, copy: copiesWhenSaving, save: true, display: result.displayID)
        case .copyAndSave:
            guard let image = result.image else { return NSSound.beep() }
            deliver(image, size: result.selection.size, copy: true, save: true, display: result.displayID)
        case .record:
            let target: CaptureRecordingTarget
            if let window = result.window {
                target = .window(window.id)
            } else if let screen = NSScreen.screens.first(where: { $0.displayID == result.displayID }),
                      screen.frame == result.selection {
                target = .display(result.displayID)
            } else {
                target = .area(result.selection, displayID: result.displayID)
            }
            startRecording(target, area: result.selection, displayID: result.displayID)
        }
    }

    /// The same shutter sound as macOS screenshots.
    private static let shutter = NSSound(contentsOfFile:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true) ?? NSSound(named: "Tink")

    private func deliver(_ image: CGImage, size: CGSize, copy: Bool, save: Bool, display: CGDirectDisplayID) {
        let rep = NSBitmapImageRep(cgImage: image)
        // Points, not pixels: a Retina capture pastes and opens at its real size (144 dpi).
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]) else { return NSSound.beep() }
        let dimensions = "\(image.width) × \(image.height)"
        var savedURL: URL?
        if save {
            let url = Self.nextFile(prefix: L("Screenshot"), ext: "png")
            do {
                try png.write(to: url)
                savedURL = url
                lastFile = url
            } catch {
                NSLog("Sirena Screen Capture: saving failed: \(error.localizedDescription)")
                CaptureToast.shared.show(title: L("Couldn't save the screenshot"), detail: error.localizedDescription,
                                         symbol: "exclamationmark.triangle")
                NSSound.beep()
                return
            }
        }
        if copy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        }
        Self.shutter?.play()
        if let url = savedURL {
            // Where it went, on the display it came from.
            CaptureSavedCard.shared.show(url, title: copy ? L("Screenshot saved and copied") : L("Screenshot saved"),
                                         folder: Self.folderName(of: url), image: image, on: display)
            if opensAfterCapture { NSWorkspace.shared.open(url) }
        } else {
            CaptureToast.shared.show(title: L("Screenshot copied"), detail: dimensions, symbol: "doc.on.doc",
                                     near: Self.cgFrame(of: display))
        }
    }

    // MARK: Recording

    private func startRecording(_ target: CaptureRecordingTarget, area: CGRect, displayID: CGDirectDisplayID) {
        let url = Self.nextFile(prefix: L("Screen Recording"), ext: "mov")
        let recorder = CaptureRecorder(url: url)
        recorder.onFinish = { [weak self] error in self?.recordingFinished(url: url, error: error) }
        self.recorder = recorder
        discardsRecording = false
        recordingDisplay = displayID
        let options = CaptureRecorder.Options(clicks: showsClicks, microphone: recordsMicrophone, systemAudio: recordsSystemAudio)
        let screen = NSScreen.screens.first { $0.displayID == displayID }
        Task { @MainActor in
            do {
                try await recorder.start(target, options: options)
                recordingStarted(area: area, screen: screen, framed: { if case .area = target { return true }; return false }())
            } catch {
                NSLog("Sirena Screen Capture: ScreenCaptureKit recording failed, using screencapture: \(error.localizedDescription)")
                recorder.onFinish = nil
                self.recorder = nil
                recordWithScreencapture(area: area, screen: screen, url: url)
            }
        }
    }

    private func recordingStarted(area: CGRect, screen: NSScreen?, framed: Bool) {
        recordingStart = Date()
        if framed { framePanel.show(around: area) }
        stopPanel.show(below: area, on: screen,
                       stop: { [weak self] in self?.stopRecording() },
                       discard: { [weak self] in self?.discardRecording() })
    }

    /// Without ScreenCaptureKit's recorder: macOS's own `screencapture -v` on the same area.
    private func recordWithScreencapture(area: CGRect, screen: NSScreen?, url: URL) {
        var args = ["-v"]
        let primaryHeight = NSScreen.screens.first?.frame.height ?? area.maxY
        args.append("-R\(Int(area.minX)),\(Int(primaryHeight - area.maxY)),\(Int(area.width)),\(Int(area.height))")
        if showsClicks { args.append("-k") }
        if recordsMicrophone { args.append("-g") }
        args.append(url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in
            Task { @MainActor in ScreenCaptureController.shared.recordingFinished(url: url, error: nil) }
        }
        do {
            try process.run()
            fallbackRecorder = process
            recordingStarted(area: area, screen: screen, framed: true)
        } catch {
            CaptureToast.shared.show(title: L("Couldn't start recording"), detail: error.localizedDescription,
                                     symbol: "exclamationmark.triangle")
            NSSound.beep()
        }
    }

    func stopRecording() {
        if let recorder {
            recorder.stop()
        } else if let fallbackRecorder, fallbackRecorder.isRunning {
            // screencapture finishes the movie on SIGINT, like ^C in Terminal.
            fallbackRecorder.interrupt()
        }
    }

    private func discardRecording() {
        discardsRecording = true
        stopRecording()
    }

    private func recordingFinished(url: URL, error: Error?) {
        guard recordingStart != nil || recorder != nil || fallbackRecorder != nil else { return }
        recorder = nil
        fallbackRecorder = nil
        recordingStart = nil
        stopPanel.close()
        framePanel.close()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if discardsRecording {
            discardsRecording = false
            try? FileManager.default.removeItem(at: url)
            CaptureToast.shared.show(title: L("Recording discarded"), detail: nil, symbol: "trash")
            return
        }
        guard size > 0 else {
            try? FileManager.default.removeItem(at: url)
            if let error {
                CaptureToast.shared.show(title: L("Recording failed"), detail: error.localizedDescription,
                                         symbol: "exclamationmark.triangle")
            }
            return
        }
        lastFile = url
        if copiesWhenSaving {
            // The movie itself, to paste into a chat or a mail.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
        CaptureSavedCard.shared.show(url, title: L("Recording saved"), folder: Self.folderName(of: url), on: recordingDisplay)
        if opensAfterCapture { NSWorkspace.shared.open(url) }
    }

    // MARK: Files

    /// The folder picked on the page (Desktop or Pictures › Screenshots), created when missing.
    static var saveFolder: URL { shared.destination.folder }

    /// Named like macOS does: "Captura de Tela 2026-10-18 às 10.15.40.png".
    private static func nextFile(prefix: String, ext: String) -> URL {
        let date = Date()
        let day = date.formatted(.iso8601.year().month().day())
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: ":", with: ".")
        var url = saveFolder.appending(path: "\(prefix) \(day) \(L("at")) \(time).\(ext)")
        // Two captures in the same second.
        var copy = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = saveFolder.appending(path: "\(prefix) \(day) \(L("at")) \(time) (\(copy)).\(ext)")
            copy += 1
        }
        return url
    }

    /// A display's frame in window-server coordinates (top-left origin), for the toast.
    private static func cgFrame(of display: CGDirectDisplayID) -> CGRect? {
        let bounds = CGDisplayBounds(display)
        return bounds.isEmpty ? nil : bounds
    }

    /// "Pictures › Screenshots" / "Desktop" for the folders on the page, else the path (~/…).
    private static func folderName(of file: URL) -> String {
        let folder = file.deletingLastPathComponent().standardizedFileURL.path
        if let known = ScreenCaptureDestination.allCases.first(where: { $0.folder.standardizedFileURL.path == folder }) {
            return known.title
        }
        return (folder as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - While recording

/// Liquid Glass on macOS 26+, a HUD material before that.
@MainActor
private func recordingBackdrop(around content: NSView, cornerRadius: CGFloat) -> NSView {
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = cornerRadius
    effect.layer?.masksToBounds = true
    content.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        content.topAnchor.constraint(equalTo: effect.topAnchor),
        content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])
    return effect
}

/// A small floating pill under the recorded area: red dot, time, stop and discard.
@MainActor
private final class RecordingStopPanel {
    private var panel: NSPanel?
    private var timer: Timer?

    func show(below area: CGRect, on screen: NSScreen?, stop: @escaping () -> Void, discard: @escaping () -> Void) {
        close()
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let dot = NSImageView(image: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil) ?? NSImage())
        dot.contentTintColor = .systemRed
        let stopTarget = ActionTarget(stop)
        let stopButton = NSButton(title: L("Stop"), target: stopTarget, action: #selector(ActionTarget.fire))
        if #available(macOS 26, *) { stopButton.bezelStyle = .glass } else { stopButton.bezelStyle = .rounded }
        stopButton.controlSize = .small
        let discardTarget = ActionTarget(discard)
        let discardButton = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: L("Discard")) ?? NSImage(),
                                     target: discardTarget, action: #selector(ActionTarget.fire))
        discardButton.isBordered = false
        discardButton.contentTintColor = .secondaryLabelColor
        discardButton.toolTip = L("Discard the recording")
        let stack = NSStackView(views: [dot, label, stopButton, discardButton])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 10)

        let glass = recordingBackdrop(around: stack, cornerRadius: 18)
        let size = NSSize(width: 186, height: 36)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // Under the area, centered; at the top of the screen when the area fills it.
        var origin = NSPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 10)
        if origin.y < visible.minY + 4 { origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10) }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Never part of a recording or a screen share.
        panel.sharingType = .none
        panel.contentView = glass
        objc_setAssociatedObject(panel, "targets", [stopTarget, discardTarget], .OBJC_ASSOCIATION_RETAIN)
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

    private final class ActionTarget: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

/// One thin line just outside the recorded area, so it is clear what is being recorded.
@MainActor
private final class RecordingFramePanel {
    private var panel: NSPanel?

    func show(around area: CGRect) {
        close()
        let pad: CGFloat = 3
        let frame = area.insetBy(dx: -pad, dy: -pad)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let line = CAShapeLayer()
        line.frame = view.bounds
        line.path = CGPath(rect: view.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        line.fillColor = nil
        line.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        line.lineWidth = 1
        line.lineDashPattern = [6, 4]
        line.shadowColor = NSColor.black.cgColor
        line.shadowOpacity = 0.4
        line.shadowRadius = 1.5
        line.shadowOffset = .zero
        view.layer?.addSublayer(line)
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
