/// ShakeDetector.swift
///
/// "Shake to pin": drag a window quickly left and right a few times to pin or unpin it.

import AppKit

@MainActor
final class ShakeDetector {
    /// Called with the shaken window.
    var onShake: ((PinnableWindow) -> Void)?

    private var monitor: Any?

    /// The window being dragged, looked up once the drag really starts.
    private var draggedWindow: PinnableWindow?
    private var dragStart: CGPoint?
    private var lastX: CGFloat = 0
    private var direction: CGFloat = 0
    private var turnX: CGFloat = 0
    private var turns: [Date] = []
    private var fired = false

    /// Direction changes needed, and the time they must happen in.
    private let requiredTurns = 4
    private let window: TimeInterval = 0.9
    /// Minimum travel between two direction changes, in points.
    private let minimumSwing: CGFloat = 24

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? install() : uninstall()
        }
    }

    private func install() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let location = NSEvent.mouseLocation
            let type = event.type
            MainActor.assumeIsolated {
                self?.handle(type, at: location)
            }
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func reset() {
        draggedWindow = nil
        dragStart = nil
        direction = 0
        turns = []
        fired = false
    }

    private func handle(_ type: NSEvent.EventType, at location: CGPoint) {
        switch type {
        case .leftMouseDown:
            reset()
            dragStart = location
            lastX = location.x
            turnX = location.x
        case .leftMouseDragged:
            dragged(to: location)
        default:
            reset()
        }
    }

    private func dragged(to location: CGPoint) {
        guard let start = dragStart, !fired else { return }
        if draggedWindow == nil {
            guard hypot(location.x - start.x, location.y - start.y) > 12 else { return }
            draggedWindow = WindowList.window(atCocoaPoint: start)
            guard draggedWindow != nil else {
                dragStart = nil
                return
            }
        }

        let dx = location.x - lastX
        lastX = location.x
        guard abs(dx) > 0.5 else { return }
        let newDirection: CGFloat = dx > 0 ? 1 : -1
        if direction == 0 {
            direction = newDirection
        } else if newDirection != direction {
            if abs(location.x - turnX) >= minimumSwing {
                let now = Date()
                turns = turns.filter { now.timeIntervalSince($0) < window } + [now]
                turnX = location.x
            }
            direction = newDirection
        }

        guard turns.count >= requiredTurns, let candidate = draggedWindow else { return }
        // Only a window that really moved counts, not a shaken text selection.
        guard let current = WindowList.window(id: candidate.id)?.window,
              hypot(current.frame.minX - candidate.frame.minX, current.frame.minY - candidate.frame.minY) > 8 else {
            turns = []
            return
        }
        fired = true
        onShake?(current)
    }
}
