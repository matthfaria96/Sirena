// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Small pieces of other Vorssaint services the switcher depends on, cut down
// to what the switcher uses (SwitcherScrollWheelSupport, SwitcherMouseAppExceptionSupport,
// SwitcherFocusFollowsMouseSupport, SwitcherDockPreviewFrameSupport, SharedUI's SwitcherHUDBackdrop).

import AppKit
import SwiftUI

enum SwitcherAppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Sirena"
    }
}

/// Sirena has no auto-quit feature; nothing needs to be recorded.
final class SwitcherAutoQuitService {
    static let shared = SwitcherAutoQuitService()
    func recordProgrammaticCloseRequest(pid: pid_t) {}
}

struct SwitcherScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
}

enum SwitcherScrollWheelSupport {
    static let syntheticTag: Int64 = 0x5349524E  // "SIRN"
    static let pointsPerLine: Double = 10
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    static func isMouseWheel(_ traits: SwitcherScrollWheelEventTraits,
                             secondsSinceLastGesturePhase: TimeInterval?) -> Bool {
        if !traits.isContinuous {
            return true
        }
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }
        return true
    }
}

enum SwitcherMouseAppExceptionSupport {
    static func isExecutablePathIdentity(_ identity: String) -> Bool {
        identity.hasPrefix("/")
    }

    static func executablePathIdentity(_ path: String?) -> String? {
        guard let path, isExecutablePathIdentity(path) else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    static func identities(bundleID: String?,
                           executablePath: @autoclosure () -> String?,
                           readsPath: Bool) -> [String] {
        var identities = bundleID.map { [$0] } ?? []
        if readsPath, let path = executablePathIdentity(executablePath()) {
            identities.append(path)
        }
        return identities
    }
}

enum SwitcherFocusFollowsMouseSupport {
    static func shouldRestoreFocus(to previousWindowID: CGWindowID,
                                   reportedFocusedWindowID: CGWindowID?,
                                   appIsFrontmost: Bool) -> Bool {
        appIsFrontmost && reportedFocusedWindowID == previousWindowID
    }
}

enum SwitcherDockPreviewFrameSupport {
    static func wasConstrained(_ current: CGRect, original: CGRect, visibleFrame: CGRect) -> Bool {
        guard !original.isEmpty, !visibleFrame.isEmpty,
              !visibleFrame.contains(original), !current.isEmpty else { return false }
        let size = CGSize(width: min(original.width, visibleFrame.width),
                          height: min(original.height, visibleFrame.height))
        let moved = CGRect(x: min(max(original.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
                           y: min(max(original.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
                           width: size.width, height: size.height)
        return [original.intersection(visibleFrame), moved].contains { expected in
            guard !expected.isEmpty, current != original else { return false }
            let matchesX = abs(current.minX - expected.minX) <= 2
            let matchesY = abs(current.minY - expected.minY) <= 2
            let matchesWidth = abs(current.width - expected.width) <= 2
            let matchesHeight = abs(current.height - expected.height) <= 2
            return matchesX && matchesY && matchesWidth && matchesHeight
        }
    }
}

/// The switcher panel's backdrop: Liquid Glass when enabled (default in
/// Sirena), otherwise the classic HUD material.
struct SwitcherHUDBackdrop: View {
    var cornerRadius: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SwitcherDefaultsKey.switcherLiquidGlass) private var liquidGlassEnabled = true

    var body: some View {
        if liquidGlassEnabled && !reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.8)
                )
        } else {
            SwitcherHUDBackdropMaterial(cornerRadius: cornerRadius)
        }
    }
}

private struct SwitcherHUDBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
