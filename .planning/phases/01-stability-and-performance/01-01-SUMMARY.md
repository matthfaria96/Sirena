---
phase: 01-stability-and-performance
plan: 01
subsystem: stability
tags: [swiftdata, skylight, crash-fix]
requires: []
provides: [clipboard-store-recovery, trap-free-skylight-wrappers]
key-files:
  modified:
    - ClipboardKit/Storage.swift
    - DockKit/Utilities/PrivateApis.swift
requirements-completed: [STAB-01, STAB-02]
completed: 2026-10-20
---

# Phase 1 Plan 01: Clipboard store recovery and SkyLight force-unwrap Summary

Corrupt Clipboard.sqlite is moved aside (`.corrupt-<epoch>`, plus -wal/-shm), retried, then falls back to an in-memory container; SkyLight wrappers return `.failure` instead of trapping.

## Tasks
1. Storage.init three-step recovery (`moveStoreAside`, `inMemoryContainer`, os.Logger) - commit 9e8c041
2. `CGError(rawValue: -1)!` replaced by `.failure` at both sites; no other `)!` / `as!` in file - commit 9b7ccb6

Debug build: BUILD SUCCEEDED. Grep gates pass (one remaining fatalError, in-memory only).

## Deviations from Plan
None in code.

## Deferred: runtime corrupt-store check (VM)
Ran in tart VM `sequoia-sirena` (host untouched). Sirena launched and stayed running (PID shown) with a corrupt Clipboard.sqlite, but no `Clipboard.sqlite.corrupt-*` appeared: `Storage.shared` is only touched at launch inside `migrateUserDefaults` (all migrations already recorded in the VM defaults) or when clipboard UI is used, so the store was never opened. A second attempt after deleting `clipboard.migrations` also did not trigger it (clipboard controller apparently not started at launch in that VM config). Marked DEFERRED; needs a run that opens the clipboard (e.g. enable the feature or open the panel) with a corrupt store.

VM state: original store files restored; `clipboard.migrations` defaults key rewritten with the 4 known keys. Leftover files in VM home: `~/main.plist.bak`, `~/cur.plist.bak`, `~/clip.plist.bak`, `/tmp/Sirena.zip` (deletion blocked by safety check, harmless). Sirena.app in VM /Applications is the new Debug build.

## Self-Check: PASSED
