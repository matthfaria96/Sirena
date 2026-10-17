// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchMascotStrings {
    let title: String
    let hint: String
    let visits: String
    let visitsHint: String
    let style: String
    let minimal: String
    let robot: String
    let shape: String
    let ball: String
    let egg: String
    let squircle: String
    let pill: String
    let color: String
    let pearl: String
    let mint: String
    let peach: String
    let lilac: String
    let lemon: String
    let rose: String
    let commandBar: String
    let commandBarHint: String
    let opensAs: String
    let droplet: String
    let openIsland: String
    /// The Settings preview, for VoiceOver, and what clicking it does.
    let preview: String
    let previewHint: String
    /// Which side of the camera it rests on.
    let side: String
    let left: String
    let right: String
    /// How often it strolls through the island.
    let frequency: String
    let rare: String
    let normal: String
    let frequent: String
    let sky: String
    /// One line for the Features page.
    let hubDescription: String
    let appearance: String
    let behavior: String
    /// Whether it comes out to react to what happens.
    let reactions: String
    let reactionsHint: String
    /// Whether it hides in the island once nothing happens for a while.
    let hidesWhenIdle: String
    let hidesWhenIdleHint: String
    /// The Settings button that has it say hello in the island now.
    let sayHi: String
    let sayHiHint: String
    /// The moments the Settings preview can act out.
    let momentsTitle: String
    let visitMoment: String
    let timerStarted: String
    let downloadFailed: String
    let unlocked: String
    /// How to pet it, and that it dozes off.
    let petTip: String
    /// Said on its page while the Dynamic Island is off.
    let livesInIsland: String
    /// More words a search finds its page by.
    let keywords: String

    func style(_ style: NotchMascotStyle) -> String {
        style == .robot ? robot : minimal
    }

    func shape(_ shape: NotchMascotShape) -> String {
        switch shape {
        case .ball: return ball
        case .egg: return egg
        case .squircle: return squircle
        case .pill: return pill
        }
    }

    func palette(_ palette: NotchMascotPalette) -> String {
        switch palette {
        case .pearl: return pearl
        case .mint: return mint
        case .peach: return peach
        case .lilac: return lilac
        case .lemon: return lemon
        case .rose: return rose
        case .sky: return sky
        }
    }

    func commandBarStyle(_ style: NotchCommandBarStyle) -> String {
        style == .island ? openIsland : droplet
    }

    func side(_ side: NotchMascotSide) -> String {
        side == .right ? right : left
    }

    /// A moment's name. Those the island already names elsewhere say it the
    /// same way here.
    func moment(_ moment: NotchMascotMoment, language: IslandLanguage) -> String {
        switch moment {
        case .visit: return visitMoment
        case .timerStarted: return timerStarted
        case .timeIsUp: return IslandStrings.notchActivities(language).finished
        case .music: return IslandStrings.radialMenu(language).mediaNowPlaying
        case .eventStarts: return IslandStrings.notchCalendar(language).ongoing
        case .downloadFinished: return IslandStrings.notchFiles(language).completed
        case .downloadFailed: return downloadFailed
        case .micMuted: return IslandCommonStrings().micMutedHUD
        case .keepAwake: return IslandCommonStrings().keepAwakeTitle
        case .charging: return IslandStrings.notch(language).charging
        case .lowBattery: return IslandStrings.notch(language).lowBattery
        case .unlocked: return unlocked
        }
    }

    /// What a search finds its page by, besides its name.
    var searchKeywords: [String] {
        [hint, visits, reactions, hidesWhenIdle, style, robot, shape, color, side, frequency, commandBar, keywords]
    }

    func frequency(_ frequency: NotchMascotVisitFrequency) -> String {
        switch frequency {
        case .rare: return rare
        case .normal: return normal
        case .frequent: return frequent
        }
    }
}

extension IslandStrings {
    static func notchMascot(_ language: IslandLanguage) -> NotchMascotStrings {
        return NotchMascotStrings(
            title: L("Companion"),
            hint: L("A little friend who lives in the Dynamic Island. It rests there when nothing else is showing, and comes out over music and activities to say hello and react to what happens."),
            visits: L("Appear now and then"),
            visitsHint: L("Every few minutes it passes through the island with a short animation."),
            style: L("Style"), minimal: L("Minimal"), robot: L("Robot"),
            shape: L("Shape"), ball: L("Ball"), egg: L("Egg"), squircle: L("Rounded square"), pill: L("Pill"),
            color: L("Color"), pearl: L("Pearl"), mint: L("Mint"), peach: L("Peach"), lilac: L("Lilac"), lemon: L("Lemon"), rose: L("Rose"),
            commandBar: L("Command Bar in the island"),
            commandBarHint: L("With the shortcut, the Command Bar comes out of the island with the companion as its face. It reacts while you search."),
            opensAs: L("Opens as"), droplet: L("Drop"), openIsland: L("Open island"),
            preview: L("Companion preview"), previewHint: L("Click to see it react."),
            side: L("Side of the camera"), left: L("Left"), right: L("Right"),
            frequency: L("How often"), rare: L("Rarely"), normal: L("Sometimes"), frequent: L("Often"),
            sky: L("Sky"),
            hubDescription: L("A little friend in the Dynamic Island who says hello now and then and reacts to what happens on your Mac."),
            appearance: L("Appearance"), behavior: L("Behavior"),
            reactions: L("React to what happens"),
            reactionsHint: L("It comes out to react to music, timers, downloads, screenshots, the microphone, Keep awake and more."),
            hidesWhenIdle: L("Hide when idle"),
            hidesWhenIdleHint: L("After half a minute with nothing going on, it hops into the island and the island goes back to its usual size. Visits and reactions still bring it out."),
            sayHi: L("Say Hi"), sayHiHint: L("Plays a visit in the Dynamic Island now."),
            momentsTitle: L("See how it reacts"),
            visitMoment: L("A visit"), timerStarted: L("Timer started"), downloadFailed: L("Download failed"), unlocked: L("Mac unlocked"),
            petTip: L("Rest the pointer on it to pet it. Left alone, it dozes off until you come back."),
            livesInIsland: L("The companion lives in the Dynamic Island."),
            keywords: L("mascot pet buddy character"))
    }
}
