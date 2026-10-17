// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import SwiftUI

/// A quick mirror before video calls, inside the Dynamic Island. Adapted for
/// Sirena: only the island's embedded preview is kept, since Sirena's Mirror
/// module is the floating one. The capture session exists only while the
/// preview is on screen, so the camera light dies the moment it closes.
final class IslandCameraPreviewService: ObservableObject {
    static let shared = IslandCameraPreviewService()

    enum PreviewState {
        case idle, waitingPermission, starting, running, denied, noCamera, unavailable
    }

    @Published private(set) var state: PreviewState = .idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var isEmbeddedPresented = false
    private var captureGeneration = UUID()
    private var sessionRequest: IslandCameraPreviewRequest?
    private var sessionObservers: [NSObjectProtocol] = []

    /// The session is created on show and destroyed on hide. The view builds
    /// its preview layer from it while the panel is up.
    private(set) var session: AVCaptureSession?

    /// startRunning blocks for a moment, so every session mutation happens
    /// here and only state lands back on the main thread.
    private let sessionQueue = DispatchQueue(label: "sirena.island.camera-preview")
    private var deviceObservers: [NSObjectProtocol] = []
    /// When the permission dialog resolves, the app that was frontmost
    /// before it reactivates a beat later; that activation must not count
    /// as the user clicking away from a mirror they just allowed.
    private var permissionResolvedAt: Date?

    private init() {}

    func syncWithPreferences() {
        if !NotchCameraSupport.isEnabled() { hideEmbedded() }
    }

    func suspend() {
        hide()
    }

    private var isPresented: Bool { isEmbeddedPresented }

    var keepsNotchPermissionPrompt: Bool {
        isEmbeddedPresented && (state == .waitingPermission
            || permissionResolvedAt.map { Date().timeIntervalSince($0) < 1 } == true)
    }

    /// The notch calls this only from its explicit camera button. Ownership
    /// transfers from the floating mirror; the two never capture together.
    func showEmbedded() {
        let notch = NotchService.shared
        guard IslandSessionActivity.shared.isActive,
            NotchCameraSupport.canPresent(expanded: notch.expanded, selected: notch.selected),
            !isEmbeddedPresented else { return }
        hide()
        isEmbeddedPresented = true
        beginCapture()
    }

    func hideEmbedded() {
        guard isEmbeddedPresented else { return }
        hide()
    }

    @discardableResult
    func showInNotchIfEnabled() -> Bool {
        guard IslandSessionActivity.shared.isActive, NotchCameraSupport.isEnabled() else { return false }
        let notch = NotchService.shared
        notch.open(.camera)
        guard NotchCameraSupport.canPresent(expanded: notch.expanded, selected: notch.selected) else { return false }
        showEmbedded()
        return isEmbeddedPresented
    }

    func hide() {
        captureGeneration = UUID()
        isEmbeddedPresented = false
        permissionResolvedAt = nil
        removeDeviceObservers()
        stopSession()
        state = .idle
        devices = []
        selectedDeviceID = nil
    }

    // MARK: - Capture

    private func beginCapture() {
        captureGeneration = UUID()
        let generation = captureGeneration
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            state = .waitingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    IslandPermissions.shared.refresh()
                    guard let self, self.isPresented, self.captureGeneration == generation else { return }
                    self.permissionResolvedAt = Date()
                    if granted {
                        self.startSession()
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func startSession() {
        guard isPresented else { return }
        // A session may still be alive when a queued permission callback or
        // a device replug lands here; two running sessions would fight over
        // the camera, so the old one always stops first.
        stopSession()
        state = .starting
        installDeviceObservers()
        refreshDevices()
        guard let device = preferredDevice() else {
            state = .noCamera
            return
        }
        selectedDeviceID = device.uniqueID
        let session = AVCaptureSession()
        let request = IslandCameraPreviewRequest()
        sessionRequest = request
        self.session = session
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            sessionObservers.append(NotificationCenter.default.addObserver(forName: name, object: session,
                queue: .main) { [weak self] _ in
                    guard let self, self.isPresented, self.session === session else { return }
                    self.stopSession()
                    self.state = .unavailable
                })
        }
        sessionQueue.async { [weak self] in
            guard !request.isCancelled else { return }
            session.beginConfiguration()
            if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            let hasInput = !session.inputs.isEmpty
            if hasInput, !request.isCancelled {
                session.startRunning()
            }
            let isRunning = hasInput && session.isRunning
            DispatchQueue.main.async {
                guard let self, self.isPresented, self.session === session else { return }
                self.state = isRunning ? .running : .unavailable
                if !isRunning { self.stopSession() }
            }
        }
    }

    private func stopSession() {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        sessionObservers.removeAll()
        sessionRequest?.cancel(); sessionRequest = nil
        guard let session else { return }
        self.session = nil
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            for input in session.inputs {
                session.removeInput(input)
            }
        }
    }

    func retryCapture() {
        guard isPresented, state == .unavailable else { return }
        beginCapture()
    }

    func selectCamera(_ device: AVCaptureDevice) {
        activateCamera(device, rememberChoice: true)
    }

    private func activateCamera(_ device: AVCaptureDevice, rememberChoice: Bool) {
        guard device.uniqueID != selectedDeviceID else { return }
        selectedDeviceID = device.uniqueID
        if rememberChoice {
            // The system remembers this choice per app, so the next preview
            // opens on the same camera without a key of our own. Only an
            // explicit pick may land here: a fallback after a disconnect
            // would overwrite the remembered camera with a stand-in.
            AVCaptureDevice.userPreferredCamera = device
        }
        guard let session, let request = sessionRequest else { return }
        sessionQueue.async { [weak self] in
            guard !request.isCancelled else { return }
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            let hasInput = !session.inputs.isEmpty
            let isRunning = hasInput && session.isRunning
            DispatchQueue.main.async {
                guard let self, self.isPresented, self.session === session else { return }
                self.state = isRunning ? .running : .unavailable
                if !isRunning { self.stopSession() }
            }
        }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices
    }

    private func preferredDevice() -> AVCaptureDevice? {
        if let preferred = AVCaptureDevice.userPreferredCamera,
           devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
        return devices.first
    }

    /// Cameras coming and going (a Continuity iPhone arriving, a USB camera
    /// unplugged) only matter while the panel is up, so the observers live
    /// exactly as long as it does.
    private func installDeviceObservers() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSNotification.Name.AVCaptureDeviceWasConnected,
                     NSNotification.Name.AVCaptureDeviceWasDisconnected] {
            deviceObservers.append(center.addObserver(forName: name, object: nil,
                                                      queue: .main) { [weak self] _ in
                self?.handleDevicesChanged()
            })
        }
    }

    private func removeDeviceObservers() {
        for observer in deviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        deviceObservers = []
    }

    private func handleDevicesChanged() {
        guard isPresented else { return }
        refreshDevices()
        let selectedStillHere = devices.contains { $0.uniqueID == selectedDeviceID }
        switch state {
        case .running, .starting:
            if !selectedStillHere {
                if let fallback = devices.first {
                    activateCamera(fallback, rememberChoice: false)
                } else {
                    stopSession()
                    state = .noCamera
                }
            }
        case .noCamera:
            if !devices.isEmpty {
                startSession()
            }
        case .idle, .waitingPermission, .denied, .unavailable:
            break
        }
    }
}
