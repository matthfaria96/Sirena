/// SettingsDrawings.swift
///
/// Small drawings for the settings pages, and a picker made of picture cards: each choice
/// shows what it does instead of only naming it. Built from the same mini windows and Dock
/// as the minimize cards (MinimizeModePicker.swift).

import SwiftUI

// MARK: - Picture cards

/// One choice of a `PictureCardPicker`.
struct PictureChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String?
    let drawing: AnyView

    var id: Value { value }

    init<Drawing: View>(_ value: Value, _ title: String, detail: String? = nil, @ViewBuilder drawing: () -> Drawing) {
        self.value = value
        self.title = title
        self.detail = detail
        self.drawing = AnyView(drawing())
    }
}

/// Choices side by side, each a card with a drawing, a title and an optional line.
struct PictureCardPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [PictureChoice<Value>]
    var drawingHeight: CGFloat = 70

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(choices) { choice in
                let selected = choice.value == selection
                Button { withAnimation(.snappy) { selection = choice.value } } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        choice.drawing
                            .frame(maxWidth: .infinity)
                            .frame(height: drawingHeight)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        HStack(spacing: 5) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            Text(choice.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                        }
                        if let detail = choice.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 3)
    }
}

/// A drawing next to a feature's switch, at the top of its topic.
struct FeatureDrawingRow<Drawing: View, Content: View>: View {
    @ViewBuilder let drawing: Drawing
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            drawing
                .frame(width: 110, height: 80)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 0) { content }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Screens

/// A tiny screen: menu bar on top, a body below.
private struct MiniScreen<Content: View>: View {
    var width: CGFloat = 84
    var height: CGFloat = 54
    var showsDock = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.primary.opacity(0.18)).frame(height: 4)
            ZStack { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsDock {
                Capsule().fill(.primary.opacity(0.15)).frame(width: width * 0.45, height: 4).padding(.bottom, 2)
            }
        }
        .frame(width: width, height: height)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}

/// Two windows snapped side by side.
struct ArrangeDrawing: View {
    var body: some View {
        MiniScreen {
            HStack(spacing: 2) {
                MiniWindow(width: 38, height: 36)
                MiniWindow(width: 38, height: 36)
            }
        }
    }
}

/// The snap popup: a window dragged to the top, the panel of layouts dropped above it, one
/// zone lit.
struct ZonesDrawing: View {
    var body: some View {
        MiniScreen {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { layout in
                        HStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(layout == 0 ? Color.accentColor : Color.secondary.opacity(0.45))
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Color.secondary.opacity(0.45))
                            if layout == 2 {
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(Color.secondary.opacity(0.45))
                            }
                        }
                        .frame(width: 14, height: 8)
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.6))
                MiniWindow(width: 44, height: 24)
            }
        }
    }
}

/// The green button: full screen (menu bar and Dock gone) or filling the screen.
struct GreenButtonDrawing: View {
    let fills: Bool

    var body: some View {
        if fills {
            MiniScreen {
                MiniWindow(width: 78, height: 38)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.85))
                MiniWindow(width: 80, height: 50)
            }
            .frame(width: 84, height: 54)
        }
    }
}

/// The ⌘ Tab switcher: a row of windows, one highlighted.
struct SwitcherDrawing: View {
    var body: some View {
        HStack(spacing: 5) {
            MiniWindow(width: 24, height: 17).opacity(0.7)
            MiniWindow(width: 24, height: 17)
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1.5))
            MiniWindow(width: 24, height: 17).opacity(0.7)
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

/// The switcher's three layouts.
struct SwitcherLayoutDrawing: View {
    enum Kind { case previews, icons, list }
    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .previews:
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        MiniWindow(width: 22, height: 16)
                            .padding(1.5)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: index == 1 ? 1.2 : 0))
                    }
                }
            case .icons:
                HStack(spacing: 6) {
                    ForEach([Color.blue, .green, .orange], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: color == .green ? 1.2 : 0))
                    }
                }
            case .list:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([Color.blue, .green, .orange], id: \.self) { color in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.75)).frame(width: 8, height: 8)
                            Capsule().fill(.primary.opacity(color == .green ? 0.5 : 0.25)).frame(width: 40, height: 4)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
