/// ShelfIncoming.swift
///
/// What lands on the shelf from a drop, the clipboard or the Services menu. Files stay where
/// they are (bookmarks). Everything that isn't a file yet becomes one, a real file in the
/// shelf's folder, so dragging it out works anywhere (an image editor, a web upload, a chat):
///
/// - Promised files (browsers, Photos, Mail): the app writes the file for the shelf. A browser
///   writes the image as it has it, with its own name.
/// - Images from the web: the original is downloaded (Google's `imgurl`, the `<img>` source, an
///   image link), so the shelf keeps the full image, not the picture the drag showed.
/// - Image bytes on the pasteboard are kept as they are; only a TIFF (pixels, no format) is
///   encoded. Formats other apps often refuse (WebP, AVIF, HEIC, BMP, TIFF) become PNG (with
///   transparency) or JPEG (`ShelfSettings.convertsImages`).
///
/// While a file is on its way the shelf shows a placeholder (`ShelfStore.pending`). Nothing is
/// read or written on the main thread but the pasteboard itself, which only lives for the drop.

import AppKit
import ImageIO
import os
import UniformTypeIdentifiers

/// Something on its way to the shelf: a promised file being written, an image downloading.
struct ShelfPending: Identifiable, Hashable {
    let id = UUID()
    var title: String
}

@MainActor
enum ShelfIncoming {
    nonisolated private static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "Shelf")

    /// Image formats read byte for byte from a pasteboard, best first.
    nonisolated static let encodedImageTypes: [NSPasteboard.PasteboardType] = [
        "public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp",
        "public.heic", "public.heif", "public.avif", "com.microsoft.bmp"
    ].map { NSPasteboard.PasteboardType($0) }

    /// Everything the shelf (and the island, for it) accepts in a drag.
    nonisolated static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string, .tiff, .color, .rtf, .html,
         NSPasteboard.PasteboardType("NSFilenamesPboardType")]
        + encodedImageTypes
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "Sirena.Shelf.promises"
        return queue
    }()

    /// Takes what `pasteboard` holds. True when something lands (now or once it's written).
    @discardableResult
    static func take(_ pasteboard: NSPasteboard) -> Bool {
        let store = ShelfStore.shared
        log.info("incoming: \((pasteboard.types ?? []).map(\.rawValue).joined(separator: ", "), privacy: .public)")

        // 1. Files that already exist (Finder, the desktop, most apps).
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let resolved = ShelfSettings.shared.resolveAliases ? urls.map(resolveAlias) : urls
            store.add([ShelfItem(content: .files(resolved.map(ShelfFile.init)))])
            return true
        }
        if let color = NSColor(from: pasteboard)?.usingColorSpace(.sRGB) {
            store.add([ShelfItem(content: .color(red: color.redComponent, green: color.greenComponent,
                                                 blue: color.blueComponent, alpha: color.alphaComponent))])
            return true
        }

        // Read now: the pasteboard is gone once the drop returns.
        let image = WebImage(pasteboard)

        // 2. Files an app promises to write (a browser's image, a photo from Photos).
        let receivers = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? [])
            .filter { receiver in
                // A link dragged from a browser may promise a .webloc: the link itself is better.
                !receiver.fileTypes.allSatisfy { UTType($0)?.conforms(to: .internetLocation) == true }
            }
        if !receivers.isEmpty {
            receive(receivers, fallback: image)
            return true
        }

        // 3. An image without a file: bytes, a data: URI or an address to download.
        if image.hasImage {
            land(image, pending: store.beginPending(image.title))
            return true
        }

        // 4. Links and text.
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           let scheme = url.scheme, ["http", "https", "mailto", "ftp"].contains(scheme.lowercased()) {
            store.add([ShelfItem(content: .link(url))])
            return true
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()), url.host() != nil {
                store.add([ShelfItem(content: .link(url))])
            } else {
                store.add([ShelfItem(content: .text(text))])
            }
            return true
        }
        return false
    }

    private static func resolveAlias(_ url: URL) -> URL {
        guard (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true else { return url }
        return (try? URL(resolvingAliasFileAt: url)) ?? url
    }

    // MARK: - Promised files

    private static func receive(_ receivers: [NSFilePromiseReceiver], fallback: WebImage) {
        let store = ShelfStore.shared
        let incoming = ShelfStore.folder.appendingPathComponent("Incoming/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let convert = ShelfSettings.shared.convertsImages
        for receiver in receivers {
            let pending = store.beginPending(receiver.fileNames.first ?? fallback.title)
            var settled = false
            // A promise that never comes (the app quit, a stalled download) doesn't spin forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                guard !settled else { return }
                settled = true
                log.error("promised file never came")
                fail(pending, fallback: fallback)
            }
            receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: promiseQueue) { url, error in
                // On the promise queue: the file is written, move it in off the main thread.
                let landed = error == nil ? ShelfFiles.adopt(url, convert: convert) : nil
                if let error { log.error("promised file failed: \(error.localizedDescription, privacy: .public)") }
                DispatchQueue.main.async {
                    if let landed {
                        if !settled { settled = true; store.endPending(pending) }
                        store.add([ShelfItem(content: .files([ShelfFile(url: landed)]), ownsFiles: true)])
                    } else if !settled {
                        settled = true
                        fail(pending, fallback: fallback)
                    }
                    try? FileManager.default.removeItem(at: incoming)
                }
            }
        }
    }

    // MARK: - Images without a file

    /// Downloads the original when there is one to fetch, else keeps the bytes that came with the drop.
    private static func land(_ image: WebImage, pending: UUID) {
        let convert = ShelfSettings.shared.convertsImages
        Task.detached(priority: .userInitiated) {
            var file: URL?
            for source in image.sources {
                file = await source.write(named: image.baseName, convert: convert)
                if file != nil { break }
            }
            let landed = file
            await MainActor.run {
                if let landed {
                    ShelfStore.shared.endPending(pending)
                    ShelfStore.shared.add([ShelfItem(content: .files([ShelfFile(url: landed)]), ownsFiles: true)])
                } else {
                    fail(pending, fallback: nil, link: image.link)
                }
            }
        }
    }

    /// Nothing could be written: what came with the drop, else the link, else a beep.
    private static func fail(_ pending: UUID, fallback: WebImage?, link: URL? = nil) {
        let store = ShelfStore.shared
        if let fallback, fallback.hasImage {
            // The promise failed but the drop also carried the image: use that.
            land(fallback, pending: pending)
            return
        }
        store.endPending(pending)
        if let link = link ?? fallback?.link {
            store.add([ShelfItem(content: .link(link))])
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - An image from a web page (or any app), read off the pasteboard

struct WebImage: Sendable {
    enum Source: Sendable {
        /// Bytes in a known format (from the pasteboard or a data: URI).
        case bytes(Data, UTType)
        /// Pixels without a format (a TIFF from the pasteboard): always encoded.
        case pixels(Data)
        case remote(URL)

        func write(named name: String, convert: Bool) async -> URL? {
            switch self {
            case .bytes(let data, let type):
                return ShelfFiles.save(data, type: type, name: name, convert: convert)
            case .pixels(let data):
                return ShelfFiles.save(data, type: .tiff, name: name, convert: true)
            case .remote(let url):
                guard let (data, type) = await ShelfFiles.download(url) else { return nil }
                return ShelfFiles.save(data, type: type, name: name, convert: convert)
            }
        }
    }

    /// Best first: the original over a copy, a copy over nothing.
    var sources: [Source] = []
    /// The page or image link, kept on the shelf if no image can be had.
    var link: URL?
    /// File name without extension.
    var baseName: String

    var hasImage: Bool { !sources.isEmpty }
    var title: String { baseName }

    @MainActor
    init(_ pasteboard: NSPasteboard) {
        let links = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [])
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        link = links.first
        let html = pasteboard.string(forType: .html) ?? ""
        let imageSource = Self.imageSource(in: html)

        // Google Images (and other search engines) link to the original with ?imgurl=.
        let original = links.lazy.compactMap(Self.imgurl).first
        // The <img> the drag started on, or a link straight to an image file.
        let remote = imageSource.flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
            ?? links.first(where: Self.looksLikeImage)

        var sources: [Source] = []
        if let original { sources.append(.remote(original)) }
        if let type = pasteboard.availableType(from: ShelfIncoming.encodedImageTypes),
           let data = pasteboard.data(forType: type), let uti = UTType(type.rawValue) {
            sources.append(.bytes(data, uti))
        }
        if let imageSource, let decoded = Self.decodeDataURI(imageSource) {
            sources.append(.bytes(decoded.data, decoded.type))
        }
        if let remote, remote != original { sources.append(.remote(remote)) }
        if let tiff = pasteboard.data(forType: .tiff) { sources.append(.pixels(tiff)) }
        self.sources = sources

        let named = [original, remote].compactMap { $0 }.first(where: Self.looksLikeImage)
        baseName = named.map(Self.baseName) ?? Self.datedName()
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff", "svg"]

    static func looksLikeImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func imgurl(_ url: URL) -> URL? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "imgurl" || $0.name == "mediaurl" })?.value,
              let target = URL(string: value), ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return nil }
        return target
    }

    /// The first `<img src>` (or `srcset`'s largest) of the dragged HTML.
    static func imageSource(in html: String) -> URL? {
        guard !html.isEmpty,
              let tag = html.range(of: "<img\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let img = String(html[tag])
        if let srcset = attribute("srcset", in: img) {
            // "a.jpg 1x, b.jpg 2x" or "a.jpg 320w, b.jpg 1024w": the last is the biggest.
            let candidates = srcset.split(separator: ",").compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first }
            if let last = candidates.last, let url = URL(string: String(last)), url.scheme != nil { return url }
        }
        return attribute("src", in: img).flatMap { URL(string: $0) }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in [2, 3] {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range]).replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }

    static func decodeDataURI(_ url: URL) -> (data: Data, type: UTType)? {
        let string = url.absoluteString
        guard string.hasPrefix("data:image/"), let comma = string.firstIndex(of: ",") else { return nil }
        let header = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let mime = header.split(separator: ";").first.map(String.init) ?? ""
        let payload = String(string[string.index(after: comma)...])
        let data = header.contains(";base64")
            ? Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters)
            : payload.removingPercentEncoding?.data(using: .utf8)
        guard let data, let type = UTType(mimeType: mime) else { return nil }
        return (data, type)
    }

    static func baseName(_ url: URL) -> String {
        let name = (url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? url.deletingPathExtension().lastPathComponent)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? datedName() : String(name.prefix(80))
    }

    static func datedName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(L("Image")) \(formatter.string(from: Date()))"
    }
}

// MARK: - Files the shelf makes (off the main thread)

enum ShelfFiles {
    /// Formats every app and web upload takes as they are.
    private static let universal: [UTType] = [.png, .jpeg, .gif]

    /// Downloads an image: nil for anything that isn't one, an error or more than 200 MB.
    static func download(_ url: URL) async -> (Data, UTType)? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Asking for the formats everyone opens: many servers then send JPEG/PNG instead of WebP.
        request.setValue("image/png,image/jpeg,image/gif;q=0.9,image/*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count < 200_000_000,
              let type = imageType(of: data) else { return nil }
        return (data, type)
    }

    /// What the bytes really are (not what the name or the server says).
    static func imageType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }

    /// Writes an image into the shelf's folder under a free name. `convert`: a format other
    /// apps often refuse becomes PNG (transparency) or JPEG.
    static func save(_ data: Data, type: UTType, name: String, convert: Bool) -> URL? {
        let actual = imageType(of: data) ?? type
        var bytes = data
        var finalType = actual
        if (convert && !universal.contains(where: { actual.conforms(to: $0) })) || actual.conforms(to: .tiff) {
            guard let encoded = reencode(data) else { return nil }
            (bytes, finalType) = encoded
        }
        let url = freeURL(name: name, ext: finalType.preferredFilenameExtension ?? "png")
        return (try? bytes.write(to: url, options: .withoutOverwriting)) != nil ? url : nil
    }

    /// A promised file just written: converted if needed, then moved into the shelf's folder.
    static func adopt(_ url: URL, convert: Bool) -> URL? {
        let type = UTType(filenameExtension: url.pathExtension)
        let base = url.deletingPathExtension().lastPathComponent
        if convert, let type, type.conforms(to: .image), !universal.contains(where: { type.conforms(to: $0) }),
           !type.conforms(to: .svg), let data = try? Data(contentsOf: url), let (bytes, newType) = reencode(data) {
            let target = freeURL(name: base, ext: newType.preferredFilenameExtension ?? "png")
            if (try? bytes.write(to: target, options: .withoutOverwriting)) != nil { return target }
        }
        let target = freeURL(name: base, ext: url.pathExtension)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// PNG when the image has transparency, otherwise a high-quality JPEG. The first frame only.
    private static func reencode(_ data: Data) -> (Data, UTType)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let alpha = image.alphaInfo
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
        let type: UTType = opaque ? .jpeg : .png
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        // Orientation and color profile come along with the image's properties.
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        if opaque { properties[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, type)
    }

    private static func freeURL(name: String, ext: String) -> URL {
        let folder = ShelfStore.folder
        // ".jpg", the name everyone knows (UTType says "jpeg").
        let ext = ext.lowercased() == "jpeg" ? "jpg" : ext
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var url = folder.appendingPathComponent(name + suffix)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(number)\(suffix)")
            number += 1
        }
        return url
    }
}
