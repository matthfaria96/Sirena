/// MirrorPanel.swift
///
/// The mirror itself: a borderless glass panel with the live camera, and controls
/// that appear when the pointer is over it.

import AVFoundation
import AppKit
import SwiftUI

final class MirrorPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 270),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow
        let hosting = NSHostingView(rootView: MirrorView())
        // The controller sizes the panel; the SwiftUI content must not.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
}

/// Live camera preview layer.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let zoom: Double

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
        view.zoom = zoom
        view.needsLayout = true
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var mirrored = true
        var zoom = 1.0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            let scale = CGFloat(zoom)
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -scale : scale, y: scale))
            CATransaction.commit()
        }
    }
}

struct MirrorView: View {
    @State private var settings = MirrorSettings.shared
    @State private var meter = MirrorAudioMeter.shared
    @State private var isHovering = false
    @State private var flash = false
    @State private var state = MirrorState.shared

    private var cornerRadius: CGFloat { settings.shape == .circle ? 1000 : 22 }

    var body: some View {
        ZStack {
            CameraPreview(session: MirrorCamera.shared.session, mirrored: settings.mirrored, zoom: settings.zoom)

            if flash {
                Color.white.transition(.opacity)
            }

            // The peek's countdown, top center.
            if let left = state.peekRemaining {
                VStack {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                        Text("\(left)s")
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .animation(.snappy, value: left)
                    .padding(.top, settings.shape == .circle ? 22 : 10)
                    Spacer()
                }
            }

            VStack {
                Spacer()
                if settings.showMicrophoneLevel {
                    MicrophoneLevel(level: meter.level)
                        .padding(.horizontal, settings.shape == .circle ? 70 : 16)
                        .padding(.bottom, isHovering ? 4 : 14)
                }
                if isHovering {
                    controls
                        .padding(.bottom, settings.shape == .circle ? 26 : 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorDidSnap)) { _ in
            withAnimation(.easeOut(duration: 0.05)) { flash = true }
            withAnimation(.easeIn(duration: 0.35).delay(0.08)) { flash = false }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            ControlButton(symbol: "plus.magnifyingglass", help: L("Zoom")) {
                settings.zoom = settings.zoom >= 2 ? 1 : settings.zoom + 0.5
            }
            .overlay(alignment: .topTrailing) {
                if settings.zoom > 1 {
                    Text(settings.zoom == 1.5 ? "1.5×" : "2×")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 4, y: -4)
                }
            }
            ControlButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: L("Mirror the image")) {
                settings.mirrored.toggle()
            }
            if settings.snapsEnabled {
                ControlButton(symbol: "camera.shutter.button", help: L("Take a Snap"), prominent: true) {
                    MirrorController.shared.takeSnap()
                }
            }
            ControlButton(symbol: settings.displayMode == .popover ? "pip.exit" : "pip.enter",
                          help: settings.displayMode == .popover ? L("Detach as a floating window") : L("Attach to the menu bar")) {
                MirrorController.shared.toggleDisplayMode()
            }
            ControlButton(symbol: "gearshape", help: L("Settings…")) {
                MirrorController.shared.openSettings()
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

private struct ControlButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 15 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(prominent ? Color.white.opacity(0.22) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct MicrophoneLevel: View {
    let level: Float

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(level > 0.85 ? Color.orange : Color.green)
                        .frame(width: proxy.size.width * CGFloat(level))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .animation(.linear(duration: 0.08), value: level)
    }
}

extension Notification.Name {
    static let mirrorDidSnap = Notification.Name("sirena.mirrorDidSnap")
}
