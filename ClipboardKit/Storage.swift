import AppKit.NSPasteboard
import Foundation
import os
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  private static let log = Logger(subsystem: "Sirena", category: "ClipboardStorage")

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url: URL = {
    let directory = URL.applicationSupportDirectory.appending(path: "Sirena", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "Clipboard.sqlite")
  }()

  init() {
    let config = ModelConfiguration(url: url)

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
      return
    } catch {
      Self.log.error("Clipboard store failed to open: \(error.localizedDescription, privacy: .public)")
    }

    Self.moveStoreAside(url)

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
      return
    } catch {
      Self.log.error("Clipboard store failed after recovery: \(error.localizedDescription, privacy: .public)")
    }

    container = Self.inMemoryContainer()
  }

  private static func moveStoreAside(_ url: URL) {
    let suffix = ".corrupt-\(Int(Date().timeIntervalSince1970))"
    let fileManager = FileManager.default

    for path in [url.path, url.path + "-wal", url.path + "-shm"] where fileManager.fileExists(atPath: path) {
      do {
        try fileManager.moveItem(atPath: path, toPath: path + suffix)
        log.notice("Moved clipboard store file aside: \(path + suffix, privacy: .public)")
      } catch {
        log.error("Cannot move \(path, privacy: .public) aside: \(error.localizedDescription, privacy: .public)")
        try? fileManager.removeItem(atPath: path)
      }
    }
  }

  private static func inMemoryContainer() -> ModelContainer {
    // A failing in-memory store means the model itself is broken (programmer error), not user data.
    do {
      return try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    } catch {
      fatalError("In-memory clipboard store unavailable: \(error)")
    }
  }

  func cleanupOrphanedContents() throws -> Int {
    let descriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )
    let count = try context.fetchCount(descriptor)
    guard count > 0 else {
      return 0
    }

    try context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
    context.processPendingChanges()
    try context.save()

    return count
  }

  func removeUnpersistableContents() throws -> Int {
    let contents = try context.fetch(FetchDescriptor<HistoryItemContent>())
    let unwanted = contents.filter {
      !Clipboard.shared.isPersistable(NSPasteboard.PasteboardType($0.type))
    }

    guard !unwanted.isEmpty else {
      return 0
    }

    unwanted.forEach(context.delete)
    context.processPendingChanges()
    try context.save()

    return unwanted.count
  }

  // Titles stored before the sanitization in `HistoryItem.generateTitle()` may
  // contain scalars that hang CoreText on macOS 26. Such an item makes Maccy
  // spin at 100% CPU on every launch without ever drawing its window, so the
  // store has to be healed before the history is first rendered.
  // See https://github.com/p0deje/Maccy/issues/1520.
  func sanitizeTitles() throws -> Int {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    var count = 0

    for item in items where item.title.containsScalarsUnsafeForTitleLayout {
      item.title = item.title.removingScalarsUnsafeForTitleLayout()
      count += 1
    }

    guard count > 0 else {
      return 0
    }

    context.processPendingChanges()
    try context.save()

    return count
  }
}
