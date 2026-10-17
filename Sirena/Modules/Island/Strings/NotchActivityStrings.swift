// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchActivityStrings {
    let timer: String
    let timerDescription: String
    let pomodoro: String
    let stopwatch: String
    let focus: String
    let shortBreak: String
    let longBreak: String
    let pomodoroHint: String
    let totalSessions: String
    let longBreakInterval: String
    let sessionProgress: String
    let pomodoroFinished: String
    let minutes: String
    let start: String
    let resume: String
    let finished: String
    let soundEnabled: String
    let hideTimerCountdown: String
    let camera: String
    let cameraUnavailable: String
    let cameraHint: String
    let startCamera: String
    let stopCamera: String
    let accessories: String
    let accessoryDescription: String
    let connected: String
    let lowBattery: String
    let keepAwakeActivity: String
    let keepAwakeActivityHint: String

    func phase(_ phase: NotchTimerPhase) -> String {
        switch phase {
        case .timer: return timer
        case .stopwatch: return stopwatch
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

extension IslandStrings {
    static func notchActivities(_ language: IslandLanguage) -> NotchActivityStrings {
        return NotchActivityStrings(
            timer: L("Timer"),
            timerDescription: L("Timers, a stopwatch and focused work sessions in the Dynamic Island."),
            pomodoro: L("Pomodoro"),
            stopwatch: L("Stopwatch"),
            focus: L("Focus"),
            shortBreak: L("Short break"),
            longBreak: L("Long break"),
            pomodoroHint: L("Start each phase when you are ready. The cycle ends after the last focus session."),
            totalSessions: L("Total sessions"),
            longBreakInterval: L("Sessions between long breaks"),
            sessionProgress: L("Session %d of %d"),
            pomodoroFinished: L("Pomodoro complete"),
            minutes: L("Minutes"),
            start: L("Start"),
            resume: L("Resume"),
            finished: L("Time is up"),
            soundEnabled: L("Play sound when time is up"),
            hideTimerCountdown: L("Hide timer countdown"),
            camera: L("Camera mirror"),
            cameraUnavailable: L("The camera could not start. Try opening it again."),
            cameraHint: L("Open a live mirror here. The camera stops when you leave this view."),
            startCamera: L("Open camera"),
            stopCamera: L("Stop camera"),
            accessories: L("Accessory alerts"),
            accessoryDescription: L("Show connected accessories and warn once when their battery falls to 20%."),
            connected: L("Connected"),
            lowBattery: L("Low battery"),
            keepAwakeActivity: L("Show “Keep awake” in the closed island"),
            keepAwakeActivityHint: L("A running session appears beside the camera with the time it has left, or ∞ when it has no end."))
    }
}
