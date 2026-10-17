/// ShelfIntents.swift
///
/// Shelf actions for the Shortcuts app.

import AppIntents
import AppKit

private enum ShelfIntentError: Error, CustomLocalizedStringResourceConvertible {
    case shelfOff

    var localizedStringResource: LocalizedStringResource {
        "Shelf is turned off in Sirena."
    }
}

@MainActor
private func requireShelf() throws {
    guard ModuleManager.shared.isRunning(.shelf) else { throw ShelfIntentError.shelfOff }
}

struct AddFilesToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Files to Shelf"
    static let description = IntentDescription("Puts the files on the Sirena shelf.")

    @Parameter(title: "Files")
    var files: [IntentFile]

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireShelf()
        // Shortcuts often hands over temporary copies (or bare data): keep our own copy
        // in the shelf's folder so the item survives.
        var urls: [URL] = []
        for file in files {
            let name = file.filename.isEmpty ? UUID().uuidString : file.filename
            var destination = ShelfStore.folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = ShelfStore.folder.appendingPathComponent("\(UUID().uuidString.prefix(6)) \(name)")
            }
            if (try? file.data.write(to: destination)) != nil { urls.append(destination) }
        }
        if !urls.isEmpty {
            ShelfStore.shared.add([ShelfItem(content: .files(urls.map(ShelfFile.init)), ownsFiles: true)])
            ShelfController.shared.show()
        }
        return .result()
    }
}

struct SaveClipboardToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard Contents to Shelf"
    static let description = IntentDescription("Puts what's on the clipboard on the Sirena shelf.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireShelf()
        ShelfActions.addFromClipboard()
        return .result()
    }
}

struct RemoveAllFromShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove All Files from Shelf"
    static let description = IntentDescription("Clears the Sirena shelf, optionally including locked items.")

    @Parameter(title: "Include Locked Items", default: false)
    var includeLocked: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireShelf()
        ShelfStore.shared.removeAll(includingLocked: includeLocked)
        return .result()
    }
}

struct GetFilesFromShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Files from Shelf"
    static let description = IntentDescription("Returns the files on the Sirena shelf.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        try requireShelf()
        let files = ShelfStore.shared.items.flatMap(\.urls).map { IntentFile(fileURL: $0) }
        return .result(value: files)
    }
}
