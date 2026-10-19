/// ScreenCaptureCompat.swift
///
/// `SCScreenshotManager.captureImage(in:)` arrived in macOS 15.2; before that, capture
/// the display under the rect and crop it there.

import AppKit
import ScreenCaptureKit

extension SCScreenshotManager {
    /// Captures a rect in global coordinates (top-left origin) on any supported macOS.
    static func compatCaptureImage(in rect: CGRect) async throws -> CGImage {
        if #available(macOS 15.2, *) { return try await captureImage(in: rect) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.intersects(rect) }) ?? content.displays.first else {
            throw NSError(domain: "Sirena.ScreenCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("No display to capture")])
        }
        let local = rect.intersection(display.frame).offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = Int(local.width * scale(of: display.displayID))
        configuration.height = Int(local.height * scale(of: display.displayID))
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func scale(of displayID: CGDirectDisplayID) -> CGFloat {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.backingScaleFactor ?? 2
    }
}
