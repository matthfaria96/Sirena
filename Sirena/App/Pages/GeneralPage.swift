/// GeneralPage.swift
///
/// Geral (sidebar, Sirena section): three tabs. Sirena holds Sirena's own permissions and
/// settings (SirenaSettingsTab.swift); Permissões dos apps the privacy lists where macOS switches
/// an app's permissions on (two columns); Ajustes do Sistema the System Settings panes people
/// open most. The last two are shortcuts only (`SettingsShortcuts.swift`): Sirena can't grant
/// a permission or change a setting there. (They were the "Ajustes do Mac" page, before that
/// tabs of the "Ajustes" card.)

import SwiftUI

struct GeneralPage: View {
    private enum Tab: String, CaseIterable {
        case sirena, permissions, system

        var title: String {
            switch self {
            case .sirena: "Sirena"
            case .permissions: L("Permissions for Apps")
            case .system: L("System Settings")
            }
        }
    }

    // SIRENA_OPEN_TAB=sirena|permissions|system opens a tab (screenshots), like ModulePage.
    @State private var tab = ProcessInfo.processInfo.environment["SIRENA_OPEN_TAB"].flatMap(Tab.init) ?? .sirena

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Section"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .sirena: SirenaSettingsTab()
                case .permissions: permissions
                case .system: system
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { BackToHomeButton() }
    }

    private var permissions: some View {
        SettingsColumn {
            intro(L("Only macOS can give a permission: each button opens the list where you switch the app on. An app missing from a list can be added with + or dragged into it from the Finder."))
            let items = SettingsShortcuts.permissions
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    GridRow {
                        SettingsTile(item: items[start], showsDetail: true)
                        if start + 1 < items.count {
                            SettingsTile(item: items[start + 1], showsDetail: true)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private var system: some View {
        SettingsColumn {
            intro(L("Each one opens its pane in System Settings; nothing changes here."))
            ForEach(SettingsShortcuts.system, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.headline)
                        .padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(group.items) { item in
                            SettingsTile(item: item, showsDetail: false)
                        }
                    }
                }
            }
        }
    }

    private func intro(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// A shortcut as a card: the whole card opens it. With its detail line on the permissions tab.
private struct SettingsTile: View {
    let item: SettingsShortcut
    let showsDetail: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            item.open()
        } label: {
            HStack(alignment: showsDetail ? .top : .center, spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .padding(.top, showsDetail ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsDetail && !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if showsDetail {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.6)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, showsDetail ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: showsDetail ? .infinity : nil, alignment: showsDetail ? .topLeading : .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(hovering ? 0.45 : 0.2), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(showsDetail ? L("Open") + " · " + item.title : item.title)
        .onHover { hovering = $0 }
    }
}
