/// CapturePanels.swift
///
/// What Text Capture shows after a capture: a short toast with the copied text, and
/// a result window to read, edit, speak or translate it.

import AppKit
import SwiftUI
import Translation

// MARK: - Toast

@MainActor
final class CaptureToast {
    static let shared = CaptureToast()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(title: String, detail: String?, symbol: String, near rect: CGRect? = nil) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: ToastView(title: title, detail: detail, symbol: symbol))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = rect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(PinGeometry.cocoaRect(fromCG: rect)) } }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // VoiceOver users get the same feedback.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: [title, detail].compactMap { $0 }.joined(separator: ". "),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])

        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel?.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { panel?.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct ToastView: View {
    let title: String
    let detail: String?
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .compatGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(8)
    }
}

// MARK: - Result window

@MainActor
final class CaptureResultWindow {
    static let shared = CaptureResultWindow()

    private var window: NSWindow?
    private let model = CaptureResultModel()

    func show(text: String, translate: Bool) {
        model.text = text
        model.presentTranslation = false
        let window = self.window ?? makeWindow()
        self.window = window
        SirenaActivation.activateForTool()
        window.makeKeyAndOrderFront(nil)
        if translate {
            // Presented after the window is up so the popover has an anchor.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [model] in model.presentTranslation = true }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow],
                             backing: .buffered, defer: false)
        window.title = L("Captured Text")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: CaptureResultView(model: model))
        window.center()
        window.setFrameAutosaveName("SirenaCaptureResult")
        return window
    }
}

@MainActor
@Observable
final class CaptureResultModel {
    var text = ""
    var presentTranslation = false
}

private struct CaptureResultView: View {
    @Bindable var model: CaptureResultModel
    @State private var controller = TextCaptureController.shared

    var body: some View {
        VStack(spacing: 10) {
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    controller.speak(model.text)
                } label: {
                    Label(L("Speak"), systemImage: "speaker.wave.2")
                }
                if controller.isSpeaking {
                    Button {
                        controller.stopSpeaking()
                    } label: {
                        Label(L("Stop Speaking"), systemImage: "stop.fill")
                    }
                }
                Spacer()
                Button {
                    model.presentTranslation = true
                } label: {
                    Label(L("Translate"), systemImage: "translate")
                }
                .translationPresentation(isPresented: $model.presentTranslation, text: model.text) { translated in
                    model.text = translated
                }
                Button {
                    controller.copyToClipboard(model.text)
                } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(minWidth: 380, minHeight: 240)
    }
}
