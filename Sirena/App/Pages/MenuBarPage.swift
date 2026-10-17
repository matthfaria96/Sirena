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
    @State private var autoHide = Preferences.isAutoHide
    @State private var autoHideDelay = Preferences.numberOfSecondForAutoHide
    @State private var recordingObserver = ShortcutRecordingObserver()

    private let delays: [Double] = [5, 10, 15, 30, 60]

    var body: some View {
        Group {
            Section {
                Picker(selection: $module.style) {
                    ForEach(HiddenIconsStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text(L("When clicking the arrow"))
                    Text(module.style == .menu
                         ? L("A translucent menu drops down with every hidden icon; click one to open it. The arrow points down.")
                         : L("The hidden icons come back into the menu bar beside the arrow; click again to hide them."))
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(L("Reveal"))
            }

            Section {
                Toggle(L("Hide the icons again automatically"), isOn: $autoHide)
                    .onChange(of: autoHide) { Preferences.isAutoHide = autoHide }
                    .disabled(module.style == .menu)
                Picker(L("Hide after"), selection: $autoHideDelay) {
                    ForEach(delays, id: \.self) { seconds in
                        Text(seconds < 60 ? L("\(Int(seconds)) seconds") : L("1 minute")).tag(seconds)
                    }
                }
                .disabled(!autoHide)
                .onChange(of: autoHideDelay) { Preferences.numberOfSecondForAutoHide = autoHideDelay }
            } header: {
                Text(L("Automatic hiding"))
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
