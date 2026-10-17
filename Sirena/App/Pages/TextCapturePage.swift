/// TextCapturePage.swift

import SwiftUI

struct TextCapturePage: View {
    var body: some View {
        ModulePage(module: .textCapture, tabs: [
            PageTab("general", L("General")) { TextCaptureSettingsView() },
            PageTab("shortcuts", L("Shortcuts")) { TextCaptureShortcutsView() },
            PageTab("history", L("History")) { TextCaptureHistoryView() }
        ]) {
            Button {
                TextCaptureController.shared.capture(.text())
            } label: {
                Label(L("Capture Text"), systemImage: "text.viewfinder")
            }
        }
    }
}

// MARK: - General

private struct TextCaptureSettingsView: View {
    @State private var settings = TextCaptureSettings.shared
    @State private var controller = TextCaptureController.shared
    @State private var hasScreenRecording = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            if !hasScreenRecording {
                Section {
                    LabeledContent {
                        Button(L("Allow…")) { controller.requestScreenRecording() }
                    } label: {
                        Label {
                            Text(L("Screen Recording"))
                            Text(L("Needed to read the text on your screen. Restart Sirena after allowing it."))
                        } icon: {
                            Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text(L("App Permissions"))
                }
            }

            Section {
                Toggle(isOn: $settings.keepLineBreaks) {
                    Text(L("Keep Line Breaks"))
                    Text(L("Off joins the lines into running text."))
                }
                Toggle(isOn: $settings.additiveClipboard) {
                    Text(L("Additive Clipboard"))
                    Text(L("Each capture is added to the previous ones instead of replacing them."))
                }
                if settings.additiveClipboard {
                    Toggle(L("Clear Automatically"), isOn: $settings.additiveAutoClear)
                    if settings.additiveAutoClear {
                        Picker(L("After no capture for"), selection: $settings.additiveAutoClearMinutes) {
                            ForEach([1, 5, 15, 30, 60], id: \.self) { minutes in
                                Text(minutes == 60 ? L("1 hour") : L("\(minutes) minutes")).tag(minutes)
                            }
                        }
                    }
                    LabeledContent(L("Collected captures")) {
                        Text("\(controller.additiveItems.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button(L("Clear")) { controller.clearAdditive() }
                            .disabled(controller.additiveItems.isEmpty)
                    }
                }
                Text(L("While selecting an area, press L, A or S to switch line breaks, the additive clipboard or speech for that capture."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Capture"))
            }

            Section {
                Picker(L("Recognition Language"), selection: $settings.language) {
                    ForEach(TextCaptureLanguage.choices, id: \.id) { Text($0.title).tag($0.id) }
                }
                Toggle(L("Language correction"), isOn: $settings.languageCorrection)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Custom Words"))
                    Text(L("Names, jargon or codes the recognizer gets wrong, separated by commas."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $settings.customWords, prompt: Text(L("Type custom words separated by comma…")), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(L("Recognition"))
            }

            Section {
                Toggle(isOn: $settings.textToSpeech) {
                    Text(L("Text to Speech"))
                    Text(L("Read every capture aloud."))
                }
                LabeledContent(L("Text to Speech Rate")) {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $settings.speechRate, in: 0.2...0.8)
                            .frame(width: 180)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
                if controller.isSpeaking {
                    Button(L("Stop Speaking")) { controller.stopSpeaking() }
                }
            } header: {
                Text(L("Speech"))
            }

            Section {
                Toggle(L("Automatically Open Links"), isOn: $settings.openLinks)
                Toggle(L("Play a sound"), isOn: $settings.playSound)
                Toggle(L("Show a notification after each capture"), isOn: $settings.showNotification)
            } header: {
                Text(L("After capturing"))
            }

            Section {
                HStack {
                    Button(L("Read QR/Bar Code")) { controller.capture(.code) }
                    Button(L("Capture and Translate")) { controller.capture(.text(translate: true)) }
                    Button(L("Read Text From Image…")) { controller.captureFromFile() }
                }
            } header: {
                Text(L("More"))
            } footer: {
                Text(L("To read a photo or document scan from your iPhone, use “Import from iPhone” in the Sirena menu."))
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasScreenRecording = CGPreflightScreenCaptureAccess()
        }
    }
}

// MARK: - Shortcuts

private struct TextCaptureShortcutsView: View {
    @State private var recordingObserver = ShortcutRecordingObserver()

    var body: some View {
        Form {
            Section {
                ForEach(TextCaptureSettings.Shortcut.allCases) { shortcut in
                    ShortcutRow(title: shortcut.title, defaultsKey: shortcut.defaultsKey, recordingObserver: recordingObserver)
                }
            } header: {
                Text(L("Keyboard shortcuts"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

private struct TextCaptureHistoryView: View {
    @State private var controller = TextCaptureController.shared

    var body: some View {
        Form {
            if controller.history.isEmpty {
                Section {
                    Text(L("Captures from this session appear here."))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(controller.history) { record in
                Section {
                    Text(record.text)
                        .textSelection(.enabled)
                        .lineLimit(8)
                    HStack {
                        Label(record.date.formatted(date: .omitted, time: .shortened),
                              systemImage: record.kind == .code ? "qrcode" : "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Speak")) { controller.speak(record.text) }
                        Button(L("Open")) { CaptureResultWindow.shared.show(text: record.text, translate: false) }
                        Button(L("Copy")) { controller.copyToClipboard(record.text) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
