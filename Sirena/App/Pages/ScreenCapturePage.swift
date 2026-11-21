/// ScreenCapturePage.swift
///
/// Captura de Tela on one page: how it works, its one shortcut, what Return does, where
/// files go, the recordings and the keys inside a capture.

import Carbon.HIToolbox
import SwiftUI

struct ScreenCapturePage: View {
    var body: some View {
        ModulePage(module: .screenCapture, tabs: [
            PageTab("general", L("General")) { ScreenCaptureSettingsView() }
        ]) {
            Button { ScreenCaptureController.shared.quickAction() } label: {
                Label(L("Capture"), systemImage: "camera.fill")
            }
        }
    }
}

private struct ScreenCaptureSettingsView: View {
    @State private var controller = ScreenCaptureController.shared
    @State private var recordingObserver = ShortcutRecordingObserver()
    @State private var hasScreenRecording = Showcase.screenRecordingShown()
    /// Re-read when the stored shortcut changes (the recorder writes it straight to the defaults).
    @State private var shortcutText = ScreenCaptureController.shortcutText

    var body: some View {
        Form {
            Section {
                HowItWorks(shortcut: shortcutText ?? (controller.printScreen ? "F13" : "—"))
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                if !hasScreenRecording {
                    LabeledContent {
                        Button(L("Allow…")) {
                            if !CGRequestScreenCaptureAccess(),
                               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        Label {
                            Text(L("Screen Recording"))
                            Text(L("Needed to freeze the screen and to record it."))
                        } icon: {
                            Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text(L("Capture"))
                    Spacer(minLength: 12)
                    Menu {
                        Button(L("⇧⌘4 — in place of macOS's area screenshot")) { set(kVK_ANSI_4, [.shift, .command]) }
                        Button(L("⇧⌘5 — in place of macOS's Screenshot toolbar")) { set(kVK_ANSI_5, [.shift, .command]) }
                        Button(L("⇧⌘2 — free in macOS")) { set(kVK_ANSI_2, [.shift, .command]) }
                        Button(L("F13 — Print Screen only")) { set(kVK_F13, []) }
                    } label: {
                        Text(L("Suggestions"))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(L("Shortcuts that work well for capturing; macOS's own ones are handed back when you pick another."))
                    MASShortcutViewRepresentable(defaultsKey: ScreenCaptureController.shortcutKey,
                                                 validator: SirenaShortcutValidator(ownKey: ScreenCaptureController.shortcutKey),
                                                 recordingObserver: recordingObserver)
                        .frame(width: 160, height: 22)
                        .fixedSize()
                }
                Toggle(isOn: $controller.printScreen) {
                    Text(L("Print Screen too"))
                    Text(L("PC keyboards: the Print Screen key reaches the Mac as F13."))
                }
            } header: {
                Text(L("Shortcut"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if controller.holdsMacShortcut, let shortcutText {
                        Text(String(format: L("While Sirena is open, %@ opens this capture instead of macOS's. macOS gets it back when you pick another shortcut or quit Sirena."), shortcutText))
                    }
                    Text(L("Logitech keyboards: the screenshot key sends a macOS screenshot shortcut. If it doesn't open this capture, set the same shortcut here as in Logi Options+."))
                }
            }

            Section {
                Picker(L("Return and double click"), selection: $controller.primaryAction) {
                    ForEach(CapturePrimaryAction.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $controller.copiesWhenSaving) {
                    Text(L("Copy when saving"))
                    Text(L("Saving also puts the screenshot (or the recording) on the clipboard."))
                }
                Toggle(isOn: $controller.detectsWindows) {
                    Text(L("Pick windows with a click"))
                    Text(L("Highlights the window under the pointer; a click on the desktop takes the whole screen."))
                }
                Toggle(L("Loupe while selecting"), isOn: $controller.showsLoupe)
                Toggle(isOn: $controller.includesPointer) {
                    Text(L("Include the pointer"))
                    Text(L("Where it was when you pressed the shortcut."))
                }
                Toggle(L("Open in Preview or QuickTime after saving"), isOn: $controller.opensAfterCapture)
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
                Toggle(L("Record the Mac's sound"), isOn: $controller.recordsSystemAudio)
            } header: {
                Text(L("Recordings"))
            } footer: {
                Text(L("Select an area or click a window, then the red button on the bar. A window is followed even when it moves or is covered. Stop from the button under the area, the shortcut again or Capture in the ⚡ menu."))
            }

            Section {
                keyRow(L("Copy · Save · Record"), "⌘C  ⌘S  ⌘R")
                keyRow(L("Return or double click"), controller.primaryAction.title)
                keyRow(L("Tools"), "1–9, 0 · P L A R O H T B N M")
                keyRow(L("Color · Thickness"), "C · [  ]")
                keyRow(L("Undo · Redo"), "⌘Z  ⇧⌘Z")
                keyRow(L("Move the selection"), "← ↑ → ↓ · ⇧ 10 pt")
                keyRow(L("Whole screen"), "⌘A")
                keyRow(L("Squares and straight lines"), "⇧")
                keyRow(L("Close"), "Esc")
            } header: {
                Text(L("During a Capture"))
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasScreenRecording = Showcase.screenRecordingShown()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let text = ScreenCaptureController.shortcutText
            if text != shortcutText { shortcutText = text }
        }
    }

    private func set(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) {
        ScreenCaptureController.setShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func keyRow(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).font(.body.monospaced()).foregroundStyle(.secondary)
        }
    }
}

/// Three steps, side by side: the key, the selection, what to do with it.
private struct HowItWorks: View {
    let shortcut: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            step(symbol: "keyboard", title: shortcut, detail: L("Freezes the screen, menus and all"))
            step(symbol: "rectangle.dashed", title: L("Select"), detail: L("Drag an area, or click a window or the desktop"))
            step(symbol: "pencil.tip.crop.circle", title: L("Mark up"), detail: L("Arrows, text, steps, ruler, pixelate…"))
            step(symbol: "doc.on.doc", title: L("Copy, save or record"), detail: L("From the bar under the selection"))
        }
    }

    private func step(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ModuleID.screenCapture.tint)
                .frame(height: 18)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
