# Codebase Structure

**Analysis Date:** 2026-10-20

## Directory Layout

```
Sirena/                              # repo root: "/Users/macmini/Documents/VSCode Temp/Sirena"
├── Sirena/                          # Sirena app target (Swift sources, resources)
│   ├── App/                         # App shell: entry, menus, main window, pages, module registry
│   │   ├── Modules/                 # ModuleID + ModuleManager (feature registry)
│   │   ├── MainWindow/              # Main window controller, home, onboarding, shortcut validator
│   │   ├── Pages/                   # One SwiftUI settings page per feature
│   │   └── Compat/                  # macOS 26+ Liquid Glass / screen capture shims
│   ├── Modules/                     # One folder per feature (17 folders)
│   │   ├── WindowManagement/        # Window snapping and shortcuts (≈205 files, largest)
│   │   ├── Island/                  # Notch overlay (≈108 files)
│   │   ├── Switcher/                # ⌘Tab window/app switcher (≈30 files)
│   │   ├── MenuBar/                 # Menu bar item hiding/layout (≈18 files)
│   │   ├── Mixer/                   # Per-app volume mixer
│   │   ├── Mirror/                  # Camera mirror
│   │   ├── PinWindow/               # Pinned screenshot/window panels
│   │   ├── ScreenBrush/             # Screen annotation
│   │   ├── Shelf/                   # File shelf
│   │   ├── TextCapture/             # OCR text capture
│   │   ├── ColorPicker/             # Color picker + store
│   │   ├── Pomodoro/                # Pomodoro timer
│   │   ├── KeepAwake/               # Caffeine-style sleep prevention
│   │   ├── DisplayOff/              # Display sleep on demand
│   │   ├── ScreenCapture/           # Screenshot controller
│   │   ├── Dock/                    # App-side glue for DockKit (DockModule.swift)
│   │   ├── Clipboard/               # App-side glue for ClipboardKit + Resources/ (strings, sounds)
│   │   └── Tweaks/                  # Finder/DMG tweaks (TweaksController, DMGInstaller)
│   └── Resources/                   # Assets.xcassets, AppIcon.icon, *.xcstrings string catalogs
├── DockKit/                         # Framework target (DockDoor port, GPL-3.0)
│   ├── Compat/                      # GlassCompat.swift
│   ├── Models/                      # MediaInfo.swift, CalendarInfo.swift
│   ├── Extensions/                  # Foundation/AppKit/CoreGraphics/AX extensions
│   │   ├── Button Styles/
│   │   ├── CoreGraphics/
│   │   └── Formatters/
│   ├── Components/                  # Reusable SwiftUI pieces
│   │   ├── FluidGradient/           # Animated gradient background
│   │   ├── Defaults/                # Preference protocol and gradient palette settings
│   │   └── PermissionsView/         # PermissionsChecker.swift
│   ├── Utilities/                   # Non-view logic (no SwiftUI)
│   │   ├── Window Management/       # Window discovery, cache, actions catalog, native tab grouping
│   │   ├── Window Gestures/         # Gesture recognizer, zones, snap registry, HUD
│   │   ├── ActiveAppIndicator/      # Dock active-app indicator window
│   │   └── Media/                   # MediaRemoteService.swift
│   └── Views/Hover Window/          # Dock hover previews
│       ├── Special Hover Windows/   # Calendar/, Pinnable/, Folder/, Media/
│       ├── WindowPreview Supporting/
│       ├── Shared Components/
│       └── CmdTabFocus Overlay/
├── ClipboardKit/                    # Framework target (Maccy port)
│   ├── Compat/                      # GlassCompat.swift
│   ├── Models/                      # HistoryItem, HistoryItemContent, SizedString
│   ├── Observables/                 # History, PinManager, AppState, HistoryItemDecorator
│   ├── Panel/                       # Popup panel controller, view, model
│   ├── Settings/                    # SirenaClipboardSettings, SirenaForm, StorageSettingsPane
│   │   └── IgnoreSettingsPane/
│   └── Extensions/                  # Small helpers and Defaults.Keys names
├── SirenaFinder/                    # FinderSync app extension
│   ├── FinderSync.swift
│   ├── Info.plist
│   └── SirenaFinder.entitlements
├── Config/                          # Info.plist, entitlements, bridging header, third-party license texts
├── Design/                          # Source artwork (Sirena-icon-original.png)
├── scripts/                         # package-release.sh
├── Sirena.xcodeproj/                # Xcode project (4 targets: Sirena, DockKit, ClipboardKit, SirenaFinder)
├── README.md, README.pt-BR.md, LICENSE
└── (excluded from analysis: References/, build/)
```

## Directory Purposes

**`Sirena/App/`:**
- Purpose: Composition root and everything that is not a single feature.
- Contains: `main.swift`, `AppDelegate.swift`, `MainMenu.swift`, `SirenaStatusItem.swift`, `BoltMenu.swift`, `Localization.swift` (`L(...)` helper).
- Key files: `Sirena/App/AppDelegate.swift`, `Sirena/App/Modules/ModuleManager.swift`, `Sirena/App/Modules/ModuleID.swift`, `Sirena/App/MainWindow/MainWindowController.swift`.

**`Sirena/App/Pages/`:**
- Purpose: One SwiftUI settings page per feature, plus General and About.
- Contains: `GeneralPage.swift`, `MenuBarPage.swift`, `WindowsPage.swift`, `IslandPage.swift`, `ClipboardPage.swift`, `MixerPage.swift`, `MirrorPage.swift`, `ShelfPage.swift`, `ShortcutsTab.swift`, `FinderTab.swift`, `AboutView.swift`, etc.
- Naming: `<Feature>Page.swift`. Pages are shown through `SidebarItem` in `MainWindowController`.

**`Sirena/App/MainWindow/`:**
- Purpose: Main window shell and onboarding.
- Key files: `MainWindowController.swift` (`SidebarItem`, `Router`), `MainView.swift`, `HomeView.swift`, `HomeOrder.swift`, `OnboardingWindow.swift`, `Components.swift`, `EnergyBackdrop.swift`, `SirenaShortcutValidator.swift`.

**`Sirena/App/Modules/`:**
- Purpose: Feature registry only.
- Key files: `ModuleID.swift` (enum of 18 cases with `isEnabled`, `hostPage`, `hostTab`), `ModuleManager.swift` (`start`, `terminate`, `setEnabled`, `relaunch`).

**`Sirena/App/Compat/`:**
- Purpose: OS-version shims for the app target.
- Key files: `GlassCompat.swift`, `ScreenCaptureCompat.swift`.

**`Sirena/Modules/<Feature>/`:**
- Purpose: Feature code, one folder per `ModuleID` case (plus shared folders).
- Naming: `<Feature>Controller.swift` (lifecycle), `<Feature>Settings.swift` (defaults keys and values), `<Feature>Panel.swift` / `*Window.swift` (AppKit windows), `*View.swift` (SwiftUI), `*Model.swift` / `*Store.swift` (state and persistence).
- Notable sub-structure:
  - `WindowManagement/` has topical subfolders: `Snapping/`, `Snapping/CompoundSnapArea/`, `WindowCalculation/`, `WindowAnimation/`, `WindowMover/`, `MultiWindow/`, `TodoMode/`, `StackBadge/`, `Popover/`, `SettingsWindow/`, `WelcomeWindow/`, `AccessibilityAuthorization/`, `Utilities/`, `Logging/`.
  - `Island/` has `UI/`, `Settings/`, `Services/` (≈40 `Notch*Service.swift` / `Notch*Support.swift` pairs), `Strings/`, `Support/`, `Resources/`.
  - `MenuBar/` has `Features/StatusBar/{Layout,Engine/Native,Engine/Legacy}/`, `Models/`, `Views/`, `Common/`, `Extensions/`.
  - `Switcher/` mixes features with `*Support*.swift` / `*Shims*.swift` helpers (`SwitcherSupport.swift`, `SwitcherSupportShims.swift`, `SwitcherSupportShims2.swift`, `SwitcherSystemShortcutTakeoverSupport.swift`).
  - `Clipboard/Resources/` holds `Settings/en.lproj`, `Settings/pt-BR.lproj`, and `Sounds/` (copied into the bundle for ClipboardKit).
  - `Dock/` contains only `DockModule.swift`; DockDoor sounds and images for DockKit also live here so they resolve from the main bundle.

**`DockKit/`:**
- Purpose: Dock previews, window cache, gestures, and the Cmd-Tab focus overlay (ported from DockDoor, GPL-3.0; license at `Config/DockDoor-LICENSE-GPL-3.0.txt`).
- Entry: `DockKit/DockController.swift`.
- Naming: mixed. Most files use `UpperCamelCase.swift`, but some use lowercase (`consts.swift`, `dockStyle.swift`, `sliderSetting.swift`, `CGimage.swift`) and some contain spaces in folder names (`Window Management/`, `Hover Window/`). Follow the surrounding file's style.

**`ClipboardKit/`:**
- Purpose: Clipboard history (ported from Maccy; no Maccy license file is present under `Config/`). Includes monitor, storage, search, popup panel and settings.
- Entry: `ClipboardKit/ClipboardController.swift` (`public final class ClipboardController`).
- Public API for the app: `ClipboardKit/SirenaHistoryAPI.swift`.
- Persistence: `ClipboardKit/Storage.swift`, models in `ClipboardKit/Models/`.
- Naming: files are `UpperCamelCase.swift`; extensions named `Type+Feature.swift` (e.g. `NSImage+Resized.swift`, `Defaults.Keys+Names.swift`).

**`SirenaFinder/`:**
- Purpose: Finder Sync extension ("Copiar Caminho").
- Contains: `FinderSync.swift`, `Info.plist`, `SirenaFinder.entitlements`.

**`Config/`:**
- Purpose: Build configuration assets referenced by the Xcode project.
- Contains: `Info.plist` (app), `Sirena.entitlements`, `Sirena-Bridging-Header.h` (ObjC bridging to private/legacy APIs), `*-LICENSE*.txt` for vendored projects (DockDoor, Fader, Rectangle).

**`Sirena/Resources/`:**
- Purpose: Asset catalog, app icon, localization catalogs.
- Contains: `Assets.xcassets/`, `AppIcon.icon/` (`icon.json`, `Assets/`), `Localizable.xcstrings`, `Sirena.xcstrings`.

**`scripts/`:**
- Purpose: Release packaging. `scripts/package-release.sh`.

**`Design/`:**
- Purpose: Source icon artwork. Not compiled.

## Key File Locations

**Entry Points:**
- `Sirena/App/main.swift`: process entry.
- `Sirena/App/AppDelegate.swift`: launch, reopen, URL scheme routing, menus.
- `SirenaFinder/FinderSync.swift`: Finder extension entry.

**Configuration:**
- `Sirena.xcodeproj/project.pbxproj`: targets, deployment target (macOS 15.0), frameworks.
- `Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme`: shared scheme.
- `Config/Info.plist`, `Config/Sirena.entitlements`, `Config/Sirena-Bridging-Header.h`.
- `SirenaFinder/Info.plist`, `SirenaFinder/SirenaFinder.entitlements`.
- `.gitignore`.

**Core Logic:**
- `Sirena/App/Modules/ModuleManager.swift`: feature lifecycle.
- `Sirena/Modules/WindowManagement/WindowManager.swift`: window placement engine.
- `Sirena/Modules/Switcher/WindowSwitcherController.swift`: ⌘Tab replacement.
- `Sirena/Modules/Island/Services/NotchService.swift`: notch overlay data hub.
- `Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift`: per-app volume.
- `DockKit/DockController.swift`: Dock previews.
- `DockKit/Utilities/DockObserver.swift`: Dock observation.
- `ClipboardKit/Clipboard.swift`: pasteboard monitor.
- `ClipboardKit/Storage.swift`: history persistence.

**Testing:**
- No test target exists in `Sirena.xcodeproj` and no `*Tests*` directories or `*_test` files were found outside the excluded folders.

## Naming Conventions

**Files:**
- Feature controllers: `<Feature>Controller.swift` (`DisplayOffController.swift`, `MirrorController.swift`, `ShelfController.swift`).
- Feature settings: `<Feature>Settings.swift` (`MirrorSettings.swift`, `ShelfSettings.swift`, `PinWindowSettings.swift`) or `Defaults.swift` in a module folder.
- Pages: `<Feature>Page.swift` in `Sirena/App/Pages/`.
- Support files: `<Module>Support.swift`, `<Module>SupportShims.swift`, `<Module>Support+Topic.swift` for helper code split off a larger module.
- Notch services: `Notch<Source>Service.swift` with `Notch<Source>Support.swift` (Island).
- Prefixes: Mixer uses `SirenaMixer*.swift`; Switcher uses `Switcher*.swift`; Island uses `Notch*.swift`; WindowManagement uses `Window*`/`Cooperative*`; ClipboardKit files are unprefixed.
- Extensions: `Type+Feature.swift` (`NSScreen+ForPopup.swift`, `ModifierFlags+Current.swift`, `String+Shortened.swift`). Some folders carry the `Extensions` name with spaces (`DockKit/Extensions/Button Styles/`).

**Directories:**
- Feature folders are PascalCase singular or noun (`Clipboard`, `Mirror`, `Island`).
- Subfolders inside `Sirena/Modules/WindowManagement/` and `DockKit/Utilities/` use Title Case with spaces (`Window Gestures`, `Window Management`, `ActiveAppIndicator`).

**Types and identifiers:**
- Types: `UpperCamelCase`. Singletons are `static let shared`. Some entry objects use `static var instance` (`AppDelegate.instance`, `SirenaStatusItem.instance`).
- Defaults keys: dotted strings (`displayOff.delaySeconds`) or `sirena…` camelCase (`sirenaOpenHomeShortcut`). Keys must not contain dots when used with `MASShortcut` (see comment in `Sirena/App/AppDelegate.swift`).
- Debug environment variables: `SIRENA_OPEN_PAGE`, `SIRENA_OPEN_SETTINGS`, `SIRENA_SHOW_MIRROR`.
- URL scheme: `sirena://<action>` handled in `AppDelegate.application(_:open:)`.

## Where to Add New Code

**New feature module:**
1. Create `Sirena/Modules/<Feature>/` with `<Feature>Controller.swift` (`@MainActor final class … { static let shared; func start(); func terminate() }`) and `<Feature>Settings.swift`.
2. Add a case to `ModuleID` in `Sirena/App/Modules/ModuleID.swift` (set `isOnByDefault`, `hostPage`, `hostTab`, and its `enabledKey`).
3. Wire `start` and `terminate` in `Sirena/App/Modules/ModuleManager.swift`; add a branch in `setEnabled` if it should stop live.
4. Add a settings page `Sirena/App/Pages/<Feature>Page.swift` and register it in `SidebarItem`/`MainView` (`Sirena/App/MainWindow/`).
5. Add strings to `Sirena/Resources/Localizable.xcstrings` (or `Sirena.xcstrings`) and use `L(...)`.
6. Add the new `.swift` files to the `Sirena` target in `Sirena.xcodeproj/project.pbxproj`.

**New Dock or window-preview behaviour:** `DockKit/Utilities/` (logic) and `DockKit/Views/Hover Window/` (UI). Add a new framework-level extension under `DockKit/Extensions/`.

**New clipboard behaviour:** `ClipboardKit/` (models in `Models/`, UI in `Panel/` or `Settings/`). Expose anything the app needs through `ClipboardKit/SirenaHistoryAPI.swift`.

**New window-management action:** `Sirena/Modules/WindowManagement/WindowAction.swift` (enum case), `WindowActionCategory.swift` (category), and the calculation in `WindowCalculation/`. Shortcuts go through `ShortcutManager.swift`.

**New Island data source:** `Sirena/Modules/Island/Services/Notch<Source>Service.swift` with a `Notch<Source>Support.swift` helper; UI in `Sirena/Modules/Island/UI/`.

**New shared SwiftUI component (app target):** `Sirena/App/MainWindow/Components.swift` for main-window pieces, or a new file in `Sirena/App/` for app-wide components. For Dock/Clipboard UI, use `DockKit/Components/` or `ClipboardKit/Extensions/View+*.swift`.

**New OS-version helper:** Add it to the matching `GlassCompat.swift` in each target that needs it (`Sirena/App/Compat/`, `DockKit/Compat/`, `ClipboardKit/Compat/`), following the `#available` pattern.

**New Finder action:** `SirenaFinder/FinderSync.swift`.

**Utilities:**
- App-level helpers: `Sirena/App/` or the feature folder.
- Framework-level helpers: `DockKit/Utilities/Misc Utils.swift` (existing grab bag) or the relevant `DockKit/Extensions/` file.
- Clipboard helpers: `ClipboardKit/Extensions/`.

**Tests:** No test layout exists. If tests are introduced, add a new unit-test target to `Sirena.xcodeproj` rather than placing files inside the app folders.

## Special Directories

**`build/`:**
- Purpose: Xcode build output (excluded from this analysis).
- Generated: Yes.
- Committed: No (ignored by `.gitignore`).

**`References/`:**
- Purpose: Reference material (excluded from this analysis).
- Generated: No.
- Committed: Check `.gitignore` before adding files.

**`Sirena.xcodeproj/-Xcc/`:**
- Purpose: Clang module cache build artifacts.
- Generated: Yes.
- Committed: No. Do not edit.

**`.planning/`:**
- Purpose: GSD planning and codebase documents (this folder).
- Generated: Yes (by the mapper).
- Committed: Currently untracked.

---

*Structure analysis: 2026-10-20*
