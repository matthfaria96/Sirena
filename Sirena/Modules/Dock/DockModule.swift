/// DockModule.swift
///
/// App-side glue for Dock previews and the window switcher (DockKit, ported from
/// DockDoor, GPL-3.0). DockDoor's sound and images live next to this file so DockKit
/// finds them in the main bundle.

import DockKit

@MainActor
enum DockModule {
    static func start(openPage: @escaping () -> Void) {
        let controller = DockController.shared
        controller.onOpenSettings = openPage
        controller.onRestartRequested = { ModuleManager.shared.relaunch() }
        controller.start()
    }

    static func terminate() {
        DockController.shared.terminate()
    }
}
