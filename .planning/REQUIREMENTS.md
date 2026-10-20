# Requirements: Sirena

**Defined:** 2026-10-20
**Core Value:** Every feature the user turns on works reliably and smoothly, without crashes, hangs or battery drain, on macOS 15 through 27.

## v1 Requirements

### Stability

- [ ] **STAB-01**: When the clipboard history store can't be opened (corrupt or migration failure), Sirena moves it aside, starts with a fresh store and keeps running instead of hitting `fatalError` (`ClipboardKit/Storage.swift`).
- [ ] **STAB-02**: Private-API wrappers have no force unwraps or traps on recoverable paths (e.g. `CGError(rawValue: -1)!` in `DockKit/Utilities/PrivateApis.swift`). Failures return errors instead.
- [ ] **STAB-03**: The window-gesture event tap callback never sleeps or does slow work synchronously. Delays and AX calls move off the tap thread (`DockKit/Utilities/Window Gestures/WindowGestureExecutor.swift`).

### Performance

- [ ] **PERF-01**: Media info stops spawning `osascript` every 0.5–1 s when the Dynamic Island or media widget isn't visible, and polls much less often when it is (`DockKit/Models/MediaInfo.swift`).
- [ ] **PERF-02**: The 20 Hz lyrics timer only runs while lyrics are on screen and stops when they are hidden or playback pauses.

### Testing

- [ ] **TEST-01**: An Xcode unit test target (SirenaTests) builds and runs with `xcodebuild test` on the Sirena scheme.
- [ ] **TEST-02**: Window calculations in `Sirena/Modules/WindowManagement/WindowCalculation/` have tests for the halves, thirds, maximize and center actions on a sample screen.
- [ ] **TEST-03**: Pure helper logic has tests (e.g. `TimeoutCache`/`Throttler`, `*Support.swift` functions without UI dependencies).

### Cleanup

- [ ] **CLEAN-01**: The unused SPM packages HotKey and SwiftHEXColors are unlinked and removed. swift-syntax is removed if nothing resolves it. The app still builds and runs.

## v2 Requirements

### Distribution

- **DIST-01**: Stable code signing identity so updates keep TCC permissions

### Observability

- **OBS-01**: Unified logging (one os.Logger approach instead of mixed print/DebugLogger)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Notarization / Hardened Runtime | Needs a paid Apple Developer account |
| Removing private APIs | They power core features. Monitored instead. |
| New user-facing features | This cycle is stability only |
| Intel runtime tests | No Intel hardware or VM |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STAB-01 | Phase 1 | Pending |
| STAB-02 | Phase 1 | Pending |
| STAB-03 | Phase 1 | Pending |
| PERF-01 | Phase 1 | Pending |
| PERF-02 | Phase 1 | Pending |
| TEST-01 | Phase 2 | Pending |
| TEST-02 | Phase 2 | Pending |
| TEST-03 | Phase 2 | Pending |
| CLEAN-01 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-20*
*Last updated: 2026-10-20 after initial definition*
