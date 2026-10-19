/// PomodoroPage.swift

import SwiftUI

struct PomodoroPage: View {
    @State private var controller = PomodoroController.shared

    var body: some View {
        ModulePage(module: .pomodoro, tabs: [
            PageTab("timer", L("Timer")) { PomodoroTimerView() },
            PageTab("settings", L("Settings")) { PomodoroSettingsView() },
            PageTab("shortcuts", L("Shortcuts")) { PomodoroShortcutsView() }
        ]) {
            Button { controller.quickAction() } label: {
                Label(controller.isTicking ? L("Pause") : (controller.hasStarted ? L("Resume") : L("Start \(controller.phase.title)")),
                      systemImage: controller.isTicking ? "pause.fill" : "play.fill")
            }
            .compatGlassProminentButtonStyle()
            .tint(controller.phase.color)
            .disabled(!controller.isRunning)
        }
    }
}

// MARK: - Timer

private struct PomodoroTimerView: View {
    @State private var controller = PomodoroController.shared
    @State private var settings = PomodoroSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !controller.isRunning {
                    Label(L("Turn on Pomodoro to use the timer."), systemImage: "power")
                        .foregroundStyle(.secondary)
                }
                Picker("", selection: Binding(get: { controller.phase }, set: { controller.select($0) })) {
                    Text(PomodoroPhase.focus.title).tag(PomodoroPhase.focus)
                    Text(PomodoroPhase.shortBreak.title).tag(PomodoroPhase.shortBreak)
                    Text(PomodoroPhase.longBreak.title).tag(PomodoroPhase.longBreak)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                ring

                HStack(spacing: 14) {
                    Button { controller.restartPhase() } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 28)
                    }
                    .help(L("Restart this phase"))
                    .disabled(!controller.hasStarted)

                    Button { controller.quickAction() } label: {
                        Label(controller.isTicking ? L("Pause") : (controller.hasStarted ? L("Resume") : L("Start")),
                              systemImage: controller.isTicking ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(minWidth: 120, minHeight: 28)
                    }
                    .compatGlassProminentButtonStyle()
                    .tint(controller.phase.color)
                    .keyboardShortcut(.space, modifiers: [])

                    Button { controller.skip() } label: {
                        Image(systemName: "forward.end.fill").frame(width: 28, height: 28)
                    }
                    .help(L("Skip to the next phase"))
                }
                .compatGlassButtonStyle()
                .controlSize(.large)

                stats
            }
            .disabled(!controller.isRunning)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(controller.phase.color.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: controller.progress)
                .stroke(controller.phase.color.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: controller.progress)
            VStack(spacing: 6) {
                Label(controller.phase.title, systemImage: controller.phase.symbol)
                    .font(.headline)
                    .foregroundStyle(controller.phase.color)
                Text(controller.remainingText)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(cycleText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, height: 260)
        .padding(20)
        .compatGlass(in: .circle)
    }

    private var cycleText: String {
        let total = max(1, settings.sessionsBeforeLongBreak)
        return L("Session \(min(controller.cycleCount + (controller.phase == .focus ? 1 : 0), total)) of \(total)")
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statCard(L("Today"), value: "\(controller.todayCount)", detail: L("of \(settings.dailyGoal) sessions"), symbol: "checkmark.circle.fill")
            statCard(L("Focused"), value: focusedText, detail: L("today"), symbol: "clock.fill")
        }
        .frame(maxWidth: 420)
    }

    private var focusedText: String {
        let minutes = Int(controller.todayFocusSeconds) / 60
        return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    private func statCard(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .compatGlass(in: .rect(cornerRadius: 16))
    }
}

// MARK: - Settings

private struct PomodoroSettingsView: View {
    @State private var settings = PomodoroSettings.shared
    @State private var controller = PomodoroController.shared

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.focusMinutes, in: 1...120) {
                    LabeledContent(L("Focus"), value: L("\(settings.focusMinutes) min"))
                }
                Stepper(value: $settings.shortBreakMinutes, in: 1...60) {
                    LabeledContent(L("Short Break"), value: L("\(settings.shortBreakMinutes) min"))
                }
                Stepper(value: $settings.longBreakMinutes, in: 1...90) {
                    LabeledContent(L("Long Break"), value: L("\(settings.longBreakMinutes) min"))
                }
                Stepper(value: $settings.sessionsBeforeLongBreak, in: 1...12) {
                    LabeledContent(L("Sessions before a long break"), value: "\(settings.sessionsBeforeLongBreak)")
                }
            } header: {
                Text(L("Durations"))
            }
            .onChange(of: settings.focusMinutes) { controller.settingsChanged() }
            .onChange(of: settings.shortBreakMinutes) { controller.settingsChanged() }
            .onChange(of: settings.longBreakMinutes) { controller.settingsChanged() }

            Section {
                Toggle(isOn: $settings.autoStartBreaks) {
                    Text(L("Start Breaks Automatically"))
                    Text(L("A break begins as soon as a focus session ends."))
                }
                Toggle(isOn: $settings.autoStartFocus) {
                    Text(L("Start Focus Automatically"))
                    Text(L("The next focus session begins as soon as a break ends."))
                }
            } header: {
                Text(L("Flow"))
            }

            Section {
                Toggle(L("Play a Sound"), isOn: $settings.playSound)
                if settings.playSound {
                    Picker(L("Sound"), selection: $settings.soundName) {
                        ForEach(PomodoroSettings.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: settings.soundName) { settings.playPreview() }
                    LabeledContent(L("Volume")) {
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $settings.soundVolume, in: 0...1) { editing in
                                if !editing { settings.playPreview() }
                            }
                            .frame(width: 180)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $settings.showNotifications.onSet { if $0 { controller.requestNotificationAuthorization() } }) {
                    Text(L("Show Notifications"))
                    Text(L("Announce the end of each focus session and break."))
                }
            } header: {
                Text(L("Alerts"))
            }

            Section {
                Stepper(value: $settings.dailyGoal, in: 1...24) {
                    LabeledContent(L("Daily Goal"), value: L("\(settings.dailyGoal) sessions"))
                }
                LabeledContent(L("Completed Today")) {
                    Text("\(controller.todayCount)").monospacedDigit().foregroundStyle(.secondary)
                    Button(L("Clear")) { controller.clearToday() }
                        .disabled(controller.todayCount == 0 && controller.todayFocusSeconds == 0)
                }
            } header: {
                Text(L("Goal"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct PomodoroShortcutsView: View {
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                ShortcutRow(title: L("Start / pause"), defaultsKey: PomodoroController.toggleShortcutKey,
                            recordingObserver: recordingObserver)
                ShortcutRow(title: L("Skip to the next phase"), defaultsKey: PomodoroController.skipShortcutKey,
                            recordingObserver: recordingObserver)
            } header: {
                Text(L("Global Shortcuts"))
            }
        }
        .formStyle(.grouped)
    }
}

private extension Binding {
    func onSet(_ action: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action($0) })
    }
}
