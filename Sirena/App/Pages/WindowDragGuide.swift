/// WindowDragGuide.swift
///
/// Janelas › Arrastar de qualquer lugar › (i): a guide with one animated scene per gesture
/// (move, resize, fill the screen, a plain click, snapping), the keys by name on a Mac and on a
/// Logitech/Windows keyboard, and what's good to know. The scenes are drawn, not recorded: a
/// mini desktop, a window, the pointer, and the keys and mouse button held at that moment,
/// played on a loop by a TimelineView (still frame with Reduce Motion).

import SwiftUI

// MARK: - The sheet

struct WindowDragGuide: View {
    let modifier: WindowDragModifier
    @Environment(\.dismiss) private var dismiss
    @State private var page: GuidePage = .move

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    GuidePageView(page: page, modifier: modifier)
                        .id(page)
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 600)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("How to Use Drag From Anywhere"))
                    .font(.headline)
                Text(L("Move, resize and arrange windows without aiming for the title bar."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help(L("Close"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(GuidePage.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .frame(width: 18)
                            .foregroundStyle(page == item ? .primary : .secondary)
                        Text(item.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background(page == item ? Color.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 200)
    }

    private var footer: some View {
        HStack {
            Text(L("\(page.index + 1) of \(GuidePage.allCases.count)"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button(L("Back")) { page = page.previous ?? page }
                .disabled(page.previous == nil)
            if let next = page.next {
                Button(L("Next")) { page = next }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Pages

enum GuidePage: Int, CaseIterable, Identifiable {
    case move, resize, maximize, click, snap, keys, tips

    var id: Int { rawValue }
    var index: Int { rawValue }
    var previous: GuidePage? { GuidePage(rawValue: rawValue - 1) }
    var next: GuidePage? { GuidePage(rawValue: rawValue + 1) }

    var title: String {
        switch self {
        case .move: return L("Move a window")
        case .resize: return L("Make it bigger or smaller")
        case .maximize: return L("Fill the screen")
        case .click: return L("A click is still a click")
        case .snap: return L("Snap while moving")
        case .keys: return L("Which keys to hold")
        case .tips: return L("Good to know")
        }
    }

    var symbol: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .maximize: return "macwindow"
        case .click: return "cursorarrow.click"
        case .snap: return "rectangle.lefthalf.inset.filled"
        case .keys: return "keyboard"
        case .tips: return "lightbulb"
        }
    }

    var scene: GuideScene? {
        switch self {
        case .move: return .move
        case .resize: return .resize
        case .maximize: return .maximize
        case .click: return .click
        case .snap: return .snap
        case .keys, .tips: return nil
        }
    }
}

private struct GuidePageView: View {
    let page: GuidePage
    let modifier: WindowDragModifier

    private var key: String { modifier.symbol }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let scene = page.scene {
                GuideStage(scene: scene, modifier: modifier)
                    .frame(maxWidth: .infinity)
            }
            Text(page.title)
                .font(.title3.weight(.semibold))
            switch page {
            case .move:
                GuideParagraph(L("Hold the key and drag from anywhere on the window: the middle, a picture, some text. The window follows the pointer as smoothly as by its title bar."))
                GuideSteps([L("Hold \(key)."),
                       L("Press the left button anywhere on the window and drag."),
                       L("Let go of the button where you want the window.")])
                GuideNote(L("A window behind others comes to the front as soon as you start dragging it."))
            case .resize:
                GuideParagraph(L("Hold the key and drag with the right button. The corner nearest the pointer follows it and the opposite corner stays put: drag outward to make the window bigger, inward to make it smaller."))
                GuideSteps([L("Hold \(key)."),
                       L("Press the right button in the quarter of the window whose corner you want to pull."),
                       L("Drag outward to make it bigger, inward to make it smaller, then let go.")])
                GuideNote(L("Where you press picks the corner: near the bottom right pulls the bottom-right corner, near the top left the top-left one."))
            case .maximize:
                GuideParagraph(L("Hold the key and double-click anywhere on the window: it fills the screen, leaving the menu bar and the Dock in view. Double-click again to give it its size back."))
                GuideSteps([L("Hold \(key)."),
                       L("Double-click inside the window: it fills the screen."),
                       L("Double-click again: it goes back to its size and place.")])
            case .click:
                GuideParagraph(L("Pressing and letting go without moving the mouse moves nothing: the click reaches the app as always. Only a drag becomes a move."))
                GuideSteps([L("Hold \(key) and click without moving the mouse."),
                       L("The app gets the click, as if Sirena weren't there.")])
            case .snap:
                GuideParagraph(L("A window moved with the key behaves as if held by its title bar: take it to an edge or a corner of the screen to snap it there, or to the top middle for the layouts."))
                GuideSteps([L("Hold \(key) and drag the window."),
                       L("Take the pointer to the left or right edge: a preview shows where the window will go."),
                       L("Let go to snap it.")])
                GuideNote(L("Needs “Snap windows by dragging” on, under Arrange Windows."))
            case .keys:
                GuideKeysPage(modifier: modifier)
            case .tips:
                GuideTipsPage()
            }
        }
    }
}

private struct GuideParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GuideSteps: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.08), in: Circle())
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct GuideNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Keys

/// A key that can be part of the held combination, by place on the keyboard.
private struct GuideModifierKeyName: Identifiable {
    let id: String
    let symbol: String
    let mac: String
    let windows: String

    static let control = GuideModifierKeyName(id: "control", symbol: "⌃", mac: "control", windows: "ctrl")
    static let option = GuideModifierKeyName(id: "option", symbol: "⌥", mac: "option", windows: "start")
    static let command = GuideModifierKeyName(id: "command", symbol: "⌘", mac: "command", windows: "alt")

    /// Left to right, as they sit on the keyboard.
    static let all = [control, option, command]

    static func held(by modifier: WindowDragModifier) -> [GuideModifierKeyName] {
        let flags = modifier.flags
        return all.filter { key in
            switch key.id {
            case "control": return flags.contains(.maskControl)
            case "option": return flags.contains(.maskAlternate)
            default: return flags.contains(.maskCommand)
            }
        }
    }
}

private struct GuideKeysPage: View {
    let modifier: WindowDragModifier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var held: [GuideModifierKeyName] { GuideModifierKeyName.held(by: modifier) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideParagraph(L("Sirena goes by where the keys are, not by what's printed on them. On a Logitech keyboard, or any keyboard made for Windows, the same places have other names:"))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let pulse = reduceMotion ? 1 : 0.55 + 0.45 * (0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2.4))
                VStack(alignment: .leading, spacing: 14) {
                    keyboardRow(L("Mac keyboard"), names: { $0.mac }, pulse: pulse)
                    keyboardRow(L("Logitech or Windows keyboard"), names: { $0.windows }, pulse: pulse)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            let mac = held.map(\.mac).joined(separator: " + ")
            let windows = held.map(\.windows).joined(separator: " + ")
            GuideParagraph(L("With \(modifier.symbol) chosen, hold \(mac) on a Mac keyboard, or \(windows) on a Logitech keyboard."))
            GuideNote(L("The key is chosen in Key, in this section; ⌥ is the default. ⌥-drag also selects columns of text in editors and duplicates files in the Finder: add those apps to Apps left alone, or pick ⌃⌘, which means nothing almost anywhere."))
            GuideNote(L("A Logitech keyboard set to its Mac layout (the Mac keys printed on it) uses the Mac names."))
        }
    }

    private func keyboardRow(_ title: String, names: @escaping (GuideModifierKeyName) -> String, pulse: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(GuideModifierKeyName.all) { key in
                    let lit = held.contains { $0.id == key.id }
                    GuideKeyCap(top: key.symbol, name: names(key), lit: lit, glow: lit ? pulse : 0, width: 72)
                }
                Text("+")
                    .foregroundStyle(.secondary)
                GuideMouseGlyph(button: .left, pressed: true, glow: pulse)
                Text(L("drag"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GuideTipsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tip("display.2", L("Works on every display and with any app's windows, even those without a title bar."))
            tip("nosign", L("In an app where the key and the drag mean something else (a game, a drawing app), add it to Apps left alone: there everything behaves as before."))
            tip("rectangle.dashed", L("Full-screen windows, the Dock, the menu bar and Sirena's own windows are never touched."))
            tip("hand.raised", L("Needs the Accessibility permission, the same one used to arrange windows."))
            tip("power", L("Turn the switch off and the keys and the mouse go back to exactly what they did before."))
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Keys and mouse drawn

private struct GuideKeyCap: View {
    let top: String
    let name: String
    let lit: Bool
    let glow: Double
    var width: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(top).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            Text(name).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(lit ? Color.primary : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: width, height: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(lit ? 0.07 + 0.13 * glow : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(lit ? 0.18 + 0.3 * glow : 0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 0.5, y: 1)
    }
}

enum GuideMouseButton { case left, right }

/// A mouse seen from above, with the pressed button filled.
private struct GuideMouseGlyph: View {
    let button: GuideMouseButton
    let pressed: Bool
    var glow: Double = 1
    var clicks: Int = 0

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2)
            HStack(spacing: 0) {
                half(.left)
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1)
                half(.right)
            }
            .frame(height: 17)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 1.2)
            .padding(.top, 1.2)
            // Where the buttons end (the middle of the mouse).
            Rectangle()
                .fill(Color.primary.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 1.2)
        }
        .frame(width: 24, height: 36)
        .overlay(alignment: .topTrailing) {
            if clicks > 1 {
                Text("×\(clicks)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .offset(x: 14, y: -4)
            }
        }
    }

    private func half(_ side: GuideMouseButton) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(pressed && side == button ? 0.25 + 0.4 * glow : 0))
    }
}

// MARK: - Animated scenes

enum GuideScene {
    case move, resize, maximize, click, snap

    var duration: Double {
        switch self {
        case .move, .click: return 4.2
        case .resize, .maximize, .snap: return 5.4
        }
    }
}

/// What a scene shows at one moment.
private struct GuideFrame {
    var window = CGRect.zero
    var cursor = CGPoint.zero
    var keysHeld = false
    var button: GuideMouseButton = .left
    var pressed = false
    var clicks = 0
    var ripples: [(CGPoint, Double)] = []
    var footprint: CGRect?
    var footprintOpacity = 0.0
    var quarters = 0.0
    var activeQuarter: CGRect?
    var okPressed = false
    var receivedOpacity = 0.0
    var caption: String?
    var opacity = 1.0
}

private enum GuideStageMetrics {
    static let size = CGSize(width: 440, height: 250)
    static let menuBar: CGFloat = 12
    static let dockHeight: CGFloat = 18
    /// Where windows may go: below the menu bar, above the Dock.
    static var usable: CGRect {
        CGRect(x: 6, y: menuBar + 4, width: size.width - 12, height: size.height - menuBar - dockHeight - 14)
    }
}

private func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
/// 0 before `a`, 1 after `b`, eased in between.
private func phase(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
    let x = clamp01((t - a) / (b - a))
    return CGFloat(x * x * (3 - 2 * x))
}
private func within(_ t: Double, _ a: Double, _ b: Double) -> Bool { t >= a && t < b }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }
private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }
private func lerp(_ a: CGRect, _ b: CGRect, _ p: CGFloat) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, p), y: lerp(a.minY, b.minY, p), width: lerp(a.width, b.width, p), height: lerp(a.height, b.height, p))
}
private func ripple(_ t: Double, at start: Double, _ point: CGPoint) -> [(CGPoint, Double)] {
    within(t, start, start + 0.12) ? [(point, (t - start) / 0.12)] : []
}
/// Fades the scene in at the start of a loop and out at its end.
private func loopOpacity(_ t: Double) -> Double {
    min(clamp01(t / 0.04), 1 - clamp01((t - 0.93) / 0.07))
}

extension GuideScene {
    fileprivate func frame(at t: Double) -> GuideFrame {
        var f = GuideFrame()
        f.opacity = loopOpacity(t)
        let enter = CGPoint(x: 400, y: 215)
        switch self {
        case .move:
            let w0 = CGRect(x: 50, y: 50, width: 160, height: 108)
            let grab = CGPoint(x: w0.midX, y: w0.midY + 8)
            let shift = CGPoint(x: 170, y: 44)
            let p = phase(t, 0.34, 0.70)
            f.window = w0.offsetBy(dx: shift.x * p, dy: shift.y * p)
            f.cursor = t < 0.3 ? lerp(enter, grab, phase(t, 0.04, 0.22)) : CGPoint(x: grab.x + shift.x * p, y: grab.y + shift.y * p)
            f.keysHeld = within(t, 0.24, 0.8)
            f.pressed = within(t, 0.30, 0.74)
            f.ripples = ripple(t, at: 0.30, grab)
            f.caption = f.pressed ? L("Moving") : nil
        case .resize:
            let w0 = CGRect(x: 70, y: 46, width: 170, height: 110)
            let grab = CGPoint(x: w0.maxX - 30, y: w0.maxY - 24)
            let grow = phase(t, 0.30, 0.50), shrink = phase(t, 0.56, 0.78)
            let dx = 100 * grow - 140 * shrink, dy = 48 * grow - 70 * shrink
            f.window = CGRect(x: w0.minX, y: w0.minY, width: w0.width + dx, height: w0.height + dy)
            f.cursor = t < 0.28 ? lerp(enter, grab, phase(t, 0.04, 0.18)) : CGPoint(x: grab.x + dx, y: grab.y + dy)
            f.button = .right
            f.keysHeld = within(t, 0.2, 0.86)
            f.pressed = within(t, 0.26, 0.82)
            f.ripples = ripple(t, at: 0.26, grab)
            f.quarters = Double(phase(t, 0.12, 0.2)) * (1 - Double(phase(t, 0.84, 0.9)))
            f.activeQuarter = CGRect(x: f.window.midX, y: f.window.midY, width: f.window.width / 2, height: f.window.height / 2)
            if within(t, 0.30, 0.53) { f.caption = L("Bigger") } else if within(t, 0.53, 0.84) { f.caption = L("Smaller") }
        case .maximize:
            let w0 = CGRect(x: 120, y: 58, width: 170, height: 104)
            let point = CGPoint(x: w0.midX + 10, y: w0.midY + 14)
            let grow = phase(t, 0.30, 0.44), back = phase(t, 0.72, 0.86)
            f.window = lerp(lerp(w0, GuideStageMetrics.usable, grow), w0, back)
            f.cursor = lerp(enter, point, phase(t, 0.04, 0.16))
            f.keysHeld = within(t, 0.18, 0.9)
            f.pressed = within(t, 0.22, 0.25) || within(t, 0.27, 0.30) || within(t, 0.60, 0.63) || within(t, 0.65, 0.68)
            f.clicks = (within(t, 0.22, 0.34) || within(t, 0.60, 0.72)) ? 2 : 0
            f.ripples = ripple(t, at: 0.22, point) + ripple(t, at: 0.27, point) + ripple(t, at: 0.60, point) + ripple(t, at: 0.65, point)
            if within(t, 0.30, 0.60) { f.caption = L("Fills the screen") } else if within(t, 0.72, 0.9) { f.caption = L("Back to its size") }
        case .click:
            let w0 = CGRect(x: 120, y: 48, width: 200, height: 128)
            f.window = w0
            let ok = CGPoint(x: w0.midX, y: w0.minY + 78)
            f.cursor = lerp(enter, ok, phase(t, 0.04, 0.22))
            f.keysHeld = within(t, 0.26, 0.74)
            f.pressed = within(t, 0.36, 0.44)
            f.okPressed = f.pressed
            f.ripples = ripple(t, at: 0.36, ok)
            f.receivedOpacity = Double(phase(t, 0.45, 0.52)) * (1 - Double(phase(t, 0.86, 0.92)))
        case .snap:
            let w0 = CGRect(x: 200, y: 56, width: 170, height: 108)
            let grab = CGPoint(x: w0.midX, y: w0.midY + 8)
            let edge = CGPoint(x: 8, y: grab.y + 20)
            let drag = phase(t, 0.24, 0.52)
            let dragged = w0.offsetBy(dx: (edge.x - grab.x) * drag, dy: (edge.y - grab.y) * drag)
            let usable = GuideStageMetrics.usable
            let half = CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height)
            f.window = lerp(dragged, half, phase(t, 0.66, 0.78))
            f.cursor = t < 0.22 ? lerp(enter, grab, phase(t, 0.04, 0.16)) : lerp(grab, edge, drag)
            f.keysHeld = within(t, 0.18, 0.8)
            f.pressed = within(t, 0.22, 0.66)
            f.ripples = ripple(t, at: 0.22, grab)
            f.footprint = half
            f.footprintOpacity = Double(phase(t, 0.46, 0.54)) * (1 - Double(phase(t, 0.66, 0.74)))
            if within(t, 0.46, 0.66) { f.caption = L("Let go to snap") }
        }
        return f
    }
}

private struct GuideStage: View {
    let scene: GuideScene
    let modifier: WindowDragModifier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = reduceMotion ? 0.5 : elapsed.truncatingRemainder(dividingBy: scene.duration) / scene.duration
            let f = scene.frame(at: t)
            VStack(spacing: 12) {
                desktop(f)
                heldRow(f)
            }
        }
        .onAppear { start = Date() }
    }

    private func desktop(_ f: GuideFrame) -> some View {
        let size = GuideStageMetrics.size
        return ZStack(alignment: .topLeading) {
            // Desktop, menu bar, Dock.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: size.width, height: GuideStageMetrics.menuBar)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(HStack(spacing: 5) {
                    ForEach(0..<7) { _ in RoundedRectangle(cornerRadius: 2.5).fill(Color.primary.opacity(0.14)).frame(width: 9, height: 9) }
                })
                .frame(width: 120, height: GuideStageMetrics.dockHeight)
                .offset(x: (size.width - 120) / 2, y: size.height - GuideStageMetrics.dockHeight - 4)

            Group {
                if let footprint = f.footprint, f.footprintOpacity > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.22)))
                        .frame(width: footprint.width, height: footprint.height)
                        .offset(x: footprint.minX, y: footprint.minY)
                        .opacity(f.footprintOpacity)
                }
                GuideMiniWindow(rect: f.window, quarters: f.quarters, activeQuarter: f.activeQuarter,
                           showsButton: scene == .click, okPressed: f.okPressed)
                ForEach(Array(f.ripples.enumerated()), id: \.offset) { _, item in
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.5 * (1 - item.1)), lineWidth: 1.5)
                        .frame(width: 10 + 26 * item.1, height: 10 + 26 * item.1)
                        .offset(x: item.0.x - (5 + 13 * item.1), y: item.0.y - (5 + 13 * item.1))
                }
                if f.receivedOpacity > 0 {
                    Label(L("The app got the click"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                        .offset(x: f.window.minX + 30, y: f.window.maxY + 10)
                        .opacity(f.receivedOpacity)
                }
                GuidePointer()
                    .offset(x: f.cursor.x - 3, y: f.cursor.y - 2)
                if let caption = f.caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                        .frame(width: size.width - 20, alignment: .trailing)
                        .offset(x: 0, y: GuideStageMetrics.menuBar + 8)
                }
            }
            .opacity(f.opacity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    /// What's held right now: the keys, then the mouse button.
    private func heldRow(_ f: GuideFrame) -> some View {
        let held = GuideModifierKeyName.held(by: modifier)
        return HStack(spacing: 8) {
            ForEach(held) { key in
                GuideKeyCap(top: key.symbol, name: key.mac, lit: f.keysHeld, glow: f.keysHeld ? 1 : 0, width: 72)
            }
            Text("+").foregroundStyle(.secondary)
            GuideMouseGlyph(button: f.button, pressed: f.pressed, clicks: f.clicks)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.button == .right ? L("Right button") : (scene == .maximize ? L("Double-click") : L("Left button")))
                    .font(.callout.weight(.medium))
                Text(L("Logitech: \(held.map(\.windows).joined(separator: " + "))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        }
        .opacity(0.4 + 0.6 * f.opacity)
    }
}

/// A plain window: title bar with neutral lights, a few lines of content.
private struct GuideMiniWindow: View {
    let rect: CGRect
    let quarters: Double
    let activeQuarter: CGRect?
    let showsButton: Bool
    let okPressed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(Color.primary.opacity(0.2)).frame(width: 6, height: 6) }
                }
                .padding(.horizontal, 7)
                .frame(height: 16)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([0.7, 0.9, 0.55], id: \.self) { share in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: max(0, (rect.width - 20) * share), height: 5)
                    }
                }
                .padding(10)
            }
            if showsButton {
                Text("OK")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 58, height: 20)
                    .background(Color.primary.opacity(okPressed ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .scaleEffect(okPressed ? 0.94 : 1)
                    .offset(x: rect.width / 2 - 29, y: 68)
            }
            if quarters > 0 {
                Path { path in
                    path.move(to: CGPoint(x: rect.width / 2, y: 17))
                    path.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
                    path.move(to: CGPoint(x: 0, y: rect.height / 2))
                    path.addLine(to: CGPoint(x: rect.width, y: rect.height / 2))
                }
                .stroke(Color.primary.opacity(0.25 * quarters), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let active = activeQuarter {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.07 * quarters))
                        .frame(width: active.width - 4, height: active.height - 4)
                        .offset(x: rect.width / 2 + 2, y: rect.height / 2 + 2)
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.5 * quarters))
                        .offset(x: rect.width - 16, y: rect.height - 16)
                }
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.14)))
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// The arrow pointer, white with a dark rim like the real one.
private struct GuidePointer: View {
    var body: some View {
        ZStack {
            Image(systemName: "cursorarrow")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.black)
            Image(systemName: "cursorarrow")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }
}
