/// CaptureSnapshot.swift
///
/// What a screen capture starts from: a still image of every display, taken the moment the
/// key is pressed (so open menus and hover states stay as they were, like Lightshot), and
/// the windows on screen front to back, so a click can pick one whole.

import AppKit
import ScreenCaptureKit

/// A window on screen, in Cocoa global coordinates (bottom-left origin).
struct CaptureWindow: Equatable {
    let id: CGWindowID
    let frame: CGRect
    let owner: String
    let pid: pid_t
}

/// One display as it was when the capture started.
struct CaptureFrame {
    let displayID: CGDirectDisplayID
    /// Cocoa global coordinates.
    let frame: CGRect
    let image: CGImage

    /// Pixels per point of the frozen image.
    var scale: CGFloat { CGFloat(image.width) / max(frame.width, 1) }

    /// The pixels of `image` under a rect in global Cocoa coordinates (rows start at the top).
    func pixelRect(for rect: CGRect) -> CGRect {
        let local = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        return CGRect(x: local.minX * scale, y: (frame.height - local.maxY) * scale,
                      width: local.width * scale, height: local.height * scale).integral
    }

    /// A piece of the frozen image, for a rect in global Cocoa coordinates.
    func crop(_ rect: CGRect) -> CGImage? {
        let pixels = pixelRect(for: rect.intersection(frame))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixels.isEmpty else { return nil }
        return image.cropping(to: pixels)
    }
}

@MainActor
enum CaptureSnapshot {
    /// ScreenCaptureKit's display list is slow to fetch (tens of ms) and rarely changes:
    /// kept until the displays change.
    private static var displays: [CGDirectDisplayID: SCDisplay] = [:]
    private static var screensObserver: NSObjectProtocol?

    /// Every display, frozen. Empty when ScreenCaptureKit refuses (no Screen Recording).
    static func freeze(includingPointer: Bool) async -> [CaptureFrame] {
        observeScreens()
        let screens = NSScreen.screens.map { (id: $0.displayID, frame: $0.frame, scale: $0.backingScaleFactor) }
        if screens.contains(where: { displays[$0.id] == nil }) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
                return []
            }
            displays = Dictionary(content.displays.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        var frames: [CaptureFrame] = []
        await withTaskGroup(of: CaptureFrame?.self) { group in
            for screen in screens {
                guard let display = displays[screen.id] else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = Int((screen.frame.width * screen.scale).rounded())
                configuration.height = Int((screen.frame.height * screen.scale).rounded())
                configuration.showsCursor = includingPointer
                configuration.captureResolution = .best
                configuration.ignoreShadowsDisplay = false
                group.addTask {
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    else { return nil }
                    return CaptureFrame(displayID: screen.id, frame: screen.frame, image: image)
                }
            }
            for await frame in group { if let frame { frames.append(frame) } }
        }
        // A display that failed (asleep, just unplugged): forget the cached list.
        if frames.count < screens.count { displays.removeAll() }
        return frames
    }

    private static func observeScreens() {
        guard screensObserver == nil else { return }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { displays.removeAll() }
        }
    }

    /// The windows a click can pick, front to back: ordinary windows, floating panels and
    /// open menus of other apps, big enough to aim at.
    static func windows() -> [CaptureWindow] {
        let own = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        // Normal windows, floating panels, modal panels and pop-up menus.
        let layers: Set<Int> = [0, 3, 8, 101]
        return list.compactMap { info in
            // Sirena's own window (a page to show someone) counts; its panels don't.
            guard let layer = info[kCGWindowLayer as String] as? Int, layers.contains(layer),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own || layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 24, bounds.height >= 24 else { return nil }
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            return CaptureWindow(id: number, frame: frame, owner: owner, pid: pid)
        }
    }
}
