/// ScreenBrushPage.swift

import SwiftUI

struct ScreenBrushPage: View {
    var body: some View {
        ModulePage(module: .screenBrush, tabs: [
            PageTab("general", L("General")) { ScreenBrushSettingsView() },
            PageTab("shortcuts", L("Shortcuts")) { ScreenBrushShortcutsView() }
        ]) {
            Button { ScreenBrushController.shared.quickAction() } label: {
                Label(L("Start Drawing"), systemImage: ModuleID.screenBrush.symbol)
            }
        }
    }
}

// MARK: - General

private struct ScreenBrushSettingsView: View {
    @State private var settings = ScreenBrushSettings.shared
    @State private var hasScreenRecording = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                Picker(L("Tool"), selection: $settings.tool) {
                    ForEach(BrushTool.available) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool)
                    }
                }
                LabeledContent(L("Color")) {
                    HStack(spacing: 6) {
                        ForEach(BrushPalette.colors.indices, id: \.self) { index in
                            Button { settings.colorIndex = index } label: {
                                Circle()
                                    .fill(Color(nsColor: BrushPalette.colors[index]))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: settings.colorIndex == index ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                LabeledContent(L("Width")) {
                    HStack {
                        Slider(value: $settings.width, in: 1...24).frame(width: 180)
                        Text("\(Int(settings.width)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(L("Fill Rectangles and Ellipses"), isOn: $settings.fillShapes)
            } header: {
                Text(L("Brush"))
            }

            Section {
                Toggle(isOn: $settings.keepStrokes) {
                    Text(L("Keep Drawing When Leaving"))
                    Text(L("The drawing comes back the next time you start drawing."))
                }
                Toggle(L("Draw on All Displays"), isOn: $settings.allScreens)
                Toggle(isOn: $settings.showToolbar) {
                    Text(L("Show Toolbar"))
                    Text(L("Without it, use the keyboard to switch tools."))
                }
            } header: {
                Text(L("Drawing Mode"))
            }

            Section {
                Picker(L("Screenshot"), selection: $settings.screenshotAction) {
                    ForEach(ScreenBrushSettings.ScreenshotAction.allCases) { Text($0.title).tag($0) }
                }
                if !hasScreenRecording {
                    LabeledContent {
                        Button(L("Allow…")) { ScreenBrushController.shared.requestScreenRecording() }
                    } label: {
                        Label {
                            Text(L("Screen Recording"))
                            Text(L("Without it, screenshots contain only the drawing."))
                        } icon: {
                            Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text(L("Screenshot"))
            }

            Section {
                keyRow(L("Leave drawing mode"), "Esc")
                keyRow(L("Switch tool"), "1–7 · P H A R O T E")
                keyRow(L("Next color"), "C")
                keyRow(L("Thinner / thicker"), "[  ]")
                keyRow(L("Undo / Redo"), "⌘Z  ⇧⌘Z")
                keyRow(L("Clear"), "⌘⌫")
                keyRow(L("Screenshot / Copy screenshot"), "⌘S  ⌘C")
                keyRow(L("Straight lines, squares and circles"), "⇧")
            } header: {
                Text(L("While Drawing"))
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasScreenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private func keyRow(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).font(.body.monospaced()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shortcuts

private struct ScreenBrushShortcutsView: View {
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                ShortcutRow(title: L("Start or Stop Drawing"), defaultsKey: ScreenBrushSettings.toggleShortcutKey, recordingObserver: recordingObserver)
            } header: {
                Text(L("Keyboard shortcuts"))
            }
        }
        .formStyle(.grouped)
    }
}
