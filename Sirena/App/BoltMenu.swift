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
    case clipboard, pinWindow, textCapture, screenCapture, pomodoro, colorPicker, screenBrush, mirror
    // Controladores
    case keepAwake, sound

    var id: String { rawValue }

    enum Kind { case shortcut, control }

    var kind: Kind {
        switch self {
        case .clipboard, .pinWindow, .textCapture, .screenCapture, .mirror, .pomodoro, .colorPicker, .screenBrush: return .shortcut
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
        case .screenCapture, .pomodoro, .colorPicker, .screenBrush: return module?.title ?? ""
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
        case .screenCapture: return L("A custom shortcut to Apple's Screenshot app: an area, the whole screen or a recording, in one click.")
        case .pomodoro: return L("A focus timer: work in sessions and take short and long breaks on their own.")
        case .colorPicker: return L("Picks any color on the screen and copies it in the format you use, with history and palettes.")
        case .screenBrush: return L("Draw, highlight and point on top of the screen, for presentations and calls.")
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
        case .textCapture: return L("Text")
        case .screenCapture: return L("Capture")
        case .pomodoro: return L("Focus")
        case .colorPicker: return L("Color")
        case .screenBrush: return L("Draw")
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
        case .screenCapture: return L("Screenshot of an area or the whole screen, or a recording of either, with macOS's own tool.")
        case .pomodoro: return L("Starts or pauses a focus session; breaks follow on their own.")
        case .colorPicker: return L("Opens a magnifier to pick a color from anywhere on the screen and copies it.")
        case .screenBrush: return L("Turns the screen into a canvas to draw, highlight and point. Esc to leave.")
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
        case .screenCapture, .pomodoro, .colorPicker, .screenBrush: return module?.symbol ?? "circle"
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
        case .screenCapture, .pomodoro, .colorPicker, .screenBrush: return module?.tint ?? .accentColor
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
        case .screenCapture: return .screenCapture
        case .pomodoro: return .pomodoro
        case .colorPicker: return .colorPicker
        case .screenBrush: return .screenBrush
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
        case .screenCapture: ScreenCaptureController.shared.quickAction()
        case .pomodoro: PomodoroController.shared.quickAction()
        case .colorPicker: ColorPickerController.shared.quickAction()
        case .screenBrush: ScreenBrushController.shared.quickAction()
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
        var items = saved.map { Set($0.compactMap(BoltMenuItem.init)) }
            ?? Set(BoltMenuItem.allCases)
        // Pomodoro, Color Picker and Freehand Drawing came later: show them once to everyone.
        if !UserDefaults.standard.bool(forKey: "boltMenu.addedFocusColorBrush") {
            items.formUnion([.pomodoro, .colorPicker, .screenBrush])
            UserDefaults.standard.set(true, forKey: "boltMenu.addedFocusColorBrush")
        }
        if !UserDefaults.standard.bool(forKey: "boltMenu.addedScreenCapture") {
            items.insert(.screenCapture)
            UserDefaults.standard.set(true, forKey: "boltMenu.addedScreenCapture")
        }
        enabled = items
    }

    /// The menu's see-through Liquid Glass look; off by default so it reads over any window.
    /// An inline panel the menu opens on (the menu bar timer opens it on Foco).
    var openInline: BoltMenuItem?

    var clearGlass = UserDefaults.standard.bool(forKey: "boltMenu.clearGlass") {
        didSet { UserDefaults.standard.set(clearGlass, forKey: "boltMenu.clearGlass") }
    }

    func isOn(_ item: BoltMenuItem) -> Bool { enabled.contains(item) }

    func set(_ item: BoltMenuItem, _ on: Bool) {
        if on { enabled.insert(item) } else { enabled.remove(item) }
    }

    /// Items to show right now: chosen, and with their feature running.
    var visibleItems: [BoltMenuItem] {
        let all = HomeOrder.shared.sorted(BoltMenuItem.shortcuts, group: "shortcuts", id: \.rawValue)
            + HomeOrder.shared.sorted(BoltMenuItem.controls, group: "controls", id: \.rawValue)
        return all.filter { item in
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
    @State private var showsCapture = false
    @State private var showsFocus = false

    var body: some View {
        let visible = settings.visibleItems
        let controls = visible.filter { $0.kind == .control && $0 != .sound }
        let shortcuts = visible.filter { $0.kind == .shortcut }
        VStack(spacing: 12) {
            if !shortcuts.isEmpty {
                // Four per row: the shortcuts no longer fit on one line.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4), spacing: 10) {
                    ForEach(shortcuts) { item in
                        ShortcutButton(item: item, isActive: isInlineOpen(item)) { tap(item) }
                    }
                }
                if showsHistory {
                    InlineHistoryPanel(closeMenu: close)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if showsFocus {
                    InlineFocusPanel {
                        close()
                        ModuleManager.shared.openPage(.module(.pomodoro))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if showsCapture {
                    InlineCapturePanel { action in
                        close()
                        ScreenCaptureController.shared.run(action)
                    }
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
            Divider()
            FeatureSwitchRow()
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
        // Liquid Glass alone vanishes over white windows: a body under it keeps the menu legible.
        .background {
            if !BoltMenuSettings.shared.clearGlass {
                Color(nsColor: .windowBackgroundColor).opacity(0.9)
                    .padding(-30)
            }
        }
        .animation(.snappy(duration: 0.28), value: showsPeek)
        .animation(.snappy(duration: 0.28), value: showsHistory)
        .animation(.snappy(duration: 0.28), value: showsCapture)
        .animation(.snappy(duration: 0.28), value: showsFocus)
        .onAppear {
            if let item = settings.openInline {
                settings.openInline = nil
                tap(item)
            }
        }
    }

    private func isInlineOpen(_ item: BoltMenuItem) -> Bool {
        switch item {
        case .mirror: return showsPeek
        case .clipboard: return showsHistory
        case .screenCapture: return showsCapture || ScreenCaptureController.shared.isRecording
        case .pomodoro: return showsFocus
        default: return false
        }
    }

    /// Histórico, Capturar and Espiar unroll inside the menu; the others run and close it.
    private func tap(_ item: BoltMenuItem) {
        if item == .screenCapture, ScreenCaptureController.shared.isRecording {
            ScreenCaptureController.shared.stopRecording()
            return
        }
        guard [.mirror, .clipboard, .screenCapture, .pomodoro].contains(item) else {
            close()
            item.perform()
            return
        }
        withAnimation(.snappy(duration: 0.25)) {
            let open = !isInlineOpen(item)
            showsPeek = item == .mirror && open
            showsHistory = item == .clipboard && open
            showsCapture = item == .screenCapture && open
            showsFocus = item == .pomodoro && open
        }
        if isInlineOpen(item) { NotificationCenter.default.post(name: .sirenaMixerCollapse, object: nil) }
    }
}

/// Foco inside the menu: the length, start / pause / end, and a way to its settings.
private struct InlineFocusPanel: View {
    let openSettings: () -> Void
    @State private var controller = PomodoroController.shared
    @State private var settings = PomodoroSettings.shared
    private let lengths = [15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.phase.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(controller.phase.color)
                    Text(controller.remainingText)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .compatGlassButtonStyle()
                .buttonBorderShape(.circle)
                .help(L("Pomodoro settings"))
            }

            if !controller.hasStarted {
                HStack(spacing: 6) {
                    ForEach(lengths, id: \.self) { minutes in
                        let isOn = settings.focusMinutes == minutes
                        Button {
                            settings.focusMinutes = minutes
                            controller.settingsChanged()
                        } label: {
                            Text(L("\(minutes) min"))
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .background(isOn ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(.quaternary),
                                            in: Capsule())
                                .foregroundStyle(isOn ? Color.white : Color.primary)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            } else {
                ProgressView(value: controller.progress)
                    .tint(controller.phase.color)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { controller.isTicking ? controller.pause() : controller.resume() }
                } label: {
                    Label(controller.isTicking ? L("Pause") : controller.hasStarted ? L("Resume") : L("Start Focus"),
                          systemImage: controller.isTicking ? "pause.fill" : "play.fill")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .compatGlassProminentButtonStyle()
                .tint(controller.phase.color)
                .controlSize(.large)
                if controller.hasStarted {
                    Button {
                        withAnimation(.snappy) { controller.reset() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 22)
                    }
                    .compatGlassProminentButtonStyle()
                    .tint(.red)
                    .controlSize(.large)
                    .help(L("End session"))
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Capturar inside the menu: the four ways to start macOS's Screenshot tool.
private struct InlineCapturePanel: View {
    let run: (ScreenCaptureAction) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(ScreenCaptureAction.allCases) { action in
                CaptureOption(action: action) { run(action) }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct CaptureOption: View {
        let action: ScreenCaptureAction
        let run: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: run) {
                HStack(spacing: 8) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(action.isRecording ? Color.red : Color.primary)
                        .frame(width: 20)
                    Text(action.title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
            .help(action.detail)
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
                    } else if item == .textCapture {
                        // The thin viewfinder outline vanished next to the filled icons: bigger and bolder.
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 22, weight: .bold))
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
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .help(item.detail)
    }
}

/// The background features, one tap to switch each on or off; a dot tells its state.
private struct FeatureSwitchRow: View {
    @State private var manager = ModuleManager.shared
    private let features: [(ModuleID, String)] = [
        (.windows, L("Window")), (.menuBar, L("Icons")), (.shelf, L("Shelf")), (.island, L("Island"))
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(features, id: \.0) { module, title in
                let isOn = manager.isEnabled(module)
                Button {
                    withAnimation(.snappy) { manager.setEnabled(module, !isOn) }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isOn ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                            .shadow(color: (isOn ? Color.green : Color.red).opacity(0.6), radius: 3)
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help(isOn ? L("\(module.title) is on — click to turn it off") : L("\(module.title) is off — click to turn it on"))
                .accessibilityLabel(module.title)
                .accessibilityValue(isOn ? L("On") : L("Off"))
            }
        }
    }
}

/// Shrinks a control slightly while pressed, like Control Center tiles.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
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
                    Text(keepAwake.isActive ? L("Turned on") : L("Turned off"))
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
                VStack(spacing: 10) {
                    Label(L("Camera unavailable"), systemImage: "video.slash.fill")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                    Button(L("Open Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
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
                .accessibilityLabel(L("Closes in \(remaining) seconds"))
                .opacity(failed ? 0 : 1)
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
            guard !failed else { return }
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
    /// Clearing asks for a second click.
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let entries = Array(controller.entries.prefix(7))
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
            HStack(spacing: 8) {
                footerButton(L("Open History"), symbol: "list.bullet.rectangle", tint: .accentColor) {
                    closeMenu()
                    ModuleManager.shared.openPage(.module(.clipboard))
                    PageNavigator.shared.requestedTab = "history"
                }
                footerButton(confirmsClear ? L("Click to Confirm") : L("Clear History"),
                             symbol: confirmsClear ? "exclamationmark.triangle.fill" : "trash", tint: .red) {
                    if confirmsClear {
                        controller.clearHistory()
                        withAnimation(.snappy) { confirmsClear = false }
                    } else {
                        withAnimation(.snappy) { confirmsClear = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.easeOut) { confirmsClear = false }
                        }
                    }
                }
                .disabled(entries.isEmpty)
                .help(L("Removes every copy except the pinned ones"))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Native Liquid Glass buttons, full-size text so they read at a glance.
    private func footerButton(_ title: String, symbol: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .compatGlassButtonStyle()
        .controlSize(.large)
        .tint(tint == .accentColor ? nil : tint)
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
                    Text(entry.title.isEmpty ? (entry.kind == .file ? L("File") : L("Image")) : entry.title)
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
