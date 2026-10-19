/// SirenaHistoryPanelView.swift
///
/// The SwiftUI content of Sirena's floating clipboard-history panel:
/// search on top, "Fixados" and "Recentes" sections, footer with count and
/// "Limpar…". All user-visible text in pt-BR.

import Defaults
import SwiftUI

struct SirenaHistoryPanelView: View {
  @Bindable private var model = SirenaHistoryPanelModel.shared
  @FocusState private var searchFocused: Bool
  @State private var hoveredID: UUID?
  @State private var confirmClear = false

  private static let cornerRadius: CGFloat = 16

  var body: some View {
    VStack(spacing: 0) {
      searchBar
      Divider()
      list
      Divider()
      footer
    }
    .frame(
      width: SirenaHistoryPanelController.panelSize.width,
      height: SirenaHistoryPanelController.panelSize.height
    )
    .background(panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
    )
  }

  @ViewBuilder
  private var panelBackground: some View {
    if #available(macOS 26.0, *) {
      Color.clear
        .compatGlass(in: .rect(cornerRadius: Self.cornerRadius))
    } else {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(.regularMaterial)
    }
  }

  // MARK: - Search

  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Buscar no histórico", text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .focused($searchFocused)
      if !model.query.isEmpty {
        Button {
          model.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Limpar busca")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .onAppear { searchFocused = true }
    .onChange(of: model.focusToken) {
      model.selectFirst()
      searchFocused = true
    }
  }

  // MARK: - List

  @ViewBuilder
  private var list: some View {
    let pinned = model.pinnedItems
    let recent = model.recentItems

    if pinned.isEmpty && recent.isEmpty {
      emptyState
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 1) {
            if !pinned.isEmpty {
              sectionHeader("Fixados")
              ForEach(pinned) { item in
                row(item)
              }
            }
            if !recent.isEmpty {
              sectionHeader("Recentes")
              ForEach(recent) { item in
                row(item)
              }
            }
          }
          .padding(6)
        }
        .onChange(of: model.selectedID) { _, newValue in
          if let newValue {
            proxy.scrollTo(newValue, anchor: nil)
          }
        }
      }
      .animation(.snappy(duration: 0.18), value: model.pinnedItems.map(\.id))
    }
  }

  private var emptyState: some View {
    Group {
      if model.query.isEmpty {
        ContentUnavailableView(
          "Nada copiado ainda",
          systemImage: "clipboard",
          description: Text("O que você copiar aparece aqui.")
        )
      } else {
        ContentUnavailableView(
          "Nenhum resultado",
          systemImage: "magnifyingglass",
          description: Text("Nada no histórico combina com “\(model.query)”.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .padding(.bottom, 2)
  }

  private func row(_ item: HistoryItemDecorator) -> some View {
    SirenaHistoryRow(
      item: item,
      isSelected: model.selectedID == item.id,
      isHovered: hoveredID == item.id,
      onActivate: { model.activate(item) },
      onPin: { model.togglePin(item) },
      onDelete: { model.delete(item) }
    )
    .id(item.id)
    .onHover { hovering in
      if hovering {
        hoveredID = item.id
      } else if hoveredID == item.id {
        hoveredID = nil
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Text(countLabel)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Spacer()
      Button("Limpar…") {
        confirmClear = true
      }
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      .disabled(model.visibleItems.isEmpty && model.query.isEmpty
        && History.shared.allPinnedItems.isEmpty && History.shared.allUnpinnedItems.isEmpty)
      .confirmationDialog(
        "Limpar o histórico?",
        isPresented: $confirmClear
      ) {
        Button("Limpar", role: .destructive) {
          model.clear()
        }
        Button("Cancelar", role: .cancel) {}
      } message: {
        Text("Os itens fixados são mantidos.")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }

  private var countLabel: String {
    let count = History.shared.allPinnedItems.count + History.shared.allUnpinnedItems.count
    return count == 1 ? "1 item" : "\(count) itens"
  }
}

// MARK: - Row

private struct SirenaHistoryRow: View {
  let item: HistoryItemDecorator
  let isSelected: Bool
  let isHovered: Bool
  let onActivate: () -> Void
  let onPin: () -> Void
  let onDelete: () -> Void

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "pt_BR")
    formatter.unitsStyle = .short
    return formatter
  }()

  var body: some View {
    HStack(spacing: 10) {
      leadingIcon

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 13))
          .lineLimit(1)
          .truncationMode(.tail)
        Text(subtitle)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if isHovered || isSelected {
        hoverButtons
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minHeight: 36)
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(
          isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.22))
            : isHovered ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear)
        )
    )
    .onTapGesture(perform: onActivate)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(item.accessibilityLabel)
    .accessibilityAddTraits(.isButton)
  }

  @ViewBuilder
  private var leadingIcon: some View {
    if item.hasImage {
      SirenaThumbnailView(item: item)
    } else {
      Image(nsImage: item.applicationImage.nsImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 22, height: 22)
    }
  }

  private var title: String {
    if item.hasImage {
      return item.title.isEmpty ? "Imagem" : item.title
    }
    let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "(vazio)" : trimmed
  }

  private var subtitle: String {
    let time = Self.relativeFormatter.localizedString(
      for: item.item.lastCopiedAt, relativeTo: Date()
    )
    if let app = item.application, !app.isEmpty {
      return "\(app) · \(time)"
    }
    return time
  }

  private var hoverButtons: some View {
    HStack(spacing: 2) {
      Button(action: onPin) {
        Image(systemName: item.isPinned ? "pin.slash" : "pin")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.plain)
      .help(item.isPinned ? "Desafixar" : "Fixar")

      Button(action: onDelete) {
        Image(systemName: "trash")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.plain)
      .help("Apagar")
    }
    .transition(.opacity)
  }
}

/// Lazily generated image thumbnail for image items.
private struct SirenaThumbnailView: View {
  let item: HistoryItemDecorator

  var body: some View {
    Group {
      if let thumbnail = item.thumbnailImage {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 26, height: 22)
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .onAppear {
      item.ensureThumbnailImage()
    }
  }
}
