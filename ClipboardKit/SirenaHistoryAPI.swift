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
  /// What it looks like at a glance (image, color, link, files, code or text).
  public let preview: ClipPreview
}

/// The menu bar panel's history settings (shown on the Clipboard page).
public enum ClipboardMenuSettings {
  public static let countKey = "clipboard.menu.count"
  public static let previewsKey = "clipboard.menu.previews"
  public static let clickPastesKey = "clipboard.menu.clickPastes"
  public static let defaultCount = 7
  public static let counts = [5, 7, 10, 15]
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
        kind: kind,
        preview: item.clipPreview
      )
    }
  }

  /// A small preview of an image item (generated on first request).
  public func thumbnail(for id: ObjectIdentifier) -> NSImage? {
    guard let item = decorator(id), item.hasImage else { return nil }
    item.ensureThumbnailImage()
    return item.thumbnailImage
  }

  /// The image preview if it was already made; reading it inside a view refreshes the
  /// view once `loadThumbnail(for:)` finishes.
  public func cachedThumbnail(for id: ObjectIdentifier) -> NSImage? {
    decorator(id)?.thumbnailImage
  }

  /// Starts making the image preview (call from `onAppear`, never while drawing).
  @MainActor
  public func loadThumbnail(for id: ObjectIdentifier) {
    guard let item = decorator(id), item.clipPreview == .image else { return }
    item.ensureThumbnailImage()
  }

  /// The whole text (up to 10,000 characters), for the hover preview.
  public func fullText(for id: ObjectIdentifier) -> String {
    decorator(id)?.text ?? ""
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

  /// Puts the item on the clipboard and presses ⌘V in the frontmost app (needs Accessibility).
  /// The caller makes sure the app to paste into is in front first.
  public func paste(_ id: ObjectIdentifier, removeFormatting: Bool = false) {
    guard let item = decorator(id) else { return }
    Clipboard.shared.copy(item.item, removeFormatting: removeFormatting)
    Clipboard.shared.paste()
  }

  /// What dragging the item out of a list drops into another app.
  public func itemProvider(for id: ObjectIdentifier) -> NSItemProvider? {
    guard let item = decorator(id) else { return nil }
    switch item.clipPreview {
    case .files(let urls):
      guard let first = urls.first else { return nil }
      return NSItemProvider(contentsOf: first) ?? NSItemProvider(object: first as NSURL)
    case .image:
      guard let image = item.item.image else { return nil }
      return NSItemProvider(object: image)
    case .link(let url):
      return NSItemProvider(object: url as NSURL)
    case .color, .code, .text:
      let text = item.item.text ?? item.item.previewableText
      return text.isEmpty ? nil : NSItemProvider(object: text as NSString)
    }
  }

  public func togglePin(_ id: ObjectIdentifier) {
    history.togglePin(decorator(id))
  }

  public func delete(_ id: ObjectIdentifier) {
    history.delete(decorator(id))
  }
}
