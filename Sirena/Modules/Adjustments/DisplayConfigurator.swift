/// DisplayConfigurator.swift
///
/// Ajustes › Monitores: the displays connected now, which one is the main display, each one's
/// resolution (macOS's scaled "looks like" sizes) and refresh rate, and mirroring. Everything
/// goes through Core Graphics' display configuration, saved like System Settings does
/// (`.permanently`). A new resolution is undone by itself after a few seconds unless the user
/// keeps it, like macOS does: a mode the display can't show must never leave it black.

import AppKit
import OSLog

struct DisplayModeOption: Identifiable, Hashable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let refresh: Double
    let mode: CGDisplayMode

    var id: String { "\(width)x\(height)@\(Int(refresh.rounded()))/\(pixelWidth)" }
    var isHiDPI: Bool { pixelWidth > width }
    var sizeKey: String { "\(width)x\(height)" }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let isBuiltin: Bool
    let current: DisplayModeOption?
    /// One per "looks like" size, largest first.
    let sizes: [DisplayModeOption]
    /// The refresh rates offered at the current size.
    let refreshRates: [DisplayModeOption]
}

@MainActor
@Observable
final class DisplayConfigurator {
    static let shared = DisplayConfigurator()

    private static let log = os.Logger(subsystem: "com.matheusfaria.Sirena", category: "Adjustments")
    static let revertSeconds = 15

    private(set) var displays: [DisplayInfo] = []
    private(set) var isMirroring = false
    /// A resolution waiting for "Keep": the display, the mode to go back to, seconds left.
    private(set) var pending: (display: CGDirectDisplayID, previous: CGDisplayMode, secondsLeft: Int)?

    private var countdown: Timer?
    private var screenObserver: NSObjectProtocol?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func reload() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        ids = Array(ids.prefix(Int(count)))
        isMirroring = ids.contains { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
        // A display mirroring another follows it: only the ones drawing their own picture.
        displays = ids.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map(Self.info(for:))
            .sorted { ($0.isMain ? 0 : 1, $0.name) < ($1.isMain ? 0 : 1, $1.name) }
    }

    private static func info(for id: CGDirectDisplayID) -> DisplayInfo {
        let name = NSScreen.screens.first { ScreenIdentity.displayID(of: $0) == id }?.localizedName
            ?? (CGDisplayIsBuiltin(id) != 0 ? L("Built-in Display") : L("Display"))
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }
            .map(option(for:))
        let current = CGDisplayCopyDisplayMode(id).map(option(for:))

        // One entry per size: the sharpest (HiDPI first), at the refresh rate in use if it has it.
        var bySize: [String: DisplayModeOption] = [:]
        for mode in modes {
            guard let best = bySize[mode.sizeKey] else { bySize[mode.sizeKey] = mode; continue }
            if better(mode, than: best, currentRefresh: current?.refresh) { bySize[mode.sizeKey] = mode }
        }
        if let current { bySize[current.sizeKey] = current }
        let sizes = bySize.values.sorted { ($0.width, $0.height) > ($1.width, $1.height) }

        var refreshRates: [DisplayModeOption] = []
        if let current {
            var seen = Set<Int>()
            for mode in modes.sorted(by: { $0.refresh > $1.refresh })
            where mode.sizeKey == current.sizeKey && mode.pixelWidth == current.pixelWidth && mode.refresh > 0 {
                if seen.insert(Int(mode.refresh.rounded())).inserted { refreshRates.append(mode) }
            }
            if !refreshRates.contains(where: { Int($0.refresh.rounded()) == Int(current.refresh.rounded()) }) {
                refreshRates.insert(current, at: 0)
            }
        }
        return DisplayInfo(id: id, name: name, isMain: CGDisplayIsMain(id) != 0, isBuiltin: CGDisplayIsBuiltin(id) != 0,
                           current: current, sizes: sizes, refreshRates: refreshRates)
    }

    private static func option(for mode: CGDisplayMode) -> DisplayModeOption {
        DisplayModeOption(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                          refresh: mode.refreshRate, mode: mode)
    }

    private static func better(_ a: DisplayModeOption, than b: DisplayModeOption, currentRefresh: Double?) -> Bool {
        if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
        if a.pixelWidth != b.pixelWidth { return a.pixelWidth > b.pixelWidth }
        if let currentRefresh {
            let aMatches = abs(a.refresh - currentRefresh) < 0.5
            let bMatches = abs(b.refresh - currentRefresh) < 0.5
            if aMatches != bMatches { return aMatches }
        }
        return a.refresh > b.refresh
    }

    // MARK: - Changing things

    /// A new resolution or refresh rate; undone after `revertSeconds` unless kept.
    func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) {
        guard let previous = pending?.display == display ? pending?.previous : CGDisplayCopyDisplayMode(display) else { return }
        guard configure({ CGConfigureDisplayWithDisplayMode($0, display, option.mode, nil) }) else { return }
        pending = (display, previous, Self.revertSeconds)
        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        reload()
    }

    func keepPending() {
        countdown?.invalidate()
        countdown = nil
        pending = nil
    }

    func revertPending() {
        countdown?.invalidate()
        countdown = nil
        guard let pending else { return }
        self.pending = nil
        configure { CGConfigureDisplayWithDisplayMode($0, pending.display, pending.previous, nil) }
        reload()
    }

    private func tick() {
        guard let current = pending else { countdown?.invalidate(); return }
        if current.secondsLeft <= 1 {
            revertPending()
        } else {
            pending = (current.display, current.previous, current.secondsLeft - 1)
        }
    }

    /// Makes `display` the main one (menu bar, Dock and new windows), keeping the arrangement.
    func makeMain(_ display: CGDirectDisplayID) {
        let target = CGDisplayBounds(display).origin
        guard target != .zero else { return }
        let active = Self.activeDisplays()
        configure { config in
            for id in active {
                let bounds = CGDisplayBounds(id)
                CGConfigureDisplayOrigin(config, id, Int32(bounds.minX - target.x), Int32(bounds.minY - target.y))
            }
        }
        reload()
    }

    /// Every other display shows the main one (on), or each its own picture again (off).
    func setMirroring(_ on: Bool) {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        let main = CGMainDisplayID()
        configure { config in
            for id in ids.prefix(Int(count)) where id != main {
                CGConfigureDisplayMirrorOfDisplay(config, id, on ? main : kCGNullDirectDisplay)
            }
        }
        reload()
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count))).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }

    @discardableResult
    private func configure(_ changes: (CGDisplayConfigRef) -> Void) -> Bool {
        // Screenshots for the site never touch the real displays.
        guard !Showcase.isActive else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        changes(config)
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result != .success {
            Self.log.error("Display configuration failed: \(result.rawValue, privacy: .public)")
            return false
        }
        return true
    }
}
