<!-- refreshed: 2026-10-20 -->
# Architecture

**Analysis Date:** 2026-10-20

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                     Sirena app target (`Sirena/`)                    │
│                                                                      │
│  App shell: `Sirena/App/main.swift` → `AppDelegate.swift`            │
│  Menu bar item `SirenaStatusItem` · main window · onboarding · menus │
├──────────────────────────────────────────────────────────────────────┤
│        ModuleManager (`Sirena/App/Modules/ModuleManager.swift`)      │
│        ModuleID enum (`Sirena/App/Modules/ModuleID.swift`)           │
│        start / terminate / pendingRestart per feature module         │
├───────────────┬───────────────┬───────────────┬──────────────────────┤
│ Feature       │ Feature       │ Feature       │ ~17 feature folders  │
│ controllers   │ controllers   │ controllers   │ `Sirena/Modules/*`   │
│ (Switcher,    │ (Mirror,      │ (KeepAwake,   │ (WindowManagement,   │
│  Island, …)   │  PinWindow…)  │  DisplayOff…) │  Island, Switcher…)  │
└───────┬───────┴───────┬───────┴───────┬───────┴──────────┬───────────┘
        │               │               │                  │
        ▼               ▼               ▼                  ▼
┌─────────────────────────────┐  ┌──────────────────────────────────────┐
│ DockKit framework           │  │ ClipboardKit framework               │
│ `DockKit/`                  │  │ `ClipboardKit/`                      │
│ Dock previews, window       │  │ Clipboard history (Maccy port),      │
│ gestures, Cmd-Tab overlay   │  │ popup panel, search, pins            │
└──────────────┬──────────────┘  └──────────────────┬───────────────────┘
               │                                     │
               ▼                                     ▼
   macOS APIs: AppKit, SwiftUI, ApplicationServices (AX), CoreGraphics,
   ScreenCaptureKit, Carbon (hot keys), EventKit, Vision, SwiftData,
   private helpers in `DockKit/Utilities/PrivateApis.swift`

┌──────────────────────────────────────────────────────────────────────┐
│ SirenaFinder (app extension, separate process)                        │
│ `SirenaFinder/FinderSync.swift` — "Copiar Caminho" Finder menu only  │
└──────────────────────────────────────────────────────────────────────┘
```

## Pattern Overview

**Overall:** Single-process, AppKit-hosted macOS menu bar app with a modular feature layout. Each feature is a `@MainActor` singleton controller (or `enum` namespace) with explicit `start()` / `terminate()` lifecycle methods, orchestrated by one `ModuleManager`. SwiftUI is used for views and settings panes; AppKit owns windows, panels, the status item and event taps.

**Key Characteristics:**
- Swift 6-era concurrency style: UI-facing types are marked `@MainActor` (`Sirena/App/AppDelegate.swift`, `Sirena/App/Modules/ModuleManager.swift`, `Sirena/Modules/DisplayOff/DisplayOffController.swift`). Entry point wraps launch in `MainActor.assumeIsolated` (`Sirena/App/main.swift`).
- Observation: `ModuleManager` uses `@Observable` (`Sirena/App/Modules/ModuleManager.swift`); some controllers still use `ObservableObject` + `@Published` (e.g. `Sirena/Modules/DisplayOff/DisplayOffController.swift`). Both styles coexist.
- Settings persistence is `UserDefaults` / the `Defaults` package (`import Defaults` appears in ~98 files), keys declared under `Defaults.Keys` extensions and `enum` namespaces (e.g. `ClipboardKit/Extensions/Defaults.Keys+Names.swift`, `Sirena/Modules/WindowManagement/Defaults.swift`).
- Hotkeys: `MASShortcut` for the global "open Sirena" shortcut (`Sirena/App/AppDelegate.swift`), `KeyboardShortcuts` and `Sauce` in ClipboardKit/DockKit, plus raw `CGEventTap` through `DockKit/Utilities/EventTapThread.swift`.
- Two vendored-and-ported frameworks (DockKit from DockDoor, GPL-3.0; ClipboardKit from Maccy) are compiled as separate framework targets and receive app-specific glue from `Sirena/Modules/Dock/DockModule.swift` and `Sirena/Modules/Clipboard/ClipboardModule.swift`.
- Each framework carries its own copy of the OS-version compatibility helpers (`Sirena/App/Compat/GlassCompat.swift`, `DockKit/Compat/GlassCompat.swift`, `ClipboardKit/Compat/GlassCompat.swift`) because "each framework is its own module" (comment in `Sirena/App/Compat/GlassCompat.swift`).

## Layers

**App shell (composition root):**
- Purpose: Launch, menu bar item, main window, onboarding, top-level menus, URL-scheme routing, and module wiring.
- Location: `Sirena/App/`
- Contains: `main.swift`, `AppDelegate.swift`, `MainMenu.swift`, `SirenaStatusItem.swift`, `BoltMenu.swift`, `Localization.swift`, `MainWindow/`, `Pages/`, `Modules/`, `Compat/`.
- Depends on: every feature module, `ClipboardKit`, `DockKit`, `MASShortcut`, `Defaults`.
- Used by: nothing (top of the graph).

**Module registry and lifecycle:**
- Purpose: Declares every toggleable feature and starts/stops it.
- Location: `Sirena/App/Modules/ModuleID.swift`, `Sirena/App/Modules/ModuleManager.swift`
- Contains: `enum ModuleID` (18 cases: `windows`, `dock`, `switcher`, `clipboard`, `menuBar`, `keepAwake`, `displayOff`, `mixer`, `mirror`, `pinWindow`, `textCapture`, `tweaks`, `shelf`, `island`, `screenCapture`, `pomodoro`, `colorPicker`, `screenBrush`), each with `isEnabled` (UserDefaults-backed, `isOnByDefault`, `isTool`), a `hostPage`/`hostTab` mapping, and the `ModuleManager.start` switch.
- Depends on: feature controllers listed in `ModuleManager.start`.
- Used by: `AppDelegate`, `MainWindowController` pages, `SirenaStatusItem`.

**Feature modules (app-side):**
- Purpose: One folder per user-facing feature; owns its controller, panels, settings and models.
- Location: `Sirena/Modules/<Feature>/` (see STRUCTURE.md for the list).
- Contains: `*Controller.swift` (singleton with `start()`/`terminate()`), `*Settings.swift`, views, models, services.
- Depends on: `DockKit`, `ClipboardKit`, system frameworks, shared Compat helpers.
- Used by: `ModuleManager` and the settings pages in `Sirena/App/Pages/`.

**Reusable frameworks:**
- `DockKit` (`DockKit/`, framework target): Dock icon observation (`DockObserver.swift`), window discovery/cache (`DockKit/Utilities/Window Management/`), hover previews (`DockKit/Views/Hover Window/`), window gestures (`DockKit/Utilities/Window Gestures/`), active-app indicator (`DockKit/Utilities/ActiveAppIndicator/`), media remote (`DockKit/Utilities/Media/MediaRemoteService.swift`). Entry singleton: `DockController.shared` (`DockKit/DockController.swift`, used by `Sirena/Modules/Dock/DockModule.swift`).
- `ClipboardKit` (`ClipboardKit/`, framework target): clipboard monitor (`ClipboardKit/Clipboard.swift`), controller (`ClipboardKit/ClipboardController.swift`), storage (`ClipboardKit/Storage.swift`, SwiftData), history panel (`ClipboardKit/Panel/`), search/sort (`Search.swift`, `Sorter.swift`), and a public facade `ClipboardKit/SirenaHistoryAPI.swift` (`public struct ClipboardEntry`, `public func thumbnail(for:)`).
- Dependency direction: the app imports both frameworks (`import ClipboardKit` in `Sirena/App/AppDelegate.swift` and `Sirena/App/Modules/ModuleManager.swift`; `import DockKit` in `Sirena/Modules/Dock/DockModule.swift`). Frameworks do not import the app. The framework → app coupling that exists is via callback properties set by glue code (e.g. `controller.onOpenSettings`, `controller.anchorButton`, `controller.onRestartRequested` in the two `*Module.swift` files).

**Out-of-process extension:**
- `SirenaFinder` (`SirenaFinder/FinderSync.swift`, `FIFinderSync` subclass) is a separate app-extension target. It shares no code with the app; it is configured from Sirena's Finder settings through the app's module switch.

## Data Flow

### Primary Request Path (app launch)

1. `main.swift` enters `MainActor.assumeIsolated`, creates `AppDelegate` and calls `NSApplicationMain` (`Sirena/App/main.swift`).
2. `AppDelegate.applicationDidFinishLaunching` installs `MainMenu.make()`, builds the status item provider, starts `SirenaMixer.shared` immediately, runs `WindowSwitcherController.recoverSystemShortcuts()` (restores ⌘Tab if a previous run crashed), and wires `ModuleManager.shared.openPage` to `MainWindowController.present` (`Sirena/App/AppDelegate.swift`).
3. `ModuleManager.startEnabledModules(windowManagement:windowsMenu:)` iterates `ModuleID.allCases` where `isEnabled`, calls `start(_:)`, and always starts `.tweaks` (`Sirena/App/Modules/ModuleManager.swift`).
4. `OnboardingWindow.shared.showIfNeeded()` runs on the next main-queue turn; `hasFinishedLaunching` is then set to `true` so reopen events are honored (`AppDelegate.swift`).
5. The global "open Sirena" hotkey is bound with `MASShortcutBinder` and calls `mainWindowController.present(.home)`.

### Feature activation (toggle from settings)

1. A settings page (e.g. `Sirena/App/Pages/MirrorPage.swift`) calls `ModuleManager.shared.setEnabled(_:_:)`.
2. `setEnabled` writes the flag to `UserDefaults` via `ModuleID.isEnabled`, bumps `switchChanges` so SwiftUI views refresh, then either starts the module immediately (`enabled == true`) or:
   - stops it immediately for `.switcher`, `.shelf`, `.menuBar`, `.island` (`terminate()` + remove from `running`), or
   - inserts it into `pendingRestart` for all other modules, which take effect on next launch (`ModuleManager.swift`).

### Window-management hotkey path

1. A key/mouse event enters `ShortcutManager` / `MouseButtonShortcut` (`Sirena/Modules/WindowManagement/ShortcutManager.swift`, `MouseButtonShortcut.swift`).
2. `WindowManagementModule` (`Sirena/Modules/WindowManagement/WindowManagementModule.swift`) / `WindowManager` resolves a `WindowAction` (`WindowAction.swift`, `WindowActionCatalog`) and calculates a frame (`WindowCalculation/`, `Snapping/`).
3. `AccessibilityElement` applies the frame through the AX API (`Sirena/Modules/WindowManagement/AccessibilityElement.swift`).
4. Multi-step behaviours (repeated maximize/restore, cycle sizes, cooperative corner resize) keep small state objects alongside (`RepeatedMaximizeRestore.swift`, `CycleSize.swift`, `CooperativeCornerResize.swift`).

### Dock preview path (DockKit)

1. `DockObserver` (`DockKit/Utilities/DockObserver.swift`) watches Dock accessibility elements and running apps.
2. `SpaceWindowCacheManager` and `WindowSeeder` (`DockKit/Utilities/Window Management/`) populate per-space window lists.
3. `EventTapThread` (`DockKit/Utilities/EventTapThread.swift`) runs a dedicated thread for the CGEvent tap and posts results back to the main actor.
4. Hover views in `DockKit/Views/Hover Window/` render previews; `WindowPreviewInteractionModifier.swift` handles clicks.

### Clipboard path (ClipboardKit)

1. `Clipboard` (`ClipboardKit/Clipboard.swift`) polls `NSPasteboard` change counts; `Throttler.swift` limits work.
2. Entries are persisted through `Storage.swift` (SwiftData, `ClipboardKit/Models/HistoryItem.swift`, `HistoryItemContent.swift`).
3. `ClipboardController` opens `SirenaHistoryPanelController` (`ClipboardKit/Panel/`), which renders `SirenaHistoryPanelView` from `SirenaHistoryPanelModel`; the status-item anchor is supplied by the app (`Sirena/Modules/Clipboard/ClipboardModule.swift`).
4. Other code reads history via `SirenaHistoryAPI.swift` (`public` surface).

**State Management:**
- Cross-feature global state lives in `@MainActor` singletons (`ModuleManager.shared`, `WindowSwitcherController.shared`, `DockController.shared`, `ClipboardController.shared`, …).
- Persistent state: `UserDefaults` (settings, module flags, shortcut bindings via `MASShortcut` defaults keys such as `AppDelegate.openHomeShortcutKey`), SwiftData store (clipboard history), per-feature JSON/files (e.g. `Sirena/Modules/Shelf/ShelfStore.swift`, `Sirena/Modules/ColorPicker/ColorStore.swift`).
- Navigation state: `Router` (`@Observable`, `Sirena/App/MainWindow/MainWindowController.swift`) holds `selection: SidebarItem`; `PageNavigator.shared.requestedTab` selects a sub-tab.

## Key Abstractions

**`ModuleID`:**
- Purpose: Canonical list of features with their enable flag, default state, host page and tab.
- Examples: `Sirena/App/Modules/ModuleID.swift`
- Pattern: `enum` with `CaseIterable`, computed properties per case; `rawValue` also used as the `SIRENA_OPEN_PAGE` debug key.

**`SidebarItem`:**
- Purpose: Addresses any main-window destination (`home`, `module(ModuleID)`, `general`, `about`).
- Examples: `Sirena/App/MainWindow/MainWindowController.swift`
- Pattern: `Hashable` enum routed by `Router`.

**Feature controller (`start()` / `terminate()`):**
- Purpose: Each feature's run loop: observers, status items, panels, event taps, timers.
- Examples: `Sirena/Modules/DisplayOff/DisplayOffController.swift`, `Sirena/Modules/Mirror/MirrorController.swift`, `Sirena/Modules/Switcher/WindowSwitcherController.swift`, `Sirena/Modules/KeepAwake/KeepAwakeModule.swift`
- Pattern: `@MainActor final class X { static let shared = X(); func start(); func terminate() }`. Some modules are `enum` namespaces instead (`DockModule`, `ClipboardModule`, `MenuBarModule` uses `.shared`).

**`WindowAction` / `WindowActionCatalog`:**
- Purpose: Declarative list of window-placement commands with categories and shortcuts.
- Examples: `Sirena/Modules/WindowManagement/WindowAction.swift`, `WindowActionCategory.swift`, `DockKit/Utilities/Window Management/WindowActionCatalog.swift`
- Pattern: enum-driven dispatch.

**`IslandController` / `Notch*Service`:**
- Purpose: "Island" notch overlay; ~40 `Notch*Service.swift` files each own one data source (music, calendar, notifications, downloads, lyrics, lock screen, etc.).
- Examples: `Sirena/Modules/Island/Services/NotchService.swift`, `NotchMusicService.swift`
- Pattern: service + paired `*Support.swift` helper per source.

**Compat helpers (`compatGlass`, `supportsLiquidGlass`):**
- Purpose: Use macOS 26+ Liquid Glass APIs when available, materials otherwise. The deployment target is macOS 15.0.
- Examples: `Sirena/App/Compat/GlassCompat.swift`, `DockKit/Compat/GlassCompat.swift`
- Pattern: `if #available(macOS 26, *)` inside `@ViewBuilder` extension methods.

## Entry Points

**Application launch:**
- Location: `Sirena/App/main.swift`
- Triggers: user launches the app, login item (`Sirena/Modules/WindowManagement/LaunchOnLogin.swift`).
- Responsibilities: create NSApplication and `AppDelegate`.

**AppDelegate lifecycle:**
- Location: `Sirena/App/AppDelegate.swift`
- Triggers: `applicationDidFinishLaunching`, `applicationShouldHandleReopen`, `application(_:open:)` (URL schemes `sirena://capture-text`, `capture-last`, `read-code`, `capture-translate`, `open-hidden-icon`, `sound`, `hidden-icons-show/hide`, `shelf-toggle`, `shelf-add-clipboard`; other URLs are forwarded to `WindowManagement`), `applicationWillTerminate`.
- Responsibilities: wiring, menus, shortcut binding, debug environment hooks (`SIRENA_OPEN_PAGE`, `SIRENA_OPEN_SETTINGS`, `SIRENA_SHOW_MIRROR`).

**Status item:**
- Location: `Sirena/App/SirenaStatusItem.swift` (singleton `SirenaStatusItem.instance`)
- Triggers: click on the menu bar icon; opens `BoltMenuView` panel (`Sirena/App/BoltMenu.swift`) or a right-click menu from `AppDelegate.makeSirenaMenu()`.

**Main window:**
- Location: `Sirena/App/MainWindow/MainWindowController.swift` (`present(_:)`, `closeIfIdle()`), content in `MainView.swift` and `HomeView.swift`.
- Triggers: status item, global hotkey, reopen, `ModuleManager.openPage`.

**Onboarding:**
- Location: `Sirena/App/MainWindow/OnboardingWindow.swift`
- Triggers: first launch or missing essential permission.

**Finder extension:**
- Location: `SirenaFinder/FinderSync.swift`
- Triggers: Finder context menu on any path under `/`.

**Feature-specific entry points:** `DockModule.start` (`Sirena/Modules/Dock/DockModule.swift`), `ClipboardModule.start` (`Sirena/Modules/Clipboard/ClipboardModule.swift`), `WindowManagementModule` (`Sirena/Modules/WindowManagement/WindowManagementModule.swift`), `TextCaptureController.capture` (called from URL scheme), `MirrorController.show`.

## Architectural Constraints

- **Threading:** UI and most controllers are `@MainActor`. Long-running or blocking work runs off-main: `DockKit/Utilities/LimitedTaskGroup.swift` bounds concurrent tasks, `DockKit/Utilities/EventTapThread.swift` owns a dedicated event-tap thread, `Sirena/Modules/Switcher/SwitcherWindowServerCaptureQueue.swift` serializes WindowServer captures.
- **Global state:** Singletons with `static let shared` across `Sirena/App/Modules/ModuleManager.swift`, `Sirena/Modules/*/…Controller.swift`, `Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift` (`SirenaMixer.shared`), `DockKit/Utilities/Window Management/SpaceWindowCacheManager.swift`. Module-level `var` flags such as `supportsLiquidGlass` (`Sirena/App/Compat/GlassCompat.swift`).
- **Private APIs:** `DockKit/Utilities/PrivateApis.swift`, `Sirena/Modules/Switcher/SwitcherSpaceWindowBridge.swift`, `SwitcherSymbolicHotKeys.swift` and `Config/Sirena-Bridging-Header.h` expose non-public symbols. Changes in macOS can break these; keep them behind the `*Support*`/`*Shims*` files.
- **Circular imports:** None observed between the app and frameworks (one-way: app → frameworks). Inside the app, `Sirena/Modules/Switcher/` contains several `*Support*` / `*Shims*` files that cross-reference each other (`SwitcherSupport.swift`, `SwitcherSupportShims.swift`, `SwitcherSupportShims2.swift`); treat them as one cluster.
- **Single-process requirement:** `ModuleManager.relaunch()` (`Sirena/App/Modules/ModuleManager.swift`) is the only supported way to apply some changes; many toggles set `pendingRestart` instead of applying live.
- **Deployment target:** macOS 15.0 (`Sirena.xcodeproj`); macOS 26+ and 27+ paths are guarded with `#available`.

## Anti-Patterns

### Duplicated compatibility helpers per target

**What happens:** `GlassCompat.swift` exists three times (`Sirena/App/Compat/`, `DockKit/Compat/`, `ClipboardKit/Compat/`).
**Why it's wrong:** Divergence risk; a fix in one copy is not applied to the others.
**Do this instead:** Keep the per-framework copies in sync when editing, or move the helpers to a shared target. New compat helpers should follow the existing `#available` pattern in `Sirena/App/Compat/GlassCompat.swift`.

### Manual module start/stop bookkeeping

**What happens:** `ModuleManager.start` and `ModuleManager.terminate` each enumerate every module by hand, and `setEnabled` has a chain of `else if module == …` branches.
**Why it's wrong:** Adding a feature requires editing `ModuleID`, `start`, `terminate` and `setEnabled`; a missed branch silently leaves a module running.
**Do this instead:** When adding a module, update all four places in `Sirena/App/Modules/ModuleManager.swift` and `Sirena/App/Modules/ModuleID.swift`, and mirror the `terminate()` path for any module that should stop live.

### Feature code reaching into the app shell

**What happens:** Feature controllers call `AppDelegate.instance` or `SirenaStatusItem.instance` directly (e.g. `ModuleManager.setEnabled` uses `AppDelegate.instance.windowManagement`; `ClipboardModule` sets `SirenaStatusItem.instance.button`).
**Why it's wrong:** Couples feature modules to the app delegate and makes them hard to test in isolation.
**Do this instead:** Pass dependencies through `start(...)` parameters, as `WindowManagementModule` and `openPage` closures already do in `ModuleManager.start`.

## Error Handling

**Strategy:** Defensive and fail-soft. Features degrade silently when a permission or API is unavailable; launch-time permission gaps are surfaced once through `OnboardingWindow`.

**Patterns:**
- `try?` for non-critical operations (e.g. `ModuleManager.relaunch` uses `try? task.run()`).
- Guard-based early returns for missing permissions or unsupported OS versions (`guard … else { return nil }` in `AppDelegate.validRequestor`).
- `DebugLogger` (`DockKit/Utilities/DebugLogger.swift`) and `Sirena/Modules/WindowManagement/Logging/` for diagnostics.

## Cross-Cutting Concerns

**Logging:** `os` framework and `DebugLogger` in DockKit; window-management logging under `Sirena/Modules/WindowManagement/Logging/`.
**Validation:** Value sanitizing in settings helpers (e.g. `SirenaMixerDefaults.sanitizedAppVolume` in `Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift`); shortcut conflict checks in `Sirena/App/MainWindow/SirenaShortcutValidator.swift`.
**Authentication:** Not applicable (local-only app). Permissions are checked with `DockKit/Components/PermissionsView/PermissionsChecker.swift` and `Sirena/Modules/WindowManagement/AccessibilityAuthorization/`.
**Localization:** String catalogs `Sirena/Resources/Localizable.xcstrings` and `Sirena/Resources/Sirena.xcstrings`, plus `L(...)` helper in `Sirena/App/Localization.swift`; Clipboard strings in `Sirena/Modules/Clipboard/Resources/Settings/{en,pt-BR}.lproj`.

---

*Architecture analysis: 2026-10-20*
