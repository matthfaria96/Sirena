import Defaults
import Foundation
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared)

  var history: History

  var menuIconText: String {
    var title = history.firstUnpinnedItem?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  init(history: History) {
    self.history = history
  }

  func quit() {
    NSApp.terminate(self)
  }
}
