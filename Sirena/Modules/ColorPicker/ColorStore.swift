/// ColorStore.swift
///
/// JSON persistence in ~/Library/Application Support/Sirena/Colors/.

import Foundation
import os

enum ColorStore {
    private static let log = os.Logger(subsystem: "Sirena", category: "ColorPicker")

    static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Sirena/Colors", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { log.error("Could not create colors directory: \(error.localizedDescription)") }
        return dir
    }()

    /// Missing file → nil. Unreadable/corrupt file → moved aside to `.bak` (so a later
    /// save can't overwrite the user's data), logged, then nil.
    static func load<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let url = directory?.appendingPathComponent(file),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try dec.decode(type, from: data)
        } catch {
            log.error("Could not read \(file): \(error.localizedDescription); moving it aside")
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            do { try FileManager.default.moveItem(at: url, to: backup) }
            catch { log.error("Could not back up \(file): \(error.localizedDescription)") }
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, file: String) {
        guard let url = directory?.appendingPathComponent(file) else { return }
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
            try enc.encode(value).write(to: url, options: .atomic)
        } catch {
            log.error("Could not save \(file): \(error.localizedDescription)")
        }
    }
}
