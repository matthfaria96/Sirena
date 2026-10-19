/// ScreenBrushToolbar.swift
///
/// The floating Liquid Glass toolbar shown while drawing.

import SwiftUI

final class BrushToolbarPanel: NSPanel {
    init(document: BrushDocument) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: BrushToolbarView(document: document))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    /// Right under Sirena's ⚡ icon, where its menu opens; top right of other screens.
    func place(on screen: NSScreen) {
        guard let host = contentView else { return }
        let size = host.fittingSize
        let visible = screen.visibleFrame
        var origin = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6)
        if let icon = SirenaStatusItem.instance.button?.window?.frame, screen.frame.intersects(icon) {
            origin.x = min(max(icon.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = icon.minY - size.height - 4
        }
        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

/// Looks like Sirena's menu: inside it the mouse works as usual, outside it draws.
private struct BrushToolbarView: View {
    let document: BrushDocument
    @State private var settings = ScreenBrushSettings.shared
    private var controller: ScreenBrushController { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("Freehand Drawing"), systemImage: ModuleID.screenBrush.symbol)
                    .font(.headline)
                Spacer()
                Button { controller.stopDrawing() } label: {
                    Label(L("Leave"), systemImage: "xmark")
                        .font(.callout.weight(.semibold))
                }
                .compatGlassProminentButtonStyle()
                .tint(.red)
                .help(L("Leave (Esc)"))
            }

            section(L("Tool")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                    ForEach(BrushTool.available.filter { $0 != .eraser }) { toolButton($0) }
                    iconButton("arrow.uturn.backward", help: L("Undo (⌘Z)")) { document.undo() }.disabled(!document.canUndo)
                    iconButton("arrow.uturn.forward", help: L("Redo (⇧⌘Z)")) { document.redo() }.disabled(!document.canRedo)
                    // Erasing comes last: the eraser, then clear everything.
                    toolButton(.eraser)
                    iconButton("trash", help: L("Clear (⌘⌫)")) { document.clear() }.disabled(document.isEmpty)
                }
            }

            section(L("Color")) {
                HStack(spacing: 6) {
                    ForEach(BrushPalette.colors.indices, id: \.self) { index in
                        Button { settings.colorIndex = index } label: {
                            Circle()
                                .fill(Color(nsColor: BrushPalette.colors[index]))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: settings.colorIndex == index ? 2.5 : 0))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            section(L("Thickness")) {
                HStack(spacing: 10) {
                    Slider(value: $settings.width, in: 1...24)
                        .help(L("Width ([ and ])"))
                    Circle()
                        .fill(Color(nsColor: BrushPalette.colors[settings.colorIndex]))
                        .frame(width: max(4, settings.width), height: max(4, settings.width))
                        .frame(width: 26, height: 26)
                    Text("\(Int(settings.width))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                }
            }

            HStack(spacing: 8) {
                Button { controller.takeScreenshot(forcing: .save) } label: {
                    Label(L("Save to Pictures"), systemImage: "photo.on.rectangle")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .help(L("Whole screen with the drawing, saved in Pictures (⌘S)"))
                Button { controller.takeScreenshot(forcing: .copy) } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .help(L("Whole screen with the drawing, copied to the clipboard (⌘C)"))
            }
            .compatGlassButtonStyle()
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor).opacity(BoltMenuSettings.shared.clearGlass ? 0 : 0.9),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .compatGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(10)
    }

    private func toolButton(_ tool: BrushTool) -> some View {
        iconButton(tool.symbol, help: "\(tool.title) (\(tool.key.uppercased()))", selected: settings.tool == tool) {
            settings.tool = tool
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func iconButton(_ symbol: String, help: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
