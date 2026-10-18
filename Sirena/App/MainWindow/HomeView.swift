/// HomeView.swift

import ClipboardKit
import DockKit
import SwiftUI

struct HomeView: View {
    let router: Router

    var body: some View {
        ScrollView {
            // One clock for the whole page: statuses (permissions, timers) refresh together.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                VStack(alignment: .leading, spacing: 36) {
                    HomeBanner()

                    HomeSection(number: 1, title: L("Shortcuts"),
                                subtitle: L("Tools you open with one click. Click a card for all of its settings."),
                                inMenu: true) {
                        menuGrid(BoltMenuItem.shortcuts)
                    }

                    HomeSection(number: 2, title: L("Controllers"),
                                subtitle: L("Adjusted right there in the menu, without opening anything."),
                                inMenu: true) {
                        menuGrid(BoltMenuItem.controls)
                    }

                    HomeSection(number: 3, title: L("Features"),
                                subtitle: L("They work on their own in the background, when you switch them on."),
                                inMenu: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            overview
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                                ForEach(ModuleID.featurePages) { module in
                                    ModuleCard(module: module) { router.selection = .module(module) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func menuGrid(_ items: [BoltMenuItem]) -> some View {
        let manager = ModuleManager.shared
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                MenuItemCard(item: item,
                             available: item.module.map { manager.isRunning($0) } ?? true,
                             open: item.module.map { module in { router.selection = .module(module) } })
            }
        }
    }

    /// One status line, plus what needs attention.
    private var overview: some View {
        let manager = ModuleManager.shared
        let features = ModuleID.featurePages
        let active = features.filter { manager.isEnabled($0) && !manager.pendingRestart.contains($0) }.count
        let needsPermission = ModuleID.featurePages.filter { ModuleStatusLabel.needsPermission($0) && manager.isEnabled($0) }
        return HStack(spacing: 10) {
            Text(L("\(active) of \(features.count) on"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
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
                if !module.isTool {
                    // Always shown, 0/0 included, so every feature card reads the same.
                    let options = FeatureOptions.count(module) ?? (0, 0)
                    OptionsRing(on: Self.isOn(module) ? options.on : 0, total: options.total,
                                tint: module.tint)
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
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
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
/// The welcome banner: what Sirena is, in a few words, with the mascot on the right.
private struct HomeBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Welcome to Sirena"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(L("Everything you use every day on the Mac, in one place. Sirena lives in the menu bar: click the orb to reach your shortcuts and controllers."))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    tip("1.circle.fill", L("Shortcuts and controllers: choose what appears in the menu."))
                    tip("2.circle.fill", L("Features: switch on what should work by itself."))
                    tip("command", L("⌃⌥S opens this window from anywhere."))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            mascot
        }
        .padding(28)
        .frame(minHeight: 230)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.32, green: 0.12, blue: 0.55), Color(red: 0.12, green: 0.08, blue: 0.30)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.pink.opacity(0.45), .clear], center: .topTrailing, startRadius: 10, endRadius: 360)
                RadialGradient(colors: [Color.blue.opacity(0.35), .clear], center: .bottomLeading, startRadius: 10, endRadius: 320)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.white.opacity(0.9))
        } icon: {
            Image(systemName: symbol).foregroundStyle(.white)
        }
        .font(.callout)
    }

    /// The mascot (asset "HomeMascot" when it exists; the orb meanwhile), saying hello.
    private var mascot: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(L("Hi! I'm here in the menu bar whenever you need me."))
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 220, alignment: .trailing)
            Image(NSImage(named: "HomeMascot") != nil ? "HomeMascot" : "SirenaIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
        .accessibilityHidden(true)
    }
}

/// A numbered section of Home. Sections 1 and 2 also show in the menu bar menu.
private struct HomeSection<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    let inMenu: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if inMenu {
                    Label(L("Appears in the menu bar menu"), systemImage: "menubar.arrow.up.rectangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            content
        }
    }
}

/// A shortcut or controller: what it does in three lines, its state, and the switch
/// that puts it in the menu bar menu. Clicking the card opens its page, when it has one.
private struct MenuItemCard: View {
    let item: BoltMenuItem
    let available: Bool
    let open: (() -> Void)?
    @State private var settings = BoltMenuSettings.shared
    @State private var isHovering = false

    var body: some View {
        let isOn = settings.isOn(item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                GlassIcon(symbol: item.symbol, image: item == .mirror ? "CameraShutter" : nil, tint: item.tint, size: 32, isOn: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(!available ? L("Feature turned off") : item.module.map { ModuleStatusLabel.detail($0) } ?? (isOn ? L("In the menu") : L("Not in the menu")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Toggle(L("Show in the menu"), isOn: Binding(get: { isOn }, set: { settings.set(item, $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help(L("Show in the menu bar menu"))
            }
            Text(item.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isHovering && open != nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture { open?() }
        .foregroundStyle(available ? .primary : .secondary)
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
                    .font(.caption2.monospacedDigit())
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
        case .mixer: return SirenaMixer.shared.isRunning
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
        case .mixer:
            return L("Volume of each app")
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
