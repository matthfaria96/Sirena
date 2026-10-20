# Testing Patterns

**Analysis Date:** 2026-10-20

## Current State

**No automated test target exists.** The project has no XCTest or Swift Testing targets, and no Swift file imports `XCTest` or `Testing`.

Evidence:
- `Sirena.xcodeproj/project.pbxproj` declares four native targets only: `Sirena` (application), `ClipboardKit` (framework), `DockKit` (framework), and `SirenaFinder` (app extension). None has `productType = "com.apple.product-type.bundle.unit-test"` or `com.apple.product-type.bundle.ui-testing`.
- No `*Tests*` directory or `*Spec*` file exists outside `References/` and `build/` (both excluded from analysis).
- `grep` for `import XCTest` and `import Testing` across all `.swift` sources returns nothing.
- `Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme` has no `<TestableReference>` entries.
- No `.github/workflows`, `Makefile`, or CI test step is present in the repository root. `scripts/package-release.sh` is a packaging script, not a test runner.
- No `jest`, `vitest`, `pytest`, or other test config files exist.

Consequence: all verification today is manual (run the app, exercise the feature). Any new test work starts from zero.

## Test Framework

**Runner:** None configured.

**Recommended for new work:**
- Swift Testing (`import Testing`, `@Test`, `#expect`) for pure logic, since the deployment target is macOS 15.0 and Swift Testing ships with the Xcode 16+ toolchain.
- XCTest (`XCTestCase`) is an acceptable alternative if UI automation (`XCUIApplication`) is needed. Swift Testing does not cover UI tests.

**Assertion library:** Built-in (`XCTAssert*` or `#expect` / `#require` depending on framework chosen).

**Run commands (once a test target exists):**
```bash
xcodebuild test -project Sirena.xcodeproj -scheme Sirena -destination 'platform=macOS'   # Run all tests
xcodebuild test -project Sirena.xcodeproj -scheme Sirena -destination 'platform=macOS' -only-testing:SirenaTests/<SuiteName>   # Single suite
xcodebuild test -project Sirena.xcodeproj -scheme Sirena -destination 'platform=macOS' -enableCodeCoverage YES   # Coverage
```
Note: the `Sirena` scheme currently has no test action, so these commands fail until a test target is added and wired into the scheme.

## Test File Organization

**Location (recommended):**
- Create a separate target, e.g. `SirenaTests`, with its own folder at the repository root: `SirenaTests/`. Do not put test files inside `Sirena/Modules/...`, which is the app target's source tree.
- Mirror the module path inside the test folder: `SirenaTests/WindowManagement/WindowCalculation/SpecifiedCalculationTests.swift` for `Sirena/Modules/WindowManagement/WindowCalculation/SpecifiedCalculation.swift`.

**Naming:**
- Test file: `<Type>Tests.swift` (e.g. `NotchLyricsSupportTests.swift`).
- Suite/type: `<Type>Tests`.

## Test Targets for Existing Code (where to start)

These areas are best suited for a first test target, because they contain pure logic with no AppKit/UI dependency. Each is cited by file path.

| Area | Files | Why testable |
|------|-------|--------------|
| Window snap/size math | `Sirena/Modules/WindowManagement/WindowCalculation/*.swift` (≈111 files, e.g. `SpecifiedCalculation.swift`, `AlmostMaximizeCalculation.swift`) | `calculateRect(_:)` is a pure function of `RectCalculationParameters` → `RectResult`. Only `Defaults` reads in init (`SpecifiedCalculation.init()` reads `Defaults.specifiedHeight/Width`); inject those values to test. |
| Window gesture resolution | `DockKit/Utilities/Window Gestures/WindowGestureResolver.swift`, `WindowGestureRecognizer.swift`, `WindowGestureZone.swift` | Resolver logic over geometry and input events. |
| Lyrics parsing and matching | `Sirena/Modules/Island/Services/NotchLyricsSupport.swift`, `NotchLyricsService.swift` | `*Support.swift` files hold pure logic (see CONVENTIONS.md). Test the Support file, not the service which owns network and `NSOpenPanel` state. |
| LRC parsing | `DockKit/Models/MediaInfo.swift` (around line 498 uses a regex `\[(\d{2}):(\d{2})\.(\d{2})\](.+)`) | Regex parsing, no UI. Note that the file also holds UI-coupled media state. |
| Search and sorting | `ClipboardKit/Search.swift`, `ClipboardKit/Sorter.swift`, `ClipboardKit/HighlightMatch.swift`, `DockKit/Utilities/StringMatchingUtil.swift` | Pure string and collection logic. |
| Keyboard layout / shortcuts | `ClipboardKit/KeyChord.swift`, `ClipboardKit/KeyShortcut.swift`, `ClipboardKit/KeyboardLayout.swift` | Value types with deterministic behavior. |
| Timeout cache | `Sirena/Modules/WindowManagement/Utilities/TimeoutCache.swift` | Self-contained data structure. Has force-unwraps (`entry!`), so tests should cover expiry edge cases. |
| Throttling | `ClipboardKit/Throttler.swift` | Time-dependent; needs an injectable clock. |
| Collection helpers | `ClipboardKit/Extensions/Array+MoveElements.swift`, `ClipboardKit/Extensions/Collection+Surrounding.swift`, `ClipboardKit/Extensions/Dictionary+RemoveItem.swift`, `ClipboardKit/ConcatenatedCollection.swift` | Pure extensions. |
| Pomodoro state | `Sirena/Modules/Pomodoro/PomodoroController.swift` (`PomodoroPhase`) | Enum with `title` / `symbol` / `color`; the controller is stateful and uses timers and notifications, so test the enum and split pure transitions out first. |

**Not practical to unit-test as-is:** `DockKit/Utilities/DockObserver.swift`, `DockKit/Utilities/EventTapThread.swift`, `DockKit/Utilities/PrivateApis.swift`, `DockKit/Extensions/AXUIElement.swift`, `ClipboardKit/Accessibility.swift`, `Sirena/Modules/ScreenCapture/`, and anything under `Sirena/Modules/Island/UI/`. These depend on live Accessibility permission, event taps, private APIs, or real windows; cover them with manual or UI tests.

## Test Structure

**Suite organization (recommended, Swift Testing):**
```swift
import Testing
@testable import Sirena

@Suite("SpecifiedCalculation")
struct SpecifiedCalculationTests {

    @Test("fractional size is a share of the visible frame")
    func fractionalSizeScalesToVisibleFrame() {
        // Arrange: inject the Defaults values before constructing
        // Act: calculate
        // Assert
        #expect(...)
    }
}
```

**Suite organization (if XCTest is chosen):**
```swift
import XCTest
@testable import Sirena

final class SpecifiedCalculationTests: XCTestCase {
    override func setUp() { super.setUp() }
    func testFractionalSizeScalesToVisibleFrame() {
        // Arrange / Act / Assert
        XCTAssertEqual(..., ...)
    }
}
```

**Patterns to adopt:**
- Arrange / Act / Assert, one behavior per test.
- Use `Defaults` suites scoped to the test (e.g. a throwaway `UserDefaults(suiteName:)`) so tests do not write to the real `com.matheusfaria.Sirena` preferences. The clipboard keys already use their own suite (`ClipboardKit/Extensions/Defaults.Keys+Names.swift`), which makes that isolation straightforward there.
- Floating-point geometry assertions: compare with a tolerance, since `round(...)` is used throughout `WindowCalculation` (`SpecifiedCalculation.swift`).

## Mocking

**Framework:** None. The codebase has no mocking library in `Package.resolved` and no `Mock*`/`Fake*` types. (A grep for `mock` matches `clock` and similar substrings; no real test doubles exist.)

**Current seams in the code:**
- `static let shared` singletons (`NotchLyricsService.shared`, `PomodoroSettings.shared`, `PomodoroMenuBarTimer.shared`) are not injectable. Adding an initializer parameter is the minimal change needed before testing them.
- Protocols are sparse (≈30 declarations). Where a seam exists, prefer protocols over subclassing. Window layouts use class inheritance (`WindowCalculation` → `SpecifiedCalculation`), which is testable by subclassing only if the base class is not `final`.
- `Defaults` keys are global `Defaults.Key` values. For tests, prefer writing values through a suite-scoped `UserDefaults` rather than mocking `Defaults`.

**What to mock:**
- Time (Throttler, TimeoutCache expiry, Pomodoro timers): pass a clock closure or a `Date` parameter.
- Network (lyrics fetch in `NotchLyricsService`): inject `URLSession` or a fetcher protocol. The service currently holds `private var session: URLSession?`.
- System services (EventKit, `NSWorkspace`, Accessibility): wrap behind a small protocol at the boundary; do not mock AppKit types directly.

**What NOT to mock:**
- Pure value types and geometry (`RectCalculationParameters`, `RectResult`, `CGRect` math).
- SwiftData models in `ClipboardKit/Models/` where an in-memory `ModelContainer` can be used instead (`ModelConfiguration(isStoredInMemoryOnly: true)`).

## Fixtures and Factories

**Test data:** None exists. Recommended location: `SirenaTests/Fixtures/`. Build small factory functions per model, for example:
```swift
func makeParameters(visible: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)) -> RectCalculationParameters {
    // construct with the minimal fields needed
}
```

**Lyric and media fixtures:** Use short inline LRC strings (`"[00:12.34]line"`) inside the test file rather than bundled resource files.

## Coverage

**Requirements:** None enforced. No coverage gate in the Xcode scheme or CI.

**Target:** The user-level rule in the global `rules/testing.md` asks for 80%+ coverage on code the user writes. Applying that to this repository means first creating the test target; until then coverage is 0% of measured code.

**View coverage (once a test target exists):**
```bash
xcodebuild test -project Sirena.xcodeproj -scheme Sirena -destination 'platform=macOS' -enableCodeCoverage YES
xcrun xccov view --report <path-to-.xcresult>
```

## Test Types

**Unit tests:** Not present. Recommended first target (see table above).

**Integration tests:** Not present. Candidates: `ClipboardKit/Storage.swift` with an in-memory SwiftData store; `DockKit` window discovery against real `CGWindowList` (only on a developer machine).

**UI tests:** Not present. The app is a menu bar app with a non-standard activation policy and a notch overlay, which makes `XCUIApplication` launch awkward. If UI tests are added, use a dedicated scheme and disable login-item and Accessibility prompts through a launch argument.

**E2E tests:** Not used. Manual verification is the current practice; see the `scripts/package-release.sh` workflow for release builds.

## Manual Verification (current practice)

Because there are no automated tests, the following areas have effectively no regression protection:
- Window snapping and multi-window layouts (`Sirena/Modules/WindowManagement/`).
- Dock hover previews and window gestures (`DockKit/`).
- Clipboard history persistence and migration (`ClipboardKit/Storage.swift`, `ClipboardKit/Observables/History.swift`).
- Island / notch overlay and media integration (`Sirena/Modules/Island/`).
- Preferences migrations (`DockKit/Extensions/NSScreen.swift` `migrateScreenIdentifier(_:)`).

## Common Patterns

**Async testing (Swift Testing):**
```swift
@Test func lyricsLoadsOnce() async throws {
    // Use an injected fetcher; await the service's async entry point
    let value = try await service.load(...)
    #expect(value != nil)
}
```

**Error testing (Swift Testing):**
```swift
@Test func rejectsInvalidInput() {
    #expect(throws: MirrorCameraError.self) {
        try parse(...)
    }
}
```
Use the existing error types as expectations, e.g. `MirrorCameraError` in `Sirena/Modules/Mirror/MirrorCamera.swift`, and `AxError` in `DockKit/Extensions/AXUIElement.swift`.

## Gaps Summary (priority order)

1. **Create the test target** (`SirenaTests`), add it to the `Sirena` scheme's Test action, and confirm `xcodebuild test` runs green on an empty suite.
2. **Window calculation tests**: cover `SpecifiedCalculation` and a sample of `*Calculation` subclasses, including the `<= 1` fraction vs. pixel branch.
3. **Pure support logic**: `NotchLyricsSupport`, `StringMatchingUtil`, `Search`, `Sorter`, `TimeoutCache`, `Throttler`.
4. **ClipboardKit storage**: in-memory SwiftData container tests for `Storage.swift` cleanup routines (`cleanupOrphanedContents()`).
5. **Injection refactors** before testing: replace `static let shared` access in `PomodoroSettings`, `NotchLyricsService` with injectable dependencies.

---

*Testing analysis: 2026-10-20*
