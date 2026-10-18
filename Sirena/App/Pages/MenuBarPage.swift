/// MenuBarPage.swift
///
/// Choose which apps' menu bar icons Sirena hides, plus the hiding behavior.

import SwiftUI

struct MenuBarPage: View {
    @State private var module = MenuBarModule.shared

    var body: some View {
        ModulePage(module: .menuBar, tabs: [
            PageTab("general", L("General")) { HiddenIconsTab() }
        ]) {
            Button {
                module.toggle()
            } label: {
                Label(module.isCollapsed ? L("Show Hidden Icons") : L("Hide Chosen Icons"),
                      systemImage: module.isCollapsed ? "chevron.left" : "chevron.right")
            }
            .disabled(module.hiddenApps.isEmpty)
        }
    }
}

struct HiddenAppsList: View {
    @State private var module = MenuBarModule.shared
    @State private var apps: [MenuBarModule.MenuBarApp] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            Section {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if apps.isEmpty {
                    Text(L("No other app has icons in the menu bar right now."))
                        .foregroundStyle(.secondary)
                } else {
                    // As many columns as the window's width allows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], alignment: .leading, spacing: 12) {
                        ForEach(apps) { app in
                            Toggle(isOn: Binding(
                                get: { module.hiddenApps.contains(app.bundleIdentifier) },
                                set: { hide in
                                    if hide { module.hiddenApps.insert(app.bundleIdentifier) }
                                    else { module.hiddenApps.remove(app.bundleIdentifier) }
                                }
                            )) {
                                HStack(spacing: 10) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                                    }
                                    Text(app.name)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 8)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text(L("Hide the icons of"))
                    Spacer()
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Refresh the list"))
                }
            }
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.primary, in: Capsule())
                    Text(L("The chosen apps' icons disappear from the menu bar. Click Sirena's arrow icon, at the far left, to bring them back and click it again to hide them. Sirena's globe is never hidden."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !module.isAvailable {
                    Label(L("Hiding icons needs macOS 27 or later."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if MenuBarModule.needsApplicationsFolder {
                    Label(L("Move Sirena to the Applications folder. On macOS 27, hiding icons only works from there; elsewhere Sirena's own icons get hidden too."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if module.needsAccessibility {
                    Label(L("Allow Accessibility access (Settings → General) so Sirena can list the apps in the menu bar."),
                          systemImage: "lock.shield")
                        .foregroundStyle(.orange)
                }
            }

        }
        .onAppear(perform: reload)
    }

    private func reload() {
        isLoading = true
        module.menuBarApps { found in
            apps = found
            isLoading = false
        }
    }
}

struct MenuBarBehavior: View {
    @State private var module = MenuBarModule.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("When clicking the arrow"))
                    Text(module.style == .menu
                         ? L("A translucent menu drops down with every hidden icon; click one to open it. The arrow points down.")
                         : L("The hidden icons come back into the menu bar beside the arrow; click again to hide them."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(HiddenIconsStyle.allCases) { style in
                            RevealStyleCard(style: style, isSelected: module.style == style) {
                                withAnimation(.snappy) { module.style = style }
                            }
                            // Still in beta: shown, greyed out, not selectable.
                            .disabled(style == .menu)
                            .opacity(style == .menu ? 0.45 : 1)
                            .saturation(style == .menu ? 0 : 1)
                            .overlay(alignment: .topTrailing) {
                                if style == .menu {
                                    HStack(spacing: 4) {
                                        Text(L("Beta"))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.orange.opacity(0.85), in: Capsule())
                                            .foregroundStyle(.white)
                                        InfoButton(L("The menu with the hidden icons is still in beta on macOS 27 and is turned off for now. The icons come back beside the arrow."))
                                    }
                                    .padding(6)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(L("Reveal"))
            }

            Section {
                ShortcutRow(title: L("Show or hide icons"), defaultsKey: MenuBarModule.shortcutKey,
                            recordingObserver: recordingObserver)
            } header: {
                Text(L("Keyboard shortcut"))
            }
        }
    }
}

/// Everything about hidden icons on one tab: reveal style, the apps, auto-hiding and the shortcut.
struct HiddenIconsTab: View {
    @State private var module = MenuBarModule.shared

    var body: some View {
        Form {
            HiddenAppsList()
            MenuBarBehavior()
        }
        .formStyle(.grouped)
    }
}

/// A small drawing of the menu bar showing what each reveal style does.
private struct RevealStyleCard: View {
    let style: HiddenIconsStyle
    let isSelected: Bool
    let select: () -> Void

    private let hidden: [(String, Color)] = [("cloud.fill", .blue), ("music.note", .pink), ("bolt.fill", .orange)]
    private let visible = ["wifi", "battery.75percent", "magnifyingglass"]

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 96, alignment: .top)
                    .background(LinearGradient(colors: [.indigo.opacity(0.55), .purple.opacity(0.35)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Label(style.title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The menu bar.
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                Image(systemName: style == .menu ? "chevron.down" : "chevron.left")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.white.opacity(0.35), in: Capsule())
                if style == .expand {
                    ForEach(hidden, id: \.0) { symbol, tint in
                        Image(systemName: symbol).foregroundStyle(tint)
                    }
                }
                ForEach(visible, id: \.self) { Image(systemName: $0) }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.black.opacity(0.35))

            if style == .menu {
                // The menu that drops down under the arrow.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(hidden, id: \.0) { symbol, tint in
                        HStack(spacing: 5) {
                            Image(systemName: symbol).foregroundStyle(tint).frame(width: 12)
                            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.7)).frame(width: 34, height: 4)
                        }
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.trailing, 52)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text(L("Hidden icons"))
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.trailing, 50)
            }
        }
    }
}
