/// PomodoroMenuBarTimer.swift
///
/// While a session is on, a black pill beside Sirena's menu bar icon shows the time left:
/// click the time to pause or resume, the red button to end the session.

import AppKit
import SwiftUI

@MainActor
final class PomodoroMenuBarTimer {
    static let shared = PomodoroMenuBarTimer()
    private var item: NSStatusItem?
    private static let width: CGFloat = 62

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: Self.width)
            item.autosaveName = "pomodoroTimer"
            if let button = item.button {
                let host = NSHostingView(rootView: PomodoroPill())
                host.frame = NSRect(x: 0, y: 0, width: Self.width, height: NSStatusBar.system.thickness)
                host.autoresizingMask = [.width, .height]
                button.addSubview(host)
                button.setAccessibilityLabel(L("Pomodoro timer"))
            }
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }
}

/// Just the time running, white on red; a click opens Sirena's menu on Foco to pause or end.
private struct PomodoroPill: View {
    @State private var controller = PomodoroController.shared

    var body: some View {
        Button {
            BoltMenuSettings.shared.openInline = .pomodoro
            SirenaStatusItem.instance.openMenu()
        } label: {
            Text(controller.remainingText)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .padding(.horizontal, 9)
                .frame(height: 19)
                .background(Color.red.opacity(controller.isTicking ? 1 : 0.55), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.isTicking ? L("Focus timer — click for pause and end") : L("Paused — click to resume or end"))
        .animation(.snappy, value: controller.remainingText)
    }
}
