/// Components.swift
///
/// Building blocks shared by every module page, so each feature keeps the same layout:
/// header (icon, name, description, on/off) → tabs → the feature's own settings.

import MASShortcut
import SwiftUI

/// The module's symbol as a Liquid Glass icon, like macOS 27's own settings icons.
struct ModuleIcon: View {
    let module: ModuleID
    var size: CGFloat = 44

    var body: some View {
        GlassIcon(symbol: module.symbol, tint: module.tint, size: size)
    }
}

/// A symbol on a tinted Liquid Glass rounded square.
struct GlassIcon: View {
    var symbol: String? = nil
    var image: String? = nil
    let tint: Color
    var size: CGFloat = 32
    var isOn = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Group {
            if let image {
                Image(image).resizable().renderingMode(.template).scaledToFit()
                    .padding(size * 0.25)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
            }
        }
        .foregroundStyle(isOn ? .white : .secondary)
        .frame(width: size, height: size)
        .background(isOn ? AnyShapeStyle(tint.gradient.opacity(0.9)) : AnyShapeStyle(Color.primary.opacity(0.06)), in: shape)
        .glassEffect(.regular.tint(isOn ? tint.opacity(0.25) : .clear), in: shape)
    }
}

/// A page tab: a title plus the content shown under the segmented control.
struct PageTab: Identifiable {
    let id: String
    let title: String
    let content: () -> AnyView

    init<Content: View>(_ id: String, _ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.content = { AnyView(content()) }
    }
}

/// Header + on/off switch + tabbed content, the standard layout of a module page.
struct ModulePage<Accessory: View>: View {
    let module: ModuleID
    let tabs: [PageTab]
    /// False for a page that groups several features, each with its own switch inside.
    var switchable = true
    @ViewBuilder var accessory: () -> Accessory

    @State private var selectedTab: String?
    @State private var manager = ModuleManager.shared
    @State private var navigator = PageNavigator.shared

    init(module: ModuleID, tabs: [PageTab], switchable: Bool = true,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.module = module
        self.tabs = tabs
        self.switchable = switchable
        self.accessory = accessory
        // Debug helper: SIRENA_OPEN_TAB=<tab id> opens a page on that tab.
        _selectedTab = State(initialValue: ProcessInfo.processInfo.environment["SIRENA_OPEN_TAB"].flatMap { $0.isEmpty ? nil : $0 })
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { !switchable || (manager.isEnabled(module) && !manager.pendingRestart.contains(module)) },
            set: { manager.setEnabled(module, $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if switchable && manager.pendingRestart.contains(module) {
                restartBanner
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            Divider()

            if isEnabled.wrappedValue {
                if let tab = tabs.first(where: { $0.id == (selectedTab ?? tabs.first?.id) }) {
                    tab.content()
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                disabledPlaceholder
            }
        }
        .onAppear(perform: openRequestedTab)
        .onChange(of: navigator.requestedTab) { openRequestedTab() }
        // The page's main action lives in the window toolbar, where it never truncates.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                accessory()
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    /// Icon, name, a two-line summary and the on/off switch, then the section tabs.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ModuleIcon(module: module, size: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(.title3.weight(.semibold))
                    Text(module.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(module.summary)
                }
                Spacer(minLength: 16)
                // Tools are always available: no on/off switch.
                if !module.isTool && switchable {
                    Toggle(L("Turn On \(module.title)"), isOn: isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .help(L("Turn this feature on or off"))
                }
            }
            if tabs.count > 1 && isEnabled.wrappedValue {
                // Segmented while the tabs fit the column; a pop-up menu otherwise, so a long
                // tab bar never pushes the page wider than the window.
                ViewThatFits(in: .horizontal) {
                    sectionPicker.pickerStyle(.segmented)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                    sectionPicker.pickerStyle(.menu)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func openRequestedTab() {
        guard let tab = navigator.requestedTab, tabs.contains(where: { $0.id == tab }) else { return }
        selectedTab = tab
        navigator.requestedTab = nil
    }

    private var sectionPicker: some View {
        Picker(L("Section"), selection: Binding(get: { selectedTab ?? tabs.first?.id }, set: { selectedTab = $0 })) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(Optional(tab.id))
            }
        }
        .labelsHidden()
    }

    private var restartBanner: some View {
        HStack {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)
            Text(L("This feature stops completely after Sirena restarts."))
                .font(.callout)
            Spacer()
            Button(L("Restart Now")) {
                ModuleManager.shared.relaunch()
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var disabledPlaceholder: some View {
        ContentUnavailableView {
            Label(module.title, systemImage: module.symbol)
        } description: {
            Text(L("This feature is turned off."))
        } actions: {
            Button(L("Turn On")) {
                ModuleManager.shared.setEnabled(module, true)
            }
            .buttonStyle(.borderedProminent)
            .tint(module.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A discreet (i) that explains a setting in a popover.
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(text)
        .popover(isPresented: $isShown, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

/// The one way Sirena shows a recordable shortcut: title on the left, recorder on the
/// right, on a single line.
struct ShortcutRow: View {
    let title: String
    let defaultsKey: String
    let recordingObserver: ShortcutRecordingObserver

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            MASShortcutViewRepresentable(defaultsKey: defaultsKey, validator: nil, recordingObserver: recordingObserver)
                .frame(width: 160, height: 22)
                .fixedSize()
        }
    }
}

/// A module shown as a tab of another page (e.g. Cafeína inside Melhorias): its own
/// summary and on/off switch on top, then its settings, or a placeholder when it's off.
struct EmbeddedModule<Content: View>: View {
    let module: ModuleID
    @ViewBuilder var content: () -> Content

    @State private var manager = ModuleManager.shared

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { manager.isEnabled(module) && !manager.pendingRestart.contains(module) },
            set: { manager.setEnabled(module, $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(module.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Toggle(L("Turn On \(module.title)"), isOn: isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if manager.pendingRestart.contains(module) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    Text(L("This feature stops completely after Sirena restarts.")).font(.callout)
                    Spacer()
                    Button(L("Restart Now")) { ModuleManager.shared.relaunch() }
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider()

            if isEnabled.wrappedValue {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(module.title, systemImage: module.symbol)
                } description: {
                    Text(L("This feature is turned off."))
                } actions: {
                    Button(L("Turn On")) { ModuleManager.shared.setEnabled(module, true) }
                        .buttonStyle(.borderedProminent)
                        .tint(module.tint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Moves a shortcut saved by an older recorder into MASShortcut's storage, once.
@MainActor
func migrateShortcut(to defaultsKey: String, keyCode: Int, modifiers: NSEvent.ModifierFlags) {
    guard UserDefaults.standard.object(forKey: defaultsKey) == nil,
          let stored = MASDictionaryTransformer().reverseTransformedValue(MASShortcut(keyCode: keyCode, modifierFlags: modifiers)) else { return }
    UserDefaults.standard.set(stored, forKey: defaultsKey)
}
