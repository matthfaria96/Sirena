/// KeepAwakePage.swift
///
/// Caffeine's preferences and controls, rebuilt for Sirena's main window.

import SwiftUI

struct KeepAwakePage: View {
    @ObservedObject var viewModel: CaffeineViewModel

    var body: some View {
        ModulePage(module: .keepAwake, tabs: [
            PageTab("general", L("General")) { KeepAwakeSettings(viewModel: viewModel) }
        ])
    }
}

struct KeepAwakeSettings: View {
    @ObservedObject var viewModel: CaffeineViewModel
    @AppStorage(PreferenceKeys.defaultDuration) private var defaultDuration = 0
    @AppStorage(PreferenceKeys.activateAtLaunch) private var activateAtLaunch = false
    @AppStorage(PreferenceKeys.deactivateOnManualSleep) private var deactivateOnManualSleep = false
    @AppStorage(PreferenceKeys.keepAppsActive) private var keepAppsActive = false

    private let durations: [(minutes: Int, title: String)] = [
        (5, String(localized: "5 minutes")),
        (10, String(localized: "10 minutes")),
        (15, String(localized: "15 minutes")),
        (30, String(localized: "30 minutes")),
        (60, String(localized: "1 hour")),
        (120, String(localized: "2 hours")),
        (300, String(localized: "5 hours")),
        (0, String(localized: "Indefinitely"))
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: viewModel.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 34))
                        .foregroundStyle(viewModel.isActive ? Color.brown : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isActive ? L("Your Mac is staying awake") : L("Your Mac can sleep normally"))
                            .font(.headline)
                        Text(viewModel.formattedTimeRemaining() ?? L("Click the cup in the menu bar to switch it on, or use the button here."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(viewModel.isActive ? L("Turn Off") : L("Turn On")) {
                        viewModel.toggleActive()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isActive ? .gray : .brown)
                    .controlSize(.large)
                }
                .padding(.vertical, 6)

            }

            Section {
                Picker(String(localized: "Default duration:"), selection: $defaultDuration) {
                    ForEach(durations, id: \.minutes) { duration in
                        Text(duration.title).tag(duration.minutes)
                    }
                }
                Toggle(L("Turn on when Sirena starts"), isOn: $activateAtLaunch)
                Toggle(String(localized: "Deactivate when device goes to sleep manually"), isOn: $deactivateOnManualSleep)
            } header: {
                Text(L("Behavior"))
            }

            Section {
                Toggle(isOn: Binding(
                    get: { keepAppsActive },
                    set: { newValue in
                        keepAppsActive = newValue
                        viewModel.updateActivitySimulation(enabled: newValue)
                    }
                )) {
                    Text(String(localized: "Keep apps active"))
                    Text(String(localized: "Prevents apps from becoming inactive and the screen saver from starting."))
                }
            } header: {
                Text(L("Activity"))
            } footer: {
                Text(L("Right-click (or ⌃-click) the cup in the menu bar for more options."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
