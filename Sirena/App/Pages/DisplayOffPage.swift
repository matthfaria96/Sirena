/// DisplayOffPage.swift
///
/// Turn the display off: the button and the wait before it goes dark, laid out like
/// Keep Awake's page.

import SwiftUI

struct DisplayOffPage: View {
    var body: some View {
        ModulePage(module: .displayOff, tabs: [
            PageTab("general", L("General")) { DisplayOffSettings() },
            PageTab("dim", L("Dim Other Screens")) { ScreenDimmerSettings() }
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

/// Dimming the screens you are not using (two or more displays).
struct ScreenDimmerSettings: View {
    @State private var dimmer = ScreenDimmer.shared
    @AppStorage(ScreenDimmer.opacityKey) private var opacity = ScreenDimmer.defaultOpacity
    @AppStorage(ScreenDimmer.delayKey) private var delay = ScreenDimmer.defaultDelay
    @AppStorage(ScreenDimmer.followKey) private var follow = ScreenDimmer.Follow.pointer.rawValue
    @AppStorage(ScreenDimmer.fullScreenKey) private var dimsFullScreen = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "display.2")
                        .font(.system(size: 30))
                        .foregroundStyle(dimmer.isDimming ? Color.indigo : Color.secondary)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Dim Other Screens"))
                            .font(.headline)
                        Text(statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(L("Dim Other Screens"), isOn: $dimmer.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 6)
            } footer: {
                Text(L("The screens you are not using fade to dark after a moment and light up again as soon as the pointer gets there. Clicks go through, and screen recordings and calls show them as they are."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L("Darkness")) {
                    HStack(spacing: 10) {
                        Slider(value: $opacity, in: 0.2...0.85)
                            .frame(maxWidth: 220)
                        Text(opacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker(L("Wait before dimming"), selection: $delay) {
                    ForEach(ScreenDimmer.delays, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                Picker(L("Screen in use"), selection: $follow) {
                    ForEach(ScreenDimmer.Follow.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Toggle(isOn: $dimsFullScreen) {
                    Text(L("Dim full-screen apps too"))
                    Text(L("Off, a video or app in full screen on another display stays bright."))
                }
            } header: {
                Text(L("Behavior"))
            } footer: {
                if follow == ScreenDimmer.Follow.focusedWindow.rawValue {
                    Text(L("Following the focused window needs Accessibility; without it, the pointer decides."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!dimmer.isEnabled)
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if !dimmer.hasSeveralScreens {
            return L("Only one display is connected: it starts working when you connect another.")
        }
        return dimmer.isEnabled ? L("On: \(dimmer.screenCount) displays") : L("Turned off")
    }
}
