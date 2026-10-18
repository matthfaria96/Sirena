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

    private var durations: [(minutes: Int, title: String)] { KeepAwakeModule.durations }

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
                        Text(viewModel.formattedTimeRemaining() ?? L("Turn it on here or in the menu bar menu, under “Keep Display On”."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(viewModel.isActive ? L("Turn Off") : L("Turn On")) {
                        viewModel.toggleActive()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    .controlSize(.large)
                }
                .padding(.vertical, 6)

            }

            Section {
                Picker(L("Default duration"), selection: $defaultDuration) {
                    ForEach(durations, id: \.minutes) { duration in
                        Text(duration.title).tag(duration.minutes)
                    }
                }
                Toggle(L("Turn on when Sirena starts"), isOn: $activateAtLaunch)
                Toggle(L("Deactivate when device goes to sleep manually"), isOn: $deactivateOnManualSleep)
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
                    Text(L("Keep apps active"))
                    Text(L("Prevents apps from becoming inactive and the screen saver from starting."))
                }
            } header: {
                Text(L("Activity"))
            }
        }
        .formStyle(.grouped)
    }
}
