/// TextCaptureSettings.swift
///
/// Preferences of Text Capture, the screen OCR feature modeled on TextSniper.
/// Written from scratch for Sirena: TextSniper is closed source, only its public
/// feature list was used.

import Foundation

/// Languages offered for recognition. "automatic" lets Vision detect it.
enum TextCaptureLanguage {
    static let automatic = "automatic"

    static let choices: [(id: String, title: String)] = [
        (automatic, L("Detect Automatically")),
        ("pt-BR", L("Portuguese")),
        ("en-US", L("English")),
        ("es-ES", L("Spanish")),
        ("fr-FR", L("French")),
        ("de-DE", L("German")),
        ("it-IT", L("Italian")),
        ("zh-Hans", L("Chinese Simplified")),
        ("zh-Hant", L("Chinese Traditional")),
        ("ja-JP", L("Japanese")),
        ("ko-KR", L("Korean"))
    ]
}

@Observable
final class TextCaptureSettings {
    static let shared = TextCaptureSettings()

    /// Shortcut keys (MASShortcut, stored by the binder).
    enum Shortcut: String, CaseIterable, Identifiable {
        case capture, captureWithLineBreaks, captureWithoutLineBreaks, captureAndSpeak, captureAndTranslate
        case captureLastSelection, readCode, toggleAdditive, clearAdditive, stopSpeaking

        var id: String { rawValue }
        /// No dots: the shortcut binder reaches the key through a key path.
        var defaultsKey: String { "textCaptureShortcut_\(rawValue)" }

        var title: String {
            switch self {
            case .capture: return L("Capture Text")
            case .captureWithLineBreaks: return L("Capture With Line Breaks")
            case .captureWithoutLineBreaks: return L("Capture Without Line Breaks")
            case .captureAndSpeak: return L("Capture With Text to Speech")
            case .captureAndTranslate: return L("Capture and Translate")
            case .captureLastSelection: return L("Capture Last Selection")
            case .readCode: return L("Read QR/Bar Code")
            case .toggleAdditive: return L("Toggle Additive Clipboard")
            case .clearAdditive: return L("Clear Additive Clipboard History")
            case .stopSpeaking: return L("Stop Speaking")
            }
        }
    }

    private let defaults = UserDefaults.standard

    var keepLineBreaks: Bool { didSet { save(keepLineBreaks, "textCapture.keepLineBreaks") } }
    /// Each capture is added to the previous ones instead of replacing the clipboard.
    var additiveClipboard: Bool { didSet { save(additiveClipboard, "textCapture.additiveClipboard") } }
    var additiveAutoClear: Bool { didSet { save(additiveAutoClear, "textCapture.additiveAutoClear") } }
    /// Minutes without a new capture after which the additive clipboard starts over.
    var additiveAutoClearMinutes: Int { didSet { save(additiveAutoClearMinutes, "textCapture.additiveAutoClearMinutes") } }
    /// Reads every capture aloud.
    var textToSpeech: Bool { didSet { save(textToSpeech, "textCapture.textToSpeech") } }
    /// 0 … 1, mapped onto the speech synthesizer's range.
    var speechRate: Double { didSet { save(speechRate, "textCapture.speechRate") } }
    var language: String { didSet { save(language, "textCapture.language") } }
    /// Words Vision should prefer, separated by commas.
    var customWords: String { didSet { save(customWords, "textCapture.customWords") } }
    var languageCorrection: Bool { didSet { save(languageCorrection, "textCapture.languageCorrection") } }
    var openLinks: Bool { didSet { save(openLinks, "textCapture.openLinks") } }
    var playSound: Bool { didSet { save(playSound, "textCapture.playSound") } }
    var showNotification: Bool { didSet { save(showNotification, "textCapture.showNotification") } }

    var customWordList: [String] {
        customWords.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private init() {
        keepLineBreaks = defaults.object(forKey: "textCapture.keepLineBreaks") as? Bool ?? true
        additiveClipboard = defaults.object(forKey: "textCapture.additiveClipboard") as? Bool ?? false
        additiveAutoClear = defaults.object(forKey: "textCapture.additiveAutoClear") as? Bool ?? false
        additiveAutoClearMinutes = defaults.object(forKey: "textCapture.additiveAutoClearMinutes") as? Int ?? 5
        textToSpeech = defaults.object(forKey: "textCapture.textToSpeech") as? Bool ?? false
        speechRate = defaults.object(forKey: "textCapture.speechRate") as? Double ?? 0.5
        language = defaults.string(forKey: "textCapture.language") ?? TextCaptureLanguage.automatic
        customWords = defaults.string(forKey: "textCapture.customWords") ?? ""
        languageCorrection = defaults.object(forKey: "textCapture.languageCorrection") as? Bool ?? true
        openLinks = defaults.object(forKey: "textCapture.openLinks") as? Bool ?? false
        playSound = defaults.object(forKey: "textCapture.playSound") as? Bool ?? true
        showNotification = defaults.object(forKey: "textCapture.showNotification") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
