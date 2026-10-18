/// OnboardingWindow.swift
///
/// First launch only: one page with the permissions Sirena needs to work, nothing else.

import AVFoundation
import DockKit
import SwiftUI

@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private static let doneKey = "sirena.onboarding.done"
    private var window: NSWindow?

    /// Shows the page unless it was finished before and the essential permissions are in place.
    func showIfNeeded() {
        let done = UserDefaults.standard.bool(forKey: Self.doneKey)
        guard !done || !OnboardingView.essentialsGranted else { return }
        show()
    }

    func show() {
        if let window { return window.makeKeyAndOrderFront(nil) }
        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in self?.finish() })
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        // Not inside the button's own click: tearing its window down there froze the app.
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
            DispatchQueue.main.async {
                self?.window = nil
                ModuleManager.shared.openPage(.home)
            }
        }
    }
}

/// MainActor throughout: the app target builds in Swift 5 mode, where a plain method of a View
/// is not on the main thread, and a state change from there froze SwiftUI for good.
@MainActor
private struct OnboardingView: View {
    let finish: () -> Void
    @State private var tick = 0
    @State private var launchOnLogin = Defaults.launchOnLogin.enabled
    /// One permission at a time: the one being asked, until it is answered or 6 s pass.
    @State private var asking: String?

    static var essentialsGranted: Bool { AXIsProcessTrusted() && CGPreflightScreenCaptureAccess() }

    private struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
        let required: Bool
        let granted: Bool
    }

    private var steps: [Step] {
        _ = tick
        return [
            Step(id: "accessibility", title: L("Accessibility"),
                 detail: L("Arranges windows, pastes from the history, powers ⌘ Tab and the Finder tweaks."),
                 symbol: "accessibility", tint: .blue, required: true, granted: AXIsProcessTrusted()),
            Step(id: "screen", title: L("Screen Recording"),
                 detail: L("Previews in the Dock and ⌘ Tab, Capture, Text, Pin Window and screenshots of drawings."),
                 symbol: "rectangle.dashed.badge.record", tint: .red, required: true,
                 granted: CGPreflightScreenCaptureAccess()),
            Step(id: "camera", title: L("Camera"), detail: L("The mirror and “Peek” from the menu."),
                 symbol: "camera.fill", tint: .green, required: false,
                 granted: AVCaptureDevice.authorizationStatus(for: .video) == .authorized),
            Step(id: "microphone", title: L("Microphone"), detail: L("Recording your voice with Capture and the mirror's sound level."),
                 symbol: "mic.fill", tint: .orange, required: false,
                 granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        ]
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text(L("Welcome to Sirena"))
                    .font(.largeTitle.weight(.bold))
                Text(L("Allow what Sirena needs to work. Everything stays on this Mac."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                // Read once per redraw: each step asks macOS (TCC) for its state.
                let current = steps
                ForEach(current) { step in
                    if step.id != current.first?.id { Divider().padding(.leading, 56) }
                    row(step)
                }
                Divider().padding(.leading, 56)
                HStack(spacing: 12) {
                    icon("power", tint: .gray)
                    Text(L("Open Sirena at login"))
                    Spacer()
                    Toggle("", isOn: $launchOnLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchOnLogin) {
                            LaunchOnLogin.isEnabled = launchOnLogin
                            Defaults.launchOnLogin.enabled = launchOnLogin
                        }
                }
                .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))

            VStack(spacing: 8) {
                Button(action: finish) {
                    Text(Self.essentialsGranted ? L("Start Using Sirena") : L("Continue Without Everything"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                Text(L("You can change these later in General."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 520)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
            // The answer came: free the other buttons.
            if let asking, steps.first(where: { $0.id == asking })?.granted == true { self.asking = nil }
        }
    }

    private func allow(_ id: String) {
        guard asking == nil else { return }
        asking = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if asking == id { asking = nil } }
        PermissionsState.request(id)
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func row(_ step: Step) -> some View {
        HStack(spacing: 12) {
            icon(step.symbol, tint: step.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title).font(.body.weight(.medium))
                    if !step.required {
                        Text(L("Optional"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if step.granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                if asking == step.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Allow…")) { allow(step.id) }
                        .buttonStyle(.bordered)
                        .disabled(asking != nil)
                }
            }
        }
        .padding(12)
        .animation(.snappy, value: step.granted)
    }
}
