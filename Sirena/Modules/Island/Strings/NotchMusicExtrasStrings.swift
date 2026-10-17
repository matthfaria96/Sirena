// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchMusicExtrasStrings {
    let lyrics: String
    let lyricsDescription: String
    let enableLyrics: String
    let online: String
    let onlineHint: String
    let importLyrics: String
    let importHint: String
    let loading: String
    let unavailable: String
    let failed: String
    let retry: String
    let instrumental: String
    let waiting: String
    let noPosition: String
    let offset: String
    let earlier: String
    let later: String
    let reset: String
    let actionFailed: String
    let playbackFailed: String
    let allowPlayback: String
    let automationPermission: String
    let automationExplanation: String
    let queue: String
    let queueDescription: String
    let enableQueue: String
    let queueUnavailable: String
    let queueEmpty: String
    let playNow: String
    let refresh: String
    let openPlayer: String
    let playbackSource: String
    let automaticSource: String
    let includeOtherPlayers: String
    let liveEqualizer: String
    /// One line for the features hub, where the hint below would not fit.
    let liveEqualizerDescription: String
    let liveEqualizerHint: String
    let liveEqualizerUnavailable: String
    let shuffle: String
    let preferredPlayer: String
    let preferredPlayerHint: String
    /// "Open Spotify", with the app's name in place of %@.
    let openNamedPlayer: String
    let browserCovers: String
    let browserCoversHint: String
}

extension IslandStrings {
    static func notchMusicExtras(_ language: IslandLanguage) -> NotchMusicExtrasStrings {
        return NotchMusicExtrasStrings(
            lyrics: L("Lyrics"),
            lyricsDescription: L("Follow the lyrics of the current song in the Dynamic Island."),
            enableLyrics: L("Show lyrics"),
            online: L("Find lyrics online"),
            onlineHint: L("While lyrics are open, send the song title, artist, album and duration to lrclib.net. Imported lyrics stay on this Mac. Song titles, artist names and albums may also be checked with musicbrainz.org."),
            importLyrics: L("Import lyrics…"),
            importHint: L("Choose timed lyrics for the current recording. They are kept only while this song is open."),
            loading: L("Loading lyrics…"),
            unavailable: L("No matching lyrics for this recording."),
            failed: L("Could not load the lyrics."),
            retry: L("Try again"),
            instrumental: L("Instrumental"),
            waiting: L("Waiting for the first verse"),
            noPosition: L("The player does not share its position."),
            offset: L("Timing"),
            earlier: L("Earlier"),
            later: L("Later"),
            reset: L("Reset"),
            actionFailed: L("The player did not switch to this song."),
            playbackFailed: L("Could not change playback."),
            allowPlayback: L("Allow playback control"),
            automationPermission: L("Playback automation"),
            automationExplanation: L("Some music apps require permission for their playback controls. Authorize the selected player from Dynamic Island; access is granted separately for each app."),
            queue: L("Up next"),
            queueDescription: L("See the actual upcoming songs shared by your player."),
            enableQueue: L("Show upcoming songs"),
            queueUnavailable: L("This player does not share its upcoming songs."),
            queueEmpty: L("No upcoming songs"),
            playNow: L("Play now"),
            refresh: L("Refresh"),
            openPlayer: L("Open player"),
            playbackSource: L("Playback source"),
            automaticSource: L("Automatic"),
            includeOtherPlayers: L("Automatically include videos and other apps"),
            liveEqualizer: L("Bars follow the music"),
            liveEqualizerDescription: L("Move the Dynamic Island bars with the sound your player makes."),
            liveEqualizerHint: L("Listens to the player’s own audio output to move the bars. macOS asks once to allow system audio recording. Nothing is stored or sent. Without it, the bars keep their usual motion."),
            liveEqualizerUnavailable: L("Needs macOS 14.4 or later."),
            shuffle: L("Shuffle"),
            preferredPlayer: L("Open when nothing is playing"),
            preferredPlayerHint: L("The cover and the playback buttons open this app. Automatic opens the music app that played last, then Spotify or Apple Music."),
            openNamedPlayer: L("Open %@"),
            browserCovers: L("Find covers for Firefox and Zen"),
            browserCoversHint: L("When Firefox, Zen or another Firefox-based browser plays without a sharp cover, read its saved session on this Mac to find the song’s YouTube tab and load its thumbnail from i.ytimg.com. If no tab shows the song but a YouTube Music tab is open, send the song title, artist and region to itunes.apple.com and load the album art from mzstatic.com."))
    }
}
