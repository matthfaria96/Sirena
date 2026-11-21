/// CaptureSavedCard.swift
///
/// After a screenshot or a recording is saved: a small card in the corner of the display it
/// came from, like macOS's own screenshot thumbnail. A preview, the folder the file went to,
/// and Show in Finder / Open. It stays 8 s, longer while the pointer is over it; the preview
/// can be dragged into another app.

import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class CaptureSavedCard {
    static let shared = CaptureSavedCard()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = CaptureSavedCardModel()

    /// - `image`: the screenshot itself, for the preview (a recording gets Quick Look's).
    /// - `displayID`: where the capture was taken; the card shows on that display.
    func show(_ url: URL, title: String, folder: String, image: CGImage? = nil, on displayID: CGDirectDisplayID?) {
        model.url = url
        model.title = title
        model.folder = folder
        model.preview = image.map { NSImage(cgImage: $0, size: .zero) } ?? NSWorkspace.shared.icon(forFile: url.path)
        if image == nil { loadPreview(of: url) }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? CGSize(width: 380, height: 100)
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(CGRect(x: visible.maxX - size.width - 8, y: visible.minY + 8, width: size.width, height: size.height),
                       display: true)
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(title). \(folder)",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        scheduleHide(after: 8)
    }

    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                // Shown again meanwhile: keep it.
                guard panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// While the pointer is over the card it stays; it goes a few seconds after it leaves.
    fileprivate func hovering(_ inside: Bool) {
        if inside {
            hideWork?.cancel()
            hideWork = nil
        } else {
            scheduleHide(after: 3)
        }
    }

    fileprivate func showInFinder() {
        guard let url = model.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismiss()
    }

    fileprivate func open() {
        guard let url = model.url else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }

    private func loadPreview(of url: URL) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 192, height: 120), scale: scale,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.model.url == url else { return }
                    self.model.preview = image
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Never part of a recording or a screen share.
        panel.sharingType = .none
        let host = FirstClickHostingView(rootView: CaptureSavedCardView(model: model, card: self))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }
}

@MainActor
@Observable
final class CaptureSavedCardModel {
    var url: URL?
    var title = ""
    var folder = ""
    var preview: NSImage?
}

/// Its buttons answer the first click, while the panel isn't key (Sirena stays in the background).
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CaptureSavedCardView: View {
    let model: CaptureSavedCardModel
    let card: CaptureSavedCard
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.headline)
                Label(model.folder, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let name = model.url?.lastPathComponent {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Button(L("Show in Finder")) { card.showInFinder() }
                    Button(L("Open")) { card.open() }
                }
                .controlSize(.small)
                .compatGlassButtonStyle()
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 360)
        .compatGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { card.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel(L("Close"))
        }
        .padding(8)
        .onHover { inside in
            isHovering = inside
            card.hovering(inside)
        }
    }

    /// The screenshot (or the recording's first frame); a click shows it in Finder, a drag
    /// takes the file along.
    private var preview: some View {
        Group {
            if let image = model.preview {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: 96, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { card.showInFinder() }
        .onDrag { model.url.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
        .help(L("Show in Finder"))
    }
}
