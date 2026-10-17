/// HomeView.swift

import ClipboardKit
import DockKit
import SwiftUI

struct HomeView: View {
    let router: Router

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    var body: some View {
        ScrollView {
            // One clock for the whole page: statuses (permissions, timers) refresh together.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    BoltMenuHero(router: router)
                        .padding(.bottom, 12)
                    overview
                        .padding(.top, 12)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ModuleID.featurePages) { module in
                            ModuleCard(module: module) { router.selection = .module(module) }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One status line, plus what needs attention.
    private var overview: some View {
        let manager = ModuleManager.shared
        let features = ModuleID.featurePages
        let active = features.filter { manager.isRunning($0) }.count
        let needsPermission = ModuleID.featurePages.filter { ModuleStatusLabel.needsPermission($0) && manager.isEnabled($0) }
        return HStack(spacing: 10) {
            Text(L("Features — \(active) of \(features.count) on"))
                .font(.headline)
            if !needsPermission.isEmpty {
                Label(needsPermission.count == 1 ? L("1 feature needs a permission") : L("\(needsPermission.count) features need permissions"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Button(L("Review…")) { router.selection = .general }
                    .controlSize(.small)
            }
            Spacer()
        }
    }
}

private struct ModuleCard: View {
    let module: ModuleID
    let open: () -> Void
    @State private var isHovering = false
    @State private var manager = ModuleManager.shared

    /// Janela e Dock groups three features: its card is on while any of them is.
    @MainActor
    static func isOn(_ module: ModuleID) -> Bool {
        let manager = ModuleManager.shared
        if module == .windows { return [.windows, .dock, .switcher].contains { manager.isEnabled($0) } }
        return manager.isEnabled(module)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ModuleIcon(module: module, size: 32)
                    .accessibilityHidden(true)
                Text(module.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                InfoButton(module.summary)
                if !module.isTool {
                    // Always shown, 0/0 included, so every feature card reads the same.
                    let options = FeatureOptions.count(module) ?? (0, 0)
                    OptionsRing(on: Self.isOn(module) ? options.on : 0, total: options.total,
                                tint: Self.isOn(module) ? .green : .red)
                }
            }
            Text(module.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if module.isTool {
                    // Tools are a matter of taste: no on/off, just what they're holding.
                    Text(ModuleStatusLabel.detail(module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ModuleStatusLabel(module: module, isEnabled: Self.isOn(module))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let action = QuickAction(module: module), manager.isRunning(module) {
                    Button(action.title, action: action.run)
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary))
        }
        .overlay {
            // Features: a steady green glow when on, red when off. No animation.
            if module.isTool {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            } else {
                let color: Color = Self.isOn(module) ? .green : .red
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.85), lineWidth: 1.5)
                    .shadow(color: color.opacity(0.55), radius: 8)
            }
        }
        .onHover { isHovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("Open")) { open() }
    }
}

/// Home's first section: what Sirena's ⚡ menu shows. It's where the app's everyday
/// reach is decided, so it gets the spotlight.
private struct BoltMenuHero: View {
    let router: Router
    @State private var settings = BoltMenuSettings.shared
    @State private var manager = ModuleManager.shared
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image("TrayOrb")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .padding(13)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: [.purple, .pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .purple.opacity(0.45), radius: 12, y: 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Your menu bar menu"))
                        .font(.title2.bold())
                    Text(L("Everything you reach for, one click away in the menu bar. Choose what it shows."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    SirenaStatusItem.instance.openMenu()
                } label: {
                    Label(L("Try It"), systemImage: "cursorarrow.click.2")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            group(L("Shortcuts"), L("Programs opened with one click from the menu."), BoltMenuItem.shortcuts)
            group(L("Controllers"), L("Adjusted right there in the menu: sound, microphone, brightness, Cafeína and a peek through the camera."), BoltMenuItem.controls)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background.secondary)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [.purple.opacity(0.18), .pink.opacity(0.10), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.purple.opacity(0.5), .pink.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1)
        }
    }
}

private extension BoltMenuHero {
    func group(_ title: String, _ info: String, _ items: [BoltMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                InfoButton(info)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    BoltItemTile(item: item, isOn: settings.isOn(item),
                                 available: item.module.map { manager.isRunning($0) } ?? true,
                                 open: item.module.map { module in { router.selection = .module(module) } }) {
                        settings.set(item, !settings.isOn(item))
                    }
                }
            }
        }
    }
}

private struct BoltItemTile: View {
    let item: BoltMenuItem
    let isOn: Bool
    let available: Bool
    /// The tool's own page (Cafeína, Espelho, Área de Transferência…), when it has one.
    let open: (() -> Void)?
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background((isOn ? item.tint : .gray).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .saturation(isOn ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(!available ? L("Feature turned off") : item.module.map { ModuleStatusLabel.detail($0) } ?? item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            InfoButton(item.detail)
            if let open {
                Button(action: open) {
                    Image(systemName: "chevron.right.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Open its page"))
            }
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(item.title)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.opacity(0.6))))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
        .opacity(available ? 1 : 0.6)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// How many of a background feature's options are on: a small ring with "on/total".
private struct OptionsRing: View {
    let on: Int
    let total: Int
    let tint: Color

    private var fraction: Double { total > 0 ? Double(on) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(on)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                Text("/\(total)")
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .help(L("\(on) of \(total) options on"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(on) of \(total) options on"))
    }
}

/// Counts of a background feature's options that are switched on.
@MainActor
enum FeatureOptions {
    static func count(_ module: ModuleID) -> (on: Int, total: Int)? {
        switch module {
        case .windows:
            // Window actions with a keyboard shortcut, plus snapping by dragging.
            let actions: [WindowAction] = [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf,
                                           .topLeft, .topRight, .bottomLeft, .bottomRight,
                                           .maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore,
                                           .nextDisplay, .previousDisplay]
            let withShortcut = actions.filter { UserDefaults.standard.object(forKey: $0.name) != nil }.count
            let snapping = Defaults.windowSnapping.userDisabled ? 0 : 1
            return (withShortcut + snapping, actions.count + 1)
        case .dock:
            return SirenaDockStats.options
        case .tweaks:
            let t = TweaksSettings.shared
            let flags = [t.finderCutAndPaste, t.finderCutSound, t.finderDeleteMovesToTrash, t.finderCopyPath,
                         t.installFromDMG, t.screenshotsShowPointer]
            return (flags.filter { $0 }.count, flags.count)
        case .menuBar:
            // Running apps whose icons are hidden, out of the apps chosen to hide.
            let module = MenuBarModule.shared
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            return (module.hiddenApps.intersection(running).count, module.hiddenApps.count)
        case .shelf:
            let s = ShelfSettings.shared
            let flags = [s.showAtCursor, s.showOnlyAtEdge, s.suppressKey != .none, !s.ignoredApps.isEmpty,
                         s.showPreviews, s.removeAfterDragOut, s.resolveAliases]
            return (flags.filter { $0 }.count, flags.count)
        default:
            return nil
        }
    }
}

/// The one thing each feature is most often used for, offered right on its card.
private struct QuickAction {
    let title: String
    let run: () -> Void

    @MainActor
    init?(module: ModuleID) {
        switch module {
        case .clipboard:
            title = L("Open History"); run = { ClipboardController.shared.togglePanel() }
        case .mirror:
            title = MirrorState.shared.isVisible ? L("Hide Mirror") : L("Show Mirror"); run = { MirrorController.shared.toggle() }
        case .pinWindow:
            title = L("Pin…"); run = { PinWindowController.shared.selectWindowToPin() }
        case .textCapture:
            title = L("Capture Text"); run = { TextCaptureController.shared.capture(.text()) }
        case .shelf:
            title = ShelfController.shared.isVisible ? L("Hide") : L("Show"); run = { ShelfController.shared.toggle() }
        case .keepAwake:
            let viewModel = KeepAwakeModule.shared.viewModel
            // Turning on always uses the default duration set on the Cafeína page.
            title = viewModel.isActive ? L("Turn Off") : L("Turn On")
            run = { viewModel.toggleActive() }
        default:
            return nil
        }
    }
}

/// A one-line live status for a module, shown on its home card.
struct ModuleStatusLabel: View {
    let module: ModuleID
    let isEnabled: Bool

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }

    /// Off, missing permission, active or idle: told by shape as well as color.
    private var symbol: String {
        if !isEnabled { return "minus.circle" }
        if Self.needsPermission(module) { return "exclamationmark.triangle.fill" }
        return isActive ? "checkmark.circle.fill" : "circle"
    }

    @MainActor
    static func needsPermission(_ module: ModuleID) -> Bool {
        switch module {
        case .windows, .tweaks, .switcher: return !AXIsProcessTrusted()
        case .dock, .pinWindow, .textCapture: return !CGPreflightScreenCaptureAccess()
        default: return false
        }
    }

    private var isActive: Bool {
        guard isEnabled else { return false }
        switch module {
        case .windows: return AXIsProcessTrusted()
        case .dock: return DockController.shared.isRunning
        case .switcher: return AXIsProcessTrusted()
        case .island: return IslandController.shared.isRunning
        case .clipboard: return !ClipboardController.shared.isPaused
        case .menuBar: return true
        case .keepAwake: return KeepAwakeModule.shared.viewModel.isActive
        case .mirror: return MirrorController.shared.isVisible
        case .pinWindow: return !PinWindowController.shared.pins.isEmpty
        case .textCapture: return CGPreflightScreenCaptureAccess()
        case .tweaks: return AXIsProcessTrusted()
        case .shelf: return !ShelfStore.shared.items.isEmpty
        }
    }

    private var color: Color {
        if !isEnabled { return .gray }
        if (module == .windows || module == .tweaks || module == .switcher) && !AXIsProcessTrusted() { return .orange }
        if module == .dock && !DockController.hasScreenRecordingPermission { return .orange }
        if (module == .pinWindow || module == .textCapture) && !CGPreflightScreenCaptureAccess() { return .orange }
        return isActive ? .green : .secondary.opacity(0.5)
    }

    private var text: String {
        isEnabled ? Self.detail(module) : L("Off")
    }

    /// What the feature is doing right now, in a few words.
    static func detail(_ module: ModuleID) -> String {
        switch module {
        case .windows:
            return AXIsProcessTrusted() ? L("Active") : L("Needs Accessibility permission")
        case .dock:
            return DockController.hasScreenRecordingPermission ? L("Active") : L("Active — allow Screen Recording for thumbnails")
        case .switcher:
            return AXIsProcessTrusted() ? L("Active on ⌘ Tab") : L("Needs Accessibility permission")
        case .island:
            return L("Active")
        case .clipboard:
            if ClipboardController.shared.isPaused { return L("Paused") }
            let count = ClipboardController.shared.historyCount
            return count == 1 ? L("1 item in history") : L("\(count) items in history")
        case .menuBar:
            let module = MenuBarModule.shared
            if module.hiddenApps.isEmpty { return L("Choose which apps to hide") }
            return module.isCollapsed ? L("\(module.hiddenApps.count) apps hidden") : L("Icons showing")
        case .keepAwake:
            let viewModel = KeepAwakeModule.shared.viewModel
            return viewModel.formattedTimeRemaining() ?? L("Mac can sleep normally")
        case .mirror:
            return MirrorController.shared.isVisible ? L("Mirror is showing") : L("Mirror is hidden")
        case .pinWindow:
            guard CGPreflightScreenCaptureAccess() else { return L("Needs Screen Recording permission") }
            let count = PinWindowController.shared.pins.count
            switch count {
            case 0: return L("No windows pinned")
            case 1: return L("1 window pinned")
            default: return L("\(count) windows pinned")
            }
        case .textCapture:
            guard CGPreflightScreenCaptureAccess() else { return L("Needs Screen Recording permission") }
            let additive = TextCaptureController.shared.additiveItems.count
            return additive > 0 ? L("Additive Clipboard: \(additive) captures") : L("Ready — press ⇧⌘2 to capture")
        case .tweaks:
            return AXIsProcessTrusted() ? L("Active") : L("Needs Accessibility permission")
        case .shelf:
            let count = ShelfStore.shared.items.count
            switch count {
            case 0: return L("Shelf is empty — start dragging to use it")
            case 1: return L("1 item on the shelf")
            default: return L("\(count) items on the shelf")
            }
        }
    }
}
