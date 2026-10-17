import SwiftUI

// Sirena: Maccy's settings panes keep their controls and preferences, but render as a
// native grouped Form (label on the left, control on the right) like every other page,
// instead of the fixed-width, right-aligned "Settings" container of a standalone app.

struct SirenaForm<Content: View>: View {
  private let content: Content

  init(contentWidth: CGFloat = 0, @ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    Form { content }
      .formStyle(.grouped)
  }
}

struct SirenaRow<Label: View, Content: View>: View {
  private let label: Label?
  private let content: Content

  init(bottomDivider: Bool = false, @ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
    self.label = label()
    self.content = content()
  }

  var body: some View {
    if let label {
      LabeledContent {
        VStack(alignment: .trailing, spacing: 6) { content }
      } label: {
        label
      }
    } else {
      VStack(alignment: .leading, spacing: 6) { content }
    }
  }
}

extension SirenaRow where Label == EmptyView {
  init(title: String, bottomDivider: Bool = false, @ViewBuilder content: () -> Content) {
    self.label = nil
    self.content = content()
  }
}
