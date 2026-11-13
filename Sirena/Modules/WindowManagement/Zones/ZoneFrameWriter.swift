/// ZoneFrameWriter.swift
///
/// Moves the windows of a group while a grip is dragged, without making the pointer wait for
/// their apps. A frame change goes through Accessibility, as slow as the app that takes it (a
/// busy editor needs tens of milliseconds); done on the main thread it would hold the grip
/// and the outlines back. Here the writes run on their own queue and only the latest frame of
/// each window matters: the grip follows the pointer, the windows follow as fast as they can.
///
/// It also learns which windows refuse to get smaller (an app's minimum size) and tells the
/// controller, so the line stops there instead of sliding a window under its neighbour.

import AppKit

final class ZoneFrameWriter {
    struct Target {
        let element: AccessibilityElement
        let frame: CGRect
    }

    /// A window kept a bigger size than the one asked of it: its id, what was asked and what
    /// it kept. Called on the main thread.
    var onRefused: ((CGWindowID, _ asked: CGSize, _ kept: CGSize) -> Void)?

    private let queue = DispatchQueue(label: "com.matheusfaria.Sirena.zones.frames", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: [CGWindowID: Target] = [:]
    /// The last frame asked of each window, so only what changed is written, and when.
    private var written: [CGWindowID: CGRect] = [:]
    private var writtenAt: [CGWindowID: Date] = [:]
    private var isDraining = false
    /// The windows waiting to be read back.
    private var checking: Set<CGWindowID> = []
    private static let checkQueue = DispatchQueue(label: "com.matheusfaria.Sirena.zones.frames.check", qos: .userInitiated)
    /// How long a window gets to take a size before what it kept counts as its answer.
    private static let settleTime: TimeInterval = 0.08

    /// A new drag: `frames` are where the windows are now.
    func begin(frames: [CGWindowID: CGRect]) {
        lock.lock()
        pending.removeAll()
        written = frames
        writtenAt.removeAll()
        checking.removeAll()
        lock.unlock()
    }

    /// The frames the windows should get now; anything not yet written for them is dropped.
    func write(_ targets: [CGWindowID: Target]) {
        lock.lock()
        pending.merge(targets) { _, new in new }
        let start = !isDraining
        if start { isDraining = true }
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    /// Runs `completion` on the main thread once every frame asked so far is written.
    func flush(_ completion: @escaping () -> Void) {
        queue.async { DispatchQueue.main.async(execute: completion) }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (id, target) = pending.first else {
                isDraining = false
                lock.unlock()
                return
            }
            pending.removeValue(forKey: id)
            let last = written[id]
            written[id] = target.frame
            writtenAt[id] = Date()
            lock.unlock()
            apply(target, last: last, id: id)
        }
    }

    private func apply(_ target: Target, last: CGRect?, id: CGWindowID) {
        let element = target.element.axElement
        let frame = target.frame
        let moves = last?.origin != frame.origin
        let resizes = last?.size != frame.size
        // Growing towards the top left: the origin first, so the window never pokes out of
        // its zone on the other side; otherwise the size first.
        let originFirst = moves && (frame.minX < (last?.minX ?? frame.minX) || frame.minY < (last?.minY ?? frame.minY))
        if moves, originFirst { Self.set(element, origin: frame.origin) }
        if resizes { Self.set(element, size: frame.size) }
        if moves, !originFirst { Self.set(element, origin: frame.origin) }
        // Only a window asked to shrink can refuse: that is the only time it is read back.
        guard resizes, let last, frame.width < last.width - 0.5 || frame.height < last.height - 0.5 else { return }
        check(id, element: element, after: Self.settleTime)
    }

    /// Reads a window's size back once it has had `settleTime` since the last write (an app
    /// may take a size a beat after answering), off the writing queue; one check per window
    /// at a time. What it still keeps bigger than asked is its minimum.
    private func check(_ id: CGWindowID, element: AXUIElement, after delay: TimeInterval) {
        lock.lock()
        let isNew = checking.insert(id).inserted
        lock.unlock()
        guard isNew else { return }
        Self.checkQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.checking.remove(id)
            let asked = self.written[id]?.size
            let age = self.writtenAt[id].map { Date().timeIntervalSince($0) } ?? Self.settleTime
            self.lock.unlock()
            guard let asked else { return }
            if age < Self.settleTime * 0.75 {
                // Written again meanwhile: give that write its time too.
                self.check(id, element: element, after: Self.settleTime - age)
                return
            }
            guard let kept = Self.size(of: element),
                  kept.width > asked.width + 1.5 || kept.height > asked.height + 1.5 else { return }
            DispatchQueue.main.async { self.onRefused?(id, asked, kept) }
        }
    }

    private static func set(_ element: AXUIElement, origin: CGPoint) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private static func set(_ element: AXUIElement, size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
