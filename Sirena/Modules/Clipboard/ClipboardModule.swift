/// ClipboardModule.swift
///
/// App-side glue for the clipboard manager (ClipboardKit, ported from Maccy).
/// Maccy's strings, sounds and images live next to this file so ClipboardKit
/// finds them in the main bundle, exactly as Maccy did.

import ClipboardKit

@MainActor
enum ClipboardModule {
    static func start(openPage: @escaping () -> Void) {
        let controller = ClipboardController.shared
        controller.onOpenSettings = openPage
        controller.onOpenAbout = openPage
        controller.showsStatusItem = false
        controller.anchorButton = SirenaStatusItem.instance.button
        controller.start()
    }

    static func terminate() {
        ClipboardController.shared.terminate()
    }
}
