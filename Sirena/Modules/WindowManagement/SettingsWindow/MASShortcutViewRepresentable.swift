/// MASShortcutViewRepresentable.swift

import SwiftUI
import MASShortcut

struct MASShortcutViewRepresentable: NSViewRepresentable {
    let defaultsKey: String
    let validator: MASShortcutValidator?
    /// Suspends the bound shortcuts while this view records, so a shortcut
    /// already in use can be recorded instead of triggering its action.
    let recordingObserver: ShortcutRecordingObserver
    /// Lets a window action's recorder take a mouse button as well as a key.
    var recordsMouseButtons = false
    /// Starts recording as soon as it appears (the Atalhos tab's inline recorder).
    var startsRecording = false
    /// Told when recording starts or stops (a shortcut was recorded, cleared or cancelled).
    var onRecordingChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> MASShortcutView {
        let view = recordsMouseButtons ? WindowActionShortcutView() : MASShortcutView()
        view.setAssociatedUserDefaultsKey(defaultsKey, withTransformerName: MASDictionaryTransformerName)
        if let validator = validator {
            view.shortcutValidator = validator
        }
        recordingObserver.observe([view])
        if let onRecordingChange {
            context.coordinator.recordingObservation = view.observe(\.isRecording, options: [.new]) { view, _ in
                let recording = view.isRecording
                DispatchQueue.main.async { onRecordingChange(recording) }
            }
        }
        if startsRecording {
            DispatchQueue.main.async { view.isRecording = true }
        }
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(recordingObserver: recordingObserver)
    }

    /// The observer keeps its views alive, so a view SwiftUI removes - when
    /// its section collapses, say - has to be let go of here, and stopped
    /// first if it was recording, or it would go on recording unseen with
    /// every other shortcut suspended.
    static func dismantleNSView(_ nsView: MASShortcutView, coordinator: Coordinator) {
        coordinator.recordingObservation = nil
        nsView.isRecording = false
        nsView.setAssociatedUserDefaultsKey(nil, withTransformerName: nil)
        coordinator.recordingObserver.unobserve(nsView)
    }

    final class Coordinator {
        let recordingObserver: ShortcutRecordingObserver
        var recordingObservation: NSKeyValueObservation?

        init(recordingObserver: ShortcutRecordingObserver) {
            self.recordingObserver = recordingObserver
        }
    }

    /// A fixed size, so in a Form row the recorder sits beside its label instead of
    /// being treated as flexible and wrapped onto a line of its own.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MASShortcutView, context: Context) -> CGSize? {
        CGSize(width: proposal.width.map { min($0, 160) } ?? 160, height: 22)
    }

    func updateNSView(_ nsView: MASShortcutView, context: Context) {
        if let validator = validator {
            nsView.shortcutValidator = validator
        }
    }
}
