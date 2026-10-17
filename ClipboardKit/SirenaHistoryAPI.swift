import AppKit

// Sirena: what the clipboard page in Sirena's main window shows and does. Maccy keeps
// its own floating history panel; this is the same history, read from the app.

/// One copied item, as Sirena's page shows it.
public struct ClipboardEntry: Identifiable, Equatable {
  public enum Kind: Sendable { case text, richText, image, file }

  public let id: ObjectIdentifier
  public let title: String
  public let appName: String?
  public let lastCopied: Date
  public let copies: Int
  public let isPinned: Bool
  public let kind: Kind
}

extension ClipboardController {
  private var history: History { AppState.shared.history }

  private var decorators: [HistoryItemDecorator] {
    history.allPinnedItems + history.allUnpinnedItems
  }

  private func decorator(_ id: ObjectIdentifier) -> HistoryItemDecorator? {
    decorators.first { ObjectIdentifier($0) == id }
  }

  /// Pinned items first, then the rest, newest first.
  public var entries: [ClipboardEntry] {
    decorators.map { item in
      let kind: ClipboardEntry.Kind = item.hasImage ? .image
        : item.hasFileURLs ? .file
        : item.hasRichText && !item.hasPlainText ? .richText : .text
      return ClipboardEntry(
        id: ObjectIdentifier(item),
        title: item.title,
        appName: item.application,
        lastCopied: item.item.lastCopiedAt,
        copies: item.item.numberOfCopies,
        isPinned: item.isPinned,
        kind: kind
      )
    }
  }

  /// A small preview of an image item (generated on first request).
  public func thumbnail(for id: ObjectIdentifier) -> NSImage? {
    guard let item = decorator(id), item.hasImage else { return nil }
    item.ensureThumbnailImage()
    return item.thumbnailImage
  }

  /// The icon of the app it was copied from.
  public func appIcon(for id: ObjectIdentifier) -> NSImage? {
    decorator(id)?.applicationImage.nsImage
  }

  /// Puts the item back on the clipboard.
  public func copy(_ id: ObjectIdentifier, removeFormatting: Bool = false) {
    guard let item = decorator(id) else { return }
    Clipboard.shared.copy(item.item, removeFormatting: removeFormatting)
  }

  public func togglePin(_ id: ObjectIdentifier) {
    history.togglePin(decorator(id))
  }

  public func delete(_ id: ObjectIdentifier) {
    history.delete(decorator(id))
  }
}
