/// WindowDragSection.swift
///
/// Janelas › Arrastar de qualquer lugar: everything about moving and resizing with a held key,
/// in one section (from AnyDrag). Keys and readers: WindowDragSettings.swift; map:
/// .planning/codebase/WINDOW-AND-DOCK.md.

import AppKit
import DockKit
import SwiftUI

struct WindowDragSection: View {
    @AppStorage(WindowDragSettings.enabledKey) private var enabled = WindowDragSettings.enabledDefault
    @AppStorage(WindowDragSettings.modifierKey) private var modifier = WindowDragSettings.modifierDefault.rawValue
    @AppStorage(WindowDragSettings.resizeKey) private var resize = WindowDragSettings.resizeDefault
    @AppStorage(WindowDragSettings.maximizeKey) private var maximize = WindowDragSettings.maximizeDefault
    @State private var excluded = UserDefaults.standard.stringArray(forKey: WindowDragSettings.excludedKey) ?? []
    @State private var showsGuide = false

    private var key: String { WindowDragModifier(rawValue: modifier)?.symbol ?? WindowDragSettings.modifierDefault.symbol }

    var body: some View {
        Section {
            FeatureDrawingRow {
                WindowDragDrawing()
            } content: {
                Toggle(isOn: $enabled) {
                    Text(L("Move windows by holding a key"))
                    Text(L("Hold the key and drag anywhere on a window, not only by its title bar. As smooth as the title bar itself: snap areas and the layouts at the top work while you drag."))
                }
            }
            if enabled {
                WindowDragGestures(key: key, resize: resize, maximize: maximize)
                Picker(selection: $modifier) {
                    ForEach(WindowDragModifier.allCases) { option in
                        Text(option.symbol).tag(option.rawValue)
                    }
                } label: {
                    Text(L("Key"))
                    if modifier == WindowDragModifier.option.rawValue {
                        Text(L("An app that uses ⌥-drag itself (columns of text in editors, duplicating in the Finder) can go in Apps left alone, below. ⌃⌘ means nothing almost anywhere."))
                    }
                }
                Toggle(isOn: $resize) {
                    Text(L("Drag with the right button to resize"))
                    Text(L("The corner nearest the pointer follows it; the opposite one stays put."))
                }
                Toggle(isOn: $maximize) {
                    Text(L("Double-click to maximize"))
                    Text(L("Another double-click gives the window its size back."))
                }
                ExcludedAppsRow(apps: $excluded)
            }
        } header: {
            HStack {
                SettingsSubheader(L("Drag From Anywhere"), symbol: "arrow.up.and.down.and.arrow.left.and.right")
                Spacer()
                Button {
                    showsGuide = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("How to use it, with animations"))
            }
            .sheet(isPresented: $showsGuide) {
                WindowDragGuide(modifier: WindowDragModifier(rawValue: modifier) ?? WindowDragSettings.modifierDefault)
            }
        } footer: {
            if enabled {
                Text(L("A click with the key held, without dragging, reaches the app as always."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: excluded) { _, apps in
            UserDefaults.standard.set(apps, forKey: WindowDragSettings.excludedKey)
        }
    }
}

/// The gestures at a glance: which button does what, with the key held.
private struct WindowDragGestures: View {
    let key: String
    let resize: Bool
    let maximize: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            cell(.left, double: false, L("Moves"), L("\(key) + drag with the left button"))
            if resize {
                cell(.right, double: false, L("Resizes"), L("\(key) + drag with the right button"))
            }
            if maximize {
                cell(.left, double: true, L("Fills the screen"), L("\(key) + double-click"))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ button: MouseGlyph.Button, double: Bool, _ title: String, _ gesture: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            MouseGlyph(button: button, double: double)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(gesture)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A small mouse with the button in use filled in (twice over, for a double-click).
private struct MouseGlyph: View {
    enum Button { case left, right }
    let button: Button
    let double: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.2)
                HStack(spacing: 1.5) {
                    half(.left)
                    half(.right)
                }
                .padding(.horizontal, 2.5)
                .padding(.top, 2.5)
            }
            .frame(width: 15, height: 22)
            if double {
                Text("2×")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18)
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    private func half(_ side: Button) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: side == .left ? 5 : 1.5, bottomLeadingRadius: 1,
                               bottomTrailingRadius: 1, topTrailingRadius: side == .right ? 5 : 1.5, style: .continuous)
            .fill(side == button ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.18))
            .frame(height: 8)
    }
}

private struct ExcludedAppsRow: View {
    @Binding var apps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Apps left alone"))
                    Text(L("In these apps the key and the click do what the app does."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Add App…")) { addApp() }
            }
            ForEach(apps, id: \.self) { bundleID in
                HStack {
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                    Spacer()
                    Button {
                        apps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
    }
}

/// A window with a hand in the middle and arrows: it moves from anywhere.
private struct WindowDragDrawing: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { _ in Circle().fill(.primary.opacity(0.25)).frame(width: 4, height: 4) }
                    Spacer()
                }
                .padding(.horizontal, 5)
                .frame(height: 9)
                .background(.primary.opacity(0.08))
                Spacer(minLength: 0)
            }
            .frame(width: 62, height: 44)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
            .offset(x: -6, y: -4)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .offset(x: -6, y: 0)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.7))
                .offset(x: 14, y: 16)
        }
    }
}
