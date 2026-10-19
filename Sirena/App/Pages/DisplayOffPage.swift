/// DisplayOffPage.swift
///
/// Turn the display off: the button and the wait before it goes dark, laid out like
/// Keep Awake's page.

import SwiftUI

struct DisplayOffPage: View {
    var body: some View {
        ModulePage(module: .displayOff, tabs: [
            PageTab("general", L("General")) { DisplayOffSettings() }
        ])
    }
}

struct DisplayOffSettings: View {
    @ObservedObject private var controller = DisplayOffController.shared
    @AppStorage(DisplayOffController.delayKey) private var delay = DisplayOffController.defaultDelay

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "display")
                        .font(.system(size: 34))
                        .foregroundStyle(controller.isCounting ? ModuleID.displayOff.tint : Color.secondary)
                        .symbolEffect(.pulse, isActive: controller.isCounting)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.isCounting ? L("The screen is about to turn off") : L("Turn off the display"))
                            .font(.headline)
                        Text(controller.isCounting ? controller.statusText : controller.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Spacer()
                    Button(controller.buttonTitle) {
                        withAnimation(.snappy) { controller.toggle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.vertical, 6)
            } footer: {
                Text(L("Click to start the countdown; you can cancel before the screen goes dark. Moving the mouse or pressing a key turns it back on."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L("Wait before turning off"), selection: $delay) {
                    ForEach(DisplayOffController.delays, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
            } header: {
                Text(L("Behavior"))
            }
        }
        .formStyle(.grouped)
    }
}
