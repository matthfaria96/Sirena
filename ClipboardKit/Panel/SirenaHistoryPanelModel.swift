/// SirenaHistoryPanelModel.swift
///
/// State for Sirena's floating clipboard-history panel: the search query, the
/// filtered pinned/recent lists and the keyboard selection. Pure reads over the
/// existing Maccy history (`History`); copying and pasting reuse `Clipboard`.

import AppKit
import Defaults
import Observation

@Observable
@MainActor
final class SirenaHistoryPanelModel {
  static let shared = SirenaHistoryPanelModel()

  /// Live search text typed in the panel.
  var query = "" {
    didSet {
      guard query != oldValue else { return }
      selectFirst()
    }
  }

  /// Keyboard selection (id of a `HistoryItemDecorator`).
  var selectedID: UUID?

  /// Bumped every time the panel opens so the view re-focuses the search field.
  var focusToken = 0

  @ObservationIgnored private let search = Search()

  var pinnedItems: [HistoryItemDecorator] { filtered(History.shared.allPinnedItems) }
  var recentItems: [HistoryItemDecorator] { filtered(History.shared.allUnpinnedItems) }
  var visibleItems: [HistoryItemDecorator] { pinnedItems + recentItems }

  var selectedItem: HistoryItemDecorator? {
    guard let selectedID else { return nil }
    return visibleItems.first { $0.id == selectedID }
  }

  /// Called right before the panel is shown.
  func prepareForOpen() {
    query = ""
    selectFirst()
    focusToken += 1
  }

  func selectFirst() {
    selectedID = (recentItems.first ?? pinnedItems.first)?.id
  }

  func moveSelection(by delta: Int) {
    let items = visibleItems
    guard !items.isEmpty else { return }
    guard let current = items.firstIndex(where: { $0.id == selectedID }) else {
      selectedID = delta > 0 ? items.first?.id : items.last?.id
      return
    }
    let next = min(max(current + delta, 0), items.count - 1)
    selectedID = items[next].id
  }

  /// What selecting an item in Maccy did: close, copy and — when the preference
  /// is on — paste into the frontmost app.
  func activate(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    SirenaHistoryPanelController.shared.close()
    Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
    if Defaults[.pasteByDefault] {
      Clipboard.shared.paste()
    }
  }

  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    History.shared.togglePin(item)
    selectedID = item.id
  }

  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    if item.id == selectedID {
      let items = visibleItems
      if let index = items.firstIndex(of: item) {
        let next = index + 1 < items.count ? items[index + 1]
          : index > 0 ? items[index - 1] : nil
        selectedID = next?.id
      }
    }
    History.shared.delete(item)
  }

  func clear() {
    History.shared.clear()
  }

  private func filtered(_ items: [HistoryItemDecorator]) -> [HistoryItemDecorator] {
    guard !query.isEmpty else { return items }
    return search.search(string: query, within: items).map(\.object)
  }
}
