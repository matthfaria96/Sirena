/// CaptureRecorder.swift
///
/// Records an area, a whole display or one window to a movie with ScreenCaptureKit
/// (`SCRecordingOutput`, macOS 15). Clicks, the microphone and the Mac's own sound are
/// options. A window recording follows that window wherever it goes, even behind others;
/// area and display recordings leave Sirena's own panels (stop button, frame) out.

import AppKit
import AVFoundation
import ScreenCaptureKit

/// What a recording takes, in Cocoa global coordinates.
enum CaptureRecordingTarget {
    case area(CGRect, displayID: CGDirectDisplayID)
    case display(CGDirectDisplayID)
    case window(CGWindowID)
}

final class CaptureRecorder: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    struct Options {
        var clicks: Bool
        var microphone: Bool
        var systemAudio: Bool
    }

    enum Failure: LocalizedError {
        case sourceGone
        var errorDescription: String? { L("The window or display to record is no longer there.") }
    }

    let url: URL
    /// On the main thread, once: the movie is finished (nil) or the recording failed.
    var onFinish: ((Error?) -> Void)?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private let queue = DispatchQueue(label: "sirena.screenCapture.recording", qos: .userInitiated)
    private var finished = false

    init(url: URL) {
        self.url = url
    }

    @MainActor
    func start(_ target: CaptureRecordingTarget, options: Options) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter
        var size: CGSize
        switch target {
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw Failure.sourceGone }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
            configuration.ignoreShadowsSingleWindow = true
        case .display(let id), .area(_, let id):
            guard let display = content.displays.first(where: { $0.displayID == id }),
                  let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { throw Failure.sourceGone }
            // Sirena's stop button and frame stay out of the movie.
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            size = screen.frame.size
            if case .area(let rect, _) = target {
                // Display-local points with a top-left origin.
                configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                                  width: rect.width, height: rect.height)
                size = rect.size
            }
        }
        let scale = CGFloat(filter.pointPixelScale)
        // Even sizes: some players refuse odd H.264 frames.
        configuration.width = max(2, Int((size.width * scale / 2).rounded()) * 2)
        configuration.height = max(2, Int((size.height * scale / 2).rounded()) * 2)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.showMouseClicks = options.clicks
        configuration.capturesAudio = options.systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = options.microphone

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        // Frames are written by the recording output; these only keep the stream from
        // dropping samples that have no receiver.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if options.microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        self.stream = stream
        self.output = output
    }

    /// Ends the recording; `onFinish` follows once the movie is written.
    func stop() {
        guard let stream else { return }
        stream.stopCapture { [weak self] error in
            if let error { self?.finish(error) }
        }
        // Never leave the caller waiting if the recording output stays silent.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finish(nil) }
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(error)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(nil)
    }

    // MARK: SCStreamDelegate

    /// The window closed or the display went away: what was recorded is still written.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finish(nil) }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    private func finish(_ error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.stream = nil
            self.output = nil
            let handler = self.onFinish
            self.onFinish = nil
            handler?(error)
        }
    }
}
