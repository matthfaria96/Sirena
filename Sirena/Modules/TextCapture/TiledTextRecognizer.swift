/// TiledTextRecognizer.swift
///
/// Vision shrinks large images to a fixed working size before reading them, so on a
/// non-Retina display a big selection loses most of its small print (a full 2560 × 1440
/// screen came back with about a third of its words). Screen captures are therefore read
/// in small overlapping tiles at full resolution and the lines are stitched back together,
/// the slicing idea from SAHI (MIT, https://github.com/obss/sahi).

import CoreGraphics
import CoreImage
import Foundation
import Vision

enum TiledTextRecognizer {
    /// Tile side in screen points; words narrower than the overlap are never lost at a seam.
    private static let tilePoints: CGFloat = 600
    private static let overlapPoints: CGFloat = 160
    /// Text is read as if on a 2× display.
    private static let targetPixelScale: CGFloat = 2

    /// A run of recognized words, in top-left-origin pixels of the whole image.
    private struct Fragment {
        let text: String
        let box: CGRect
        /// The leftmost piece's box, which keeps the line's own height for ordering.
        let anchor: CGRect
    }

    private struct Tile {
        let rect: CGRect
        /// Words whose centre falls within these bounds belong to this tile; a neighbour reads the rest whole.
        let ownedX: ClosedRange<CGFloat>
        let ownedY: ClosedRange<CGFloat>

        func owns(_ box: CGRect) -> Bool {
            ownedX.contains(box.midX) && ownedY.contains(box.midY)
        }
    }

    /// Recognized lines, top to bottom and left to right.
    static func recognizeLines(in image: CGImage, pixelScale: CGFloat,
                               read: (CGImage) async throws -> [RecognizedTextObservation]) async throws -> [String] {
        let tileSide = Int(tilePoints * pixelScale)
        let overlap = Int(overlapPoints * pixelScale)
        let upscale = max(1, targetPixelScale / pixelScale)
        var fragments: [Fragment] = []
        for tile in tiles(width: image.width, height: image.height, side: tileSide, overlap: overlap) {
            try Task.checkCancellation()
            guard let crop = image.cropping(to: tile.rect) else { continue }
            let observations = try await read(enlarged(crop, by: upscale))
            fragments += observations.flatMap { ownedFragments(of: $0, in: tile) }
        }
        return assemble(fragments)
    }

    // MARK: - Tiling

    private static func tiles(width: Int, height: Int, side: Int, overlap: Int) -> [Tile] {
        let xs = starts(length: width, side: side, overlap: overlap)
        let ys = starts(length: height, side: side, overlap: overlap)
        return ys.indices.flatMap { yi in
            xs.indices.map { xi in
                let rect = CGRect(x: xs[xi], y: ys[yi], width: min(side, width - xs[xi]), height: min(side, height - ys[yi]))
                let minX = xi == 0 ? -CGFloat.infinity : (rect.minX + CGFloat(xs[xi - 1] + side)) / 2
                let maxX = xi == xs.count - 1 ? CGFloat.infinity : (CGFloat(xs[xi + 1]) + rect.maxX) / 2
                let minY = yi == 0 ? -CGFloat.infinity : (rect.minY + CGFloat(ys[yi - 1] + side)) / 2
                let maxY = yi == ys.count - 1 ? CGFloat.infinity : (CGFloat(ys[yi + 1]) + rect.maxY) / 2
                return Tile(rect: rect, ownedX: minX...maxX, ownedY: minY...maxY)
            }
        }
    }

    /// Evenly spaced tile origins covering `length`, each pair overlapping by at least `overlap`.
    private static func starts(length: Int, side: Int, overlap: Int) -> [Int] {
        guard length > side else { return [0] }
        let count = Int((Double(length - overlap) / Double(side - overlap)).rounded(.up))
        let step = Double(length - side) / Double(count - 1)
        return (0..<count).map { Int((Double($0) * step).rounded()) }
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private static func enlarged(_ image: CGImage, by scale: CGFloat) -> CGImage {
        guard scale > 1, let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return image }
        lanczos.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = lanczos.outputImage else { return image }
        return context.createCGImage(output, from: output.extent.integral) ?? image
    }

    // MARK: - Words

    /// The observation's words owned by the tile, as runs of consecutive words.
    private static func ownedFragments(of observation: RecognizedTextObservation, in tile: Tile) -> [Fragment] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let string = candidate.string
        var fragments: [Fragment] = []
        var words: [(text: Substring, box: CGRect)] = []
        func flush() {
            guard let first = words.first else { return }
            let box = words.dropFirst().reduce(first.box) { $0.union($1.box) }
            fragments.append(Fragment(text: words.map(\.text).joined(separator: " "), box: box, anchor: box))
            words.removeAll()
        }
        for range in wordRanges(in: string) {
            guard let normalized = candidate.boundingBox(for: range)?.boundingBox.cgRect else { continue }
            let box = CGRect(x: tile.rect.minX + normalized.minX * tile.rect.width,
                             y: tile.rect.minY + (1 - normalized.maxY) * tile.rect.height,
                             width: normalized.width * tile.rect.width,
                             height: normalized.height * tile.rect.height)
            if tile.owns(box) {
                words.append((string[range], box))
            } else {
                flush()
            }
        }
        flush()
        return fragments
    }

    /// Space-separated words, punctuation included.
    private static func wordRanges(in string: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in string.indices {
            if string[index].isWhitespace {
                if let wordStart = start { ranges.append(wordStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let wordStart = start { ranges.append(wordStart..<string.endIndex) }
        return ranges
    }

    // MARK: - Stitching

    /// Joins pieces of a line split at tile seams, then orders lines top to bottom, left to right.
    private static func assemble(_ fragments: [Fragment]) -> [String] {
        var lines: [Fragment] = []
        for fragment in fragments.sorted(by: { $0.box.minX < $1.box.minX }) {
            let height = fragment.box.height
            let continues = lines.indices.filter { index in
                let line = lines[index].box
                return line.maxX <= fragment.box.minX + height
                    && fragment.box.minX - line.maxX < height * 2
                    && verticalMatch(line, fragment.box) > 0.6
            }
            if let best = continues.max(by: { verticalMatch(lines[$0].box, fragment.box) < verticalMatch(lines[$1].box, fragment.box) }) {
                let line = lines[best]
                lines[best] = Fragment(text: line.text + " " + fragment.text, box: line.box.union(fragment.box), anchor: line.anchor)
            } else {
                lines.append(fragment)
            }
        }

        var rows: [[Fragment]] = []
        for line in lines.sorted(by: { $0.anchor.midY < $1.anchor.midY }) {
            if let first = rows.last?.first, verticalMatch(first.anchor, line.anchor) > 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text) }
    }

    /// How much two boxes share vertically, relative to the shorter one.
    private static func verticalMatch(_ a: CGRect, _ b: CGRect) -> CGFloat {
        (min(a.maxY, b.maxY) - max(a.minY, b.minY)) / max(1, min(a.height, b.height))
    }
}
