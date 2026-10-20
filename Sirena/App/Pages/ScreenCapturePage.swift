/// ScreenCapturePage.swift

import SwiftUI

struct ScreenCapturePage: View {
    var body: some View {
        ModulePage(module: .screenCapture, tabs: [
            PageTab("general", L("General")) { ScreenCaptureSettingsView() },
            PageTab("shortcuts", L("Shortcuts")) { ScreenCaptureShortcutsView() }
        ]) {
            Menu {
                ForEach(ScreenCaptureAction.allCases) { action in
                    Button { ScreenCaptureController.shared.run(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } label: {
                Label(L("Capture"), systemImage: "camera.fill")
            } primaryAction: {
                ScreenCaptureController.shared.run(.area)
            }
        }
    }
}

private struct ScreenCaptureSettingsView: View {
    @State private var controller = ScreenCaptureController.shared

    var body: some View {
        Form {
            Section {
                // Two per row, small: the same actions live in the ⚡ menu, this is a shortcut.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: ScreenCaptureAction.allCases.count, by: 2)), id: \.self) { index in
                        GridRow {
                            ForEach(ScreenCaptureAction.allCases[index..<min(index + 2, ScreenCaptureAction.allCases.count)]) { action in
                                ActionTile(action: action, enabled: controller.isRunning) { controller.run(action) }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(L("Capture"))
            } footer: {
                Text(L("Uses macOS's own Screenshot tool, starting directly in the mode you pick."))
            }

            Section {
                Toggle(isOn: $controller.copiesScreenshots) {
                    Text(L("Copy screenshots to the clipboard"))
                    Text(L("Besides saving the file."))
                }
                Toggle(L("Include the pointer in full-screen screenshots"), isOn: $controller.showsCursor)
                Toggle(L("Open in Preview or QuickTime afterwards"), isOn: $controller.opensAfterCapture)
                LabeledContent(L("Saved to")) {
                    HStack(spacing: 8) {
                        Picker(L("Saved to"), selection: $controller.destination) {
                            ForEach(ScreenCaptureDestination.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button(L("Show")) { NSWorkspace.shared.open(controller.destination.folder) }
                    }
                }
            } header: {
                Text(L("Screenshots"))
            }

            Section {
                Toggle(L("Show clicks"), isOn: $controller.showsClicks)
                Toggle(isOn: $controller.recordsMicrophone) {
                    Text(L("Record the microphone"))
                    Text(L("Uses the default input."))
                }
            } header: {
                Text(L("Recordings"))
            } footer: {
                Text(L("Stop a recording from the red button at the top of the screen, or the Capture button in the ⚡ menu."))
            }
        }
        .formStyle(.grouped)
    }
}

/// One capture mode: icon, name and a short line, the whole tile is the button.
private struct ActionTile: View {
    let action: ScreenCaptureAction
    let enabled: Bool
    let run: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ModuleID.screenCapture.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(action.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.quaternary.opacity(isHovering ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .help(action.detail)
    }
}

private struct ScreenCaptureShortcutsView: View {
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                ForEach(ScreenCaptureAction.allCases) { action in
                    ShortcutRow(title: action.title, defaultsKey: action.shortcutKey, recordingObserver: recordingObserver)
                }
            } footer: {
                Text(L("Optional: macOS keeps ⇧⌘3, ⇧⌘4 and ⇧⌘5."))
            }
        }
        .formStyle(.grouped)
    }
}
