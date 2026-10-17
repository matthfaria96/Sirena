/// GeneralPage.swift
///
/// Geral: permissions first, then Sirena's own settings, then About — one quiet column
/// of grouped rows, in the manner of System Settings.

import AVFoundation
import DockKit
import SwiftUI

struct GeneralPage: View {
    @State private var launchOnLogin = Defaults.launchOnLogin.enabled
    @State private var hideMenuBarIcon = Defaults.hideMenuBarIcon.enabled
    @State private var recordingObserver = ShortcutRecordingObserver()
    @State private var permissions = PermissionsState()

    var body: some View {
        SettingsColumn {
            SettingsGroup(L("Permissions"),
                          footer: L("Each status is read from macOS right now and updates as soon as you change it in System Settings. Everything stays on this Mac.")) {
                Text(L("\(permissions.grantedCount) of \(permissions.items.count) allowed"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } content: {
                ForEach(Array(permissions.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsSeparator(indented: true) }
                    PermissionLine(item: item)
                }
            }

            SettingsGroup("Sirena") {
                SettingsRow(L("Open Sirena at login"), symbol: "power") {
                    Toggle("", isOn: $launchOnLogin).settingsSwitch()
                        .onChange(of: launchOnLogin) {
                            LaunchOnLogin.isEnabled = launchOnLogin
                            Defaults.launchOnLogin.enabled = launchOnLogin
                        }
                }
                SettingsSeparator(indented: true)
                SettingsRow(L("Hide the Sirena icon in the menu bar"),
                            detail: hideMenuBarIcon ? L("Open Sirena again from Finder or Spotlight to see this window.") : nil,
                            symbol: "menubar.rectangle") {
                    Toggle("", isOn: $hideMenuBarIcon).settingsSwitch()
                        .onChange(of: hideMenuBarIcon) {
                            Defaults.hideMenuBarIcon.enabled = hideMenuBarIcon
                            SirenaStatusItem.instance.refreshVisibility()
                        }
                }
                SettingsSeparator(indented: true)
                SettingsRow(L("Open Sirena on Home"), detail: L("From any app."), symbol: "keyboard") {
                    MASShortcutViewRepresentable(defaultsKey: AppDelegate.openHomeShortcutKey, validator: nil,
                                                 recordingObserver: recordingObserver)
                        .frame(width: 150, height: 22)
                }
            }

            AboutBlock()
        }
        .toolbar { BackToHomeButton() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissions.refresh()
        }
    }
}

// MARK: - Permissions

@MainActor
@Observable
private final class PermissionsState {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let purpose: String
        let symbol: String
        var granted: Bool
    }

    private(set) var items: [Item] = []
    var grantedCount: Int { items.filter(\.granted).count }

    init() { refresh() }

    func refresh() {
        let next = [
            Item(id: "accessibility", title: L("Accessibility"),
                 purpose: L("Moves and resizes windows, pastes from the clipboard history and powers the switcher."),
                 symbol: "accessibility", granted: AXIsProcessTrusted()),
            Item(id: "screen", title: L("Screen Recording"),
                 purpose: L("Window previews in the Dock and the switcher, and capturing text from the screen."),
                 symbol: "rectangle.dashed.badge.record", granted: DockController.hasScreenRecordingPermission),
            Item(id: "camera", title: L("Camera"),
                 purpose: L("The mirror and “Peek” from the menu."),
                 symbol: "camera", granted: AVCaptureDevice.authorizationStatus(for: .video) == .authorized),
            Item(id: "microphone", title: L("Microphone"),
                 purpose: L("The microphone level in the mirror and the microphone controls."),
                 symbol: "mic", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        ]
        if next != items { items = next }
    }

    static func request(_ id: String) {
        switch id {
        case "accessibility":
            AppDelegate.instance.windowManagement.requestAuthorization()
        case "screen":
            DockController.requestScreenRecordingPermission()
        case "camera":
            ask(.video, pane: "Privacy_Camera")
        case "microphone":
            ask(.audio, pane: "Privacy_Microphone")
        default:
            break
        }
    }

    /// Asks the first time; once answered, macOS only changes it in System Settings.
    private static func ask(_ media: AVMediaType, pane: String) {
        if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
            AVCaptureDevice.requestAccess(for: media) { _ in }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionLine: View {
    let item: PermissionsState.Item

    var body: some View {
        SettingsRow(item.title, detail: item.purpose, symbol: item.symbol) {
            if item.granted {
                Label(L("Allowed"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            } else {
                Button(L("Allow…")) { PermissionsState.request(item.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Building blocks (System Settings style)

/// A centered scrolling column of groups.
struct SettingsColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }
}

/// A titled group of rows with an optional footer.
struct SettingsGroup<Content: View, Accessory: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) { content }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// One line: a monochrome symbol, what it is, and the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
    }
}

/// A hairline between rows, starting where the text starts.
struct SettingsSeparator: View {
    var indented = false

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 0.5)
            .padding(.leading, indented ? 46 : 14)
    }
}

extension View {
    func settingsSwitch() -> some View {
        labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}
