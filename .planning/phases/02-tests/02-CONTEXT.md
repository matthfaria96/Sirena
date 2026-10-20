# Phase 2: Tests - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss)

<domain>
## Phase Boundary

An automated test suite guards window calculations and pure helper logic. Covers TEST-01, TEST-02, TEST-03.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Implementation choices are at Claude's discretion. Use ROADMAP success criteria, `.planning/codebase/TESTING.md` (suggested first targets) and codebase conventions.

### Constraints from the owner
- The Xcode project uses PBXFileSystemSynchronizedRootGroup folders. A new test target needs a native target + synchronized group + scheme TestAction entry in `Sirena.xcodeproj/project.pbxproj` and `xcshareddata/xcschemes/Sirena.xcscheme`. Edit the pbxproj carefully (unique 24-hex IDs) or generate with a script; verify with `xcodebuild -list`.
- Prefer Swift Testing (`import Testing`) if the toolchain supports it for the macOS 15 deployment target, else XCTest. Unit tests hosted by the Sirena app (`@testable import Sirena`) are fine; tests must not need TCC permissions or touch the user's real data.
- Run with: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Sirena.xcodeproj -scheme Sirena -destination 'platform=macOS' -derivedDataPath ~/Library/Caches/sirena-dd` (disk has ~5 GB free).
- Hosted tests launch the app: make sure test runs don't start modules that hijack the user's session (event taps, ⌘ Tab, menu bar). If needed, detect `XCTestConfigurationFilePath` / a test env var at launch and skip `startEnabledModules`.
- Don't touch files outside scope (another session may edit AboutView and READMEs). Stage only the files you change.

</decisions>

<code_context>
## Existing Code Insights

- Window calculations: `Sirena/Modules/WindowManagement/WindowCalculation/` (Rectangle port: LeftRightHalfCalculation, thirds, maximize, center…).
- Pure helpers named in TESTING.md: `TimeoutCache`, `Throttler`, `*Support.swift` (Island/Switcher support enums).
- App entry: `Sirena/App/main.swift`, `AppDelegate.applicationDidFinishLaunching` starts modules.

</code_context>

<specifics>
## Specific Ideas

Refer to ROADMAP phase success criteria.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
