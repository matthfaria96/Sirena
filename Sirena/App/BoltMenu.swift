/// BoltMenu.swift
///
/// What Sirena's menu bar icon shows, chosen on Home. Two kinds of things:
/// - Atalhos: tools opened with one click (clipboard history, pin a window, capture
///   text, a peek through the camera).
/// - Controladores: things adjusted right there (Cafeína, and the sound mixer with the
///   Mac's volume, each app's and the microphone).

import AppKit
import AVFoundation
import ClipboardKit
import SwiftUI

enum BoltMenuItem: String, CaseIterable, Identifiable {
    // Atalhos
    case clipboard, pinWindow, textCapture, mirror
    // Controladores
    case keepAwake, sound

    var id: String { rawValue }

    enum Kind { case shortcut, control }

    var kind: Kind {
        switch self {
        case .clipboard, .pinWindow, .textCapture, .mirror: return .shortcut
        default: return .control
        }
    }

    static var shortcuts: [BoltMenuItem] { allCases.filter { $0.kind == .shortcut } }
    static var controls: [BoltMenuItem] { allCases.filter { $0.kind == .control } }

    var title: String {
        switch self {
        case .clipboard: return L("History")
        case .pinWindow: return ModuleID.pinWindow.title
        case .textCapture: return ModuleID.textCapture.title
        case .keepAwake: return L("Keep Display On")
        case .mirror: return L("Peek Camera")
        case .sound: return L("Sound Mixer")
        }
    }

    /// One short, direct line about what it is, for its card on Home.
    var tagline: String {
        switch self {
        case .clipboard: return L("Everything you copied, ready to paste again.")
        case .pinWindow: return L("Keeps a window on top of all the others.")
        case .textCapture: return L("Copies the text from any part of the screen.")
        case .mirror: return L("A quick look at yourself before a call.")
        case .keepAwake: return L("Keeps the display on for as long as you want.")
        case .sound: return L("Each app's volume and where the sound goes.")
        }
    }

    /// One word, for the buttons at the top of the menu.
    var shortTitle: String {
        switch self {
        case .clipboard: return L("History")
        case .pinWindow: return L("Pin")
        case .textCapture: return L("Capture")
        case .mirror: return L("Peek")
        default: return title
        }
    }

    /// What it does, shown on Home.
    var detail: String {
        switch self {
        case .clipboard: return L("Opens the list of everything you copied, to paste it again.")
        case .pinWindow: return L("Choose a window to keep floating above all the others.")
        case .textCapture: return L("Select an area of the screen and copy the text in it, even from images and videos.")
        case .keepAwake: return L("Keeps the Mac and the display from sleeping, for the time you choose or indefinitely. The time is remembered.")
        case .mirror: return L("Opens the camera below the menu bar for a quick look at yourself, with a countdown. It closes by itself after 10 seconds (changeable on its page).")
        case .sound: return L("Volume of the Mac and of each app, the sound output and the microphone, all in one place.")
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return ModuleID.clipboard.symbol
        case .pinWindow: return ModuleID.pinWindow.symbol
        case .textCapture: return ModuleID.textCapture.symbol
        case .keepAwake: return "cup.and.saucer.fill"
        case .mirror: return "camera.fill"
        case .sound: return "slider.vertical.3"
        }
    }

    var tint: Color {
        switch self {
        case .clipboard: return ModuleID.clipboard.tint
        case .pinWindow: return ModuleID.pinWindow.tint
        case .textCapture: return ModuleID.textCapture.tint
        case .keepAwake: return ModuleID.keepAwake.tint
        case .mirror: return ModuleID.mirror.tint
        case .sound: return .purple
        }
    }

    /// The module that has to run for this item to make sense.
    var module: ModuleID? {
        switch self {
        case .clipboard: return .clipboard
        case .pinWindow: return .pinWindow
        case .textCapture: return .textCapture
        case .keepAwake: return .keepAwake
        case .mirror: return .mirror
        case .sound: return .mixer
        default: return nil
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .clipboard: ClipboardController.shared.togglePanel()
        case .pinWindow: PinWindowController.shared.selectWindowToPin()
        case .textCapture: TextCaptureController.shared.capture(.text())
        case .mirror: MirrorController.shared.peek()
        default: break
        }
    }
}

/// Which items the menu shows (kept in UserDefaults).
@MainActor
@Observable
final class BoltMenuSettings {
    static let shared = BoltMenuSettings()
    private static let key = "boltMenu.items.v2"

    var enabled: Set<BoltMenuItem> {
        didSet { UserDefaults.standard.set(enabled.map(\.rawValue).sorted(), forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key)
        enabled = saved.map { Set($0.compactMap(BoltMenuItem.init)) }
            ?? [.clipboard, .pinWindow, .textCapture, .mirror, .keepAwake, .sound]
    }

    func isOn(_ item: BoltMenuItem) -> Bool { enabled.contains(item) }

    func set(_ item: BoltMenuItem, _ on: Bool) {
        if on { enabled.insert(item) } else { enabled.remove(item) }
    }

    /// Items to show right now: chosen, and with their feature running.
    var visibleItems: [BoltMenuItem] {
        BoltMenuItem.allCases.filter { item in
            enabled.contains(item) && (item.module.map { ModuleManager.shared.isRunning($0) } ?? true)
        }
    }
}

// MARK: - The popover

struct BoltMenuView: View {
    @State private var settings = BoltMenuSettings.shared
    let close: () -> Void
    /// Inline panels under the shortcut row (camera peek and the last copies).
    @State private var showsPeek = false
    @State private var showsHistory = false

    var body: some View {
        let visible = settings.visibleItems
        let controls = visible.filter { $0.kind == .control && $0 != .sound }
        let shortcuts = visible.filter { $0.kind == .shortcut }
        VStack(spacing: 12) {
            if !shortcuts.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(shortcuts) { item in
                        ShortcutButton(item: item, isActive: isInlineOpen(item)) { tap(item) }
                    }
                }
                if showsHistory {
                    InlineHistoryPanel(closeMenu: close)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if showsPeek {
                    InlinePeekPanel { withAnimation(.snappy(duration: 0.25)) { showsPeek = false } }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Divider()
            }
            ForEach(controls) { item in
                ControlRow(item: item, close: close)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if visible.contains(.sound) {
                // Vorssaint's volume mixer; scrolls when many apps are playing.
                ScrollView(.vertical) {
                    SirenaMixerView(width: 296, compact: true)
                        .padding(10)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if visible.isEmpty {
                ContentUnavailableView(L("Nothing here yet"), systemImage: "circle.hexagongrid",
                                       description: Text(L("Choose what this menu shows on Sirena's Home.")))
                    .frame(height: 140)
            }
            HStack(spacing: 10) {
                FooterButton(title: L("Settings"), symbol: "gearshape", tint: nil) {
                    close()
                    ModuleManager.shared.openPage(.home)
                }
                .help(L("Opens Sirena on Home (⌃⌥S)"))
                FooterButton(title: L("Quit"), symbol: "power", tint: .red) {
                    NSApp.terminate(nil)
                }
                .help(L("Quits Sirena"))
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 344)
        .animation(.snappy(duration: 0.28), value: showsPeek)
        .animation(.snappy(duration: 0.28), value: showsHistory)
    }

    private func isInlineOpen(_ item: BoltMenuItem) -> Bool {
        item == .mirror ? showsPeek : item == .clipboard ? showsHistory : false
    }

    /// Histórico and Espiar unroll inside the menu; the others run and close it.
    private func tap(_ item: BoltMenuItem) {
        switch item {
        case .mirror:
            withAnimation(.snappy(duration: 0.25)) {
                showsPeek.toggle()
                if showsPeek { showsHistory = false }
            }
        case .clipboard:
            withAnimation(.snappy(duration: 0.25)) {
                showsHistory.toggle()
                if showsHistory { showsPeek = false }
            }
        default:
            close()
            item.perform()
        }
    }
}

/// A shortcut at the top: a quiet rounded square with the icon, the name below.
private struct ShortcutButton: View {
    let item: BoltMenuItem
    var isActive = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if item == .mirror {
                        Image("CameraShutter").resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: item.symbol)
                            .symbolVariant(.fill)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(isActive ? AnyShapeStyle(item.tint.gradient)
                            : isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(item.shortTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.detail)
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let tint: Color?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((tint ?? .primary).opacity(isHovering ? 0.22 : (tint == nil ? 0.07 : 0.14))))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((tint ?? .primary).opacity(0.25), lineWidth: 0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Controllers

private struct ControlRow: View {
    let item: BoltMenuItem
    let close: () -> Void
    @ObservedObject private var keepAwake = KeepAwakeModule.shared.viewModel
    @AppStorage(PreferenceKeys.defaultDuration) private var defaultDuration = 0

    var body: some View {
        switch item {
        case .keepAwake:
            HStack(alignment: .center, spacing: 10) {
                GlassIcon(symbol: item.symbol, tint: item.tint, size: 32, isOn: keepAwake.isActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(keepAwake.isActive ? (keepAwake.formattedTimeRemaining() ?? L("On")) : L("Off"))
                        .font(.caption)
                        .foregroundStyle(keepAwake.isActive ? .green : .secondary)
                }
                Spacer(minLength: 6)
                // The switch, with how long it lasts right below it.
                VStack(alignment: .trailing, spacing: 4) {
                    Toggle(item.title, isOn: Binding(get: { keepAwake.isActive },
                                                     set: { $0 ? keepAwake.activate() : keepAwake.deactivate() }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    Menu {
                        Picker(L("Duration"), selection: $defaultDuration) {
                            ForEach(Self.durations, id: \.minutes) { Text($0.title).tag($0.minutes) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(Self.durations.first { $0.minutes == defaultDuration }?.title ?? L("Indefinitely"))
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(L("How long the display stays on. Remembered for next time."))
                    .onChange(of: defaultDuration) { _, _ in
                        // Already on: restart with the new time.
                        if keepAwake.isActive { keepAwake.activate() }
                    }
                }
            }
            .help(item.detail)
        default:
            EmptyView()
        }
    }

    static var durations: [(minutes: Int, title: String)] { KeepAwakeModule.durations }

}

// MARK: - Inline panels (inside the menu)

/// Espiar inside the menu: the camera unrolls below the shortcuts, with the countdown.
private struct InlinePeekPanel: View {
    let close: () -> Void
    @State private var remaining = max(MirrorSettings.shared.peekSeconds, 3)
    @State private var failed = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            InlineCameraView(failed: $failed)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if failed {
                Label(L("Camera unavailable"), systemImage: "video.slash.fill")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("\(remaining)s").monospacedDigit().contentTransition(.numericText(countsDown: true))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
            }
            .padding(8)
        }
        .onReceive(clock) { _ in
            withAnimation(.snappy) { remaining -= 1 }
            if remaining <= 0 { close() }
        }
    }
}

/// The live camera, started on appear and stopped when the panel goes away
/// (unless the mirror window is also using it).
private struct InlineCameraView: NSViewRepresentable {
    @Binding var failed: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: MirrorCamera.shared.session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)
        Task { @MainActor in
            do {
                try await MirrorCamera.shared.start()
                if let connection = preview.connection, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = MirrorSettings.shared.mirrored
                }
            } catch {
                failed = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        Task { @MainActor in
            if !MirrorState.shared.isVisible { MirrorCamera.shared.stop() }
        }
    }
}

/// Histórico inside the menu: the last copies, one click puts one back on the clipboard.
private struct InlineHistoryPanel: View {
    let closeMenu: () -> Void
    @State private var controller = ClipboardController.shared
    @State private var copied: ObjectIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let entries = Array(controller.entries.prefix(6))
            if entries.isEmpty {
                Label(L("Nothing copied yet"), systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry, isCopied: copied == entry.id) {
                        controller.copy(entry.id)
                        withAnimation(.snappy) { copied = entry.id }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            if copied == entry.id { withAnimation(.easeOut) { copied = nil } }
                        }
                    }
                }
            }
            Divider().padding(.vertical, 4)
            Button {
                closeMenu()
                ClipboardController.shared.togglePanel()
            } label: {
                Label(L("Open Full History"), systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct HistoryRow: View {
        let entry: ClipboardEntry
        let isCopied: Bool
        let copy: () -> Void
        @State private var isHovering = false
        private var controller: ClipboardController { .shared }

        var body: some View {
            Button(action: copy) {
                HStack(spacing: 8) {
                    if let icon = controller.appIcon(for: entry.id) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                    }
                    Text(entry.title.isEmpty ? L("Image") : entry.title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if isCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else if isHovering {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(entry.title)
            .accessibilityLabel(entry.title)
        }
    }
}
