/// TextRecognizer.swift
///
/// On-device text and barcode recognition with Vision.
///
/// The recognition tuning (no minimum text height, contrast boost, fast-level retry)
/// follows TRex by Ameba Labs (MIT, https://github.com/amebalabs/TRex).

import CoreGraphics
import CoreImage
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
        let prepared = prepared(image)
        let observations: [RecognizedTextObservation]
        do {
            observations = try await recognize(prepared, options: options, level: .accurate)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The accurate model can fail inside the Neural Engine; the fast one is a different model.
            observations = try await recognize(prepared, options: options, level: .fast)
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return options.keepLineBreaks ? lines.joined(separator: "\n") : joinedWithoutBreaks(lines)
    }

    private static func recognize(_ image: CGImage, options: TextRecognitionOptions,
                                  level: RecognizeTextRequest.RecognitionLevel) async throws -> [RecognizedTextObservation] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = options.languageCorrection
        // The default skips text shorter than 1/32 of the image, which drops small print in tall selections.
        request.minimumTextHeightFraction = 0
        if options.languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
        }
        if !options.customWords.isEmpty {
            request.customWords = options.customWords
        }
        return try await request.perform(on: image, orientation: .up)
    }

    /// Payloads of the QR codes and barcodes in the image.
    static func detectCodes(in image: CGImage) async throws -> [String] {
        let observations = try await DetectBarcodesRequest().perform(on: image)
        var seen = Set<String>()
        return observations.compactMap(\.payloadString).filter { seen.insert($0).inserted }
    }

    // MARK: - Image preparation

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Selections on non-Retina displays are too small for Vision to read every line,
    /// so small images are enlarged, and contrast is raised for faint text.
    private static func prepared(_ image: CGImage) -> CGImage {
        var output = CIImage(cgImage: image)
        let longestSide = CGFloat(max(image.width, image.height))
        let scale = min(3, max(1, 2400 / longestSide)).rounded(.down)
        if scale > 1 {
            let lanczos = CIFilter(name: "CILanczosScaleTransform")
            lanczos?.setValue(output, forKey: kCIInputImageKey)
            lanczos?.setValue(scale, forKey: kCIInputScaleKey)
            lanczos?.setValue(1.0, forKey: kCIInputAspectRatioKey)
            output = lanczos?.outputImage ?? output
        }
        let contrast = CIFilter(name: "CIColorControls")
        contrast?.setValue(output, forKey: kCIInputImageKey)
        contrast?.setValue(1.2, forKey: kCIInputContrastKey)
        output = contrast?.outputImage ?? output
        let extent = output.extent.integral
        return context.createCGImage(output, from: extent) ?? image
    }

    // MARK: - Joining

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
