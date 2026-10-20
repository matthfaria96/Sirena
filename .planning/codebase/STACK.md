# Technology Stack

**Analysis Date:** 2026-10-20

## Languages

**Primary:**
- Swift 5.0 and Swift 6.0 (set per target via `SWIFT_VERSION` in `Sirena.xcodeproj/project.pbxproj`) - All app, framework, and extension code
  - Swift 5.0: `Sirena` app target, `DockKit` framework, `SirenaFinder` extension
  - Swift 6.0: `ClipboardKit` framework only
- Source roots: `Sirena/` (app shell and feature modules), `DockKit/` (framework), `ClipboardKit/` (framework), `SirenaFinder/` (Finder Sync extension). About 650 `.swift`/`.h`/`.m` files excluding `References/` and `build/`.

**Secondary:**
- Objective-C - Native menu bar visibility shim: `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m` with header `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.h`
- Objective-C bridging header: `Config/Sirena-Bridging-Header.h` (imports AppKit, declares `_AXUIElementGetWindow`, imports the shim header)
- Shell - Release packaging: `scripts/package-release.sh`
- String catalogs: `Sirena/Resources/Sirena.xcstrings` and `Sirena/Resources/Localizable.xcstrings` (source language `en`; about 1326 `pt-BR` entries in `Localizable.xcstrings`)
- XML property lists: `Config/Info.plist`, `Config/Sirena.entitlements`, `SirenaFinder/Info.plist`, `SirenaFinder/SirenaFinder.entitlements`

## Runtime

**Environment:**
- macOS 15.0 (Sequoia) minimum deployment target (`MACOSX_DEPLOYMENT_TARGET = 15.0`), SDK `macosx`
- Version-gated code paths: macOS 26+ Liquid Glass look (`DockKit/Utilities/LiquidGlass.swift`, `DockKit/Compat/GlassCompat.swift`, `ClipboardKit/Compat/GlassCompat.swift`); macOS 27 native menu bar visibility, enabled by the `HIDDENBAR_NATIVE_VISIBILITY` compile condition on the app target (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`)
- Application type: menu bar agent app. `LSUIElement = true` in `Config/Info.plist`, principal class `NSApplication`. Entry point `Sirena/App/main.swift` (calls `NSApplicationMain`), delegate `Sirena/App/AppDelegate.swift`
- Bundle identifiers: `com.matheusfaria.Sirena` (app), `com.matheusfaria.Sirena.DockKit`, `com.matheusfaria.Sirena.ClipboardKit`, `com.matheusfaria.Sirena.Finder` (Finder Sync extension, package type `XPC!`)
- URL scheme: `sirena` (`CFBundleURLTypes` in `Config/Info.plist`)
- Current version: `MARKETING_VERSION = 0.4.1`, `CURRENT_PROJECT_VERSION = 111`

**Package Manager:**
- Xcode project with Swift Package Manager dependencies resolved by Xcode. No CocoaPods, Carthage, or Mint files.
- Lockfile: present - `Sirena.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (format version 3)
- Xcode project format: `objectVersion = 77` (`README.md` says the project requires Xcode 27)
- Build command (from `README.md`): `xcodebuild -scheme Sirena -configuration Release -derivedDataPath build/DerivedData -skipMacroValidation -skipPackagePluginValidation build`

## Frameworks

**Core (Apple system frameworks, as imported in source):**
- SwiftUI - Settings, main window, hover previews, Island UI, overlays (about 140 files)
- AppKit / Cocoa - Windows, panels, status items, menus, pasteboard (about 230 files)
- Foundation, Combine, Observation, Darwin - Runtime and reactive state
- SwiftData - Clipboard history persistence: `ClipboardKit/Storage.swift`, `ClipboardKit/Observables/History.swift`, `ClipboardKit/Models/HistoryItem.swift`, `ClipboardKit/Models/HistoryItemContent.swift`
- CoreGraphics, QuartzCore, CoreImage, ImageIO, IOSurface, Accelerate, Compression - Window capture, layers, image processing, audio DSP, artwork decompression
- ScreenCaptureKit - Window thumbnails and streams: `DockKit/Utilities/Window Management/LiveWindowCapture.swift`, `DockKit/Utilities/Window Management/WindowUtil.swift`
- ApplicationServices (Accessibility: AXUIElement, AXValue, AXError, role and attribute constants) - Window control and Dock inspection
- Carbon and Carbon.HIToolbox (Events) - Key codes and hotkey events: `DockKit/consts.swift`, `DockKit/Utilities/KeybindHelper.swift`, `DockKit/Utilities/DockObserver.swift`, `DockKit/Utilities/KeyboardLabel.swift`
- AVFoundation - Camera (Mirror, Island camera preview) and microphone level metering: `Sirena/Modules/Mirror/`, `Sirena/Modules/Island/Support/IslandCameraPreviewService.swift`
- CoreAudio - Per-app audio mixer (`Sirena/Modules/Mixer/`) and audio output device enumeration (`DockKit/Views/Hover Window/Special Hover Windows/Media/AudioOutputDevice.swift`)
- EventKit - Calendar events: `DockKit/Models/CalendarInfo.swift`, `Sirena/Modules/Island/Support/IslandPermissions.swift`
- Vision, NaturalLanguage, Translation - OCR and text capture: `Sirena/Modules/TextCapture/TextRecognizer.swift`, `Sirena/Modules/TextCapture/TextCaptureController.swift`, `Sirena/Modules/TextCapture/CapturePanels.swift`
- UserNotifications - `ClipboardKit/Notifier.swift`, `Sirena/Modules/Pomodoro/PomodoroController.swift`
- ServiceManagement - Launch at login: `Sirena/Modules/WindowManagement/LaunchOnLogin.swift`
- AppIntents - Shelf intents: `Sirena/Modules/Shelf/ShelfIntents.swift`
- QuickLookThumbnailing, Quartz, UniformTypeIdentifiers - Shelf file previews: `Sirena/Modules/Shelf/`
- IOKit (`ps`, `pwr_mgt`, IOHIDSystem lookup) - Power sources (`Sirena/Modules/Island/Services/NotchService.swift`), sleep prevention assertions (`Sirena/Modules/KeepAwake/SleepPreventionManager.swift`), HID idle state (`DockKit/Utilities/DockObserver.swift`)
- CoreBluetooth, IOBluetooth - Bluetooth accessory connection and battery: `Sirena/Modules/Island/Services/NotchAccessoryService.swift`, `Sirena/Modules/Island/Support/IslandPeripheralBatterySampler.swift`
- FinderSync - Finder extension: `SirenaFinder/FinderSync.swift`

**Testing:**
- Not detected. No test target in `Sirena.xcodeproj/project.pbxproj`, no `*Tests` directories, no XCTest imports.

**Build/Dev:**
- Xcode 27 and `xcodebuild`. Shared scheme: `Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme`
- `-skipMacroValidation` and `-skipPackagePluginValidation` are passed to the build (see `scripts/package-release.sh`)
- `ENABLE_USER_SCRIPT_SANDBOXING = YES` (Debug and Release)
- `ENABLE_HARDENED_RUNTIME = YES` on the app target; `scripts/package-release.sh` overrides it to `NO` for ad-hoc distribution
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the `ClipboardKit` target
- `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`
- `ALWAYS_SEARCH_USER_PATHS = NO`, `CLANG_ENABLE_MODULES = YES`, `ENABLE_STRICT_OBJC_MSGSEND = YES`
- Debug configuration: `GCC_OPTIMIZATION_LEVEL = 0`, `SWIFT_OPTIMIZATION_LEVEL = -Onone`, `ONLY_ACTIVE_ARCH = YES`, `DEBUG=1`

## Key Dependencies

All remote Swift packages are declared in `Sirena.xcodeproj/project.pbxproj` and pinned in `Sirena.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

**Critical (feature-bearing packages):**
- `Defaults` 9.0.9 (`https://github.com/sindresorhus/Defaults`) - Typed `UserDefaults` wrapper. Linked into `ClipboardKit` (28 files import it) and `DockKit` (70 files).
- `KeyboardShortcuts` 3.1.0 (`https://github.com/sindresorhus/KeyboardShortcuts`) - User-configurable global hotkeys. Used in `ClipboardKit/ClipboardController.swift`, `ClipboardKit/KeyChord.swift`, `ClipboardKit/Settings/SirenaClipboardSettings.swift`.
- `MASShortcut` (revision `2f9fbb3f959b7a683c6faaf9638d22afad37a235`, `https://github.com/rxhanson/MASShortcut`) - Shortcut recorder and global hotkeys for the main app. Imported in `Sirena/App/AppDelegate.swift`, `Sirena/App/Pages/ShortcutsTab.swift`, `Sirena/App/Pages/WindowsPage.swift`, `Sirena/App/MainWindow/Components.swift`, `Sirena/App/MainWindow/SirenaShortcutValidator.swift`.
- `HotKey` 0.2.1 (`https://github.com/soffes/HotKey`) - Carbon-based hotkey library. Linked into the project, but no `import HotKey` was found in sources (only credited in `Sirena/App/Pages/AboutView.swift`).
- `Sauce` 2.5.2 (`https://github.com/Clipy/Sauce`) - Keyboard layout and key code translation. Used in `ClipboardKit/KeyChord.swift` and `ClipboardKit/Extensions/Sauce+KeyboardShortcuts.swift`.
- `MediaRemoteAdapter` (branch `master`, revision `5b6afde3f501a3da567e23bf7f23d562938a1809`, `https://github.com/ejbills/mediaremote-adapter.git`) - Now-playing and media control bridge, wrapped by `DockKit/Utilities/Media/MediaRemoteService.swift`.
- `Fuse` 1.4.0 (`https://github.com/krisk/fuse-swift`) - Fuzzy search. Used only in `ClipboardKit/Search.swift`.
- `Settings` 3.1.2 (`https://github.com/sindresorhus/Settings.git`) - Preferences window scaffolding. Used in `ClipboardKit/Settings/StorageSettingsPane.swift` and `ClipboardKit/Extensions/Settings.PaneIdentifier+Panes.swift`.

**Supporting:**
- `Logging` (swift-log) 1.16.1 (`https://github.com/apple/swift-log`) - Logging facade. Used in `ClipboardKit/Observables/History.swift`.
- `SmoothGradient` 1.0.1 (`https://github.com/raymondjavaxx/SmoothGradient`) - SwiftUI gradient helper. Used in `DockKit/Extensions/View.swift`.
- `SwiftHEXColors` 1.4.1 (`https://github.com/thii/SwiftHEXColors`) - Hex color package. Linked into the project, but no `import SwiftHEXColors` was found in sources.
- `swift-syntax` 604.0.0 (`https://github.com/swiftlang/swift-syntax`) - Pinned in `Package.resolved` only. No direct reference in `Sirena.xcodeproj/project.pbxproj`, so it is not a declared product dependency of any target.

**Local framework targets (in-repo, not packages):**
- `ClipboardKit` (`ClipboardKit/`, product type framework, Swift 6.0, bundle `com.matheusfaria.Sirena.ClipboardKit`) - Clipboard history feature
- `DockKit` (`DockKit/`, product type framework, Swift 5.0, bundle `com.matheusfaria.Sirena.DockKit`) - Dock previews, window switcher, media controls, and related window management
- Both are embedded in the app bundle; `LD_RUNPATH_SEARCH_PATHS` includes `@executable_path/../Frameworks` and `@loader_path/Frameworks`.

**Vendored code and licensing:**
- No third-party source is vendored in the repo tree outside `References/` (excluded from analysis). Code adapted from Rectangle (MIT), DockDoor (GPL-3.0), Vorssaint, Maccy (MIT), Hidden Bar (MIT), Caffeine (MIT), Iris (MIT), and Fader (MIT) is credited in `README.md` and `Sirena/App/Pages/AboutView.swift`. License texts shipped in `Config/`: `Config/Rectangle-LICENSE.txt`, `Config/DockDoor-LICENSE-GPL-3.0.txt`, `Config/Fader-LICENSE.txt`. Top-level `LICENSE` is GPL-3.0.

## Configuration

**Environment:**
- No `.env` files present. No runtime configuration is read from environment files.
- The shared Run scheme sets `SIRENA_OPEN_SETTINGS=1` (`Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme`).
- Runtime settings live in `UserDefaults` (for example `NSWindow Frame SirenaMainWindow` in `Sirena/App/MainWindow/MainWindowController.swift`, `boltMenu.addedFocusColorBrush` in `Sirena/App/BoltMenu.swift`, `PreferenceKeys.*` used with `@AppStorage` in `Sirena/App/Pages/KeepAwakePage.swift`). The Finder extension reads `AppleInterfaceStyle` from `UserDefaults.standard` (`SirenaFinder/FinderSync.swift`).
- Application support files: `Sirena/Modules/ColorPicker/ColorStore.swift`, `Sirena/Modules/Shelf/ShelfStore.swift`, `Sirena/Modules/Island/Services/NotchBrowserArtwork.swift` (all via `FileManager.default.urls(for: .applicationSupportDirectory, ...)`).
- Clipboard history is stored with SwiftData (`ClipboardKit/Storage.swift`).

**Build:**
- `Sirena.xcodeproj/project.pbxproj` - Single source of truth for targets, build settings, and package references
- `Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme` - Shared scheme
- `Config/Info.plist` - App Info.plist, uses `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`, `$(MACOSX_DEPLOYMENT_TARGET)` placeholders
- `Config/Sirena.entitlements` - App entitlements (see Platform Requirements)
- `SirenaFinder/SirenaFinder.entitlements` - Finder extension entitlements
- `Config/Sirena-Bridging-Header.h` - Swift/Objective-C bridging header (`SWIFT_OBJC_BRIDGING_HEADER`)
- `Sirena/Resources/AppIcon.icon/icon.json` and `Sirena/Resources/Assets.xcassets/` - App icon and asset catalog
- `.gitignore` - Excludes `References/`, `build/`, `DerivedData/`, `.build/`, `xcuserdata/`, and `Sirena.xcodeproj/-Xcc/`

## Platform Requirements

**Development:**
- macOS with Xcode 27 (project format `objectVersion = 77`), SDK `macosx`
- Manual code signing with identity `Sirena Local Dev` (`CODE_SIGN_STYLE = Manual`) in Debug and Release. Per `README.md`, this certificate exists only on the developer's Mac.
- Toolchain must support Swift 5.0 and 6.0 language modes

**Production:**
- Distributed outside the Mac App Store under GPL-3.0. Release artifacts (`Sirena.zip`, `Sirena-<version>.dmg`) are produced by `scripts/package-release.sh`: ad-hoc signing (`CODE_SIGN_IDENTITY=-`), `ENABLE_HARDENED_RUNTIME=NO`, `ditto` to keep framework symlinks, and `hdiutil` to build the DMG.
- Not notarized (per `README.md`). Minimum OS: macOS 15.0.
- App sandbox: the main `Sirena` target does not enable `com.apple.security.app-sandbox` (absent from `Config/Sirena.entitlements`). The `SirenaFinder` extension does enable it (`SirenaFinder/SirenaFinder.entitlements`).
- Entitlements in `Config/Sirena.entitlements`: `com.apple.security.automation.apple-events`, `com.apple.security.device.audio-input`, `com.apple.security.device.camera`, `com.apple.security.personal-information.calendars`.
- Distribution via GitHub Releases (`README.md`). Git tags present: `v0.3.0`, `v0.4.0`.

---

*Stack analysis: 2026-10-20*
