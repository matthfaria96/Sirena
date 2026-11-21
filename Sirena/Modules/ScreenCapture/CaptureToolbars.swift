/// CaptureToolbars.swift
///
/// The two bars around a capture's selection, as in Lightshot: the marks on its side
/// (tools, color, thickness, undo) and what to do with it underneath (record, copy, save,
/// close). Neutral glass, icons only; the name of the button under the pointer shows in a
/// small label next to the actions.

import SwiftUI

struct CaptureToolsBar: View {
    let session: CaptureSession
    @State private var controller = ScreenCaptureController.shared

    private var color: Color { Color(nsColor: BrushPalette.color(controller.colorIndex)) }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                ForEach(BrushTool.capture) { tool in
                    CaptureBarButton(hint: "\(tool.title)  \(tool.key.uppercased())", selected: session.tool == tool,
                                     session: session) {
                        session.selectTool(tool)
                    } label: {
                        Image(systemName: tool.symbol)
                    }
                }
                CaptureBarDivider(vertical: false)
                CaptureBarButton(hint: L("Color  C"), selected: session.showsPalette, session: session) {
                    session.showsPalette.toggle()
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
                CaptureBarButton(hint: L("Thickness  [ ]"), session: session) {
                    session.cycleWidth()
                } label: {
                    let index = CaptureSession.widths.firstIndex { $0 >= controller.width } ?? 1
                    Circle()
                        .fill(.primary)
                        .frame(width: [4, 7, 11][min(index, 2)], height: [4, 7, 11][min(index, 2)])
                }
                CaptureBarDivider(vertical: false)
                CaptureBarButton(hint: L("Undo  ⌘Z"), enabled: session.document.canUndo, session: session) {
                    session.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .opacity(session.showsPalette ? 0 : 1)

            if session.showsPalette {
                VStack(spacing: 4) {
                    ForEach(BrushPalette.colors.indices, id: \.self) { index in
                        Button { session.chooseColor(index) } label: {
                            Circle()
                                .fill(Color(nsColor: BrushPalette.colors[index]))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(.primary.opacity(controller.colorIndex == index ? 0.9 : 0), lineWidth: 2))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(4)
        .captureBar()
    }
}

struct CaptureActionsBar: View {
    let session: CaptureSession

    var body: some View {
        HStack(spacing: 2) {
            CaptureBarButton(hint: session.pickedWindow != nil ? L("Record this window  ⌘R") : L("Record this area  ⌘R"),
                             session: session) {
                session.finish(.record)
            } label: {
                Image(systemName: "record.circle").foregroundStyle(.red)
            }
            CaptureBarDivider(vertical: true)
            CaptureBarButton(hint: L("Copy  ⌘C"), session: session) {
                session.finish(.copy)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            CaptureBarButton(hint: L("Save  ⌘S"), session: session) {
                session.finish(.save)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            CaptureBarDivider(vertical: true)
            CaptureBarButton(hint: L("Close  Esc"), session: session) {
                session.finish(.cancel)
            } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(4)
        .captureBar()
    }
}

/// One square button of a bar: a soft fill under the pointer, a stronger one when selected.
private struct CaptureBarButton<Label: View>: View {
    let hint: String
    var selected = false
    var enabled = true
    let session: CaptureSession
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.18 : isHovering && enabled ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering in
            isHovering = hovering
            session.setHint(hovering ? hint : nil, clearing: hint)
        }
        .accessibilityLabel(hint)
    }
}

private struct CaptureBarDivider: View {
    let vertical: Bool

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: vertical ? 1 : 22, height: vertical ? 20 : 1)
            .padding(vertical ? .horizontal : .vertical, 3)
    }
}

private extension View {
    /// Neutral glass with a body under it, so the bar reads over any screenshot.
    func captureBar() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: shape)
            .compatGlass(in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
