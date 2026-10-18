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
                        .modifier(Entrance(order: 0))

                    HomeSection(number: 1, title: L("Shortcuts"),
                                subtitle: L("Tools you open with one click. Click a card for all of its settings."),
                                inMenu: true) {
                        menuGrid(BoltMenuItem.shortcuts)
                    }
                    .modifier(Entrance(order: 1))

                    HomeSection(number: 2, title: L("Controllers"),
                                subtitle: L("Adjusted right there in the menu, without opening anything."),
                                inMenu: true) {
                        menuGrid(BoltMenuItem.controls)
                    }
                    .modifier(Entrance(order: 2))

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
                    .modifier(Entrance(order: 3))
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
            Text(module.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OpensPage(enabled: true))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("Open")) { open() }
    }
}

/// Home's first section: what Sirena's ⚡ menu shows. It's where the app's everyday
/// reach is decided, so it gets the spotlight.
/// The welcome banner: what Sirena is, with the mascot (hair flowing, orb in hand) on the right.
private struct HomeBanner: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            // The mascot fills the right side and fades into the banner's color.
            GeometryReader { proxy in
                Image("HomeMascot")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .scaleEffect(appeared || reduceMotion ? 1 : 1.06, anchor: .trailing)
                    .opacity(appeared || reduceMotion ? 1 : 0)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                Label(L("Lives in your menu bar"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.16), in: Capsule())
                Text(L("Welcome to Sirena"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(L("Everything you use every day on the Mac, in one place. Click the orb in the menu bar to reach your shortcuts and controllers."))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("1", L("Shortcuts"))
                    chip("2", L("Controllers"))
                    chip("⌃⌥S", L("Opens this window"))
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(32)
            .offset(x: appeared || reduceMotion ? 0 : -12)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.20, green: 0.06, blue: 0.36), Color(red: 0.42, green: 0.10, blue: 0.48)],
                               startPoint: .leading, endPoint: .trailing)
                RadialGradient(colors: [Color.blue.opacity(0.35), .clear], center: .bottomLeading, startRadius: 10, endRadius: 340)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color(red: 0.4, green: 0.1, blue: 0.5).opacity(0.25), radius: 20, y: 10)
        .onAppear {
            withAnimation(.smooth(duration: 0.7)) { appeared = true }
        }
    }

    private func chip(_ key: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color(red: 0.3, green: 0.08, blue: 0.45))
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(.white, in: Capsule())
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.12), in: Capsule())
    }
}

/// Lifts a card under the pointer and shows where clicking leads, like a link to a page.
private struct OpensPage: ViewModifier {
    let enabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.6))
                        .padding(14)
                        .offset(x: isHovering ? 2 : 0)
                        .accessibilityHidden(true)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovering && enabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHovering && enabled ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(.separator),
                              lineWidth: isHovering && enabled ? 1 : 0.5))
            .shadow(color: .black.opacity(isHovering && enabled ? 0.12 : 0), radius: 10, y: 4)
            .scaleEffect(isHovering && enabled ? 1.012 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { hovering in
                withAnimation(.snappy(duration: 0.22)) { isHovering = hovering }
                if enabled { hovering ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            .accessibilityAddTraits(enabled ? .isButton : [])
    }
}

/// Fades a section in from below, a little later than the one above it.
private struct Entrance: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.55).delay(0.08 * Double(order))) { shown = true }
            }
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
            Text(item.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .padding(.trailing, open != nil ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OpensPage(enabled: open != nil))
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
