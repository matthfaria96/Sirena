/// IslandPage.swift

import SwiftUI

struct IslandPage: View {
    var body: some View {
        ModulePage(module: .island, tabs: [
            PageTab("general", L("General")) { IslandSettingsView() }
        ]) {
            Button {
                IslandController.shared.toggleIsland()
            } label: {
                Label(L("Open Island"), systemImage: "capsule.portrait")
            }
        }
    }
}
