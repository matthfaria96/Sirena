/// SirenaHistoryPanelController.swift
///
/// A borderless, non-activating floating panel that hosts Sirena's clipboard
/// history (SwiftUI). Replaces Maccy's FloatingPanel/ContentView stack.

import AppKit
import Defaults
import SwiftUI

final class SirenaHistoryPanelWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()
    SirenaHistoryPanelController.shared.close()
  }

  override func cancelOperation(_ sender: Any?) {
    SirenaHistoryPanelController.shared.close()
  }
}

@MainActor
final class SirenaHistoryPanelController {
  static let shared = SirenaHistoryPanelController()

  static let panelSize = NSSize(width: 360, height: 480)

  private var panel: SirenaHistoryPanelWindow?
  private var keyMonitor: Any?
  private(set) var isOpen = false

  func toggle(at position: PopupPosition = Defaults[.popupPosition]) {
    if isOpen {
      close()
    } else {
      open(at: position)
    }
  }

  func open(at position: PopupPosition = Defaults[.popupPosition]) {
    guard !isOpen else { return }
    let panel = ensurePanel()
    SirenaHistoryPanelModel.shared.prepareForOpen()
    panel.setFrameOrigin(origin(for: Self.panelSize, position: position))
    isOpen = true
    panel.orderFrontRegardless()
    panel.makeKey()
    installKeyMonitor()
  }

  func close() {
    guard isOpen else { return }
    isOpen = false
    removeKeyMonitor()
    panel?.orderOut(nil)
  }

  // MARK: - Panel

  private func ensurePanel() -> SirenaHistoryPanelWindow {
    if let panel { return panel }

    let panel = SirenaHistoryPanelWindow(
      contentRect: NSRect(origin: .zero, size: Self.panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = false
    panel.animationBehavior = .utilityWindow

    let host = NSHostingView(rootView: SirenaHistoryPanelView())
    host.frame = NSRect(origin: .zero, size: Self.panelSize)
    panel.contentView = host

    self.panel = panel
    return panel
  }

  // MARK: - Keyboard

  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isOpen, event.window === self.panel else { return event }
      return self.handle(event)
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    let model = SirenaHistoryPanelModel.shared
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    switch event.keyCode {
    case 53: // Esc
      close()
      return nil
    case 125: // ↓
      model.moveSelection(by: 1)
      return nil
    case 126: // ↑
      model.moveSelection(by: -1)
      return nil
    case 36, 76: // Return / Enter
      model.activate(model.selectedItem)
      return nil
    case 51 where flags.contains(.command): // ⌘⌫
      model.delete(model.selectedItem)
      return nil
    case 35 where flags == .command: // ⌘P
      model.togglePin(model.selectedItem)
      return nil
    default:
      return event
    }
  }

  // MARK: - Position

  private func origin(for size: NSSize, position: PopupPosition) -> NSPoint {
    switch position {
    case .cursor:
      return PopupPosition.cursor.origin(size: size, statusBarButton: nil)
    case .center:
      return PopupPosition.center.origin(size: size, statusBarButton: nil)
    case .statusItem:
      if let button = ClipboardController.shared.anchorButton {
        return PopupPosition.statusItem.origin(size: size, statusBarButton: button)
      }
      return spotlightOrigin(for: size)
    default:
      // .window / .lastPosition: keep it simple and solid, like Spotlight.
      return spotlightOrigin(for: size)
    }
  }

  /// Centered on the active screen, top of the panel in the upper third.
  private func spotlightOrigin(for size: NSSize) -> NSPoint {
    guard let frame = (NSScreen.forPopup ?? NSScreen.main)?.visibleFrame else {
      return .zero
    }
    let x = frame.midX - size.width / 2
    let y = frame.maxY - frame.height * 0.18 - size.height
    return NSPoint(x: x, y: max(y, frame.minY))
  }
}
