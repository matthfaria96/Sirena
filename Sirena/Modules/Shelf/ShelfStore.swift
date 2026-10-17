/// ShelfStore.swift
///
/// What sits on the shelf, kept across launches. Files are referenced by bookmarks
/// (the shelf points at them, it never copies them); text, links, colors and images
/// dragged from apps are stored by the shelf itself.

import AppKit
import UniformTypeIdentifiers

struct ShelfFile: Codable, Hashable {
    var bookmark: Data?
    var path: String

    init(url: URL) {
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        path = url.path
    }

    /// Where the file was when it was added (or last renamed/moved from the shelf).
    var storedURL: URL { URL(fileURLWithPath: path) }

    /// Follows the file if it was moved or renamed since it was added. Resolved without
    /// mounting volumes and cached, because SwiftUI asks for it on every render.
    var url: URL {
        guard let bookmark else { return storedURL }
        if let cached = ShelfFile.resolved[bookmark] { return cached }
        var stale = false
        let resolved = (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)) ?? storedURL
        ShelfFile.resolved[bookmark] = resolved
        return resolved
    }

    nonisolated(unsafe) private static var resolved: [Data: URL] = [:]

    /// Forgets resolved locations (files may have moved since).
    static func clearResolvedCache() {
        resolved.removeAll()
    }
}

struct ShelfItem: Identifiable, Codable, Hashable {
    enum Content: Codable, Hashable {
        /// One file, or several kept together as a stack.
        case files([ShelfFile])
        case text(String)
        case link(URL)
        /// sRGB components, 0 … 1.
        case color(red: Double, green: Double, blue: Double, alpha: Double)
    }

    var id = UUID()
    var content: Content
    var isLocked = false
    var added = Date()
    /// The item holds a file the shelf created itself (an image dragged from an app).
    /// Only files still inside the shelf's own folder are ever deleted, see ShelfStore.
    var ownsFiles = false

    init(content: Content, isLocked: Bool = false, ownsFiles: Bool = false) {
        self.content = content
        self.isLocked = isLocked
        self.ownsFiles = ownsFiles
    }

    // Fields added later must not make older saved shelves unreadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try container.decode(Content.self, forKey: .content)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        added = try container.decodeIfPresent(Date.self, forKey: .added) ?? Date()
        ownsFiles = try container.decodeIfPresent(Bool.self, forKey: .ownsFiles) ?? false
    }

    var urls: [URL] {
        if case .files(let files) = content { return files.map(\.url) }
        return []
    }

    var isStack: Bool { urls.count > 1 }

    var title: String {
        switch content {
        case .files(let files):
            let names = files.map { $0.url.lastPathComponent }
            return names.count == 1 ? names[0] : L("\(names.count) files")
        case .text(let text):
            let firstLine = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty ? L("Text Snippet") : firstLine
        case .link(let url):
            return url.host() ?? url.absoluteString
        case .color:
            return hexColor ?? L("Color Swatch")
        }
    }

    var nsColor: NSColor? {
        guard case .color(let red, let green, let blue, let alpha) = content else { return nil }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexColor: String? {
        guard case .color(let red, let green, let blue, _) = content else { return nil }
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()

    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []
    /// Batches of items taken off the shelf, newest last, for "Restore Last Removed Files".
    private(set) var removedBatches: [[ShelfItem]] = []

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Sirena/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private var fileURL: URL { Self.folder.appendingPathComponent("items.json") }

    private init() {
        load()
        removeOrphanedFiles()
    }

    /// Reads the saved shelf item by item: one unreadable item is skipped, not the whole
    /// shelf. If anything couldn't be read, the original file is kept as a backup.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        struct Lenient: Decodable {
            let item: ShelfItem?
            init(from decoder: Decoder) throws { item = try? ShelfItem(from: decoder) }
        }
        guard let entries = try? JSONDecoder().decode([Lenient].self, from: data) else {
            backUpUnreadableFile(data)
            return
        }
        items = entries.compactMap(\.item)
        if items.count != entries.count { backUpUnreadableFile(data) }
    }

    private func backUpUnreadableFile(_ data: Data) {
        let backup = Self.folder.appendingPathComponent("items-backup-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: backup)
    }

    /// Images the shelf saved for items that are gone (e.g. removed before Sirena quit).
    private func removeOrphanedFiles() {
        let referenced = Set(items.flatMap { item -> [String] in
            guard case .files(let files) = item.content else { return [] }
            return files.map { $0.storedURL.standardizedFileURL.path }
        })
        let contents = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.pathExtension == "png" && !referenced.contains(url.standardizedFileURL.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private func save() {
        ShelfFile.clearResolvedCache()
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Adding

    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        save()
    }

    /// Reads whatever a pasteboard holds: files become one item (a stack when there are
    /// several), otherwise images, links, colors or text.
    @discardableResult
    func add(from pasteboard: NSPasteboard) -> Bool {
        let newItems = Self.items(from: pasteboard)
        add(newItems)
        return !newItems.isEmpty
    }

    static func items(from pasteboard: NSPasteboard) -> [ShelfItem] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let resolved = ShelfSettings.shared.resolveAliases ? urls.map(resolveAlias) : urls
            return [ShelfItem(content: .files(resolved.map(ShelfFile.init)))]
        }
        if let color = NSColor(from: pasteboard)?.usingColorSpace(.sRGB) {
            return [ShelfItem(content: .color(red: color.redComponent, green: color.greenComponent,
                                              blue: color.blueComponent, alpha: color.alphaComponent))]
        }
        if let image = NSImage(pasteboard: pasteboard), pasteboard.availableType(from: [.png, .tiff]) != nil,
           let url = saveImage(image) {
            return [ShelfItem(content: .files([ShelfFile(url: url)]), ownsFiles: true)]
        }
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           let scheme = url.scheme, ["http", "https", "mailto", "ftp"].contains(scheme.lowercased()) {
            return [ShelfItem(content: .link(url))]
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()), url.host() != nil {
                return [ShelfItem(content: .link(url))]
            }
            return [ShelfItem(content: .text(text))]
        }
        return []
    }

    private static func resolveAlias(_ url: URL) -> URL {
        guard (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true else { return url }
        return (try? URL(resolvingAliasFileAt: url)) ?? url
    }

    static func saveImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "\(L("Image")) \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).png")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number).png")
            number += 1
        }
        return (try? png.write(to: url, options: .withoutOverwriting)) != nil ? url : nil
    }

    // MARK: - Removing

    func remove(_ ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        rememberRemoved(removed)
        save()
    }

    /// Removes everything except locked items (unless `includingLocked`).
    func removeAll(includingLocked: Bool = false) {
        remove(Set(items.filter { includingLocked || !$0.isLocked }.map(\.id)))
    }

    var canRestore: Bool { !removedBatches.isEmpty }

    func restoreLastRemoved() {
        guard let batch = removedBatches.popLast() else { return }
        items.append(contentsOf: batch)
        save()
    }

    private func rememberRemoved(_ removed: [ShelfItem]) {
        removedBatches.append(removed)
        if removedBatches.count > 10 {
            // Forgotten for good: delete the files the shelf made itself.
            let forgotten = removedBatches.removeFirst()
            for item in forgotten where item.ownsFiles {
                deleteOwnedFiles(of: item)
            }
        }
    }

    /// Deletes (to the Trash) only files the shelf made that are still where it saved
    /// them, inside its own folder. Never follows a bookmark: a file the user moved
    /// elsewhere, or a user file merged into the same stack, is never touched.
    private func deleteOwnedFiles(of item: ShelfItem) {
        guard case .files(let files) = item.content else { return }
        let folder = Self.folder.standardizedFileURL.path + "/"
        for file in files {
            let url = file.storedURL.standardizedFileURL
            guard url.path.hasPrefix(folder), FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    // MARK: - Changing

    func update(_ id: UUID, _ change: (inout ShelfItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    func toggleLock(_ ids: Set<UUID>) {
        let lock = items.contains { ids.contains($0.id) && !$0.isLocked }
        for id in ids { update(id) { $0.isLocked = lock } }
    }

    /// Joins the file items into one stack, placed where the first of them was.
    func mergeToStack(_ ids: Set<UUID>) {
        let fileItems = items.filter { ids.contains($0.id) && !$0.urls.isEmpty }
        guard fileItems.count > 1, let index = items.firstIndex(where: { $0.id == fileItems[0].id }) else { return }
        let files = fileItems.flatMap { item -> [ShelfFile] in
            if case .files(let files) = item.content { return files }
            return []
        }
        var stack = ShelfItem(content: .files(files))
        stack.isLocked = fileItems.allSatisfy(\.isLocked)
        stack.ownsFiles = fileItems.contains(where: \.ownsFiles)
        items.removeAll { item in fileItems.contains { $0.id == item.id } }
        items.insert(stack, at: min(index, items.count))
        selection = [stack.id]
        save()
    }

    func mergeAllToStack() {
        mergeToStack(Set(items.map(\.id)))
    }

    /// Turns a stack back into one item per file.
    func split(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .files(let files) = items[index].content, files.count > 1 else { return }
        let original = items[index]
        let singles = files.map { file in
            ShelfItem(content: .files([file]), isLocked: original.isLocked, ownsFiles: original.ownsFiles)
        }
        items.replaceSubrange(index...index, with: singles)
        selection = Set(singles.map(\.id))
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Points file items at their new place after a rename or move.
    func replaceURL(_ old: URL, with new: URL) {
        for index in items.indices {
            guard case .files(var files) = items[index].content,
                  let fileIndex = files.firstIndex(where: {
                      $0.storedURL.standardizedFileURL == old.standardizedFileURL || $0.url.standardizedFileURL == new.standardizedFileURL
                  }) else { continue }
            files[fileIndex] = ShelfFile(url: new)
            items[index].content = .files(files)
        }
        save()
    }
}
