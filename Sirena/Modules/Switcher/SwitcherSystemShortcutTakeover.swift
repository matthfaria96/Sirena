// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Switches WindowServer symbolic hotkeys off for as long as a Vorssaint
/// feature wants a key macOS would otherwise answer, and gives them back on
/// every exit path. Only ids that are enabled right now are ever touched, and
/// the marker is written before each change so a crash can be repaired at the
/// next launch. Callers decide which ids; this decides how.
enum SwitcherSystemShortcutTakeover {
    private static let lock = NSLock()
    private static var suppressed: Set<Int32> = SwitcherSystemShortcutTakeoverSupport.migratedMarker(
        old: UserDefaults.standard.array(forKey: SwitcherDefaultsKey.switcherNativeHotkeysSuppressed) as? [Int],
        new: UserDefaults.standard.array(forKey: SwitcherDefaultsKey.systemShortcutsSuppressed) as? [Int])
    static let switcherSource = "switcher"
    private static var wanted: [String: Set<Int32>] = [:]
    private static var claims: [String: SwitcherGlobalShortcut] = [:]
    private static var takeOverKeys: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: SwitcherDefaultsKey.systemShortcutTakeOverKeys) ?? [])
    private static var wakeObserver: NSObjectProtocol?

    /// Raw-id callers (the switcher) say what they want under their own name.
    static func setWanted(_ ids: Set<Int32>, for source: String) {
        lock.lock()
        defer { lock.unlock() }
        if ids.isEmpty { wanted.removeValue(forKey: source) } else { wanted[source] = ids }
        applyLocked(desired: SwitcherSystemShortcutTakeoverSupport.union(of: wanted))
    }

    /// A feature whose hotkey just registered. Only shortcuts the user chose to
    /// take over resolve to any ids; everything else is a no-op that costs one
    /// dictionary write.
    static func claim(_ storageKey: String, shortcut: SwitcherGlobalShortcut) {
        lock.lock()
        claims[storageKey] = shortcut
        lock.unlock()
        refresh(storageKey)
    }

    static func release(_ storageKey: String) {
        lock.lock()
        claims.removeValue(forKey: storageKey)
        lock.unlock()
        setWanted([], for: storageKey)
    }

    /// The recorder's choice, kept as a preference so it survives a relaunch.
    static func setTakeOver(_ storageKey: String, _ on: Bool) {
        lock.lock()
        if on { takeOverKeys.insert(storageKey) } else { takeOverKeys.remove(storageKey) }
        UserDefaults.standard.set(takeOverKeys.sorted(), forKey: SwitcherDefaultsKey.systemShortcutTakeOverKeys)
        lock.unlock()
        refresh(storageKey)
    }

    static func isTakenOver(_ storageKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return takeOverKeys.contains(storageKey)
    }


    /// The live table can change under us (System Settings, another app, wake).
    /// Re-resolve every claim; `apply` only writes what actually differs.
    static func reconcile() {
        let keys: [String]
        lock.lock()
        keys = Array(claims.keys)
        lock.unlock()
        for key in keys { refresh(key) }
    }

    private static func refresh(_ storageKey: String) {
        lock.lock()
        let shortcut = takeOverKeys.contains(storageKey) ? claims[storageKey] : nil
        lock.unlock()
        guard let shortcut else {
            setWanted([], for: storageKey)
            return
        }
        // A nil table means the private calls are missing on this macOS, so
        // nothing could have been taken over and nothing needs handing back.
        guard let entries = SwitcherSymbolicHotKeys.liveEntries() else { return }
        setWanted(SwitcherSystemShortcutTakeoverSupport.ids(matching: shortcut, in: entries), for: storageKey)
    }

    /// Quit: every key a feature took over goes back, whichever feature held
    /// it. Not every claimant suspends in `applicationWillTerminate`, and the
    /// ones that do should not each have to remember this.
    static func restoreAll() {
        lock.lock()
        defer { lock.unlock() }
        wanted.removeAll()
        claims.removeAll()
        applyLocked(desired: [])
    }

    /// The transition itself. Callers hold `lock`, so the decision about what
    /// every source wants and the writes that follow are one critical section.
    private static func applyLocked(desired: Set<Int32>) {
        guard let setEnabled = SwitcherSymbolicHotKeys.setEnabled,
              let isEnabled = SwitcherSymbolicHotKeys.isEnabled else { return }
        let candidates = desired.union(suppressed)
        let currentlyEnabled = candidates.filter { isEnabled($0) }
        let transition = SwitcherSystemShortcutTakeoverSupport.transition(
            from: suppressed, to: desired, currentlyEnabled: currentlyEnabled)
        suppressed = SwitcherSystemShortcutTakeoverSupport.apply(
            transition, owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
    }

    /// Launch only repairs previous ownership. Keep ids a feature will claim
    /// again without toggling them; new suppression waits for its live handler.
    /// The old switcher marker, already absorbed into `suppressed`, is written to
    /// the shared key before it is removed, so a restore that fails here still
    /// has a marker to retry from.
    static func recoverIfNeeded(keeping desired: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        persist(suppressed)
        UserDefaults.standard.removeObject(forKey: SwitcherDefaultsKey.switcherNativeHotkeysSuppressed)
        guard let setEnabled = SwitcherSymbolicHotKeys.setEnabled else { return }
        // A feature that claimed before recovery ran (keep-awake registers
        // first) is a source too; keeping only the switcher's ids would give
        // its key back and leave it off.
        let keep = desired.union(SwitcherSystemShortcutTakeoverSupport.union(of: wanted))
        suppressed = SwitcherSystemShortcutTakeoverSupport.apply(
            SwitcherSystemShortcutTakeoverSupport.recoveryTransition(from: suppressed, keeping: keep),
            owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
        // What stayed off for the switcher is held on its behalf until its tap
        // comes up and says so itself. Recorded as its source, or the first
        // claim of the launch resolves what every source wants without those
        // ids and hands them straight back — the flip the keeping exists to
        // avoid. Only ids the marker already owned and that are still off are
        // recorded, so this still takes nothing new — an owned id macOS has
        // since re-enabled is left to the tap; if the tap never starts,
        // `syncWithPreferences` clears the entry and the keys go back as before.
        let isEnabled = SwitcherSymbolicHotKeys.isEnabled
        let held = desired.intersection(suppressed).filter { isEnabled?($0) != true }
        if !held.isEmpty { wanted[switcherSource] = held }
    }

    /// Wake can leave the live table changed under a claim that is still ours,
    /// so a held key is re-resolved after the switcher's own three seconds, which
    /// keep the two reconciles from racing the WindowServer right after wake.
    /// The observer exists only while some feature holds a key and goes away
    /// when the last one is given back, as the switcher does with its own; a Mac
    /// where nothing was ever taken over never installs it. Callers hold `lock`;
    /// the notification arrives later on the main queue and takes it afresh.
    private static func observeWake(_ holding: Bool) {
        if holding, wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reconcile() }
                }
        } else if !holding, let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private static func persist(_ ids: Set<Int32>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: SwitcherDefaultsKey.systemShortcutsSuppressed)
        } else {
            UserDefaults.standard.set(ids.map(Int.init).sorted(), forKey: SwitcherDefaultsKey.systemShortcutsSuppressed)
        }
    }
}
