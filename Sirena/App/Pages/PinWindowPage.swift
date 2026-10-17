/// PinWindowPage.swift

import ScreenCaptureKit
import SwiftUI

struct PinWindowPage: View {
    var body: some View {
        ModulePage(module: .pinWindow, tabs: [
            PageTab("windows", L("Windows")) { PinWindowListView() },
            PageTab("settings", L("General")) { PinWindowSettingsView() }
        ]) {
            Button {
                PinWindowController.shared.selectWindowToPin()
            } label: {
                Label(L("Choose Window to Pin…"), systemImage: "pin")
            }
            .help(L("Select Window to Pin…"))
        }
    }
}

// MARK: - Windows

/// The windows Pin Window can pin, by display, with live thumbnails.
@MainActor
@Observable
private final class PinWindowListModel {
    var windows: [PinnableWindow] = []
    var thumbnails: [CGWindowID: NSImage] = [:]
    var hasAccessibility = PinAX.isTrusted
    var hasScreenRecording = CGPreflightScreenCaptureAccess()

    func refresh(thumbnails loadThumbnails: Bool) async {
        hasAccessibility = PinAX.isTrusted
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        windows = WindowList.onScreen()
        guard loadThumbnails, hasScreenRecording,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
        for window in windows where thumbnails[window.id] == nil {
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }
            let configuration = SCStreamConfiguration()
            let scale = 160 / max(window.frame.width, 1)
            configuration.width = Int(window.frame.width * scale * 2)
            configuration.height = Int(window.frame.height * scale * 2)
            configuration.ignoreShadowsSingleWindow = true
            configuration.showsCursor = false
            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: configuration) {
                thumbnails[window.id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    /// Windows grouped by the display showing them, in display order.
    var byDisplay: [(index: Int, name: String, windows: [PinnableWindow])] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            let windows = windows.filter { $0.screen == screen }
            return windows.isEmpty ? nil : (index + 1, screen.localizedName, windows)
        }
    }
}

private struct PinWindowListView: View {
    @State private var model = PinWindowListModel()
    @State private var controller = PinWindowController.shared

    var body: some View {
        Form {
            if !model.hasScreenRecording || !model.hasAccessibility {
                permissionsSection
            }

            Section {
                HStack {
                    Text(L("Pinned: \(controller.pins.count) · Total: \(model.windows.count)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Unpin All")) { controller.unpinAll() }
                        .disabled(controller.pins.isEmpty)
                    Button {
                        Task { await model.refresh(thumbnails: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L("Refresh"))
                }
            }

            if !controller.pins.isEmpty {
                Section(L("Pinned")) {
                    ForEach(controller.pins) { pin in
                        PinnedRow(pin: pin, thumbnail: model.thumbnails[pin.id])
                    }
                }
            }

            ForEach(model.byDisplay, id: \.index) { display in
                Section(L("Display \(display.index): \(display.name)")) {
                    let unpinned = display.windows.filter { !controller.isPinned($0.id) }
                    if unpinned.isEmpty {
                        Text(L("Every window on this display is pinned."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(unpinned) { window in
                        WindowRow(window: window, thumbnail: model.thumbnails[window.id],
                                  isPending: controller.pending.contains(window.id)) {
                            controller.pin(window)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refresh(thumbnails: true)
            // Keep the list current while the page is open; thumbnails only for new windows.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await model.refresh(thumbnails: true)
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            if !model.hasScreenRecording {
                PermissionRow(title: L("Screen Recording"),
                              detail: L("Needed to show the pinned copy of the window and the previews."),
                              symbol: "rectangle.dashed.badge.record") {
                    controller.requestScreenRecording()
                }
            }
            if !model.hasAccessibility {
                PermissionRow(title: L("Accessibility"),
                              detail: L("Lets the pinned copy follow its window and bring it forward when you use it."),
                              symbol: "accessibility") {
                    controller.requestAccessibility()
                }
            }
        } header: {
            Text(L("App Permissions"))
        } footer: {
            Text(L("After allowing Screen Recording, restart Sirena."))
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let request: () -> Void

    var body: some View {
        LabeledContent {
            Button(L("Allow…"), action: request)
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.orange)
            }
        }
    }
}

private struct WindowThumbnail: View {
    let thumbnail: NSImage?
    let icon: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
            }
            .frame(width: 72, height: 46)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 76, height: 50)
    }
}

private struct WindowRow: View {
    let window: PinnableWindow
    let thumbnail: NSImage?
    let isPending: Bool
    let pin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            WindowThumbnail(thumbnail: thumbnail, icon: window.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.displayName)
                    .lineLimit(1)
                Text(window.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPending {
                ProgressView().controlSize(.small)
            } else {
                Button(action: pin) {
                    Label(L("Pin"), systemImage: "pin")
                }
            }
        }
    }
}

private struct PinnedRow: View {
    @Bindable var pin: PinnedWindow
    let thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                WindowThumbnail(thumbnail: thumbnail, icon: pin.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.displayName)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(pin.appName)
                        if let date = pin.unpinDate {
                            Text("·")
                            Text(L("Unpins \(date.formatted(date: .omitted, time: .shortened))"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(PinAutoUnpin.choices, id: \.self) { minutes in
                        Button(PinAutoUnpin.title(minutes)) { pin.scheduleUnpin(minutes: minutes) }
                    }
                } label: {
                    Image(systemName: "timer")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("Unpin in"))
                Button {
                    PinWindowController.shared.unpin(pin.id)
                } label: {
                    Label(L("Unpin"), systemImage: "pin.slash")
                }
            }
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Slider(value: $pin.opacity, in: 0.2...1)
                Text("\(Int((pin.opacity * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .help(L("Adjust window transparency"))
            if !pin.hasTrafficLights {
                Picker(L("Pin position"), selection: $pin.controlPosition) {
                    ForEach(PinControlPosition.allCases) { Text($0.title).tag($0) }
                }
                .help(L("This window has no close, minimize and zoom buttons. Choose where its pin sits; Sirena remembers it for this app."))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings

private struct PinWindowSettingsView: View {
    @State private var settings = PinWindowSettings.shared
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.activationMode) {
                    ForEach(PinActivationMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text(L("Activation Mode"))
                    Text(settings.activationMode == .click
                         ? L("Click a pinned window to use it.")
                         : L("Rest the pointer over a pinned window to use it."))
                }
                .pickerStyle(.segmented)
                LabeledContent(L("Opacity of new pins")) {
                    HStack {
                        Slider(value: $settings.defaultOpacity, in: 0.2...1)
                            .frame(width: 180)
                        Text("\(Int((settings.defaultOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker(L("Auto Unpin"), selection: $settings.autoUnpinMinutes) {
                    ForEach(PinAutoUnpin.choices, id: \.self) { Text(PinAutoUnpin.title($0)).tag($0) }
                }
                Toggle(isOn: $settings.allSpaces) {
                    Text(L("Show on every Space"))
                    Text(L("Pinned windows follow you when you switch Spaces."))
                }
            } header: {
                Text(L("Pinning"))
            } footer: {
                Text(L("A pinned window shows a pin in place of its close, minimize and zoom buttons. Click it to unpin, minimize, maximize or close the window."))
            }

            Section {
                Toggle(isOn: $settings.shakeToPin) {
                    Text(L("Shake Window to Pin"))
                    Text(L("Shake the window to pin or unpin it."))
                }
            } header: {
                Text(L("Gestures"))
            }

            Section {
                shortcutRow(L("Select window to pin"), PinWindowSettings.selectShortcutKey)
                shortcutRow(L("Pin / unpin the front window"), PinWindowSettings.toggleFrontShortcutKey)
                shortcutRow(L("Unpin all windows"), PinWindowSettings.unpinAllShortcutKey)
            } header: {
                Text(L("Keyboard shortcuts"))
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, _ key: String) -> some View {
        ShortcutRow(title: title, defaultsKey: key, recordingObserver: recordingObserver)
    }
}
