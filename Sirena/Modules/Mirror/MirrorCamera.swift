/// MirrorCamera.swift
///
/// The capture session behind the mirror. It runs only while the mirror is on screen,
/// so the camera light is off the rest of the time.

import AVFoundation
import AppKit

enum MirrorCameraError: LocalizedError {
    case permissionDenied
    case noCamera

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L("Sirena needs camera access. Enable it in System Settings > Privacy & Security > Camera.")
        case .noCamera:
            return L("No camera device found. Please connect a camera.")
        }
    }
}

final class MirrorCamera: NSObject {
    static let shared = MirrorCamera()

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "sirena.mirror.camera")
    private var input: AVCaptureDeviceInput?
    private var photoHandler: ((NSImage?) -> Void)?

    private(set) var currentDevice: AVCaptureDevice?

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged),
                                               name: .AVCaptureDeviceWasDisconnected, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Asks for permission if needed, picks the camera and starts the session.
    func start() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw MirrorCameraError.permissionDenied }
        default:
            throw MirrorCameraError.permissionDenied
        }

        let preferred = MirrorSettings.shared.cameraID.flatMap { id in Self.availableCameras().first { $0.uniqueID == id } }
        guard let device = preferred ?? AVCaptureDevice.default(for: .video) ?? Self.availableCameras().first else {
            throw MirrorCameraError.noCamera
        }
        if device.uniqueID != currentDevice?.uniqueID || input == nil {
            use(device)
        }
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func switchTo(_ device: AVCaptureDevice) {
        MirrorSettings.shared.cameraID = device.uniqueID
        use(device)
    }

    /// Reconfigured on the session's own queue, never racing startRunning/stopRunning.
    private func use(_ device: AVCaptureDevice) {
        let newInput = try? AVCaptureDeviceInput(device: device)
        let old = input
        queue.sync { [session] in
            session.beginConfiguration()
            if let old { session.removeInput(old) }
            if let newInput, session.canAddInput(newInput) { session.addInput(newInput) }
            session.commitConfiguration()
        }
        if let newInput { input = newInput; currentDevice = device }
    }

    @objc private func devicesChanged(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice, device.uniqueID == currentDevice?.uniqueID,
              let fallback = Self.availableCameras().first(where: { $0.uniqueID != device.uniqueID }) else { return }
        use(fallback)
    }

    @objc private func systemDidWake() {
        // After sleep the input can be left dead while the session still reports running.
        guard let device = currentDevice else { return }
        use(device)
    }

    // MARK: - Snaps

    func capturePhoto(_ completion: @escaping (NSImage?) -> Void) {
        guard session.isRunning else { return completion(nil) }
        photoHandler = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension MirrorCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { NSImage(data: $0) }
        DispatchQueue.main.async {
            self.photoHandler?(image)
            self.photoHandler = nil
        }
    }
}
