// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted for Sirena: the island shows and drives Sirena's own Keep Awake and
// Shelf instead of Vorssaint's.

import AppKit
import Combine

/// Sirena's Keep Awake, as the island reads it.
final class IslandKeepAwake: ObservableObject {
    static let shared = IslandKeepAwake()
    @Published private(set) var isActive = false
    /// When a timed session ends; nil while it runs until switched off.
    @Published private(set) var endDate: Date?
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        MainActor.assumeIsolated {
            let model = KeepAwakeModule.shared.viewModel
            model.$isActive.combineLatest(model.$timeRemaining)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] active, remaining in
                    guard let self else { return }
                    if self.isActive != active { self.isActive = active }
                    let end = active ? remaining.map { Date().addingTimeInterval($0) } : nil
                    // The remaining time ticks every second; only a real change
                    // of the end moves the island's reading.
                    if let end, let current = self.endDate, abs(end.timeIntervalSince(current)) < 2 { return }
                    if self.endDate != end { self.endDate = end }
                }
                .store(in: &subscriptions)
        }
    }

    func toggle() {
        MainActor.assumeIsolated { KeepAwakeModule.shared.viewModel.toggleActive() }
    }

    static func remainingText(until end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSinceNow))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }
}

/// Files dropped on the island go to Sirena's Shelf.
enum IslandShelfBridge {
    @discardableResult
    static func add(from pasteboard: NSPasteboard, near point: CGPoint? = nil) -> Bool {
        MainActor.assumeIsolated {
            guard ShelfStore.shared.add(from: pasteboard) else { return false }
            ShelfController.shared.show(near: point)
            return true
        }
    }

    static func add(_ urls: [URL]) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sirena.island.shelf"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        add(from: pasteboard)
    }

    /// What Sirena's Shelf takes: files, links, images and text.
    static let dropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .tiff, .png,
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: dropTypes) != nil
    }

    static var isAvailable: Bool { MainActor.assumeIsolated { ShelfController.shared.isRunning } }
}
