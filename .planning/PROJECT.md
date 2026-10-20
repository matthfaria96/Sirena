# Sirena

## What This Is

Sirena is a free macOS menu bar app (macOS 15 Sequoia and later, universal build) that gathers everyday utilities in one place: window management, Dock previews, a ⌘ Tab switcher, clipboard history, text capture (OCR), screen capture, Pomodoro, a color picker, freehand screen drawing, keep-awake, turn off display, a per-app sound mixer, hidden menu bar icons, a file shelf and a Dynamic Island in the notch. It is distributed as an ad-hoc signed DMG through GitHub Releases and witchmymac.com. The UI is in Brazilian Portuguese.

## Core Value

Every feature the user turns on works reliably and smoothly, without crashes, hangs or battery drain, on macOS 15 through 27.

## Requirements

### Validated

- ✓ Window management (Rectangle port): snapping, shortcuts, edge-drag tiling. macOS tiling is turned off silently. — existing
- ✓ Dock previews and dock-click hide/restore (DockDoor port) — existing
- ✓ ⌘ Tab switcher with previews (Vorssaint port) — existing
- ✓ Clipboard history (Maccy port, SwiftData) — existing
- ✓ Text capture with OCR and QR codes — existing
- ✓ Screen capture through macOS screencapture: copies and saves to Desktop or Pictures › Screenshots — existing (v0.4.2)
- ✓ Freehand drawing with area or full-screen screenshots, saved and copied — existing (v0.4.1)
- ✓ Hidden menu bar icons: native on macOS 27, separator technique on older versions — existing (v0.4.0)
- ✓ Keep awake, turn off display, sound mixer, Pomodoro, color picker, mirror, shelf, Dynamic Island — existing
- ✓ macOS 15 support with glass fallbacks (GlassCompat helpers) — existing (v0.4.0)
- ✓ The main window stays hidden while tools are used and only opens when asked for — existing (v0.4.2)

### Active

- [ ] Clipboard history recovers from a corrupt or unreadable store instead of crashing on every launch
- [ ] The media/lyrics features stop polling Music/Spotify through osascript every 0.5–1 s and stop the 20 Hz lyrics timer when nothing is shown
- [ ] Window gestures never block input inside the event tap (no Thread.sleep or slow AX calls in the tap callback)
- [ ] No force unwraps or fatalError on recoverable paths in private-API wrappers (`CGError(rawValue: -1)!`)
- [ ] A test target exists and covers window calculations and pure *Support logic
- [ ] Unused dependencies are removed (HotKey, SwiftHEXColors, swift-syntax)

### Out of Scope

- Notarization and Hardened Runtime: needs a paid Apple Developer account, which the owner decided not to have
- Replacing private APIs: they power core features (window server, glass, menu bar). They are monitored, not removed.
- New features: this cycle only covers stability, tests and cleanup
- Intel runtime testing: no Intel hardware or VM is available. Builds stay universal.

## Context

- Brownfield. The codebase map lives in `.planning/codebase/` (2026-10-20). `CONCERNS.md` ranks the risks.
- Single-process AppKit/SwiftUI app with 4 targets: Sirena, DockKit, ClipboardKit and SirenaFinder. There is no test target.
- Modules are ported from open-source apps (Rectangle, DockDoor, Maccy, Hidden Bar, Caffeine, Vorssaint, Iris). They have mixed conventions and Swift 5/6 language modes.
- A macOS 15.7 test VM exists (tart, `sequoia-sirena`, on the Midias drive). The owner's Mac runs macOS 27. The VM can't grant TCC permissions without the owner.
- Releases: `scripts/package-release.sh` produces an ad-hoc signed DMG. Each update makes macOS ask for Accessibility and Screen Recording again.
- The owner's disk is nearly full (about 5 GB free). Keep build artifacts small and clean them up.

## Constraints

- **Platform**: macOS 15.0+ deployment target, built with Xcode 27 (SDK 27). Watch for SDK-27-only symbols leaking into older OS runtime paths.
- **Distribution**: ad-hoc signing, no notarization.
- **Language**: UI strings go through `L(...)` into `Sirena/Resources/Sirena.xcstrings` (pt-BR).
- **Git**: conventional commits (feat/fix/chore/docs/test/refactor/perf/ci).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Support macOS 15+ with glass fallbacks | Reach older Macs without Liquid Glass | ✓ Good (v0.4.0) |
| Ad-hoc signed releases | No paid developer account | ⚠️ Revisit: permissions reset on every update |
| Stability cycle before new features | The owner wants it at 100% and smooth | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-20 after initialization*
