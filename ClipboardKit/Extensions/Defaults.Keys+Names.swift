import AppKit
import Defaults

nonisolated struct StorageType: Sendable {
  static let files = StorageType(types: [.fileURL])
  static let images = StorageType(types: [.png, .tiff, .jpeg, .heic])
  static let text = StorageType(types: [.html, .rtf, .string])
  static let all = StorageType(types: files.types + images.types + text.types)

  var types: [NSPasteboard.PasteboardType]
}

nonisolated extension Defaults.Keys {
  // Sirena: clipboard preferences live in their own suite so generic keys
  // (windowSize, migrations, …) never collide with other modules.
  nonisolated(unsafe) private static let preferencesSuite: UserDefaults =
    UserDefaults(suiteName: "com.matheusfaria.Sirena.clipboard") ?? .standard

  static let clearOnQuit = Key<Bool>("clipboard.clearOnQuit", default: false, suite: preferencesSuite)
  static let clearSystemClipboard = Key<Bool>("clipboard.clearSystemClipboard", default: false, suite: preferencesSuite)
  static let clipboardCheckInterval = Key<Double>("clipboard.clipboardCheckInterval", default: 0.5, suite: preferencesSuite)
  static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>(
    "clipboard.enabledPasteboardTypes", default: Set(StorageType.all.types), suite: preferencesSuite
  )
  static let highlightMatch = Key<HighlightMatch>("clipboard.highlightMatch", default: .bold, suite: preferencesSuite)
  static let ignoreAllAppsExceptListed = Key<Bool>("clipboard.ignoreAllAppsExceptListed", default: false, suite: preferencesSuite)
  static let ignoreEvents = Key<Bool>("clipboard.ignoreEvents", default: false, suite: preferencesSuite)
  static let ignoreOnlyNextEvent = Key<Bool>("clipboard.ignoreOnlyNextEvent", default: false, suite: preferencesSuite)
  static let ignoreRegexp = Key<[String]>("clipboard.ignoreRegexp", default: [], suite: preferencesSuite)
  static let ignoredApps = Key<[String]>("clipboard.ignoredApps", default: [], suite: preferencesSuite)
  static let ignoredPasteboardTypes = Key<Set<String>>(
    "clipboard.ignoredPasteboardTypes",
    default: Set([
      "Pasteboard generator type",
      "com.agilebits.onepassword",
      "com.typeit4me.clipping",
      "de.petermaurer.TransientPasteboardType",
      "net.antelle.keeweb"
    ]),
    suite: preferencesSuite
  )
  static let imageMaxHeight = Key<Int>("clipboard.imageMaxHeight", default: 40, suite: preferencesSuite)
  static let lastReviewRequestedAt = Key<Date>("clipboard.lastReviewRequestedAt", default: Date.now, suite: preferencesSuite)
  static let menuIcon = Key<MenuIcon>("clipboard.menuIcon", default: .clipboard, suite: preferencesSuite)
  static let migrations = Key<[String: Bool]>("clipboard.migrations", default: [:], suite: preferencesSuite)
  static let numberOfUsages = Key<Int>("clipboard.numberOfUsages", default: 0, suite: preferencesSuite)
  static let pasteByDefault = Key<Bool>("clipboard.pasteByDefault", default: false, suite: preferencesSuite)
  static let pinOrder = Key<PinOrder>("clipboard.pinOrder", default: PinOrder(), suite: preferencesSuite)
  static let pinTo = Key<PinsPosition>("clipboard.pinTo", default: .top, suite: preferencesSuite)
  static let popupPosition = Key<PopupPosition>("clipboard.popupPosition", default: .cursor, suite: preferencesSuite)
  static let popupScreen = Key<Int>("clipboard.popupScreen", default: 0, suite: preferencesSuite)
  static let openPreviewAutomatically = Key<Bool>("clipboard.openPreviewAutomatically", default: true, suite: preferencesSuite)
  static let previewDelay = Key<Int>("clipboard.previewDelay", default: 1500, suite: preferencesSuite)
  static let removeFormattingByDefault = Key<Bool>("clipboard.removeFormattingByDefault", default: false, suite: preferencesSuite)
  static let searchMode = Key<Search.Mode>("clipboard.searchMode", default: .exact, suite: preferencesSuite)
  static let showFooter = Key<Bool>("clipboard.showFooter", default: true, suite: preferencesSuite)
  static let showInStatusBar = Key<Bool>("clipboard.showInStatusBar", default: true, suite: preferencesSuite)
  static let showRecentCopyInMenuBar = Key<Bool>("clipboard.showRecentCopyInMenuBar", default: false, suite: preferencesSuite)
  static let showSearch = Key<Bool>("clipboard.showSearch", default: true, suite: preferencesSuite)
  static let searchVisibility = Key<SearchVisibility>("clipboard.searchVisibility", default: .always, suite: preferencesSuite)
  static let showSpecialSymbols = Key<Bool>("clipboard.showSpecialSymbols", default: true, suite: preferencesSuite)
  static let showTitle = Key<Bool>("clipboard.showTitle", default: true, suite: preferencesSuite)
  static let size = Key<Int>("clipboard.historySize", default: 200, suite: preferencesSuite)
  static let sortBy = Key<Sorter.By>("clipboard.sortBy", default: .lastCopiedAt, suite: preferencesSuite)
  static let suppressClearAlert = Key<Bool>("clipboard.suppressClearAlert", default: false, suite: preferencesSuite)
  static let windowSize = Key<NSSize>("clipboard.windowSize", default: NSSize(width: 450, height: 800), suite: preferencesSuite)
  static let windowPosition = Key<NSPoint>("clipboard.windowPosition", default: NSPoint(x: 0.5, y: 0.8), suite: preferencesSuite)
  static let showApplicationIcons = Key<Bool>("clipboard.showApplicationIcons", default: false, suite: preferencesSuite)
  static let showHexColorSwatch = Key<Bool>("clipboard.showHexColorSwatch", default: true, suite: preferencesSuite)
  static let previewWidth = Key<CGFloat>("clipboard.previewWidth", default: 400, suite: preferencesSuite)
}
