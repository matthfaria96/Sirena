/// TextCaptureController.swift
///
/// Text Capture, modeled on TextSniper: select an area of the screen and its text
/// (or QR/barcode) lands on the clipboard. Optional additive clipboard, reading aloud,
/// translation and import from an iPhone camera.

import AVFoundation
import AppKit
import Carbon.HIToolbox
import MASShortcut
import NaturalLanguage
import ScreenCaptureKit

/// What to do with the selected area.
enum CaptureIntent {
    case text(lineBreaks: Bool? = nil, speak: Bool? = nil, translate: Bool = false)
    case code
}

struct CaptureRecord: Identifiable {
    enum Kind { case text, code }

    let id = UUID()
    let date = Date()
    let text: String
    let kind: Kind
}

@MainActor
@Observable
final class TextCaptureController {
    static let shared = TextCaptureController()

    private(set) var isRunning = false
    private(set) var isSpeaking = false
    private(set) var isWorking = false
    /// Captures collected by the additive clipboard, oldest first.
    private(set) var additiveItems: [String] = []
    /// This session's captures, newest first.
    private(set) var history: [CaptureRecord] = []

    @ObservationIgnored private let selector = AreaSelector()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let speechDelegate = SpeechDelegate()
    @ObservationIgnored private var additiveClearTimer: Timer?
    @ObservationIgnored private var openPage: () -> Void = {}

    private var settings: TextCaptureSettings { .shared }

    private static let lastSelectionKey = "textCapture.lastSelection"

    /// Last selected area, in Core Graphics global coordinates.
    var lastSelection: CGRect? {
        get {
            UserDefaults.standard.string(forKey: Self.lastSelectionKey).map { NSRectToCGRect(NSRectFromString($0)) }
        }
        set {
            UserDefaults.standard.set(newValue.map { NSStringFromRect(NSRectFromCGRect($0)) }, forKey: Self.lastSelectionKey)
        }
    }

    private init() {
        synthesizer.delegate = speechDelegate
        speechDelegate.onChange = { [weak self] speaking in self?.isSpeaking = speaking }
    }

    // MARK: - Module lifecycle

    func start(openPage: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.openPage = openPage

        let binder = MASShortcutBinder.shared()
        binder?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder?.registerDefaultShortcuts([
            TextCaptureSettings.Shortcut.capture.defaultsKey: MASShortcut(keyCode: kVK_ANSI_2, modifierFlags: [.shift, .command])
        ])
        for shortcut in TextCaptureSettings.Shortcut.allCases {
            binder?.bindShortcut(withDefaultsKey: shortcut.defaultsKey) { [weak self] in self?.perform(shortcut) }
        }
    }

    func terminate() {
        selector.cancel()
        stopSpeaking()
        for shortcut in TextCaptureSettings.Shortcut.allCases {
            MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: shortcut.defaultsKey)
        }
        isRunning = false
    }

    func perform(_ shortcut: TextCaptureSettings.Shortcut) {
        switch shortcut {
        case .capture: capture(.text())
        case .captureWithLineBreaks: capture(.text(lineBreaks: true))
        case .captureWithoutLineBreaks: capture(.text(lineBreaks: false))
        case .captureAndSpeak: capture(.text(speak: true))
        case .captureAndTranslate: capture(.text(translate: true))
        case .captureLastSelection: captureLastSelection()
        case .readCode: capture(.code)
        case .toggleAdditive: toggleAdditive()
        case .clearAdditive: clearAdditive()
        case .stopSpeaking: stopSpeaking()
        }
    }

    // MARK: - Permissions

    var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func ensureScreenRecording() -> Bool {
        guard hasScreenRecording else {
            // A single explanation with a way to fix it (no system prompt + Settings + alert).
            let alert = NSAlert()
            alert.messageText = L("Text Capture needs Screen Recording")
            alert.informativeText = L("Allow Sirena in System Settings › Privacy & Security › Screen & System Audio Recording, then restart Sirena.")
            alert.addButton(withTitle: L("Open System Settings"))
            alert.addButton(withTitle: L("Cancel"))
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
        return true
    }

    // MARK: - Capturing

    func capture(_ intent: CaptureIntent) {
        guard isRunning, !selector.isActive, ensureScreenRecording() else { return }
        var lineBreaks = settings.keepLineBreaks
        var speak = settings.textToSpeech
        let hint: String
        var toggles: [AreaSelectorToggle] = []
        switch intent {
        case .text(let breaks, let speakNow, let translate):
            if let breaks { lineBreaks = breaks }
            if let speakNow { speak = speakNow }
            hint = translate ? L("Select the text to translate") : L("Select the text to capture")
            toggles = [
                AreaSelectorToggle(key: "l", title: L("Line breaks"), isOn: { lineBreaks }, toggle: { lineBreaks.toggle() }),
                AreaSelectorToggle(key: "a", title: L("Additive"), isOn: { [settings] in settings.additiveClipboard },
                                   toggle: { [settings] in settings.additiveClipboard.toggle() }),
                AreaSelectorToggle(key: "s", title: L("Speak"), isOn: { speak }, toggle: { speak.toggle() })
            ]
        case .code:
            hint = L("Select a QR code or barcode")
        }

        selector.begin(hint: hint, toggles: toggles) { [weak self] rect in
            guard let self, let rect else { return }
            self.lastSelection = rect
            let resolved: CaptureIntent
            switch intent {
            case .text(_, _, let translate): resolved = .text(lineBreaks: lineBreaks, speak: speak, translate: translate)
            case .code: resolved = .code
            }
            Task {
                // Let the overlay leave the screen before taking the picture.
                try? await Task.sleep(for: .milliseconds(120))
                await self.process(rect: rect, intent: resolved)
            }
        }
    }

    func captureLastSelection() {
        guard isRunning else { return }
        guard let rect = lastSelection else {
            capture(.text())
            return
        }
        guard ensureScreenRecording() else { return }
        Task { await process(rect: rect, intent: .text()) }
    }

    /// Reads text from an image file picked by the user.
    func captureFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        handleImportedImage(image)
    }

    /// An image from Continuity Camera or a file.
    func handleImportedImage(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task { await recognize(cgImage, rect: nil, intent: .text(), showWindow: true) }
    }

    /// The same shutter sound as macOS screenshots.
    private static let shutterSound = NSSound(contentsOfFile:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true) ?? NSSound(named: "Pop")

    private func process(rect: CGRect, intent: CaptureIntent) async {
        do {
            let image = try await SCScreenshotManager.compatCaptureImage(in: rect)
            if settings.playSound { Self.shutterSound?.play() }
            await recognize(image, rect: rect, intent: intent, showWindow: false)
        } catch {
            fail(error.localizedDescription, rect: rect)
        }
    }

    private func recognize(_ image: CGImage, rect: CGRect?, intent: CaptureIntent, showWindow: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch intent {
            case .code:
                let codes = try await TextRecognizer.detectCodes(in: image)
                guard !codes.isEmpty else {
                    fail(L("No QR code or barcode found"), rect: rect)
                    return
                }
                deliver(codes.joined(separator: "\n"), kind: .code, rect: rect)
            case .text(let lineBreaks, let speak, let translate):
                var options = TextRecognitionOptions()
                options.keepLineBreaks = lineBreaks ?? settings.keepLineBreaks
                options.languageCorrection = settings.languageCorrection
                options.customWords = settings.customWordList
                if settings.language != TextCaptureLanguage.automatic {
                    options.languages = [settings.language]
                }
                let text = try await TextRecognizer.recognizeText(in: image, options: options)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fail(L("No text found"), rect: rect)
                    return
                }
                deliver(text, kind: .text, rect: rect)
                if speak ?? settings.textToSpeech { self.speak(text) }
                if translate || showWindow { CaptureResultWindow.shared.show(text: text, translate: translate) }
            }
        } catch {
            fail(error.localizedDescription, rect: rect)
        }
    }

    private func deliver(_ text: String, kind: CaptureRecord.Kind, rect: CGRect?) {
        history.insert(CaptureRecord(text: text, kind: kind), at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }

        let title: String
        if settings.additiveClipboard {
            additiveItems.append(text)
            copyToClipboard(additiveItems.joined(separator: "\n"))
            scheduleAdditiveClear()
            title = L("Added to the clipboard (\(additiveItems.count))")
        } else {
            copyToClipboard(text)
            title = kind == .code ? L("Code copied") : L("Text copied")
        }

        if settings.showNotification {
            CaptureToast.shared.show(title: title, detail: text, symbol: kind == .code ? "qrcode" : "text.viewfinder", near: rect)
        }
        if settings.openLinks, let link = firstLink(in: text) {
            NSWorkspace.shared.open(link)
        }
    }

    private func fail(_ message: String, rect: CGRect?) {
        if settings.playSound { NSSound.beep() }
        CaptureToast.shared.show(title: message, detail: nil, symbol: "exclamationmark.triangle", near: rect)
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url.flatMap { url in
            ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? url : nil
        }
    }

    // MARK: - Additive clipboard

    func toggleAdditive() {
        settings.additiveClipboard.toggle()
        if !settings.additiveClipboard { clearAdditive(silently: true) }
        CaptureToast.shared.show(title: settings.additiveClipboard ? L("Additive Clipboard on") : L("Additive Clipboard off"),
                                 detail: nil, symbol: "square.stack.3d.up")
    }

    func clearAdditive(silently: Bool = false) {
        additiveClearTimer?.invalidate()
        additiveClearTimer = nil
        guard !additiveItems.isEmpty else { return }
        additiveItems.removeAll()
        if !silently {
            CaptureToast.shared.show(title: L("Additive Clipboard cleared"), detail: nil, symbol: "trash")
        }
    }

    private func scheduleAdditiveClear() {
        additiveClearTimer?.invalidate()
        additiveClearTimer = nil
        guard settings.additiveAutoClear else { return }
        let timer = Timer(timeInterval: TimeInterval(settings.additiveAutoClearMinutes * 60), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearAdditive(silently: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        additiveClearTimer = timer
    }

    // MARK: - Text to speech

    func speak(_ text: String) {
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: text)
        // The setting uses the synthesizer's own 0 … 1 scale, 0.5 being the normal rate.
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate
            + (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) * Float(settings.speechRate)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        }
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}

/// Reports when speech starts and stops.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onChange: ((Bool) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        report(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        report(synthesizer.isSpeaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        report(false)
    }

    private func report(_ speaking: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onChange?(speaking) }
    }
}
