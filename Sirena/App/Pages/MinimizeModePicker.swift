/// MinimizeModePicker.swift
///
/// The three minimize modes on the Dock tab, as cards with a small drawing each:
/// "Como o macOS" (nothing changes: each window shrinks into the Dock, one at a time),
/// "Tudo junto pelo Dock" (minimizing is macOS's, one window; a click on the app in front in
/// the Dock hides every window at once and the next one brings all back, minimized ones too)
/// and "Ocultar tudo" (minimizing a window hides the whole app as well).

import DockKit
import SwiftUI

struct MinimizeModePicker: View {
    @Binding var hidesApp: Bool
    @Binding var dockTogether: Bool

    var body: some View {
        HStack(spacing: 10) {
            card(selected: !hidesApp && !dockTogether,
                 title: L("Like macOS"),
                 detail: L("Nothing changes: each window shrinks into the Dock and comes back one at a time.")) {
                MacOSModeDrawing()
            } select: {
                hidesApp = false
                dockTogether = false
            }
            card(selected: !hidesApp && dockTogether,
                 title: L("All together from the Dock"),
                 detail: L("The yellow button minimizes only that window. Clicking the app in the Dock hides all of its windows at once, and brings all of them back.")) {
                RestoreAllModeDrawing()
            } select: {
                hidesApp = false
                dockTogether = true
            }
            card(selected: hidesApp,
                 title: L("Hide everything"),
                 detail: L("Minimizing, or clicking the app in the Dock, hides all of its windows. They all come back together.")) {
                HideModeDrawing()
            } select: { hidesApp = true }
        }
        .padding(.vertical, 4)
    }

    private func card<Drawing: View>(selected: Bool, title: String, detail: String,
                                     @ViewBuilder drawing: () -> Drawing,
                                     select: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { select() } }) {
            VStack(alignment: .leading, spacing: 8) {
                drawing()
                    .frame(maxWidth: .infinity)
                    .frame(height: 86)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(title).font(.headline)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Drawings

/// A window: title bar with three dots, a body.
struct MiniWindow: View {
    var width: CGFloat
    var height: CGFloat
    var dashed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack(alignment: .topLeading) {
            if dashed {
                shape.strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                HStack(spacing: 2) {
                    Circle().fill(.red.opacity(0.8))
                    Circle().fill(.yellow.opacity(0.9))
                    Circle().fill(.green.opacity(0.8))
                }
                .frame(height: max(height * 0.1, 3))
                .padding(3)
            }
        }
        .frame(width: width, height: height)
    }
}

/// The Dock: a pill with three icons, the middle one the app.
struct MiniDock: View {
    var highlighted = false

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5).fill(.blue.opacity(0.6)).frame(width: 11, height: 11)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.accentColor)
                .frame(width: 11, height: 11)
                .overlay(alignment: .bottom) {
                    Circle().fill(.primary.opacity(0.6)).frame(width: 2.5, height: 2.5).offset(y: 4)
                }
                .scaleEffect(highlighted ? 1.15 : 1)
            RoundedRectangle(cornerRadius: 2.5).fill(.orange.opacity(0.6)).frame(width: 11, height: 11)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.08), in: Capsule())
    }
}

/// Windows shrinking into the Dock one after another.
private struct MacOSModeDrawing: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                MiniWindow(width: 44, height: 30)
                MiniWindow(width: 30, height: 20).opacity(0.75)
                MiniWindow(width: 18, height: 12).opacity(0.5)
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 44)
            MiniDock()
        }
    }
}

/// The windows going down into the app's Dock icon together and coming back up.
private struct RestoreAllModeDrawing: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                MiniWindow(width: 30, height: 22).opacity(0.55)
                MiniWindow(width: 30, height: 22).opacity(0.55)
                MiniWindow(width: 30, height: 22).opacity(0.55)
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 44)
            MiniDock(highlighted: true)
        }
    }
}

/// Every window gone at once, the app still in the Dock.
private struct HideModeDrawing: View {
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                HStack(spacing: 6) {
                    MiniWindow(width: 36, height: 26, dashed: true)
                    MiniWindow(width: 36, height: 26, dashed: true)
                    MiniWindow(width: 36, height: 26, dashed: true)
                }
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(5)
                    .background(.background, in: Circle())
            }
            .frame(height: 44)
            MiniDock(highlighted: true)
        }
    }
}

/// A preview card over the app's Dock icon, with two of its windows.
struct DockPreviewDrawing: View {
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                MiniWindow(width: 34, height: 23)
                MiniWindow(width: 34, height: 23)
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
            MiniDock(highlighted: true)
        }
    }
}
