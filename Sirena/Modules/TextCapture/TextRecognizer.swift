/// TextRecognizer.swift
///
/// On-device text and barcode recognition with Vision.

import CoreGraphics
import Foundation
import Vision

struct TextRecognitionOptions: Sendable {
    /// BCP 47 identifiers; empty lets Vision detect the language.
    var languages: [String] = []
    var customWords: [String] = []
    var languageCorrection = true
    var keepLineBreaks = true
}

enum TextRecognizer {
    static func recognizeText(in image: CGImage, options: TextRecognitionOptions) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = options.languageCorrection
        if options.languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
        }
        if !options.customWords.isEmpty {
            request.customWords = options.customWords
        }
        let observations = try await request.perform(on: image)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return options.keepLineBreaks ? lines.joined(separator: "\n") : joinedWithoutBreaks(lines)
    }

    /// Payloads of the QR codes and barcodes in the image.
    static func detectCodes(in image: CGImage) async throws -> [String] {
        let observations = try await DetectBarcodesRequest().perform(on: image)
        var seen = Set<String>()
        return observations.compactMap(\.payloadString).filter { seen.insert($0).inserted }
    }

    /// Joins lines into running text, mending words hyphenated across lines.
    private static func joinedWithoutBreaks(_ lines: [String]) -> String {
        var text = ""
        for line in lines {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if text.hasSuffix("-"), let first = line.first, first.isLowercase {
                text.removeLast()
                text += line
            } else {
                text += text.isEmpty ? line : " " + line
            }
        }
        return text
    }
}
