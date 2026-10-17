// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena from RadialMenuSupport.swift, RadialNowPlayingService.swift,
// ActivationHandoff.swift and ShellSupport.swift.

import AppKit
import Foundation

struct IslandNowPlayingSnapshot: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?

    var radialLabel: String? {
        let parts = [title, artist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

enum IslandNowPlayingSupport {
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)
    /// The one artwork cap. The adapter (`Sources/NowPlayingAdapter`) drops
    /// artwork above it before encoding, and the bridge's pipe cap is
    /// `maximumAdapterReplyBytes`, sized so the base64 line (4/3 of the bytes,
    /// so 16 MB) plus the other keys fits.
    static let maximumArtworkBytes = 12 * 1_024 * 1_024
    static let maximumAdapterReplyBytes = maximumArtworkBytes / 3 * 4 + 1_024 * 1_024

    static func playbackIsActive(remoteIsPlaying: Bool?, info: [String: Any]) -> Bool {
        if let remoteIsPlaying { return remoteIsPlaying }
        return (info[playbackRateKey] as? NSNumber)?.doubleValue ?? 0 > 0
    }

    /// One reply from the Now Playing adapter (`Resources/now-playing.pl`):
    /// the MediaRemote metadata keys it forwards, plus the owning app and the
    /// remote's own playing flag, in the shape `snapshot(info:...)` reads.
    struct AdapterReply {
        let info: [String: Any]
        let pid: Int32
        let displayID: String?
        let isPlaying: Bool?
    }

    /// Parses the adapter's JSON line, the last non-blank line of the run's
    /// output: stderr shares the pipe, so a perl warning (a locale it cannot
    /// set, say) can precede it. Artwork arrives base64-encoded under
    /// `artworkBase64` and is handed on as `artworkDataKey` bytes. An `error`
    /// key, a non-object or unreadable bytes read as no reply.
    static func adapterReply(from data: Data) -> AdapterReply? {
        let blank: Set<UInt8> = [0x20, 0x09, 0x0D]
        guard let line = data.split(separator: 0x0A).last(where: { $0.contains { !blank.contains($0) } }),
              let object = try? JSONSerialization.jsonObject(with: line),
              let fields = object as? [String: Any],
              fields["error"] == nil else { return nil }
        var info: [String: Any] = [:]
        for key in [titleKey, artistKey, albumKey] {
            if let value = fields[key] as? String { info[key] = value }
        }
        for key in [playbackRateKey, "kMRMediaRemoteNowPlayingInfoDuration",
                    "kMRMediaRemoteNowPlayingInfoElapsedTime"] {
            if let value = fields[key] as? NSNumber { info[key] = value }
        }
        if fields["artworkUnchanged"] as? Bool == true { info["artworkUnchanged"] = true }
        for key in ["canSeek", "canSkipNext", "canSkipPrevious"] {
            if let value = fields[key] as? Bool { info[key] = value }
        }
        if let identifier = fields["itemIdentifier"] as? String, !identifier.isEmpty,
           identifier.utf8.count <= 512, !identifier.contains("\0") { info["itemIdentifier"] = identifier }
        if let artwork = fields["artworkBase64"] as? String,
           let bytes = Data(base64Encoded: artwork), !bytes.isEmpty {
            info[artworkDataKey] = bytes
        }
        return AdapterReply(info: info,
                            pid: (fields["pid"] as? NSNumber)?.int32Value ?? 0,
                            displayID: fields["displayID"] as? String,
                            isPlaying: fields["isPlaying"] as? Bool)
    }

    static func snapshot(info: [String: Any],
                         isPlaying: Bool,
                         appBundleIdentifier: String?,
                         appPID: Int32) -> IslandNowPlayingSnapshot? {
        guard isPlaying else { return nil }
        let title = sanitizedText(info[titleKey])
        let artist = sanitizedText(info[artistKey])
        let album = sanitizedText(info[albumKey])
        let bundleIdentifier = sanitizedBundleIdentifier(appBundleIdentifier)
        let pid = appPID > 0 ? appPID : nil
        let artworkData = sanitizedArtworkData(info[artworkDataKey])
        guard title != nil || bundleIdentifier != nil || pid != nil else { return nil }
        return IslandNowPlayingSnapshot(title: title,
                                        artist: artist,
                                        album: album,
                                        artworkData: artworkData,
                                        appBundleIdentifier: bundleIdentifier,
                                        appPID: pid)
    }

    private static func sanitizedText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clean = String(String.UnicodeScalarView(
            trimmed.unicodeScalars.filter { !forbiddenScalars.contains($0) }))
        return clean.isEmpty ? nil : String(clean.prefix(300))
    }

    private static func sanitizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) })
        else { return nil }
        return trimmed
    }

    private static func sanitizedArtworkData(_ value: Any?) -> Data? {
        guard let data = value as? Data, !data.isEmpty, data.count <= maximumArtworkBytes else {
            return nil
        }
        return data
    }
}

enum IslandNowPlayingApplication {
    private static var icons: [String: NSImage] = [:]
    private static var missingIcons = Set<String>()

    static func runningApplication(for snapshot: IslandNowPlayingSnapshot) -> NSRunningApplication? {
        if let bundleIdentifier = snapshot.appBundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return application
        }
        if let pid = snapshot.appPID {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
    }

    static func name(for snapshot: IslandNowPlayingSnapshot) -> String? {
        if let name = runningApplication(for: snapshot)?.localizedName, !name.isEmpty { return name }
        guard let identifier = snapshot.appBundleIdentifier else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    static func icon(for snapshot: IslandNowPlayingSnapshot) -> NSImage? {
        let key = snapshot.appBundleIdentifier ?? snapshot.appPID.map { "pid:\($0)" } ?? ""
        if let icon = icons[key] { return icon }
        if missingIcons.contains(key) { return nil }
        let icon: NSImage?
        if let runningIcon = runningApplication(for: snapshot)?.icon {
            icon = runningIcon
        } else if let identifier = snapshot.appBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = nil
        }
        if let icon {
            icons[key] = icon
        } else {
            missingIcons.insert(key)
        }
        return icon
    }

    /// The island and the radial card are non-activating panels, so Vorssaint
    /// rarely holds activation when one is clicked. Since macOS 14 a bare
    /// request from an inactive app is refused, and the player stayed behind.
    static func open(_ snapshot: IslandNowPlayingSnapshot) {
        if let application = runningApplication(for: snapshot) {
            // A helper takes no activation; the handoff would leave Vorssaint in front.
            guard application.activationPolicy == .regular else { return }
            // Read before the unhide below: a hidden player's windows come back with it.
            let showsNoWindow = !application.isHidden && !hasWindowOnScreen(pid: application.processIdentifier)
            if application.isHidden { application.unhide() }
            IslandActivationHandoff.yield(to: application)
            if !application.activate(from: NSRunningApplication.current, options: [.activateAllWindows]) {
                application.activate(options: [.activateAllWindows])
            }
            // Like a Dock click, a player that keeps playing with its window
            // closed shows one again, the way the App Switcher reopens a
            // windowless app. Activation alone would leave nothing to see.
            if showsNoWindow, let url = application.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Whether the player has a window on the current Space. One on another
    /// Space reads as none, and the reopen that follows is harmless there.
    private static func hasWindowOnScreen(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}

enum IslandActivationHandoff {
    /// Our own activation notification arrives within a turn of the request.
    /// Past that, an activation of Vorssaint is the user opening one of its
    /// windows, which is a real use and stays in the switcher's history.
    private static let selfActivationWindow: CFTimeInterval = 1

    private static var lastSelfActivation: CFAbsoluteTime = 0

    /// Whether the activation of Vorssaint being reported right now is the one
    /// `yield(to:)` asked for on its way out. Main thread, like every `NSApp`
    /// call here and like the activation notifications that read it.
    static var isHandingOff: Bool {
        CFAbsoluteTimeGetCurrent() - lastSelfActivation < selfActivationWindow
    }

    static func yield(to app: NSRunningApplication) {
        lastSelfActivation = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.yieldActivation(to: app)
    }
}

enum IslandAppleScriptRunner {
    /// True when this app may script `bundleID`. Undetermined → shows the system
    /// prompt (attributed to this app); granted → returns at once; denied →
    /// false without nagging.
    @discardableResult
    static func consentToAutomate(bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(typeApplicationBundleID, ptr, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true) == noErr
    }

    /// Runs the AppleScript in this process. Returns whether it succeeded and the
    /// result string (or the error message on failure). Sending the event in
    /// process itself triggers the Automation prompt when consent is undetermined.
    @discardableResult
    static func run(_ source: String) -> (ok: Bool, output: String) {
        let result = runDetailed(source)
        return (result.ok, result.ok ? result.output : result.message)
    }

    /// Same as `run`, keeping the AppleScript error number so callers can tell
    /// a declined Automation consent (-1743/-1744) apart from a real failure.
    @discardableResult
    static func runDetailed(_ source: String) -> (ok: Bool, errorNumber: Int?, message: String, output: String) {
        guard let script = NSAppleScript(source: source) else { return (false, nil, "", "") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (false,
                    error[NSAppleScript.errorNumber] as? Int,
                    (error[NSAppleScript.errorMessage] as? String) ?? "",
                    "")
        }
        return (true, nil, "", result.stringValue ?? "")
    }

    /// Escapes a value for embedding inside an AppleScript double-quoted string.
    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
