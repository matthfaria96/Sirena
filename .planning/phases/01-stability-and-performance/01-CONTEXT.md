# Phase 1: Stability and Performance - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss)

<domain>
## Phase Boundary

Every enabled feature runs without crashing, stalling input or draining battery in the background. Covers STAB-01, STAB-02, STAB-03, PERF-01, PERF-02 (see REQUIREMENTS.md).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion: discuss phase was skipped per user setting. Use ROADMAP phase goal, success criteria, `.planning/codebase/CONCERNS.md` and codebase conventions.

### Constraints from the owner
- Build with: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Sirena.xcodeproj -scheme Sirena -configuration Debug -derivedDataPath ~/Library/Caches/sirena-dd build` (disk has ~5 GB free; delete ~/Library/Caches/sirena-dd at the end).
- Deployment target macOS 15: don't introduce SDK-27-only symbols outside availability checks.
- Do not touch files outside this phase's scope (another session may edit AboutView and READMEs).
- UI strings through `L(...)` in `Sirena/Resources/Sirena.xcstrings` with pt-BR.

</decisions>

<code_context>
## Existing Code Insights

- `ClipboardKit/Storage.swift:27-33` — `fatalError` when ModelContainer fails.
- `DockKit/Utilities/PrivateApis.swift:161,167` — `CGError(rawValue: -1)!`; SkyLight globals at 130-157.
- `DockKit/Utilities/Window Gestures/WindowGestureExecutor.swift:121-135` — sleeps/AX inside event tap.
- `DockKit/Models/MediaInfo.swift` — osascript polling (lines ~13, ~44, 640-667) and 20 Hz lyrics timer (`startLyricsTimer`, ~565).

</code_context>

<specifics>
## Specific Ideas

Refer to ROADMAP phase success criteria.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
