/// FinderAddressBar.swift
///
/// An address bar for the Finder, like Windows Explorer's: ⌘L in a Finder window (or the
/// Sirena button in its toolbar) lays an editable path over the window's toolbar, holding the
/// folder it shows, selected. Paste or type another one and Return takes *that same window*
/// there — a file's folder opens with the file selected. As you type, the folders (and files)
/// that match show below; ↑ ↓ choose, Tab completes, Esc or a click elsewhere leaves.
///
/// Nothing can go inside the Finder's own toolbar (an extension may only add a button, and
/// injecting code into the Finder needs SIP off), so this is Sirena's own panel laid over it.
/// Which folder a window shows, and showing another one, go through Apple Events (the Finder
/// doesn't tell Accessibility): `osascript`, off the main thread, so a Finder that hangs, or
/// the one-time "Sirena wants to control Finder" prompt, never stalls Sirena.

import AppKit
import SwiftUI

// MARK: - Talking to the Finder

enum FinderScripting {
    enum Failure: Error {
        /// Sirena isn't allowed to control the Finder (Privacy › Automation).
        case notAllowed
        case failed
    }

    /// The folder the front Finder window shows; nil when it shows no folder (Recents,
    /// AirDrop, a search) or there is no window.
    static func frontFolder(_ done: @escaping @MainActor (Result<String?, Failure>) -> Void) {
        run("""
            tell application "Finder"
                if (count of Finder windows) = 0 then return ""
                try
                    return POSIX path of (target of front Finder window as alias)
                on error
                    return ""
                end try
            end tell
            """, arguments: []) { result in
            done(result.map { $0.isEmpty ? nil : $0 })
        }
    }

    /// The front Finder window goes to `path` (a new window when there is none). A file (or an
    /// app, a package): its folder, with it selected.
    static func show(_ path: String, isFolder: Bool, _ done: @escaping @MainActor (Result<String, Failure>) -> Void) {
        run("""
            on run argv
                set destination to (POSIX file (item 1 of argv)) as alias
                tell application "Finder"
                    if (count of Finder windows) = 0 then make new Finder window
                    if (item 2 of argv) is "folder" then
                        set target of front Finder window to destination
                    else
                        set target of front Finder window to (container of destination)
                        select destination
                    end if
                end tell
                return ""
            end run
            """, arguments: [path, isFolder ? "folder" : "file"], done)
    }

    private static func run(_ script: String, arguments: [String],
                            _ done: @escaping @MainActor (Result<String, Failure>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script] + arguments
            let output = Pipe()
            let errors = Pipe()
            task.standardOutput = output
            task.standardError = errors
            let result: Result<String, Failure>
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    result = .success((String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines))
                } else {
                    // -1743: not allowed to send Apple Events to the Finder.
                    result = .failure(errorText.contains("-1743") ? .notAllowed : .failed)
                }
            } catch {
                result = .failure(.failed)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - The bar

@MainActor
final class FinderAddressBar {
    static let shared = FinderAddressBar()

    private var panel: AddressPanel?
    fileprivate let model = FinderAddressModel()
    private var resignToken: NSObjectProtocol?
    private var deactivateToken: NSObjectProtocol?
    private var suggestionWork: DispatchWorkItem?
    /// Where the bar sits (Accessibility coordinates): its top left and width.
    private var anchor = CGRect.zero

    static let barHeight: CGFloat = 36
    static let rowHeight: CGFloat = 28
    static let maxSuggestions = 8
    /// Room around the bar for its shadow.
    static let margin: CGFloat = 14

    private init() {}

    var isShown: Bool { panel?.isVisible == true }

    /// Lays the bar over the front Finder window's toolbar (or near the top of the screen
    /// when there's no Finder window) and fills it with the folder that window shows.
    /// `text`: start with this typed in instead (sirena://finder-address?path=…).
    /// Only ever over the Finder in front: called from elsewhere (a script, a Shortcut), it
    /// brings the Finder forward first, so it never takes the keyboard from another app.
    func show(text: String? = nil) {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        if let finder, !finder.isActive {
            finder.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, finder.isActive else { return }
                self.show(text: text)
            }
            return
        }
        let window = finder.flatMap { Self.frontWindowFrame(of: $0.processIdentifier) }
        if let window {
            // After the traffic lights, across the toolbar.
            let left: CGFloat = window.width > 520 ? 84 : 12
            let width = max(300, window.width - left - 12)
            anchor = CGRect(x: window.minX + left, y: window.minY + 9, width: width, height: Self.barHeight)
        } else {
            let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame.screenFlipped
            let width = min(720, screen.width - 80)
            anchor = CGRect(x: screen.midX - width / 2, y: screen.minY + 120, width: width, height: Self.barHeight)
        }

        model.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        layout()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        model.focusTick += 1
        watch()
        if let text, !text.isEmpty {
            model.edited = true
            model.replacement = text
            model.replaceTick += 1
            textChanged(text)
        }

        FinderScripting.frontFolder { [weak self] result in
            guard let self, self.isShown else { return }
            switch result {
            case .success(let path):
                if let path { self.model.setInitial(Self.displayed(path)) }
                self.model.folderIcon = path.map { NSWorkspace.shared.icon(forFile: $0) }
            case .failure(.notAllowed):
                self.model.problem = .notAllowed
                self.layout()
            case .failure(.failed):
                break
            }
            self.model.focusTick += 1
        }
    }

    func close(refocusFinder: Bool = true) {
        suggestionWork?.cancel()
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        if let deactivateToken { NSWorkspace.shared.notificationCenter.removeObserver(deactivateToken) }
        resignToken = nil
        deactivateToken = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        })
        if refocusFinder {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
        }
    }

    /// A click elsewhere, or another app coming forward, puts it away.
    private func watch() {
        if resignToken == nil, let panel {
            resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(refocusFinder: false) }
            }
        }
        if deactivateToken == nil {
            deactivateToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let app, app.bundleIdentifier != "com.apple.finder", app != .current else { return }
                    self?.close(refocusFinder: false)
                }
            }
        }
    }

    /// The panel grows with the list under the bar.
    private func layout() {
        guard let panel else { return }
        let rows = CGFloat(model.suggestions.count)
        let list = rows > 0 ? rows * Self.rowHeight + 12 + 6 : 0
        let message: CGFloat = model.problem == nil ? 0 : 30
        let frame = CGRect(x: anchor.minX - Self.margin, y: anchor.minY - Self.margin,
                           width: anchor.width + Self.margin * 2,
                           height: Self.barHeight + list + message + Self.margin * 2)
        panel.setFrame(frame.screenFlipped, display: true)
    }

    // MARK: Typing

    fileprivate func textChanged(_ text: String) {
        model.text = text
        model.highlighted = nil
        if model.problem != nil {
            model.problem = nil
            layout()
        }
        suggestionWork?.cancel()
        guard model.edited, let path = PathOpener.path(from: text) else {
            setSuggestions([])
            return
        }
        // What's typed after the last "/" is the start of a name in the folder before it.
        let endsWithSlash = text.trimmingCharacters(in: .whitespaces).hasSuffix("/")
        let folder = endsWithSlash ? path : (path as NSString).deletingLastPathComponent
        let prefix = endsWithSlash ? "" : (path as NSString).lastPathComponent
        let work = DispatchWorkItem { [weak self] in
            let found = Self.entries(in: folder, starting: prefix)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.model.text == text else { return }
                    self.setSuggestions(found)
                }
            }
        }
        suggestionWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    fileprivate func setSuggestions(_ entries: [FinderAddressModel.Entry]) {
        guard entries != model.suggestions else { return }
        model.suggestions = entries
        layout()
    }

    /// The folder's entries whose names start with `prefix` (case and accents ignored),
    /// folders first. Hidden ones only when the prefix asks for them.
    nonisolated private static func entries(in folder: String, starting prefix: String) -> [FinderAddressModel.Entry] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder) else { return [] }
        let wanted = prefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var found: [FinderAddressModel.Entry] = []
        for name in names {
            if name.hasPrefix("."), !prefix.hasPrefix(".") { continue }
            guard wanted.isEmpty || name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(wanted) else { continue }
            let full = (folder as NSString).appendingPathComponent(name)
            if case .missing = PathOpener.target(at: full) { continue }
            let isFolder: Bool
            if case .folder = PathOpener.target(at: full) { isFolder = true } else { isFolder = false }
            found.append(.init(name: name, path: full, isFolder: isFolder))
            if found.count > 200 { break }
        }
        found.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(found.prefix(maxSuggestions))
    }

    /// ↑ ↓ through the list.
    fileprivate func moveHighlight(_ step: Int) {
        guard !model.suggestions.isEmpty else { return }
        let count = model.suggestions.count
        if let current = model.highlighted {
            let next = current + step
            model.highlighted = next < 0 || next >= count ? nil : next
        } else {
            model.highlighted = step > 0 ? 0 : count - 1
        }
    }

    /// Tab: the highlighted entry (or the first) goes into the field; a folder ends in "/" so
    /// its contents show next.
    fileprivate func complete() {
        guard let entry = model.suggestions[safe: model.highlighted ?? 0] else { return }
        let text = Self.displayed(entry.path) + (entry.isFolder ? "/" : "")
        model.replaceTick += 1
        model.replacement = text
        textChanged(text)
    }

    /// Return: the highlighted entry, or what's in the field.
    fileprivate func commit() {
        let raw = model.highlighted.flatMap { model.suggestions[safe: $0]?.path } ?? model.text
        guard let path = PathOpener.path(from: raw) else { return }
        let target = PathOpener.target(at: path)
        let destination: (path: String, isFolder: Bool)
        switch target {
        case .folder(let url): destination = (url.path(percentEncoded: false), true)
        case .file(let url): destination = (url.path(percentEncoded: false), false)
        case .missing:
            model.problem = .missing
            model.shakeTick += 1
            layout()
            return
        }
        model.isGoing = true
        FinderScripting.show(destination.path, isFolder: destination.isFolder) { [weak self] result in
            guard let self else { return }
            self.model.isGoing = false
            switch result {
            case .success:
                self.close()
            case .failure(.notAllowed):
                self.model.problem = .notAllowed
                self.layout()
            case .failure(.failed):
                self.model.problem = .failed
                self.model.shakeTick += 1
                self.layout()
            }
        }
    }

    fileprivate func pick(_ index: Int) {
        model.highlighted = index
        commit()
    }

    /// Paths in the home folder keep their full form: it's what gets copied and pasted.
    private static func displayed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    // MARK: Windows

    /// The Finder's front regular window, in Accessibility coordinates (no Accessibility call:
    /// the window server's list, front to back).
    private static func frontWindowFrame(of pid: pid_t) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 320, frame.height >= 200 else { continue }
            return frame
        }
        return nil
    }

    private func makePanel() -> AddressPanel {
        let panel = AddressPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = FinderAddressView(model: model, bar: self)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        return panel
    }
}

/// Takes the keyboard without bringing Sirena forward: the Finder stays the app in front.
private final class AddressPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
@Observable
final class FinderAddressModel {
    struct Entry: Equatable, Identifiable {
        let name: String
        let path: String
        let isFolder: Bool
        var id: String { path }
    }

    enum Problem: Equatable { case missing, notAllowed, failed }

    var text = ""
    /// Typed into (not just filled with the window's folder): suggestions show from then on.
    var edited = false
    var suggestions: [Entry] = []
    var highlighted: Int?
    var problem: Problem?
    var isGoing = false
    var folderIcon: NSImage?
    /// The field takes `replacement` when this changes (filling it, Tab).
    var replacement = ""
    var replaceTick = 0
    /// Select everything in the field (the window's folder just arrived).
    var selectAll = false
    var focusTick = 0
    var shakeTick = 0

    func reset() {
        text = ""
        edited = false
        suggestions = []
        highlighted = nil
        problem = nil
        isGoing = false
        folderIcon = nil
        replacement = ""
        replaceTick += 1
        selectAll = false
    }

    func setInitial(_ path: String) {
        guard !edited else { return }
        text = path
        replacement = path
        selectAll = true
        replaceTick += 1
    }
}

// MARK: - The view

private struct FinderAddressView: View {
    let model: FinderAddressModel
    let bar: FinderAddressBar
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            field
            if let problem = model.problem { problemLine(problem) }
            if !model.suggestions.isEmpty { list }
            Spacer(minLength: 0)
        }
        .padding(FinderAddressBar.margin)
        .onChange(of: model.shakeTick) { _, _ in
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 7 }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4).delay(0.08)) { shake = 0 }
        }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 8) {
            Group {
                if let icon = model.folderIcon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "folder").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            AddressField(model: model, bar: bar)
                .frame(height: 20)
            if model.isGoing {
                ProgressView().controlSize(.small)
            } else {
                Text("↩")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.6))
                    .help(L("Return goes there · Tab completes · Esc closes"))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: FinderAddressBar.barHeight)
        // Nearly solid: the Finder's own toolbar is right under it and must not show through.
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.96)))
        .compatGlass(.regular, in: shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
        .overlay(shape.strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5).padding(-0.5))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .offset(x: shake)
    }

    private func problemLine(_ problem: FinderAddressModel.Problem) -> some View {
        HStack(spacing: 8) {
            switch problem {
            case .missing:
                Label(L("Nothing at this path"), systemImage: "questionmark.folder")
            case .failed:
                Label(L("The Finder couldn't open it"), systemImage: "exclamationmark.triangle")
            case .notAllowed:
                Label(L("Sirena needs permission to control the Finder"), systemImage: "lock")
                Spacer(minLength: 4)
                Button(L("Allow…")) { FinderScripting.openAutomationSettings() }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(problem == .notAllowed ? Color.secondary : Color.orange)
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, entry in
                SuggestionRow(entry: entry, isLit: model.highlighted == index) { bar.pick(index) }
                    .onHover { if $0 { model.highlighted = index } }
            }
        }
        .padding(6)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.96)))
        .compatGlass(.regular, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
        .overlay(shape.strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5).padding(-0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .transition(.opacity)
    }
}

private struct SuggestionRow: View {
    let entry: FinderAddressModel.Entry
    let isLit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(entry.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if entry.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: FinderAddressBar.rowHeight)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isLit ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The text field: AppKit's, for the keys a SwiftUI field won't hand over (Tab, ↑ ↓, Esc).
private struct AddressField: NSViewRepresentable {
    let model: FinderAddressModel
    let bar: FinderAddressBar

    func makeCoordinator() -> Coordinator { Coordinator(bar: bar) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingHead
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderString = L("Paste or type a path")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        if coordinator.replaceTick != model.replaceTick {
            coordinator.replaceTick = model.replaceTick
            field.stringValue = model.replacement
            if let editor = field.currentEditor() {
                let end = (model.replacement as NSString).length
                editor.selectedRange = model.selectAll ? NSRange(location: 0, length: end) : NSRange(location: end, length: 0)
            }
            model.selectAll = false
        }
        if coordinator.focusTick != model.focusTick {
            coordinator.focusTick = model.focusTick
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                if window.firstResponder !== field.currentEditor() { window.makeFirstResponder(field) }
                // Becoming first responder selects everything; that's what we want here.
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let bar: FinderAddressBar
        var replaceTick = -1
        var focusTick = -1

        init(bar: FinderAddressBar) { self.bar = bar }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            bar.markEdited()
            bar.textChanged(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): bar.commit(); return true
            case #selector(NSResponder.insertTab(_:)): bar.complete(); return true
            case #selector(NSResponder.moveDown(_:)): bar.moveHighlight(1); return true
            case #selector(NSResponder.moveUp(_:)): bar.moveHighlight(-1); return true
            case #selector(NSResponder.cancelOperation(_:)): bar.escape(); return true
            default: return false
            }
        }
    }
}

extension FinderAddressBar {
    /// Esc: the list first, then the bar.
    fileprivate func escape() {
        if !model.suggestions.isEmpty {
            model.highlighted = nil
            setSuggestions([])
        } else {
            close()
        }
    }

    fileprivate func markEdited() { model.edited = true }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
