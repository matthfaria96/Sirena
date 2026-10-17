import AppKit
import CoreAudio
import SwiftUI

/// Sirena's entry point into Fader (MIT, © pantafive): output switching, per-app
/// volume, several outputs at once and the microphone, shown from Sirena's menu bar
/// icon. Fader's own menu bar item, updater and context menu are not used.
@MainActor
public final class SoundController {
    public static let shared = SoundController()

    private let engine = MixerEngine()
    private var started = false

    private init() {}

    /// Starts the audio engine once the audio system has proven responsive: the first
    /// HAL contact happens off the main thread, so a wedged coreaudiod can't hang Sirena.
    public func start() {
        guard !started else { return }
        started = true
        let engine = engine
        Task.detached(priority: .userInitiated) {
            _ = try? AudioObjectID.readDefaultOutputDevice()
            await MainActor.run { engine.start() }
        }
    }

    /// Quitting must fade and release the per-app taps and dissolve a multi-output
    /// aggregate, or it would outlive Sirena as the default output in Sound settings.
    public func stop() {
        guard started else { return }
        engine.fadeOutAndStop()
        engine.multiOutput.shutdown()
    }

    /// The mixer (outputs, apps, microphone) for a popover.
    public func makeViewController() -> NSViewController {
        let controller = NSHostingController(rootView: MixerView().environment(engine))
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }
}
