# Coding Conventions

**Analysis Date:** 2026-10-20

## Scope

Analyzed: all Swift sources in the four Xcode targets (`Sirena`, `ClipboardKit`, `DockKit`, `SirenaFinder`), about 650 `.swift` files. Excluded: `References/`, `build/`, and `Sirena.xcodeproj/-Xcc/` (Xcode index artifacts, also in `.gitignore`).

Counts below are grep-based approximations across that set.

## Language and Build Settings

- Swift, AppKit + SwiftUI, deployment target macOS 15.0.
- Language mode is mixed across targets in `Sirena.xcodeproj/project.pbxproj`: some configurations use `SWIFT_VERSION = 5.0`, others `SWIFT_VERSION = 6.0`. The 6.0 configurations also set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so top-level types default to main-actor isolation there.
- Write code that compiles under Swift 6 strict concurrency where possible. Use `nonisolated` and `@MainActor` explicitly, and avoid introducing new `nonisolated(unsafe)` (already used in 1 place, see Concurrency).
- Availability checks use `#available(macOS 26, *)` (about 63 sites), always wrapped in the Compat helpers (see below).

## Naming Patterns

**Files:**
- One primary type per file, named after the type: `Sirena/Modules/Pomodoro/PomodoroController.swift`, `Sirena/Modules/Island/Services/NotchLyricsService.swift`.
- Feature-scoped prefixes are common: `Notch*` for everything in `Sirena/Modules/Island/` (e.g. `NotchMusicService.swift`, `NotchMusicSupport.swift`), `Sirena*` for shared ClipboardKit/DockKit types (e.g. `SirenaHistoryPanelController.swift`, `SirenaDockSettings.swift`).
- Type-role suffixes (by frequency in the repo): `...Calculation.swift` (~106, one per snap/size layout under `Sirena/Modules/WindowManagement/WindowCalculation/`), `...View.swift` (~50), `...Support.swift` (~27), `...Controller.swift` (~17), `...Manager.swift` (~16), `...Service.swift` (~13), `...Settings.swift` (~10).
- `*Support.swift` holds pure helpers and logic that is separated from the stateful `*Service.swift` / `*Coordinator` type (e.g. `Sirena/Modules/Island/Services/NotchLyricsSupport.swift` next to `NotchLyricsService.swift`). Follow this split when adding logic that should be testable without side effects.
- Some legacy files break the convention: `DockKit/Utilities/Misc Utils.swift` (space in name), `DockKit/Components/sliderSetting.swift` (lowercase type name), `DockKit/Components/dockStyle.swift`. Do not copy these patterns.

**Types:**
- `UpperCamelCase` for types, enums, protocols. Enum cases are `lowerCamelCase`: `enum PomodoroPhase: String { case focus, shortBreak, longBreak }` in `Sirena/Modules/Pomodoro/PomodoroController.swift`.
- Error types end in `Error`: `MirrorCameraError` (`Sirena/Modules/Mirror/MirrorCamera.swift`), `AxError` (`DockKit/Extensions/AXUIElement.swift`), `CommandError` (`DockKit/Utilities/ScriptCommands.swift`). Nested private error enums are also used (`PinError` in `Sirena/Modules/PinWindow/PinWindowController.swift`).
- Nested `State` enums for observable services: `enum State: Equatable { case idle, consent, loading, ... }` in `NotchLyricsService.swift`.

**Functions and variables:**
- `lowerCamelCase`. Boolean properties read as predicates (`isImporting`, `isEnabled()`, `visible`).
- Verb-first action names: `calculateRect(_:)`, `update(playback:visible:)`, `cleanupOrphanedContents()`.

**Constants and keys:**
- Static constants on the owning type: `static let shared = ...`, `private static let width: CGFloat = 62`.
- UserDefaults keys are dotted, feature-prefixed strings: `"clipboard.clearOnQuit"`, `"pomodoro.*"`. See the Defaults section below.

## Formatting

**Indentation:**
- Predominantly 4 spaces (about 636 of 650 files). Some older ClipboardKit files (inherited from Maccy) use 2 spaces (about 61 files, e.g. `ClipboardKit/Observables/History.swift`, `ClipboardKit/Storage.swift`). For new code in `Sirena/`, `DockKit/`, use 4 spaces. For edits inside a 2-space file, match that file.
- No tabs in source.

**Formatting tools:**
- No `.swiftformat`, `.swift-format`, or SwiftLint config is present in the repository. Formatting is by hand and by Xcode defaults.

**Line length:** Not enforced. Long SwiftUI modifier chains and `Defaults.Key` declarations are wrapped at the argument level.

## File Headers

Three header styles coexist:
- Most common (~268 files): a doc comment with the file name and a one-line purpose:
  ```swift
  /// PomodoroController.swift
  /// Clean-room focus timer: focus sessions, short and long breaks.
  ```
- License header (~148 files, mostly `Sirena/Modules/Island/` and newer code):
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 Vorssaint
  ```
- No header (much of `DockKit/` and `ClipboardKit/`).

When creating a new file, use the `///` file-name header to match the majority of `Sirena/`. If a file is inside a vendored area (see Module Design), keep that area's license header.

## Import Organization

Imports are alphabetical and grouped by framework, with system frameworks first and the rest after. Typical block (`Sirena/Modules/Pomodoro/PomodoroController.swift`):

```swift
import AppKit
import MASShortcut
import SwiftUI
import UserNotifications
```

- No module-qualified imports or path aliases (Xcode project, no SPM path mapping).
- Third-party SPM packages (from `Sirena.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`): `Defaults`, `KeyboardShortcuts`, `MASShortcut`, `Sauce`, `HotKey`, `swift-log`, `swift-syntax`, `SmoothGradient`, `SwiftHexColors`, `mediaremote-adapter`, `fuse-swift`, `Settings`.
- `import Foundation` is first in files that have only Foundation plus a few others (`Sirena/App/Localization.swift`).

## Language Usage in Comments and Strings

- Code comments are predominantly English. A few comments are in Portuguese, from the author's notes.
- User-facing text goes through localization: `L("Focus")` (`Sirena/App/Localization.swift`) which wraps `String(localized:table: "Sirena")`. Strings live in `Sirena/Resources/Sirena.xcstrings` (≈316 KB). The older table `Sirena/Resources/Localizable.xcstrings` (≈472 KB) is inherited from Rectangle and is still used by `String(localized:)` calls without a table. Add new user-visible strings to `Sirena.xcstrings` and use `L(...)`.

## Concurrency

- `@MainActor` is the default for UI and state types (≈259 occurrences). Mark any new type that touches AppKit/SwiftUI state `@MainActor`.
- Observation: two styles coexist.
  - Modern: `@Observable` (≈37) with `@ObservationIgnored` (≈75) for non-observed stored properties, e.g. `PomodoroSettings` in `Sirena/Modules/Pomodoro/PomodoroController.swift`.
  - Legacy: `ObservableObject` with `@Published` (≈37 / ≈177), e.g. `NotchLyricsService` in `Sirena/Modules/Island/Services/NotchLyricsService.swift`.
  - Prefer `@Observable` + `@MainActor` for new code.
- Singletons: `static let shared = Type()` with `private init() {}` is the pattern (`NotchLyricsService`, `PomodoroSettings`).
- Concurrency primitives in use: `DispatchQueue` (≈413 mentions, dominant), `Task { }` (≈117), `Task.detached` (≈13), `async` (≈364). Prefer `Task`/`async` for new code. Do not add more `DispatchQueue.main.async` where `@MainActor` isolation suffices.
- `@unchecked Sendable` appears 11 times and `nonisolated(unsafe)` once (`ClipboardKit/Extensions/Defaults.Keys+Names.swift`). Avoid adding new occurrences; wrap the state in an actor or main-actor type instead.
- `nonisolated struct` / `nonisolated extension` appear in new ClipboardKit code (`StorageType` in `Defaults.Keys+Names.swift`) to opt out of default main-actor isolation. Use the same when a value type must be usable off the main actor.

## Preferences (Defaults)

- Use the `Defaults` package. Keys are declared in `Defaults.Keys` extensions:
  ```swift
  nonisolated extension Defaults.Keys {
    static let clearOnQuit = Key<Bool>("clipboard.clearOnQuit", default: false, suite: preferencesSuite)
  }
  ```
  (`ClipboardKit/Extensions/Defaults.Keys+Names.swift`)
- Read/write via `Defaults[.key]` (≈441 uses).
- Clipboard preferences use their own `UserDefaults` suite (`com.matheusfaria.Sirena.clipboard`) so generic keys cannot collide. Keep that rule for new module-scoped preferences.
- Pomodoro uses plain `UserDefaults.standard` with a `pomodoro.` key prefix via `@ObservationIgnored private let defaults`.
- `DockKit/Extensions/NSScreen.swift` contains `migrateScreenIdentifier(_:)`: when changing a persisted identifier, add a migration helper rather than silently breaking stored values.

## Error Handling

**Predominant patterns (counts are approximate):**
- Optional `try?` for best-effort operations (≈325 occurrences). Use only where a failure is genuinely ignorable.
- `do { try ... } catch` blocks (≈75). Use these when the error must be logged or surfaced.
- `throws` functions with typed local error enums conforming to `LocalizedError` for user-visible failures (e.g. `MirrorCameraError` in `Sirena/Modules/Mirror/MirrorCamera.swift`).
- `fatalError` only for unrecoverable startup failures: `ClipboardKit/Storage.swift` (database container load) and `init(coder:)` stubs in `DockKit/Components/FluidGradient/*.swift`. Do not add `fatalError` to runtime paths.
- Force unwrap `!` and `try!` appear in a few places (`try!` 4 times, e.g. `DockKit/Models/MediaInfo.swift:498` for a constant regex). For new code, use `guard let` / `if let` or `try` with a thrown error. Constant regexes may use `try!`.

**Example to follow** (`ClipboardKit/Storage.swift`):
```swift
do {
  container = try ModelContainer(for: HistoryItem.self, configurations: config)
} catch let error {
  fatalError("Cannot load database: \(error.localizedDescription).")
}
```

**Example to avoid:** silent `try?` on writes whose failure leaves state inconsistent.

## Logging

Multiple mechanisms, no single standard:
- `os.Logger` via `private static let log = os.Logger(subsystem: "Sirena", category: "ColorPicker")` in `Sirena/Modules/ColorPicker/ColorStore.swift`. This is the preferred pattern for new code. Only 2 uses in the repo.
- `DebugLogger` enum (`DockKit/Utilities/DebugLogger.swift`), ≈81 call sites. It is the dominant logger in DockKit and the window-management code.
- `Logger(label: "org.p0deje.Maccy")` (swift-log) in `ClipboardKit/Observables/History.swift`, inherited.
- `NSLog` (6 uses) and `print(...)` (about 20 lines in 10 files, e.g. `ClipboardKit/ApplicationImage.swift`). Treat `print` as debug-only leftovers; do not add new ones.
- `Sirena/Modules/WindowManagement/Logging/` contains `LogViewer.swift` and its storyboard (a log viewer window), not a logging API.

## Compatibility (macOS version gating)

Central pattern: a `Compat/` folder per target provides helpers that hide `#available` branching:
- `ClipboardKit/Compat/GlassCompat.swift`, `DockKit/Compat/GlassCompat.swift`, `Sirena/App/Compat/GlassCompat.swift`, and `Sirena/App/Compat/ScreenCaptureCompat.swift` (SwiftUI/AppKit extensions).
- Example (`ClipboardKit/Compat/GlassCompat.swift`):
  ```swift
  @ViewBuilder
  func compatGlass<S: Shape>(_ kind: CompatGlass = .regular, tint: Color? = nil,
                             interactive: Bool = false, in shape: S) -> some View {
      if #available(macOS 26, *) {
          glassEffect(...)
      } else {
          background(.regularMaterial, in: shape)
      }
  }
  ```
- Views call `.compatGlass(...)`, `.compatGlassButtonStyle()`, `.compatGlassProminentButtonStyle()` rather than checking availability inline.
- New Liquid Glass UI must go through these helpers. Do not add raw `#available(macOS 26, *)` in feature views.

## Comments and Documentation

- Explain *why*, not *what*. Examples: the `Defaults.Keys` suite comment in `ClipboardKit/Extensions/Defaults.Keys+Names.swift` explains the suite isolation; `GlassCompat.swift` header explains the macOS 26 fallback.
- `// MARK:` is used heavily (≈355 occurrences) to section files. Use `// MARK: - Section` for long types.
- `///` doc comments on public-facing helpers and file headers.
- TODO/FIXME: only 3 occurrences, all in `Sirena/Modules/WindowManagement/MultiWindow/MultiWindowManager.swift`. Prefer opening an issue over adding new TODOs.

## Function and Type Design

- `final class` is the default for non-subclassed classes; `struct` for value models (548 structs, 401 classes, 393 enums in the repo).
- Enums with associated values or `String` raw values are used for mode/phase/state modelling (`PomodoroPhase`, `NotchLyricsService.State`).
- Protocols are used sparingly (≈30 declarations). Prefer concrete types with `static let shared` unless a test seam is needed.
- Window-layout code uses class inheritance: `final class SpecifiedCalculation: WindowCalculation` overrides `calculateRect(_:)` (`Sirena/Modules/WindowManagement/WindowCalculation/SpecifiedCalculation.swift`). Each layout is a subclass that takes `RectCalculationParameters` and returns `RectResult`. Add new window layouts the same way.
- Parameter structs (`RectCalculationParameters`) are preferred over long argument lists.
- Codable models: `struct ... : Codable` (80 occurrences), e.g. `DockKit/Models/MediaInfo.swift`.

## Module Design

**Module layout:**
- `Sirena/Modules/<Feature>/` is one folder per user-facing feature. Each folder owns its controller, views, and settings (e.g. `Pomodoro`, `Mixer`, `Island`, `Shelf`, `ColorPicker`).
- `Sirena/Modules/Island/` is split into `Services/`, `UI/`, `Support/`, `Strings/`. Follow this split for large features.
- `DockKit/` is a vendored-derived package (see License below) organized by `Components/`, `Extensions/`, `Models/`, `Utilities/`, `Views/`.
- `ClipboardKit/` is organized by `Models/`, `Observables/`, `Panel/`, `Settings/`, `Extensions/`, `Compat/`.

**Exports:** Swift access control. `internal` by default; `private`/`fileprivate` for helpers. Use `private` helpers inside a type before reaching for file-scope functions.

**Barrel files:** Not used.

**Third-party / inherited code:** Config licenses exist for `Config/Fader-LICENSE.txt`, `Config/DockDoor-LICENSE-GPL-3.0.txt`, `Config/Rectangle-LICENSE.txt`. Code derived from those projects keeps its license. Do not remove existing headers or license text from those files.

## Quick Checklist for New Code

- 4-space indent, `///` file header, `@MainActor` on UI/state types, `@Observable` for new observable state.
- Preferences via `Defaults.Keys` extension with a feature-prefixed key.
- User-visible strings via `L(...)` into `Sirena.xcstrings`.
- Logging via `os.Logger` (new code) or existing `DebugLogger` in DockKit.
- `guard`/`do-catch` instead of `try!`/force unwrap; no `fatalError` outside startup.
- macOS 26-only UI through the `compat*` helpers.
- Put pure logic in a `*Support.swift` file so it can be tested without AppKit.

---

*Convention analysis: 2026-10-20*
