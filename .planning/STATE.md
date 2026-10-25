

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-20)

**Core value:** Every feature the user turns on works reliably and smoothly, without crashes, hangs or battery drain, on macOS 15 through 27.
**Current focus:** Phase 1: Stability and Performance

## Current Position

Phase: 2 of 3 (tests)
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-24 (v0.5.0 release)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 3

## Accumulated Context

### Decisions

- Phase order set by owner: Stability + performance, Tests, Cleanup.

### Pending Todos

None yet.

### Releases

- 2026-10-24: v0.5.0 released (bundles the unreleased 0.4.1/0.4.2 work, the phase 1 stability fixes and the crisper menu bar icon). Phase 1 human checks are still pending.
- 2026-10-25: v0.5.2 built locally (not published): Sparkle 2 in-app updates (app menu + About, daily check, feed witchmymac.com/appcast/sirena.xml) and release builds re-signed with the witchmymac certificate so permissions survive updates. Outside the GSD phases; see CLAUDE.md.
- 2026-10-25: v0.5.3 built locally (not published): AccessibilityGuard — revoking Accessibility no longer freezes the Mac (taps dropped at once, never re-enabled without trust); simpler onboarding (Accessibility, then Screen Recording last); Sobre is its own page.

### Blockers/Concerns

- Disk nearly full (~5 GB free): keep build artifacts small.
- macOS 15.7 VM cannot grant TCC permissions without the owner.

## Session Continuity

Last session: 2026-10-20
Stopped at: Roadmap created
Resume file: None
