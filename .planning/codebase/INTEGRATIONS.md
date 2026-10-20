# External Integrations

**Analysis Date:** 2026-10-20

Sirena is a local macOS menu bar app. It has no backend, no accounts, no database server, and no webhooks. Its "integrations" are the macOS system frameworks, private system frameworks and processes it talks to, the TCC permissions it requests, a few public HTTP lookup services, URL schemes it handles, and Swift packages it links.

## APIs & External Services

**Public HTTP services (the only outbound network calls found in source):**
- lrclib.net - Synced lyrics lookup
  - Endpoints: `https://lrclib.net/api/get`, `https://lrclib.net/api/search`
  - Client: `URLSession` in `Sirena/Modules/Island/Services/NotchLyricsSupport.swift` (lines ~134, ~206, ~328, ~602) and `DockKit/Models/MediaInfo.swift` (lines ~438-479)
  - Data sent: track title, artist, album, and duration (the Island settings hint in `Sirena/Modules/Island/Strings/NotchMusicExtrasStrings.swift` says this is sent while lyrics are open)
  - Auth: none
- MusicBrainz - Artist, recording and release-group lookup used to match lyrics and metadata
  - Endpoints: `https://musicbrainz.org/ws/2/artist/`, `https://musicbrainz.org/ws/2/recording/`, `https://musicbrainz.org/ws/2/release-group/` (`Sirena/Modules/Island/Services/NotchLyricsSupport.swift` lines ~501-571)
  - Decoding model: `DockKit/Models/MediaInfo.swift` (`MusicBrainzRelease`, `release-list` key)
  - Auth: none
- Apple iTunes Search API - Album artwork lookup for now-playing items
  - Endpoint: `https://itunes.apple.com/search` (`Sirena/Modules/Island/Services/NotchBrowserArtworkSupport.swift` line ~171, `DockKit/Models/MediaInfo.swift` line ~779)
  - Auth: none
- YouTube thumbnail CDN - Cover art for browser playback
  - Endpoint pattern: `https://i.ytimg.com/vi/<id>/maxresdefault.jpg` and `mqdefault.jpg` (`Sirena/Modules/Island/Services/NotchBrowserArtworkSupport.swift` line ~241)
  - Video id comes from the browser session data described below
  - Auth: none
- Artwork download fallback: `NotchBrowserArtwork.swift` (`download(_:completion:)`) fetches candidate URLs in sequence and caches results under `applicationSupportDirectory` (`Sirena/Modules/Island/Services/NotchBrowserArtwork.swift` line ~171)

**Links only (opened in a browser, no client code):**
- `https://support.apple.com/102646` - Screenshot help (`Sirena/App/Modules/ModuleID.swift`)
- `https://imagestudiopro.com` - ScreenBrush credit (`Sirena/App/Modules/ModuleID.swift`)
- `https://ss64.com/mac/pmset.html` - pmset reference (`Sirena/App/Modules/ModuleID.swift`)
- GitHub repositories for credited projects (`Sirena/App/Pages/AboutView.swift`, `README.md`)

**Not detected:** Any analytics, crash reporting, telemetry, payments, AI or LLM API, cloud storage, or push service SDK. No update checker (no Sparkle or GitHub Releases API calls found).

## Data Storage

**Databases:**
- SwiftData (local, on device) - Clipboard history
  - Models: `ClipboardKit/Models/HistoryItem.swift`, `ClipboardKit/Models/HistoryItemContent.swift`
  - Store and access: `ClipboardKit/Storage.swift`, `ClipboardKit/Observables/History.swift`
  - Connection: none (no URL or env var)
- No server database, no SQLite client code of Sirena's own

**File Storage:**
- Local filesystem only
  - Color picker palettes and history: JSON in `~/Library/Application Support/Sirena/Colors/` (`Sirena/Modules/ColorPicker/ColorStore.swift`)
  - Shelf items: `Sirena/Modules/Shelf/ShelfStore.swift` (Application Support)
  - Browser artwork cache: `Sirena/Modules/Island/Services/NotchBrowserArtwork.swift` (Application Support)
  - Folder widgets: security-scoped bookmarks from `NSOpenPanel` (`DockKit/Views/Hover Window/Special Hover Windows/Folder/FolderWidgetModel.swift`, `FolderWidgetView.swift`)
  - Mirror and Shelf file pickers: `Sirena/App/Pages/MirrorPage.swift`, `Sirena/App/Pages/ShelfPage.swift`, `Sirena/Modules/Switcher/WindowSwitcherSettingsView.swift`

**Caching:**
- In-memory caches only: `MediaInfo.cache` (`DockKit/Models/MediaInfo.swift`), `ApplicationImageCache` (`ClipboardKit/ApplicationImageCache.swift`), now-playing artwork cache in `Sirena/Modules/Island/Services/NotchMusicService.swift`
- No Redis, Memcached, or other external cache

**Preferences:**
- `UserDefaults.standard` and `@AppStorage` throughout (for example `Sirena/App/MainWindow/HomeOrder.swift`, `Sirena/App/BoltMenu.swift`, `Sirena/App/Pages/KeepAwakePage.swift`)
- `UserDefaults(suiteName: "com.apple.WindowManager")` is read to detect Stage Manager ("GloballyEnabled") in `DockKit/Utilities/Window Management/ScreenReservations.swift`
- Menu bar state is changed via `/usr/bin/defaults` (`Sirena/Modules/MenuBar/MenuBarModule.swift` line ~563)

## Authentication & Identity

**Auth Provider:**
- None. No user accounts, no sign-in, no OAuth, no tokens.
- Keychain: not used (no `SecItem` or `SecKey` calls found).

**Operating system authorization (TCC), requested by the app:**
- Accessibility - `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions` (`DockKit/Utilities/DockObserver.swift`, `DockKit/Utilities/Window Management/WindowSeeder.swift`, `DockKit/Components/PermissionsView/PermissionsChecker.swift`, `Sirena/App/MainWindow/OnboardingWindow.swift`). Required by window management, Switcher, Dock previews.
- Screen Recording - `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` (`DockKit/DockController.swift`, `Sirena/App/MainWindow/OnboardingWindow.swift`). Required by Dock thumbnails, Pin Window, Capture Text. Usage string: `NSScreenCaptureUsageDescription`.
- Camera - `com.apple.security.device.camera` entitlement; Mirror and the Island camera preview (`Sirena/Modules/Mirror/MirrorCamera.swift`, `Sirena/Modules/Island/Support/IslandCameraPreviewService.swift`). Usage string: `NSCameraUsageDescription`.
- Microphone - `com.apple.security.device.audio-input` entitlement; used only for the Mirror level meter (`Sirena/Modules/Mirror/MirrorAudioMeter.swift`). Usage string: `NSMicrophoneUsageDescription`.
- Audio capture - `NSAudioCaptureUsageDescription` (per-app volume mixer via Core Audio process taps, `Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift`, which calls `AudioHardwareCreateProcessTap` and `AudioHardwareCreateAggregateDevice`).
- Calendars - `com.apple.security.personal-information.calendars` entitlement and `NSCalendarsFullAccessUsageDescription` / `NSCalendarsUsageDescription` (`DockKit/Models/CalendarInfo.swift`, `Sirena/Modules/Island/Support/IslandPermissions.swift`)
- Apple Events / Automation - `com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription`. Used to query and control Music and Spotify (see below).
- Bluetooth - `NSBluetoothAlwaysUsageDescription` (`Sirena/Modules/Island/Services/NotchAccessoryService.swift`, `Sirena/Modules/Island/Support/IslandPeripheralBatterySampler.swift`)
- Downloads folder - `NSDownloadsFolderUsageDescription` (`Sirena/Modules/Island/Services/NotchDownloadService.swift`)
- Notifications - `UNUserNotificationCenter` (`ClipboardKit/Notifier.swift`, `Sirena/Modules/Pomodoro/PomodoroController.swift`)
- Login item - `ServiceManagement` (`Sirena/Modules/WindowManagement/LaunchOnLogin.swift`)

## Apple System Interfaces

**Public frameworks:** see `STACK.md` for the full list. Integration-relevant ones:
- Accessibility (`ApplicationServices`) - AXUIElement access to the Dock's app list (`DockKit/Utilities/DockObserver.swift` `applicationDockItems()`), windows, and the Notification Center UI (see below)
- ScreenCaptureKit - `SCShareableContent`, `SCStream` for window thumbnails (`DockKit/Utilities/Window Management/LiveWindowCapture.swift`, `WindowUtil.swift`); `ScreenCaptureCompat.swift` in `Sirena/App/Compat/`
- EventKit - Calendar events (`DockKit/Models/CalendarInfo.swift`)
- Core Audio - Default device and volume (`Sirena/Modules/Island/Support/IslandHardware.swift`), mixer (`Sirena/Modules/Mixer/`), device listing (`DockKit/Views/Hover Window/Special Hover Windows/Media/AudioOutputDevice.swift`)
- CoreBluetooth and IOBluetooth - Paired device list and connect/disconnect notifications (`IOBluetoothDevice.pairedDevices()`, `IOBluetoothDevice.register(forConnectNotifications:...)` in `Sirena/Modules/Island/Services/NotchAccessoryService.swift`)
- IOKit - Power sources (`Sirena/Modules/Island/Services/NotchService.swift`), IOPM sleep assertions (`Sirena/Modules/KeepAwake/SleepPreventionManager.swift`), `IOHIDSystem` (`DockKit/Utilities/DockObserver.swift`)
- Vision and NaturalLanguage - On-device OCR and language detection (`Sirena/Modules/TextCapture/`)
- Translation - On-device translation (`Sirena/Modules/TextCapture/CapturePanels.swift`)
- AppIntents - Shortcuts actions (`Sirena/Modules/Shelf/ShelfIntents.swift`)
- FinderSync - Finder extension `com.matheusfaria.Sirena.Finder` (`SirenaFinder/FinderSync.swift`), copies selected item paths to the pasteboard
- NSServices - "Adicionar à Prateleira do Sirena" Services menu entry for `public.item`, `public.utf8-plain-text`, `public.url`, `public.image` (`Config/Info.plist`, handled in `Sirena/App/AppDelegate.swift`, `validRequestor(forSendType:returnType:)` and `readSelection(from:)`)
- DistributedNotificationCenter - Observers for keyboard layout changes (`Sirena/Modules/Switcher/SwitcherAppSwitcher.swift`, `Sirena/Modules/Switcher/SwitcherGlobalShortcut.swift`), download announcements (`Sirena/Modules/Island/Services/NotchDownloadService.swift`), and Island events (`Sirena/Modules/Island/Services/NotchService.swift`)
- Pasteboard - Clipboard history polls `NSPasteboard.changeCount` (`ClipboardKit/Clipboard.swift`, `ClipboardKit/Observables/History.swift`); Shelf and Tweaks also watch it (`Sirena/Modules/Shelf/ShelfController.swift`, `Sirena/Modules/Tweaks/TweaksController.swift`)
- CGEvent - Event taps and synthetic mouse events (`DockKit/Utilities/DockObserver.swift`, `DockKit/Utilities/KeybindHelper.swift`, `DockKit/Utilities/Window Gestures/WindowGestureController.swift`, `DockKit/Utilities/TrackpadSwipeTrigger.swift`, `Sirena/Modules/Switcher/SwitcherAppSwitcher.swift`, `Sirena/Modules/Tweaks/TweaksController.swift`, `Sirena/Modules/WindowManagement/Utilities/EventMonitor.swift`). Event-tap permission depends on tap type. This was not verified per tap.

## Private and Undocumented APIs

These are not part of the public SDK. They are the most fragile integration points across macOS releases.

- CoreGraphics Services (CGS/SLS-style) - Declared in `DockKit/Utilities/PrivateApis.swift` and used from `DockKit/Extensions/CoreGraphics/CGWindowID.swift` (`CGSCopyWindowProperty`, `CGSGetWindowLevel`, `CGSCopySpacesForWindows`, `CGSMainConnectionID`), `DockKit/Utilities/Window Management/WindowDiscoveryShared.swift` (`CGSCopyManagedDisplaySpaces`), and `DockKit/Utilities/Window Management/WindowUtil.swift` (`CGSHWCaptureWindowList`). Used for Space and window-level lookup and capture options.
- `_AXUIElementGetWindow` - Declared in `Config/Sirena-Bridging-Header.h` and `DockKit/Utilities/PrivateApis.swift` (`@_silgen_name`). Maps an `AXUIElement` to a `CGWindowID`.
- SwiftUI Liquid Glass symbols - `@_silgen_name` bindings for `$s7SwiftUI5GlassV...` and `$s7SwiftUI6_GlassV...` in `DockKit/Utilities/LiquidGlass.swift` (weak-linked). The `OTHER_LDFLAGS` in `Sirena.xcodeproj/project.pbxproj` add `-Xlinker -U` entries for these symbols so the link succeeds on older SDKs. Used only on macOS 26+.
- MenuBarClientCore (`/System/Library/PrivateFrameworks/MenuBarClientCore.framework`) - Resolved at runtime with `dlopen`/`NSClassFromString` in `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m` (classes `MBAssessmentModeConfiguration`, `MBAssessmentModeAssertion`). Used for native hidden-icon visibility on macOS 27. Enabled only when the `HIDDENBAR_NATIVE_VISIBILITY` compile condition is set. Header: `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.h`.
- DisplayServices (`/System/Library/PrivateFrameworks/DisplayServices.framework`) - `dlopen`/`dlsym` of `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness`, `DisplayServicesRegisterForBrightnessChangeNotifications` in `Sirena/Modules/Island/Support/IslandHardware.swift` (lines ~390-394). Used for display brightness.
- MediaRemote - Via the `MediaRemoteAdapter` Swift package (see below). `DockKit/Utilities/Media/MediaRemoteService.swift` wraps it for now-playing info, playback commands, and seek. `Sirena/Modules/Island/Services/NotchMusicService.swift` runs a bundled perl helper from the same package to read Now Playing.
- Notification Center UI - `Sirena/Modules/Island/Services/NotchNotificationReader.swift` uses `Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")` for localized strings and reads banners through the Accessibility API (`AXUIElement`, pid-based access in `NotchNotificationReaderCore`).
- Window server Space mask - `kCGSAllSpacesMask` and window capture option flags in `DockKit/Utilities/PrivateApis.swift`.
- Browser session files (read-only, local) - When a Firefox-family browser (Firefox, Zen) plays without cover art, `Sirena/Modules/Island/Services/NotchBrowserArtwork.swift` reads that browser's saved session data on this Mac to find the video id (described in `Sirena/Modules/Island/Strings/NotchMusicExtrasStrings.swift`).

## Music and Media Players

- Spotify (`com.spotify.client`) and Apple Music (`com.apple.Music`, legacy `com.apple.iTunes`) - Playback state and control
  - Via AppleScript run through `/usr/bin/osascript` (`DockKit/Models/MediaInfo.swift`, `OSAScriptRunner`, `Process()` with stdin/stdout pipes)
  - Also via the MediaRemote adapter for other apps
  - Known apps list: `DockKit/consts.swift` (`spotifyAppIdentifier`), `Sirena/Modules/Island/Services/NotchPreferredPlayer.swift` (`known`), `Sirena/Modules/Island/Services/NotchPlaybackSource.swift` (`knownMusicApps`)
  - Command writer: `Sirena/Modules/Island/Services/NotchMusicCommandWriter.swift` serializes playback commands
  - Usage string: `NSAppleEventsUsageDescription` ("...mostrar a música tocando no Música e no Spotify...")
- Safari (`com.apple.Safari`) - Only named in AppleScript help text (`DockKit/Utilities/ScriptCommands.swift`, line ~376)

## AppleScript and Scripting

- No scripting dictionary is present. No `.sdef`, `.scriptSuite`, or `.scriptTerminology` file exists in the repo.
- `DockKit/Utilities/ScriptCommands.swift` contains command parsing and handlers modelled on DockDoor's AppleScript commands (`WindowAction`, position strings). It is not connected to a scripting dictionary in this repo, so its reachability from outside the app is unverified.

## URL Scheme (`sirena://`)

Registered in `Config/Info.plist` (`CFBundleURLTypes`, scheme `sirena`). Handled in `Sirena/App/AppDelegate.swift` (`application(_:open:)`):

- `sirena://capture-text` - Capture text from the screen
- `sirena://capture-last` - Capture last selection
- `sirena://read-code` - Capture code (QR and barcode path)
- `sirena://capture-translate` - Capture text and translate
- `sirena://open-hidden-icon?app=<bundle id>` - Open a hidden menu bar icon (`MenuBarModule.shared.openHiddenIcon(bundleID:)`)
- `sirena://hidden-icons-show` and `sirena://hidden-icons-hide` - Expand or collapse hidden icons
- `sirena://sound` - Open the sound menu
- `sirena://shelf-toggle` and `sirena://shelf-add-clipboard` - Shelf actions
- `sirena://execute-action?name=<action>` - Window management actions, such as `left-half` (`Sirena/Modules/WindowManagement/WindowManagementModule.swift`, `handle(urls:)`, line ~513)

Other URLs are passed to `windowManagement.handle(urls:)`.

## Command-Line Tools Invoked

Spawned with `Process()` (not a shell, except one case noted):

- `/usr/bin/osascript` - Music and Spotify queries and commands (`DockKit/Models/MediaInfo.swift`)
- `/usr/sbin/screencapture` - Screenshot tool (`Sirena/Modules/ScreenCapture/ScreenCaptureController.swift`, line ~251)
- `/usr/bin/defaults` - Menu bar settings (`Sirena/Modules/MenuBar/MenuBarModule.swift`, line ~563)
- `/usr/bin/pmset` - Display off (`Sirena/Modules/DisplayOff/DisplayOffController.swift`, line ~81)
- `/usr/bin/pluginkit -e use|ignore -i com.matheusfaria.Sirena.Finder` - Enables or disables the Finder extension (`Sirena/Modules/Tweaks/TweaksSettings.swift`, line ~121)
- `/usr/bin/hdiutil` and `/usr/bin/ditto` - Mount and copy apps from DMG files for the Tweaks installer (`Sirena/Modules/Tweaks/DMGInstaller.swift`, lines ~55, ~168)
- `/usr/sbin/system_profiler SPBluetoothDataType -json` - Bluetooth battery sampling (`Sirena/Modules/Island/Support/IslandPeripheralBatterySampler.swift`, line ~164)
- `/usr/bin/open` - Relaunch via `/bin/sh -c "sleep 1; /usr/bin/open ..."` (`Sirena/App/Modules/ModuleManager.swift`, lines ~138-140), the only `/bin/sh` invocation
- `/usr/bin/perl` helper from the MediaRemoteAdapter package (see above)

Build-time and release tools: `xcodebuild`, `codesign`, `ditto`, `hdiutil`, `shasum` (`scripts/package-release.sh`)

## Swift Package Dependencies

Remote packages, pinned in `Sirena.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. No API keys are used. Full details are in `STACK.md`.

- `MediaRemoteAdapter` (`https://github.com/ejbills/mediaremote-adapter.git`, branch `master`) - MediaRemote bridge and perl helper
- `Defaults`, `KeyboardShortcuts`, `MASShortcut`, `HotKey`, `Sauce`, `Fuse`, `Settings`, `Logging`, `SmoothGradient`, `SwiftHEXColors`, `swift-syntax` - See `STACK.md`

No Swift package performs network I/O at runtime except through Sirena's own code.

## Environment Configuration

**Required env vars:**
- None. The app reads no environment variables for configuration. The Xcode scheme sets `SIRENA_OPEN_SETTINGS=1` for debugging only (`Sirena.xcodeproj/xcshareddata/xcschemes/Sirena.xcscheme`).

**Secrets location:**
- No secrets are used or stored by the project. No `.env` files exist. No API keys or tokens are required by any integration above.
- Code signing identity `Sirena Local Dev` is managed by the developer's Keychain on their Mac (`Sirena.xcodeproj/project.pbxproj`). It is not stored in the repo.

## Webhooks & Callbacks

**Incoming:**
- URL scheme `sirena://` (see above). No HTTP server or listening socket.
- Services menu entry (NSServices) and Shortcuts intents (AppIntents)

**Outgoing:**
- lrclib.net, musicbrainz.org, itunes.apple.com, i.ytimg.com HTTP GET requests only (see above)
- No webhooks, no POST requests, no third-party callbacks

## CI/CD & Deployment

**Hosting:**
- GitHub Releases for distribution (`README.md`: "Download the `.dmg` (or `Sirena.zip`) from the Releases page"). Release artifacts are built locally by `scripts/package-release.sh`.

**CI Pipeline:**
- None detected. No `.github/` directory, no `.gitlab-ci.yml`, no `fastlane/`, no `Makefile`.

**Notarization:**
- Not performed. Release artifacts are ad-hoc signed (`scripts/package-release.sh`), so Gatekeeper requires the user to allow the app manually (`README.md`).

## Monitoring & Observability

**Error Tracking:** None.

**Logs:**
- `os.log` (`import os.log`, 3 files) and `Logging` (swift-log, `ClipboardKit/Observables/History.swift`). Debug logger at `DockKit/Utilities/DebugLogger.swift`. Logs are local only.

---

*Integration audit: 2026-10-20*
