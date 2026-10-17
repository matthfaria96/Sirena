/// MainView.swift

import SwiftUI

struct MainView: View {
    @Bindable var router: Router
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $router.selection) {
                Section {
                    sidebarRow(.home, title: L("Home"), symbol: "house.fill", tint: .purple)
                }
                Section(L("Shortcuts")) {
                    ForEach([ModuleID.clipboard, .pinWindow, .textCapture, .mirror]) { module in
                        sidebarRow(.module(module), title: module.title, symbol: module.symbol, tint: module.tint)
                    }
                }
                Section(L("Controllers")) {
                    sidebarRow(.module(.keepAwake), title: ModuleID.keepAwake.title,
                               symbol: ModuleID.keepAwake.symbol, tint: ModuleID.keepAwake.tint)
                }
                Section(L("Features")) {
                    ForEach(ModuleID.featurePages) { module in
                        sidebarRow(.module(module), title: module.title, symbol: module.symbol, tint: module.tint)
                    }
                }
                Section("Sirena") {
                    sidebarRow(.general, title: L("General"), symbol: "gearshape.fill", tint: .gray)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            // The page gets exactly the space of the detail column: a page's own
            // minimum size must never grow the window or push the sidebar.
            GeometryReader { proxy in
                if router.isWindowOpen {
                    detail(for: router.selection ?? .home)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .navigationTitle(title(for: router.selection ?? .home))
    }

    private func sidebarRow(_ item: SidebarItem, title: String, symbol: String, tint: Color) -> some View {
        // Like System Settings: a small colored glass square, then the name.
        Label {
            Text(title)
        } icon: {
            GlassIcon(symbol: symbol, tint: tint, size: 22, glass: false)
        }
        .tag(item)
    }

    private func title(for item: SidebarItem) -> String {
        switch item {
        case .home: return "Sirena"
        case .module(let module): return module.title
        case .general: return L("General")
        case .about: return L("General")
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            HomeView(router: router)
        case .module(.windows), .module(.dock), .module(.switcher), .module(.tweaks):
            WindowsPage()
        case .module(.island):
            IslandPage()
        case .module(.clipboard):
            ClipboardPage()
        case .module(.menuBar):
            MenuBarPage()
        case .module(.keepAwake):
            KeepAwakePage(viewModel: KeepAwakeModule.shared.viewModel)
        case .module(.mirror):
            MirrorPage()
        case .module(.pinWindow):
            PinWindowPage()
        case .module(.textCapture):
            TextCapturePage()
        case .module(.shelf):
            ShelfPage()
        case .general, .about:
            GeneralPage()
        }
    }
}
