/// PinCapture.swift
///
/// Live video of one window through ScreenCaptureKit. macOS has no public way to raise
/// another app's window above everything, so a pinned window is really this video,
/// shown in a floating panel of Sirena's own.

import CoreMedia
import CoreVideo
import Foundation
import IOSurface
import ScreenCaptureKit

final class PinCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on the main thread with each new frame.
    var onFrame: ((IOSurfaceRef) -> Void)?
    /// Called on the main thread when the stream stops by itself (window closed, …).
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "sirena.pinWindow.capture", qos: .userInteractive)
    private var pixelSize = CGSize.zero

    func start(window: SCWindow, pixelSize: CGSize) async throws {
        self.pixelSize = pixelSize
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: Self.configuration(pixelSize), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Follows the window when it is resized, so the video stays sharp.
    func resize(to size: CGSize) {
        guard let stream, abs(size.width - pixelSize.width) >= 1 || abs(size.height - pixelSize.height) >= 1 else { return }
        pixelSize = size
        stream.updateConfiguration(Self.configuration(size)) { _ in }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        onFrame = nil
        onStop = nil
    }

    /// Longest side of the captured image; bigger windows are scaled down (the copy is
    /// still sharp at normal viewing size).
    private static let maxDimension: CGFloat = 3200

    private static func configuration(_ requested: CGSize) -> SCStreamConfiguration {
        let ratio = min(1, maxDimension / max(requested.width, requested.height, 1))
        let size = CGSize(width: requested.width * ratio, height: requested.height * ratio)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(size.width.rounded()), 2)
        configuration.height = max(Int(size.height.rounded()), 2)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // 30 fps and a short queue: a pinned copy needs to look live, not to cost
        // hundreds of megabytes of surfaces.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        return configuration
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(surface)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStop?(error)
        }
    }
}
