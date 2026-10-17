/// MirrorAudioMeter.swift
///
/// Optional microphone level shown under the mirror, to check you can be heard
/// before a call. Runs only while the mirror is visible.

import AVFoundation

@Observable
final class MirrorAudioMeter {
    static let shared = MirrorAudioMeter()

    /// 0…1, smoothed.
    private(set) var level: Float = 0
    private let engine = AVAudioEngine()
    private var running = false

    func start() {
        guard !running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { DispatchQueue.main.async { self.begin() } }
            }
        default:
            break
        }
    }

    private func begin() {
        // Access may arrive after the mirror closed, or after a second start().
        guard !running, MainActor.assumeIsolated({ MirrorState.shared.isVisible }) else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            let rms = sqrt(sum / Float(max(count, 1)))
            // Map roughly -50 dB…0 dB to 0…1.
            let db = 20 * log10(max(rms, 0.000_01))
            let normalized = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = self.level * 0.6 + normalized * 0.4
            }
        }
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
    }
}
