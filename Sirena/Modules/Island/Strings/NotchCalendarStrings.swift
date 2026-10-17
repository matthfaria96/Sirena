// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCalendarStrings {
    let title: String
    let description: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let empty: String
    let next: String
    let ongoing: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let week: String
    let today: String
    let requestFailed: String
    let previousMonth: String
    let nextMonth: String
    let previousWeek: String
    let nextWeek: String
    /// The month grid, offered from the week strip of a short island.
    let month: String
    let emptyDay: String
    let hasEvents: String
    let countdown: String
    let countdownHint: String
    /// An event's menu in the island, to count down to that event alone.
    let addCountdown: String
    let removeCountdown: String
    /// Counts the event under way down to its end.
    let timeLeft: String
    let timeLeftHint: String
    /// Numbers each week of the month grid, as Calendar can.
    let weekNumbers: String
    /// Read out for each of those numbers, which the grid shows bare.
    let weekNumber: String
    /// Heads the per-calendar checkboxes in Settings.
    let calendars: String
}

extension IslandStrings {
    static func notchCalendar(_ language: IslandLanguage) -> NotchCalendarStrings {
        return NotchCalendarStrings(
            title: L("Calendar"),
            description: L("Browse the month and your upcoming appointments in the Dynamic Island."),
            permission: L("Read your calendars to show upcoming appointments. Events stay on this Mac."),
            allow: L("Allow Calendar Access"),
            denied: L("Allow calendar access in System Settings to see your appointments."),
            settings: L("Open System Settings"),
            empty: L("No upcoming appointments"),
            next: L("Up next"),
            ongoing: L("Happening now"),
            allDay: L("All day"),
            untitled: L("Untitled event"),
            openCalendar: L("Open Calendar"),
            week: L("Next 7 days"),
            today: L("Today"),
            requestFailed: L("Could not request calendar access. Please try again."),
            previousMonth: L("Previous month"),
            nextMonth: L("Next month"),
            previousWeek: L("Previous week"),
            nextWeek: L("Next week"),
            month: L("Month"),
            emptyDay: L("No appointments on this day"),
            hasEvents: L("Has appointments"),
            countdown: L("Event countdown"),
            countdownHint: L("Show every timed event in the closed island during the hour before it starts. To count down to only some, turn this off and right-click them on the island’s Calendar page. Titles may appear in screen captures."),
            addCountdown: L("Add Countdown"),
            removeCountdown: L("Remove Countdown"),
            timeLeft: L("Time left in current event"),
            timeLeftHint: L("Show a timed event in progress in the closed island during the hour before it ends. Its title may appear in screen captures."),
            weekNumbers: L("Week numbers"),
            weekNumber: L("Week %d"),
            calendars: L("Calendars shown"))
    }
}
