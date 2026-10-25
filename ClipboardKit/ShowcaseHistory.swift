import AppKit
import SwiftData

// Sirena showcase (SIRENA_SHOWCASE=1, screenshots for the site): an empty history gets fictional
// text entries. The pasteboard is never read or written, and no sound or notification is played.
extension ClipboardController {
  @MainActor
  public func loadShowcaseHistory(_ samples: [(text: String, app: String, minutesAgo: Double, pinned: Bool)]) async {
    let context = Storage.shared.context
    if (try? context.fetchCount(FetchDescriptor<HistoryItem>())) == 0 {
      var pins = HistoryItem.sortedPins(HistoryItem.supportedPins)
      for sample in samples {
        let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                         value: sample.text.data(using: .utf8))
        let item = HistoryItem(contents: [content])
        item.application = sample.app
        item.lastCopiedAt = Date.now.addingTimeInterval(-sample.minutesAgo * 60)
        item.firstCopiedAt = item.lastCopiedAt
        item.title = sample.text
        if sample.pinned, !pins.isEmpty { item.pin = pins.removeFirst() }
        context.insert(item)
      }
      try? context.save()
    }
    try? await AppState.shared.history.load()
  }
}
