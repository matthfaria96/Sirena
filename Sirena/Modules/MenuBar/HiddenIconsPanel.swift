/// HiddenIconsPanel.swift
///
/// The "menu" way of reaching hidden icons: clicking Sirena's arrow drops down a small
/// popover (like the ⚡ menu) with every hidden app. Clicking one briefly lets its icon back into
/// the menu bar and opens it, as if it had been clicked there.

import AppKit
import SwiftUI

@MainActor
final class HiddenIconsPanel: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var onClose: (() -> Void)?

    var isShown: Bool { popover?.isShown == true }
    /// The click on the arrow that closed it must not reopen it.
    var closedJustNow: Bool { Date().timeIntervalSince(lastClose) < 0.3 }
    private var lastClose = Date.distantPast

    /// Shows the menu below the arrow, in a popover like the ⚡ menu: fixed to the icon,
    /// closed by a click outside or Esc.
    func show(from button: NSStatusBarButton, apps: [NSRunningApplication],
              onPick: @escaping (NSRunningApplication) -> Void,
              onSettings: @escaping () -> Void, onClose: @escaping () -> Void) {
        let view = HiddenIconsView(apps: apps, onPick: { [weak self] app in
            self?.close()
            onPick(app)
        }, onSettings: { [weak self] in
            self?.close()
            onSettings()
        })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        self.popover = popover
        self.onClose = onClose
        SirenaActivation.activateForTool()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        onClose?()
    }
}

private struct HiddenIconsView: View {
    let apps: [NSRunningApplication]
    let onPick: (NSRunningApplication) -> Void
    let onSettings: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(64), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Hidden Icons"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onSettings) {
                    Label(L("Settings"), systemImage: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L("Hidden Icons Settings"))
                .accessibilityLabel(L("Hidden Icons Settings"))
            }
            .padding(.horizontal, 6)

            if apps.isEmpty {
                Text(L("No hidden icons right now."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 4 * 64 + 12, height: 56)
            } else {
                LazyVGrid(columns: Array(columns.prefix(min(apps.count, 4))), spacing: 4) {
                    ForEach(apps, id: \.processIdentifier) { app in
                        HiddenIconCell(app: app) { onPick(app) }
                    }
                }
            }
            if !apps.isEmpty {
                Text(L("Click an app to bring its icon back for a moment and use it."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 4 * 64 + 12, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
        .padding(12)
    }
}

private struct HiddenIconCell: View {
    let app: NSRunningApplication
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: app.icon ?? NSImage())
                    .resizable()
                    .frame(width: 30, height: 30)
                Text(app.localizedName ?? "")
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 60, height: 56)
            .background(isHovered ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(app.localizedName ?? "")
        .accessibilityLabel(L("Open \(app.localizedName ?? "")"))
    }
}
