/// DMGInstaller.swift
///
/// Supercharge's "install apps from disk images": open a .dmg that carries an app and
/// Sirena offers to install it. One click copies the app to Applications (replacing an
/// older copy, which goes to the Trash), ejects the disk image, moves the .dmg to the
/// Trash and opens the new app. Written from scratch after Supercharge's feature list.

import AppKit

@MainActor
final class DMGInstaller {
    static let shared = DMGInstaller()

    private var observer: NSObjectProtocol?
    /// Volumes already offered, so remounting or a second notification doesn't ask twice.
    private var offered = Set<URL>()

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { note in
            guard let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { DMGInstaller.shared.volumeDidMount(volume) }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    // MARK: - Detecting

    private func volumeDidMount(_ volume: URL) {
        guard TweaksSettings.shared.installFromDMG, !offered.contains(volume) else { return }
        Task.detached(priority: .userInitiated) {
            // Give Finder a moment to open its window and the volume to settle.
            try? await Task.sleep(for: .milliseconds(400))
            guard let image = Self.diskImage(mountedAt: volume),
                  image.pathExtension.lowercased() == "dmg",
                  let app = Self.singleApp(in: volume) else { return }
            await MainActor.run { DMGInstaller.shared.offer(app: app, volume: volume, image: image) }
        }
    }

    /// The .dmg file behind a mounted volume, from `hdiutil info`.
    nonisolated private static func diskImage(mountedAt volume: URL) -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }
        let target = volume.standardizedFileURL.path
        for image in images {
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mounted = entities.contains {
                ($0["mount-point"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == target
            }
            if mounted, let path = image["image-path"] as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// The one app at the top of the volume. Installers with several apps or a .pkg
    /// are left alone, like in Supercharge.
    nonisolated private static func singleApp(in volume: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: volume, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        if items.contains(where: { ["pkg", "mpkg"].contains($0.pathExtension.lowercased()) }) { return nil }
        let apps = items.filter {
            $0.pathExtension.lowercased() == "app"
                && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }
        return apps.count == 1 ? apps[0] : nil
    }

    // MARK: - Installing

    private func offer(app: URL, volume: URL, image: URL) {
        offered.insert(volume)
        let name = app.deletingPathExtension().lastPathComponent
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(app.lastPathComponent)
        let replacing = FileManager.default.fileExists(atPath: destination.path)

        let alert = NSAlert()
        alert.icon = NSWorkspace.shared.icon(forFile: app.path)
        alert.messageText = String(format: L("Install “%@”?"), name)
        alert.informativeText = replacing
            ? L("The version in Applications will be replaced (the old one goes to the Trash). Then the disk image is ejected and moved to the Trash.")
            : L("It will be copied to Applications. Then the disk image is ejected and moved to the Trash.")
        alert.addButton(withTitle: replacing ? L("Replace") : L("Install"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundleID = Bundle(url: app)?.bundleIdentifier
        Task.detached(priority: .userInitiated) {
            let result = await Self.install(app: app, to: destination, bundleID: bundleID, volume: volume, image: image)
            await MainActor.run {
                DMGInstaller.shared.offered.remove(volume)
                switch result {
                case .success(let installed):
                    NSWorkspace.shared.openApplication(at: installed, configuration: .init())
                case .failure(let error):
                    let fail = NSAlert(error: error)
                    fail.messageText = String(format: L("Couldn't install “%@”"), name)
                    fail.informativeText = error.localizedDescription
                    NSApp.activate()
                    fail.runModal()
                }
            }
        }
    }

    nonisolated private static func install(app: URL, to destination: URL, bundleID: String?,
                                            volume: URL, image: URL) async -> Result<URL, Error> {
        let fm = FileManager.default
        do {
            // Quit the old copy first, or it keeps running from the Trash.
            if let bundleID {
                let running = await MainActor.run { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) }
                for instance in running where instance.bundleURL?.standardizedFileURL == destination.standardizedFileURL {
                    _ = await MainActor.run { instance.terminate() }
                    for _ in 0..<50 where !instance.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
                    if !instance.isTerminated { _ = await MainActor.run { instance.forceTerminate() } }
                }
            }
            // Copy beside the destination first, so a failed copy never loses the old app.
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).sirena-install")
            try? fm.removeItem(at: staging)
            try runDitto(from: app, to: staging)
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.moveItem(at: staging, to: destination)

            // Eject, then trash the disk image (left in place if it's somewhere read-only).
            try? await NSWorkspace.shared.ejectVolume(at: volume)
            if fm.fileExists(atPath: image.path) {
                try? fm.trashItem(at: image, resultingItemURL: nil)
            }
            return .success(destination)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func runDitto(from source: URL, to destination: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = [source.path, destination.path]
        let errors = Pipe()
        task.standardError = errors
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Sirena.DMGInstaller", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? L("The app couldn't be copied to Applications.") : message])
        }
    }
}

private extension NSWorkspace {
    func ejectVolume(at url: URL) async throws {
        try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value
    }
}
