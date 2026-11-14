/// GoToPath.swift
///
/// Reading a path the way people copy it, for the Finder's address bar (FinderAddressBar):
/// `~/…`, `$HOME`, a path in quotes, Terminal's `My\ Folder`, a `file://` URL, a path relative
/// to the home folder. And what is there: a folder, a file (an app or a bundle counts as a
/// file: Finder shows it selected, it doesn't open it), or nothing.

import Foundation

enum PathTarget: Equatable {
    case folder(URL)
    case file(URL)
    /// Nothing there; the closest folder that exists, if it isn't just "/".
    case missing(closest: URL?)
}

enum PathOpener {
    /// The path written in `raw`, cleaned up and absolute, or nil when there's nothing to go to.
    static func path(from raw: String) -> String? {
        // The first line only: a copied path often brings a newline along.
        var text = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        text = text.trimmingCharacters(in: .whitespaces)
        let quotes: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"), ("`", "`")]
        while text.count >= 2, quotes.contains(where: { text.first == $0.0 && text.last == $0.1 }) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("file://") {
            guard let url = URL(string: text) ?? URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
                  url.isFileURL else { return nil }
            text = url.path(percentEncoded: false)
        } else if text.contains("\\") {
            // Terminal escapes spaces and symbols (`My\ Folder`); a real backslash is "\\".
            var unescaped = ""
            var escaping = false
            for character in text {
                if escaping || character != "\\" {
                    unescaped.append(character)
                    escaping = false
                } else {
                    escaping = true
                }
            }
            text = unescaped
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if text == "$HOME" || text.hasPrefix("$HOME/") { text = home + text.dropFirst("$HOME".count) }
        text = (text as NSString).expandingTildeInPath
        if !text.hasPrefix("/") { text = (home as NSString).appendingPathComponent(text) }
        return (text as NSString).standardizingPath
    }

    /// What's at `path`. Reads the disk: call it off the main thread (a network volume can hang).
    static func target(at path: String) -> PathTarget {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        if manager.fileExists(atPath: path, isDirectory: &isFolder) {
            let url = URL(fileURLWithPath: path, isDirectory: isFolder.boolValue)
            // An app or a bundle is a folder Finder shows as a file: select it, don't open it.
            let isPackage = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
            if isFolder.boolValue, !isPackage { return .folder(url) }
            return .file(url)
        }
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1 {
            if manager.fileExists(atPath: parent, isDirectory: &isFolder), isFolder.boolValue {
                return .missing(closest: URL(fileURLWithPath: parent, isDirectory: true))
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return .missing(closest: nil)
    }

}
