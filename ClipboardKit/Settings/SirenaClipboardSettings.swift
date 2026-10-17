import Defaults
import KeyboardShortcuts
import SwiftUI

// Sirena: every clipboard setting worth changing on one grouped page, in the same style
// as Sirena's other pages (Maccy spread them over five tabs, one of them with tabs of
// its own).

private func SL(_ key: String.LocalizationValue) -> String {
  String(localized: key, table: "Sirena", bundle: .main)
}

public struct SirenaClipboardSettings: View {
  @Default(.size) private var size
  @Default(.sortBy) private var sortBy
  @Default(.popupPosition) private var popupAt
  @Default(.pinTo) private var pinTo
  @Default(.ignoreEvents) private var isPaused
  @State private var storage = StorageSettingsPane.ViewModel()

  public init() {}

  public var body: some View {
    Form {
      Section {
        shortcutRow(SL("Open the history panel"), .popup)
        shortcutRow(SL("Pin or unpin an item"), .pin)
        shortcutRow(SL("Delete an item"), .delete)
        shortcutRow(SL("Preview an item"), .togglePreview)
      } header: {
        Text(SL("Keyboard shortcuts"))
      }

      Section {
        Defaults.Toggle(key: .pasteByDefault) {
          Text(SL("Paste right away"))
          Text(SL("Choosing an item pastes it into the front app, not just copies it."))
        }
        Defaults.Toggle(key: .removeFormattingByDefault) {
          Text(SL("Paste without formatting"))
          Text(SL("Text comes in plain, taking the style of where you paste it."))
        }
      } header: {
        Text(SL("When choosing an item"))
      }

      Section {
        LabeledContent(SL("Keep")) {
          HStack(spacing: 14) {
            Toggle(SL("Text"), isOn: $storage.saveText)
            Toggle(SL("Images"), isOn: $storage.saveImages)
            Toggle(SL("Files"), isOn: $storage.saveFiles)
          }
          .toggleStyle(.checkbox)
        }
        Picker(SL("Remember up to"), selection: $size) {
          ForEach([50, 100, 200, 500, 999], id: \.self) { count in
            Text(SL("\(count) items")).tag(count)
          }
          if ![50, 100, 200, 500, 999].contains(size) {
            Text(SL("\(size) items")).tag(size)
          }
        }
        Picker(SL("Order"), selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description).tag(mode)
          }
        }
        Toggle(isOn: $isPaused) {
          Text(SL("Pause history"))
          Text(SL("Stops keeping new copies until you resume. Useful before copying something private."))
        }
        Defaults.Toggle(key: .clearOnQuit) {
          Text(SL("Clear the history when Sirena quits"))
          Text(SL("Pinned items are kept."))
        }
      } header: {
        Text(SL("History"))
      }

      Section {
        Picker(SL("Show the panel"), selection: $popupAt) {
          ForEach(PopupPosition.allCases) { position in
            Text(position.description).tag(position)
          }
        }
        Picker(SL("Pinned items"), selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description).tag(position)
          }
        }
        Defaults.Toggle(key: .showSearch) { Text(SL("Show the search field")) }
        Defaults.Toggle(key: .showApplicationIcons) { Text(SL("Show the icon of the app each item came from")) }
        Defaults.Toggle(key: .openPreviewAutomatically) { Text(SL("Preview the selected item automatically")) }
      } header: {
        Text(SL("History panel"))
      }

      Section {
        IgnoreApplicationsSettingsView()
          .frame(height: 180)
      } header: {
        Text(SL("Ignored apps"))
      } footer: {
        Text(SL("Copies made in these apps are never kept. Password managers already mark their copies as private."))
      }
    }
    .formStyle(.grouped)
  }

  private func shortcutRow(_ title: String, _ name: KeyboardShortcuts.Name) -> some View {
    HStack {
      Text(title)
      Spacer(minLength: 12)
      KeyboardShortcuts.Recorder(for: name)
        .fixedSize()
    }
  }
}
