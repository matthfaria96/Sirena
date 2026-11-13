/// GoToPath.swift
///
/// "Go to a path" at the bottom of the menu: paste or type a path and Finder opens it — a folder
/// in a window of its own, a file (or an app, a package) selected in its folder. Takes what
/// people actually copy: `~/…`, a path in quotes, Terminal's `My\ Folder`, a `file://` URL, a
/// path relative to the home folder. A path copied just before opening the menu is already in
/// the field.

import AppKit
import SwiftUI

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

    @MainActor
    static func open(_ target: PathTarget) {
        switch target {
        case .folder(let url), .missing(closest: .some(let url)):
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path(percentEncoded: false))
        case .file(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .missing(closest: nil):
            return
        }
        // Finder doesn't always come forward on its own when Sirena opened the window.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    }

    /// The clipboard, when it holds a path (as text, or a file copied in Finder).
    @MainActor
    static func pathOnClipboard() -> String? {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            return url.path(percentEncoded: false)
        }
        guard let text = board.string(forType: .string), text.count < 2048 else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let start = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“‘`"))
        guard start.hasPrefix("/") || start.hasPrefix("~") || start.lowercased().hasPrefix("file://") else { return nil }
        return line
    }

    /// `/Users/me/Documents` → `~/Documents`, for the lines under the field.
    static func shortened(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == trimmedHome { return "~" }
        if path.hasPrefix(trimmedHome + "/") { return "~" + path.dropFirst(trimmedHome.count) }
        return path
    }
}

/// The field inside the menu, with one quiet line saying what Enter will do.
struct InlineGoToPathPanel: View {
    let close: () -> Void
    @State private var text = ""
    @State private var target: PathTarget?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("Paste or type a path"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .onSubmit(go)
                Button(action: go) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(canGo ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .disabled(!canGo)
                .help(L("Open in Finder (Return)"))
                .accessibilityLabel(L("Open"))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            status
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if let copied = PathOpener.pathOnClipboard() { text = copied }
            // Focused once the panel is in place; the whole text gets selected, so ⌘V replaces it.
            DispatchQueue.main.async { focused = true }
        }
        .task(id: text) {
            // Read the disk off the main thread, a moment after the last keystroke.
            guard let path = PathOpener.path(from: text) else { target = nil; return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) { PathOpener.target(at: path) }.value
            guard !Task.isCancelled else { return }
            target = found
        }
    }

    private var canGo: Bool {
        switch target {
        case .folder, .file, .missing(closest: .some): return true
        default: return false
        }
    }

    @ViewBuilder private var status: some View {
        switch target {
        case .folder:
            Text(L("Opens this folder in Finder")).foregroundStyle(.secondary)
        case .file:
            Text(L("Shows it selected in its folder")).foregroundStyle(.secondary)
        case .missing(closest: .some(let url)):
            Text(L("Nothing here — Return opens \(PathOpener.shortened(url))")).foregroundStyle(.orange)
        case .missing(closest: nil):
            Text(L("Nothing at this path")).foregroundStyle(.orange)
        case nil:
            Text(L("~/, quotes, Terminal escapes and file:// all work")).foregroundStyle(.tertiary)
        }
    }

    private func go() {
        // Read again: Return may come before the check of the last keystroke.
        guard let path = PathOpener.path(from: text) else { return }
        let current = PathOpener.target(at: path)
        target = current
        if case .missing(closest: nil) = current { return }
        close()
        PathOpener.open(current)
    }
}
