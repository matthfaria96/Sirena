# Roadmap: Sirena

## Overview

A stability cycle for an existing app, in the order the owner asked for: first remove the crash and battery risks, then add a test safety net, then clean out unused dependencies. No new features.

## Phases

- [x] **Phase 1: Stability and Performance** - No crash loops, no input stalls, no wasteful media polling (completed 2026-10-20)
- [ ] **Phase 2: Tests** - A test target that runs and covers window math and pure helper logic
- [ ] **Phase 3: Cleanup** - Unused packages removed and the app still builds and runs

## Phase Details

### Phase 1: Stability and Performance
**Goal**: Every enabled feature runs without crashing, stalling input or draining battery in the background
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: STAB-01, STAB-02, STAB-03, PERF-01, PERF-02
**Success Criteria** (what must be TRUE):
  1. With a corrupt or unreadable clipboard store, Sirena launches, keeps the bad file aside and shows an empty clipboard history instead of crashing
  2. Window gestures (scroll/drag) never make keyboard or scroll input lag, and the system does not disable the event tap because of a stalled callback
  3. When the SkyLight private API is unavailable, the affected feature fails gracefully and the app keeps running (no trap from a force unwrap)
  4. With the Dynamic Island or media widget hidden, Activity Monitor shows no repeated `osascript` processes, and while visible they spawn far less often than every 0.5-1 s
  5. The lyrics timer is idle when lyrics are hidden or playback is paused (no 20 Hz wakeups)
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Clipboard store recovery (STAB-01) and trap-free SkyLight wrappers (STAB-02)
- [x] 01-02-PLAN.md — Gesture session window-frame AX read moved off the event-tap thread (STAB-03)
- [x] 01-03-PLAN.md — Slower osascript polling and gated lyrics timer (PERF-01, PERF-02)

### Phase 2: Tests
**Goal**: The owner can run an automated test suite that guards window calculations and pure helper logic
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. `xcodebuild test` on the Sirena scheme builds the SirenaTests target and runs it to completion
  2. Tests for halves, thirds, maximize and center on a sample screen pass, and break if a calculation changes
  3. Tests for `TimeoutCache`/`Throttler` and UI-free `*Support.swift` functions pass
**Plans**: TBD

### Phase 3: Cleanup
**Goal**: The project carries no unused dependencies
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: CLEAN-01
**Success Criteria** (what must be TRUE):
  1. HotKey and SwiftHEXColors no longer appear in the project's package list, and swift-syntax is gone if nothing resolves it
  2. The app builds, launches and the test suite from Phase 2 still passes
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Stability and Performance | 3/3 | Complete    | 2026-10-20 |
| 2. Tests | 0/TBD | Not started | - |
| 3. Cleanup | 0/TBD | Not started | - |
