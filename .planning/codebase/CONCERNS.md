# Codebase Concerns

**Analysis Date:** 2026-10-20

**Scope:** Static review of all Swift/ObjC sources in `Sirena/`, `DockKit/`, `ClipboardKit/`, `SirenaFinder/`, `Config/`, `scripts/`, and `Sirena.xcodeproj/project.pbxproj`. `References/` and `build/` were excluded. Nothing was built or run, so every item is a code-level finding. Items marked "verify" need a runtime check (Instruments, Console logs, or a reproduction) before they are treated as bugs.

## Short answer for the owner

The app is not provably "100%, smooth and bug-free" from the code alone, and nothing in the repository can prove it. The codebase has no test target at all (no XCTest or Swift Testing bundle exists in `Sirena.xcodeproj/project.pbxproj`), and it is about 650 Swift files. Most of the risk sits in four places:

1. Work done synchronously on the event-tap thread and the main thread (Cmd-Tab AX walk every 100 ms, gesture executor sleeps inside a default event tap).
2. Continuous polling that spawns processes or walks the Accessibility tree (media fallback spawns `osascript` every 0.5 to 1 s).
3. Heavy reliance on private and weak-linked SwiftUI/SkyLight/CoreDock symbols that can break on any OS update (the machine here already runs Darwin 27).
4. Several `fatalError`, force casts and unchecked assumptions that are safe on the happy path but turn into crash loops in unusual states (corrupt clipboard database, missing mouse event, nil app delegate).

Crash risk on the normal path is low. Battery, responsiveness and OS-update breakage are the most likely real-world complaints.

## Priority Ranking

| # | Severity | Area | Summary | Primary location |
|---|----------|------|---------|------------------|
| 1 | High | Main thread / CPU | Cmd-Tab AX tree walk runs every 100 ms, unbounded, until found | `DockKit/Utilities/DockObserver+CmdTab.swift:32`, `:281-300` |
| 2 | High | Event tap stall | Gesture executor sleeps and does AX calls inside a default (non-listen-only) event tap | `DockKit/Utilities/Window Gestures/WindowGestureExecutor.swift:121-135`, `WindowGestureController.swift:578` |
| 3 | High | Battery | Media fallback spawns `osascript` every 0.5 to 1 s; lyrics timer at 20 Hz | `DockKit/Models/MediaInfo.swift:565-572`, `:640-667`, `:13-44` |
| 4 | High | OS updates | Private/weak-linked SwiftUI symbols, SkyLight/CGS/CoreDock functions, and `-U` linker flags | `DockKit/Utilities/LiquidGlass.swift`, `DockKit/Utilities/PrivateApis.swift`, `Sirena.xcodeproj/project.pbxproj` (OTHER_LDFLAGS) |
| 5 | High | Crash loop | `fatalError` when the clipboard store fails to open; no recovery path | `ClipboardKit/Storage.swift:27-33` |
| 6 | High | Quality process | No automated tests of any kind | `Sirena.xcodeproj` (no test target) |
| 7 | High | Distribution | Release script disables Hardened Runtime and signs ad hoc; no notarization | `scripts/package-release.sh:14-22`, `Sirena.xcodeproj/project.pbxproj` (`ENABLE_HARDENED_RUNTIME`, `CODE_SIGN_IDENTITY = "Sirena Local Dev"`) |
| 8 | Medium | AX CPU | Brute-force window discovery issues up to 1000 AX IPC calls per PID | `DockKit/Extensions/AXUIElement.swift:117-200` |
| 9 | Medium | Battery | NotchService installs global `mouseMoved` monitors while hidden; 3,993-line file | `Sirena/Modules/Island/Services/NotchService.swift:1995-2000`, `:2020-2025` |
| 10 | Medium | CPU | Pin tracking at 20 Hz on the main thread in hover mode | `Sirena/Modules/PinWindow/PinWindowController.swift:247-251`, `:261-282` |
| 11 | Medium | Crash | `CGError(rawValue: -1)!` force unwrap in SkyLight fallback path | `DockKit/Utilities/PrivateApis.swift:161`, `:167` |
| 12 | Medium | Concurrency | Lazily loaded SkyLight globals written without synchronization | `DockKit/Utilities/PrivateApis.swift:130-157` |
| 13 | Medium | Crash | Force cast of `NSApp.delegate` in a shared accessor | `Sirena/App/AppDelegate.swift:11-13` |
| 14 | Medium | Lifetime | `AppDelegate` is held only by a local in `main.swift`, and `NSApplication.delegate` is weak | `Sirena/App/main.swift:5-8` |
| 15 | Medium | Crash | `fatalError` if `CGEvent(source: nil)` returns nil | `DockKit/Utilities/DockObserver.swift:717-720` |
| 16 | Medium | Crash | `OSAScriptRunner` writes to a pipe whose reader may already be gone; no timeout on `waitUntilExit` | `DockKit/Models/MediaInfo.swift:24-40`, `:43-60` |
| 17 | Medium | Security | DMG installer replaces `/Applications` apps without a code-signature check | `Sirena/Modules/Tweaks/DMGInstaller.swift:95-111`, `:118-160`, `:162-180` |
| 18 | Medium | Concurrency | Shared mutable statics without a lock; heavy use of `@unchecked Sendable` and `nonisolated(unsafe)` | `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift:6`, `Sirena/Modules/Switcher/SwitcherSupportShims.swift:116`, `Sirena/Modules/Island/IslandController.swift:18-22`, `Sirena/Modules/Shelf/ShelfStore.swift:34` |
| 19 | Medium | Responsiveness | `Thread.sleep` in code paths that may run on the main thread (verify) | `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Legacy/LegacyMenuBarHider.swift:179`, `Sirena/Modules/WindowManagement/WindowAnimation/WindowAnimationLookup.swift:37`, `DockKit/Utilities/Window Management/WindowInfo.swift:483` |
| 20 | Medium | Fragility | Menu bar moving by synthetic Cmd-drag and by writing Control Center preferences | `LegacyMenuBarHider.swift:165-182`, `Sirena/Modules/MenuBar/MenuBarModule.swift:556-570` |
| 21 | Medium | Privacy | Global key and mouse monitors installed by several features | `Sirena/Modules/ScreenBrush/ScreenBrushController.swift:95`, `:187`, `Sirena/Modules/PinWindow/ShakeDetector.swift:37`, `DockKit/Utilities/ActiveAppIndicator/ActiveAppIndicatorCoordinator.swift:217` |
| 22 | Medium | Maintainability | 24 files over 800 lines; largest is 3,993 lines | see Fragile Areas |
| 23 | Low | Polling | Clipboard poll, KeybindHelper 60 s timer, RunLoopThread idle wake-ups | `ClipboardKit/Clipboard.swift:55-60`, `DockKit/Utilities/KeybindHelper.swift:460`, `Sirena/Modules/WindowManagement/Utilities/RunLoopThread.swift:23-30` |
| 24 | Low | Crash risk (latent) | Force unwraps in `TimeoutCache` and `RunLoopThread` | `Sirena/Modules/WindowManagement/Utilities/TimeoutCache.swift:49-53`, `RunLoopThread.swift:24` |
| 25 | Low | Security | Shell command built by string interpolation for relaunch | `Sirena/App/Modules/ModuleManager.swift:136-141` |
| 26 | Low | Dependencies | Pinned revision of an old library, unused packages, private-framework wrapper | `Sirena.xcodeproj/project.pbxproj:938-943` and package list |
| 27 | Low | Debt | Dead code, duplicated type names across modules, `print` in production, DockDoor branding | see Tech Debt |

---

## Tech Debt

**No automated tests:**
- Issue: The project has no XCTest or Swift Testing target. `Sirena.xcodeproj/project.pbxproj` has zero references to a test bundle, and no file imports `XCTest` or `Testing`.
- Files: `Sirena.xcodeproj/project.pbxproj`
- Impact: Every regression in window management, the switcher, the notch and the mixer is found by hand. The owner's question ("100% without bugs") cannot be answered by the repo.
- Fix approach: Add a unit test target for the pure logic modules first. Good candidates are `Sirena/Modules/Island/Services/NotchSupport.swift`, `Sirena/Modules/Switcher/SwitcherSupport.swift`, `Sirena/Modules/WindowManagement/WindowCalculation/*.swift`, `DockKit/Models/MediaInfo.swift` (the lyrics distance code), and `Sirena/Modules/Island/Support/IslandPeripheralBatterySupport.swift` (already pure JSON parsing). Then add a smoke UI test for the menu bar launch.

**Oversized files:**
- Issue: 24 Swift files exceed 800 lines. The user's coding-style rule caps files at 800 lines.
- Files (line counts): `Sirena/Modules/Island/Services/NotchService.swift` (3,993), `Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift` (2,867), `Sirena/Modules/Island/Services/NotchSupport.swift` (2,681), `Sirena/Modules/Switcher/SwitcherAppSwitcher.swift` (2,054), `Sirena/Modules/Switcher/SwitcherSupport.swift` (2,039), `Sirena/Modules/Island/Services/NotchWindowHost.swift` (1,785), `Sirena/Modules/WindowManagement/WindowManager+CooperativeCornerResize.swift` (1,545), `Sirena/Modules/WindowManagement/CooperativeCornerResize.swift` (1,451), `DockKit/Utilities/DockObserver.swift` (1,443), `Sirena/Modules/Mixer/SirenaMixerView.swift` (1,442), `DockKit/consts.swift` (1,426), `DockKit/Utilities/KeybindHelper.swift` (1,348), `Sirena/Modules/Island/Services/NotchMascotSupport.swift` (1,347), `Sirena/Modules/Island/UI/NotchMascotView.swift` (1,332), `Sirena/Modules/WindowManagement/WindowAction.swift` (1,266), `Sirena/Modules/Switcher/SwitcherWindowActivator.swift` (1,229), `Sirena/Modules/Switcher/SwitcherView.swift` (1,219), `Sirena/Modules/Switcher/SwitcherWindowEnumerator.swift` (1,156), `Sirena/Modules/Mixer/SirenaMixerRoutingSupport.swift` (1,016), `DockKit/Models/MediaInfo.swift` (965), `Sirena/Modules/WindowManagement/WindowAnimation/DirectWindowAnimator.swift` (932), `Sirena/App/BoltMenu.swift` (896), `Sirena/Modules/Island/UI/NotchComponents.swift` (886), plus `Sirena/Modules/Island/Services/NotchService.swift` already listed.
- Impact: Hard to review, high merge-conflict risk, and the `NotchService` monitor lifecycle (about ten monitor install sites, each with a matching removal helper) is easy to break.
- Fix approach: Split by responsibility. For `NotchService.swift`, separate hover tracking, pointer following, screen-edge clicks, power state and presentation into their own types. The `*Support.swift` files already show the intended pattern (pure logic split from the service).

**Dead code:**
- `Sirena/Modules/Island/Support/IslandNowPlaying.swift:260-285` (`IslandAppleScriptRunner.run` and `runDetailed`) has no call sites. Only `consentToAutomate` (lines 246-254) is used, from `Sirena/Modules/Island/Services/NotchMusicService.swift:625` and `Sirena/Modules/Island/Services/NotchShuffleService.swift:106`. Delete the unused runner or confirm it is needed.
- `HotKey` and `SwiftHEXColors` are declared in `Sirena.xcodeproj/project.pbxproj` but have zero `import` statements in any target. Remove them.

**Duplicate type names across modules:**
- `WindowUtil`, `WindowInfo`, `WindowAction`, and `CompatGlass` are each declared in both `DockKit/` and `Sirena/`. Examples: `DockKit/Utilities/Window Management/WindowUtil.swift` and `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift`; `DockKit/Utilities/Window Management/WindowInfo.swift` and a second `WindowInfo` declaration in `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift` (verify); `Sirena/Modules/WindowManagement/WindowAction.swift` and the DockKit copy.
- Impact: Name shadowing depends on import order and makes code search and debugging confusing.
- Fix approach: Prefix or move the shared code into one module, and let `Sirena` import it.

**Mixed Swift language modes:**
- Issue: Some targets use `SWIFT_VERSION = 5.0` and others `6.0`, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on some (see `Sirena.xcodeproj/project.pbxproj` lines near 514, 576-578, 607-609, 721, 833, 858).
- Impact: Swift 5 mode does not enforce strict concurrency, so the actor and thread mistakes in the next section compile silently.
- Fix approach: Move every target to Swift 6 (or at least `-strict-concurrency=complete`) and fix the warnings. This is the single change that would surface most of the threading risks below.

**Debug and branding leftovers:**
- `DockKit/Utilities/DebugLogger.swift` writes `DockDoor-Debug.log` to `$TMPDIR` when `debugMode` is on, and the name refers to the upstream app.
- `DockKit/Utilities/EventTapThread.swift:5`, `DockKit/Utilities/Window Gestures/WindowGestureController.swift:48` use `com.ethanbills.DockDoor.*` as thread names.
- About 20 bare `print(` calls remain in production code, for example `DockKit/Utilities/PrivateApis.swift:140` and the retry failure in `DockKit/Utilities/Window Management/WindowInfo.swift` near line 490.
- Fix approach: Route all output through `os.Logger` or `DebugLogger`, and rename the thread labels to `com.matheusfaria.Sirena.*`.

---

## Known Bugs

These are reproducible by reading the code. Symptoms are inferred and should be confirmed.

**Clipboard database failure crashes the app on every launch:**
- Symptoms: If `Clipboard.sqlite` in `~/Library/Application Support/Sirena/` is corrupt, unreadable or from an incompatible schema, the app traps at startup.
- Files: `ClipboardKit/Storage.swift:27-33`
- Trigger: A failed SwiftData migration, a disk-full write, or a manual edit of the file.
- Workaround: Delete `~/Library/Application Support/Sirena/Clipboard.sqlite*`.
- Fix approach: Replace `fatalError` with a fallback. Move the bad store aside (`Clipboard.sqlite.corrupt-<date>`), create a fresh store, and show a non-blocking notice. Keep the in-memory container as a last resort.

**Cmd-Tab enhancements keep polling when the Dock switcher list is absent:**
- Symptoms: CPU stays above idle and the main thread is busy while Cmd-Tab enhancements are enabled, even when no switcher is shown.
- Files: `DockKit/Utilities/DockObserver+CmdTab.swift:32-40` (timer every 0.1 s), `:52-66` (`attemptCmdTabSubscription`), `:281-300` (`findCmdTabSwitcherElement`).
- Trigger (inferred from code, verify): Cmd-Tab enhancements are on and the Dock does not expose `AXProcessSwitcherList` as a child in the walked tree. The polling only stops once the subscription succeeds.
- Workaround: Disable "Cmd-Tab enhancements" in settings.
- Fix approach: Cap the retries (for example, 30 attempts, then back off to 5 s), and cache the element. Replace the recursive walk with a bounded breadth-first search with a depth limit and a visited set.

---

## Security Considerations

**DMG installer trusts any mounted app:**
- Risk: When the user confirms, `DMGInstaller` replaces an existing app in `/Applications` with whatever `.app` is on the mounted disk image. It does not check the code signature, the Team ID, or Gatekeeper assessment. A malicious or spoofed DMG can replace a trusted app after one click.
- Files: `Sirena/Modules/Tweaks/DMGInstaller.swift:95-111` (offer and prompt), `:118-160` (install: quit old copy, `ditto`, trash old, move), `:162-180` (`runDitto`).
- Current mitigation: Only one `.app` at the root of the volume, no `.pkg`, a user prompt with the app icon and name.
- Recommendations: Run `codesign --verify --deep --strict` and `spctl --assess` on the new bundle before the `ditto` step, and refuse ad-hoc or unknown-Team-ID apps when an existing app with a different Team ID is being replaced. Show the Team ID in the prompt.

**Release build weakens platform protections:**
- Risk: `scripts/package-release.sh:14-22` builds with `ENABLE_HARDENED_RUNTIME=NO` and `CODE_SIGN_IDENTITY=-`, so the distributed `.zip` and `.dmg` are ad-hoc signed. Gatekeeper will flag them on other Macs, and the app runs without library validation, runtime protections, or notarization.
- Files: `scripts/package-release.sh:14-22`, `Sirena.xcodeproj/project.pbxproj` (`ENABLE_HARDENED_RUNTIME = YES` and `CODE_SIGN_IDENTITY = "Sirena Local Dev"` in the Debug and Release blocks).
- Current mitigation: The script states the trade-off in its header comment.
- Recommendations: Obtain a Developer ID certificate, keep Hardened Runtime on, notarize with `notarytool`, and staple the ticket. Until then, document the Gatekeeper workaround for users.

**Entitlements and TCC surface:**
- Risk: `Config/Sirena.entitlements` enables `apple-events`, `audio-input`, `camera`, and `calendars`. The app also needs Accessibility, Screen Recording, and Input Monitoring (global key monitors). These are granted per-user, but they make a compromised process very powerful.
- Files: `Config/Sirena.entitlements`, `Config/Info.plist` (`NSAppleEventsUsageDescription` at line 40).
- Current mitigation: Each permission is tied to a feature toggle, and permissions are checked in `DockKit/Components/PermissionsView/PermissionsChecker.swift`.
- Recommendations: Confirm each entitlement is still needed. Keep a short list of which feature needs which permission in `README.md`.

**Global input monitors:**
- Risk: Several features observe every key press or mouse click system-wide. Handlers filter to a few keys, but the monitors see all input.
- Files: `Sirena/Modules/ScreenBrush/ScreenBrushController.swift:95` and `:187` (`addGlobalMonitorForEvents(matching: .keyDown)`), `Sirena/Modules/PinWindow/ShakeDetector.swift:37` (global `leftMouseDown`/`Dragged`/`Up`), `DockKit/Utilities/ActiveAppIndicator/ActiveAppIndicatorCoordinator.swift:217` (global `mouseMoved`), `Sirena/Modules/Mirror/MirrorController.swift:251`, `:274`.
- Current mitigation: Handlers return early when a feature is off, and the screen-brush key monitor is removed when the brush closes (`Sirena/Modules/ScreenBrush/ScreenBrushController.swift:112-113`).
- Recommendations: Install global monitors only while the feature is visible. Document the Input Monitoring prompt in the settings UI.

**Synthetic input and CPU-level keep-awake tricks:**
- Risk: `Sirena/Modules/KeepAwake/ActivitySimulator.swift:38-110` posts synthetic mouse events to keep the system awake, and `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Legacy/LegacyMenuBarHider.swift:165-182` posts Cmd-drag mouse events at `.cghidEventTap`. Both can move the cursor or interact with the user's apps unexpectedly.
- Files: as listed.
- Recommendations: Keep these behind explicit opt-in toggles and state the behavior in the UI.

**Shell command built from a string:**
- Risk: `Sirena/App/Modules/ModuleManager.swift:136-141` runs `/bin/sh -c "sleep 1; /usr/bin/open \"<path>\""`. A bundle path containing `"`, `$`, or a backtick would break or inject into the command. The risk is low because the path comes from `Bundle.main`.
- Recommendations: Pass the path as an argument (`/usr/bin/open` with a separate argument array and a `sleep` done in Swift), so no shell is involved.

**Osascript pipe and automation consent:**
- Risk: `DockKit/Models/MediaInfo.swift:24-40` writes the script to `osascript`'s stdin and then calls `closeFile()`. If `osascript` exits early, the write raises an Objective-C exception and terminates the app. The `IslandAppleScriptRunner.consentToAutomate` path (`Sirena/Modules/Island/Support/IslandNowPlaying.swift:246-254`) correctly runs off the main thread, but the `OSAScriptRunner` path has no timeout at all.
- Recommendations: Use `FileHandle.write(contentsOf:)` inside a `do`/`catch`, or pass the script with `-e` arguments, and bound `waitUntilExit` with a deadline.

**No hardcoded secrets found:** Searches for API keys, passwords, bearer tokens and secret literals turned up nothing in source. No `.env` file is present in the repository.

---

## Performance Bottlenecks

**Cmd-Tab AX tree walk every 100 ms:**
- Problem: Described under Known Bugs. Each tick does a recursive walk of the Dock's entire accessibility tree on the main thread.
- Files: `DockKit/Utilities/DockObserver+CmdTab.swift:32`, `:281-300`.
- Cause: No depth limit, no visited set, no backoff, no cache.
- Improvement path: Subscribe to the Dock's `AXWindowCreated`/focus notifications instead of polling. Until then, bound the walk and back off.

**Media fallback spawns a process every 0.5 to 1 s:**
- Problem: `fetchMediaData` runs `/usr/bin/osascript` each tick whenever a media view is active and MediaRemote is not in use. Each spawn costs tens of milliseconds of CPU and a process launch, and it keeps the Music or Spotify app busy.
- Files: `DockKit/Models/MediaInfo.swift:640-652` (timer and fetch), `:13-44` (`OSAScriptRunner.run`), `:565-572` (lyrics timer at 0.05 s, 20 Hz, hopping to main each tick).
- Cause: Polling instead of notifications. The MediaRemote path (`switchToMediaRemote`, lines 212-232) is the preferred source but is not always available.
- Improvement path: Subscribe to the Music and Spotify distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) for state changes, and poll only for position. Drop the lyrics timer to 0.2 s or derive position from a clock.

**Window discovery brute force:**
- Problem: `windowsByBruteForce` iterates 0 to 999 element IDs and performs an AX `role()` IPC call for each (`DockKit/Extensions/AXUIElement.swift:117-160`). It is triggered when `hasUnreachedWindow` finds an on-screen or other-Space window that AX did not return (lines 181-196).
- Files: `DockKit/Extensions/AXUIElement.swift:117-200`.
- Cause: Private token brute force, used because some windows on other Spaces are invisible to the AX window list. The loop breaks after two timeouts, but a responsive app can take the full 1000 iterations.
- Improvement path: Cache the discovered token range per PID and invalidate it on window-count change. Lower the upper bound after the first successful run.

**Pinned windows are tracked at 20 Hz on the main thread:**
- Problem: In hover mode, `PinWindowController.track()` runs 20 times per second, computes hover state for all pins, and polls each pin every 0.5 s.
- Files: `Sirena/Modules/PinWindow/PinWindowController.swift:247-251` (timer, tolerance 0.01), `:261-282` (`track`).
- Improvement path: Track the pointer with a global `mouseMoved` monitor and only update when the pointer enters or leaves a pin frame.

**Hidden-notch global mouse monitoring:**
- Problem: While the notch is hidden, `NotchService` installs a global and a local `mouseMoved` monitor (`Sirena/Modules/Island/Services/NotchService.swift:1995-2000`), and it calls `hover(true)` for every mouse move on the system.
- Files: `Sirena/Modules/Island/Services/NotchService.swift:1995-2030`, plus pointer-follow monitors at `:2020-2025` and screen-edge monitors at `:2422-2427`, `:2869-2876`.
- Cause: Deliberate design to detect entry into a hidden notch. The per-event work is small, but it runs continuously.
- Improvement path: Restrict the monitor to the hidden notch's rect plus a margin, or use a tracking area on a transparent window at the notch's edge.

**Screen Brush laser timer at 60 Hz:**
- Files: `Sirena/Modules/ScreenBrush/ScreenBrushController.swift:158-161` (`Timer(timeInterval: 1.0/60, repeats: true)`).
- Improvement path: Run the timer only while the laser stroke is active, which the code appears to do (`ScreenBrushCanvas.swift:190`, `:199`). Verify it stops on stroke end.

**Window-list queries:**
- Files: `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift:18-60` (`CGWindowListCopyWindowInfo`, cached for 100 ms by `TimeoutCache`). `StackBadgeManager`, `MultiWindowManager`, `StackCycleManager`, and `StageUtil` all call `getWindowList`.
- Cause: Several callers can hit the cache in the same frame, but a cache miss does a full `CGWindowListCopyWindowInfo` each time.
- Improvement path: Coalesce calls within one run-loop turn.

**Clipboard polling:**
- Files: `ClipboardKit/Clipboard.swift:53-60`. The interval comes from `Defaults[.clipboardCheckInterval]`. `checkForChangesInPasteboard` compares `changeCount` first, so idle cost is small. This is acceptable.

---

## Threading and Actor Risks

These are the items the owner specifically asked about. Current state: no confirmed crash, but these are the spots that will crash if a callback ever arrives on a different thread.

**`MainActor.assumeIsolated` usage (51 call sites):**
- Most sites are inside `DispatchQueue.main.async` or an observer registered with `queue: .main`. Examples: `Sirena/Modules/PinWindow/PinWindowController.swift:46-72`, `DockKit/Utilities/Window Gestures/WindowGestureController.swift:310`, `:384`, `:442`, `:459`. These are safe.
- Risky pattern to watch: `assumeIsolated` inside a callback whose delivery thread is not main. `NSEvent` global monitors and `Timer` closures on the main run loop are main; `CGEventTap` callbacks and `AXObserver` callbacks depend on the run loop they were added to. The AX observers at `Sirena/Modules/WindowManagement/TitleBarManager.swift:213`, `DockKit/Utilities/Window Management/WindowManipulationObservers.swift:249`, and `Sirena/Modules/PinWindow/PinnedWindow.swift:339` add their sources to `CFRunLoopGetMain()`, so they are safe. The gesture and DockLocker taps add sources to their own threads, so any `assumeIsolated` placed directly in those callbacks would trap. Current code wraps them, but a future edit could break this.
- Fix approach: Prefer `Task { @MainActor in … }` in callbacks that may come from any thread. Reserve `assumeIsolated` for code that is provably on main.

**`MainActor.assumeIsolated` in `main.swift`:**
- `Sirena/App/main.swift:5-8` wraps the whole startup in `assumeIsolated`. This is correct for the top-level code, but if the app delegate is later created off-main, it traps.

**Event-tap thread does synchronous work:**
- `DockKit/Utilities/Window Gestures/WindowGestureExecutor.swift:121-135` (`select(_:in:)`) calls `Thread.sleep(forTimeInterval: 0.03)` up to 15 times (about 450 ms) and performs AX calls with a 0.15 s messaging timeout (`WindowGestureZone.swift:46`). It runs from `WindowGestureController.execute` (`:575-580`), which is called from the tap callback on `EventTapThread` (`:48`, `:72`, `:78`).
- Impact: While the tap is blocked, every scroll and key event passing through `.cghidEventTap` with `.defaultTap` waits. macOS disables the tap after a timeout; the code re-enables it (`WindowGestureController.swift:148-152`), but the user sees input lag.
- Fix approach: Return from the tap immediately and run `execute` on a serial background queue, sending only the results back to the tap state.

**Blocking sleeps:**
- `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Legacy/LegacyMenuBarHider.swift:179` sleeps `dragStepDelay` between synthetic drag events. Verify which thread calls `commandDrag`.
- `Sirena/Modules/WindowManagement/WindowAnimation/WindowAnimationLookup.swift:37` sleeps up to 20 ms per iteration inside a deadline loop capped at 250 ms. Verify its caller thread.
- `DockKit/Utilities/Window Management/WindowInfo.swift:483` calls `usleep(50000)` up to `maxRetries` times while bringing a window to front. Verify its caller thread.
- `DockKit/Utilities/DockLocker.swift:374-380` runs `usleep` on a global queue (safe).

**Run-loop thread busy wait:**
- `Sirena/Modules/WindowManagement/Utilities/RunLoopThread.swift:23-30` loops `runLoop.run(mode:before:.distantFuture)` and sleeps 100 ms whenever `run` returns false, which happens when no sources are attached. This wakes the CPU 10 times per second while idle. Add a keep-alive source or block on a semaphore instead.

**Unsafe `as!` casts on Accessibility values (39 sites):**
- Most are `value as! AXUIElement` or `as! AXValue` after a `CFGetTypeID` check or an `AXUIElementCopyAttributeValue == .success` check. Examples: `Sirena/Modules/WindowManagement/AccessibilityElement.swift:32`, `:468`, `:481`; `Sirena/Modules/PinWindow/PinnableWindow.swift:131`, `:143-144`, `:155`, `:169`; `Sirena/Modules/Switcher/SwitcherWindowEnumerator.swift:941-942`, `:1064`, `:1093`; `DockKit/Utilities/Window Gestures/WindowGestureZone.swift:306`, `:324`; `Sirena/Modules/WindowManagement/TitleBarManager.swift:280-290`.
- Risk: A foreign process can return a non-AX value for an attribute the API says is an AX element. A failed cast in Swift traps.
- Fix approach: Use `CFGetTypeID` checks before every `as!` on CoreFoundation types, or use the existing helpers in `DockKit/Extensions/AXUIElement.swift`.

**Force unwraps and casts in helper types:**
- `Sirena/Modules/WindowManagement/Utilities/TimeoutCache.swift:49-53` uses `entry!` in a loop. Safe under the current invariant, but the invariant depends on `remove` not clearing `next`.
- `Sirena/Modules/WindowManagement/Utilities/RunLoopThread.swift:24` uses `runLoop!`. Safe because it is set before `startSemaphore.signal()`.
- `DockKit/Models/MediaInfo.swift:498` uses `try! NSRegularExpression(...)` on a constant pattern. Safe.
- `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift:35-45` uses unconditional `as CFNumber` and `as CFDictionary` on values from `CGWindowListCopyWindowInfo`. These keys are always present in practice. Verify on macOS 27.

**Force unwrap and fatal path in private API code:**
- `DockKit/Utilities/PrivateApis.swift:161` and `:167` return `CGError(rawValue: -1)!`. The C-imported `CGError` initializer is failable for raw values outside the SDK's cases (verify against the SDK), so if it returns nil for `-1` this traps the first time SkyLight is unavailable. Replace with a named error case (for example, `.failure`).

**Shared mutable statics without a lock:**
- `Sirena/Modules/WindowManagement/Utilities/WindowUtil.swift:6` (`private static var windowListCache`) is a non-thread-safe `TimeoutCache`. Callers include `StackBadgeManager`, `MultiWindowManager`, `StackCycleManager`, and `StageUtil`. If any caller runs off main, the dictionary and linked list race.
- `Sirena/Modules/Switcher/SwitcherSupportShims.swift:116` (`nonisolated(unsafe) private static var switcherRunning`).
- `Sirena/Modules/Island/IslandController.swift:18`, `:22` (`nonisolated(unsafe) static var isActive`, `openSettingsHandler`).
- `Sirena/Modules/Shelf/ShelfStore.swift:34` (`nonisolated(unsafe) private static var resolved: [Data: URL]`). Access from the detached tasks in the shelf should be checked.
- `ClipboardKit/Extensions/Defaults.Keys+Names.swift:16` (`nonisolated(unsafe)` on a `UserDefaults` suite; benign).
- `@unchecked Sendable` on 11 types (for example `DockKit/Utilities/Window Management/ScreenReservations.swift:86`, `DockKit/Utilities/Window Gestures/WindowSnapRegistry.swift:4`, `Sirena/Modules/Tweaks/TweaksController.swift:134`, `Sirena/Modules/Switcher/SwitcherWindowServerCaptureQueue.swift:9`, `Sirena/Modules/Island/Services/NotchMusicCommandWriter.swift:9`). Each one turns off compiler checking for its contents.

**Private SkyLight globals written lazily:**
- `DockKit/Utilities/PrivateApis.swift:130-157`: `skyLightHandle`, `setFrontProcessPtr`, `postEventRecordPtr`, `windowIsOrderedInPtr` are module-level `var`s written in `loadSkyLightFunctions()` with no lock. Three public wrappers call it (lines 160, 166, 172), and `SLSMoveWindowsToManagedSpace` calls it at line 180. If two threads hit the first call together, the pointers race.
- Fix approach: Use `static let` initialized through `dispatch_once` semantics (a `lazy` global in Swift), which is thread-safe.

**Dead or nil-prone AppDelegate access:**
- `Sirena/App/AppDelegate.swift:11-13`: `static var instance: AppDelegate { NSApp.delegate as! AppDelegate }` traps if the delegate is nil or a different type.
- `Sirena/App/main.swift:5-8`: the `delegate` local is the only strong reference, and `NSApplication.delegate` is a weak property. After `app.delegate = delegate`, the optimizer may release the local before `NSApplicationMain` runs. The app currently launches, which implies another strong reference exists, but the code does not guarantee it. Fix: `withExtendedLifetime(delegate) { _ = NSApplicationMain(...) }`, or keep the delegate in a global `let`.

**Fatal errors:**
- `DockKit/Utilities/DockObserver.swift:717-720` (`getMousePosition`) calls `fatalError("Unable to get mouse event")` when `CGEvent(source: nil)` returns nil. This function runs on hover paths, so a nil return would crash the Dock feature. Return `.zero` or the last known point instead.
- `ClipboardKit/Storage.swift:31` (see Known Bugs).
- `Sirena/Modules/WindowManagement/Logging/LogViewer.swift:50` (`fatalError` if the storyboard lacks the window controller). Only triggers if the storyboard is broken at build time.
- `init(coder:)` `fatalError`s across about 14 views (for example `Sirena/Modules/PinWindow/PinPanels.swift:47`, `Sirena/Modules/Shelf/ShelfPanel.swift:57`, `DockKit/Components/FluidGradient/FluidGradientView.swift:81`). These are the standard pattern for code-only views and are not a risk in practice.

---

## Private API and OS-Update Fragility

**Weak-linked SwiftUI internal symbols (`Glass`):**
- Risk: `DockKit/Utilities/LiquidGlass.swift:9-32` declares `@_silgen_name` bindings to mangled, internal SwiftUI symbols (`$s7SwiftUI6_GlassV…`). The file marks them `@_weakLinked`, and at runtime `resolvable(_:)` (line 67-69) checks each with `dlsym`. `opacityOrdered` (lines 47-65) lists 17 variants. The struct layout (`PrivateGlassStorage`, lines 3-7) is guessed to be large enough (`MemoryLayout` checks at lines 71-79). If SwiftUI changes the layout of `Glass`, the getters write past the buffer.
- Build-time coupling: `Sirena.xcodeproj/project.pbxproj` `OTHER_LDFLAGS` (near lines 633-640 and 745-752) passes `-Xlinker -U -Xlinker _$$s7SwiftUI5GlassV8explicitAcA01_C0V_tcfC` (and more) so the link succeeds with undefined symbols.
- Current mitigation: `availableFlavors` (line 86-89) only exposes flavors whose symbols resolve, and `usesModernPipeline` (lines 81-84) gates by macOS 27.
- Impact: A macOS 27 update that renames or removes a symbol will either fall back quietly or, if a getter is called without checking `availableFlavors`, crash. The memory-layout guess is the riskiest part.
- Fix approach: Confirm every call to a `glassXxx()` getter is behind `availableFlavors.contains`. Add a launch-time self-check that logs the outcome. Prefer public `glassEffect` APIs once they cover these variants.

**SkyLight, CGS, CoreDock and AX private calls:**
- `DockKit/Utilities/PrivateApis.swift:17-103` declares `_AXUIElementGetWindow`, `CoreDockGetOrientationAndPinning`, `CoreDockSetAutoHideEnabled`, `CoreDockGetAutoHideEnabled`, `CoreDockIsMagnificationEnabled`, `CGSMainConnectionID`, `CGSHWCaptureWindowList`, `CGSCopySpacesForWindows`, `CGSCopyManagedDisplaySpaces`, `CGSGetWindowLevel`, `CGSCopyWindowProperty`, `_AXUIElementCreateWithRemoteToken`, and `GetProcessForPID`. These are linked at build time, so a removed symbol fails at launch (dyld), not just at call time. `Sirena/Modules/Switcher/SwitcherAXWindowResolver.swift` also binds `_AXUIElementGetWindow` again.
- `_AXUIElementCreateWithRemoteToken` is the basis for the brute-force window search (`DockKit/Extensions/AXUIElement.swift:129`). Apple has used this token layout for years, but it is undocumented.
- `DockKit/Utilities/PrivateApis.swift:179-215` (`SLSMoveWindowsToManagedSpace`) creates an instance of `SLSBridgedMoveWindowsToManagedSpaceOperation` by name, calls `alloc` and `initWithWindows:spaceID:` through `unsafeBitCast` of `method(for:)` IMPs, and then `performWithWMBridgeDelegate`. This is the most brittle call in the repository: the Objective-C signature is guessed, and a change in the class or selector will either return false or call the wrong IMP.
- Fix approach: Gate every private call on a launch-time OS-version range, log when a call is skipped, and show a settings-level warning instead of silently failing. Keep a list of which macOS builds were tested.

**Private Dock and menu bar preferences:**
- `Sirena/Modules/MenuBar/MenuBarModule.swift:556-570` runs `/usr/bin/defaults write … TrailingItemPreferredPositions -dict-add` to move menu bar items. The domain and key names are private and have changed between macOS releases.
- `Sirena/Modules/MenuBar/Features/StatusBar/Engine/Legacy/LegacyMenuBarHider.swift` is named "Legacy", which suggests a newer engine exists; both paths need testing on macOS 26 and 27.

**Media control through MediaRemote:**
- `DockKit/Utilities/Media/MediaRemoteService.swift` uses the `MediaRemoteAdapter` package (`Sirena.xcodeproj/project.pbxproj`, package reference `5E1A0000000000000000031B`). Apple restricted direct MediaRemote access to entitled processes in macOS 15.4; the adapter works around it. Expect breakage on OS updates.

**Accessibility and system behavior assumptions:**
- `DockKit/Extensions/AXUIElement.swift:11-33` (`AXResponsiveness`) is a good mitigation: it records unresponsive PIDs and skips them. Use it everywhere AX is called on a background path.
- Messaging timeouts are set in about 11 places (for example `DockKit/DockController.swift:44` sets 1.0 s on the system-wide element, which does not apply to per-app elements; `Sirena/Modules/MenuBar/MenuBarModule.swift:488` sets 0.3 s). Many other per-element calls use the 6 s system default. `Sirena/Modules/WindowManagement/WindowAnimation/WindowAnimationElement.swift:7` defaults `messagingTimeout` to 0 (system default). Animation loops that call these can freeze for seconds on an unresponsive app.

---

## Fragile Areas

**`Sirena/Modules/Island/Services/NotchService.swift` (3,993 lines):**
- Files: `Sirena/Modules/Island/Services/NotchService.swift`, `Sirena/Modules/Island/Services/NotchSupport.swift`, `Sirena/Modules/Island/Services/NotchWindowHost.swift`.
- Why fragile: It owns about a dozen global, local and power monitors, timers and presentation states. Every monitor install is guarded by `isEmpty`, and removal is done through `hoverExitMonitors`, `hiddenHoverMonitors`, `pointerMonitors`, `screenEdgeClickMonitors`, `eventMonitors`, and others. A missed removal leaves a monitor firing after the notch is closed. The closures use `[weak self]`, so there is no retain cycle, but the monitor arrays are the only guard.
- Safe modification: Add a single `teardownAllMonitors()` that every stop path calls, and a debug-only assertion that all arrays are empty after `stop()`.
- Test coverage: None.

**`DockKit/Utilities/DockObserver.swift` (1,443 lines) with `DockObserver+CmdTab.swift`:**
- Why fragile: Mixes the Dock AX observer, the Cmd-Tab timer, a canary `NSEvent` local monitor (`:132`), a 5 s health check (`:156-158`), and the event tap. The tap is removed through `EventTapThread.shared.remove` (`:780`) and its callback (`:854`) routes through `reEnableIfNeeded`. Verify that re-enabling works with a stalled Dock.
- Safe modification: Keep the re-enable path in the callback and cover it with a manual test.

**`Sirena/Modules/Mixer/SirenaAppVolumeMixer.swift` (2,867 lines) and `SirenaMixerRoutingSupport.swift`:**
- Why fragile: CoreAudio process taps and aggregate devices. A device or output change mid-build leaves partially constructed engines (the code uses `DispatchSemaphore` `firstRead` with a 50 ms wait, at `:2331-2337`). Crashes or silent audio loss are likely on device hot-plug.
- Safe modification: Test with a Bluetooth headset connect and disconnect while an app plays.

**`DockKit/Utilities/Window Gestures/`:**
- Why fragile: Mixed threads (tap thread, main, `DispatchQueue.main.async` hops to a `@MainActor` HUD), the blocking `select` loop described in Threading, and `session` state shared across threads.
- Safe modification: Keep all state changes on the tap thread; only post immutable snapshots to main.

**Switcher (`Sirena/Modules/Switcher/`, about 10 files over 500 lines):**
- Why fragile: Global shortcut tap (`SwitcherGlobalShortcut.swift`, 682 lines) running on its own thread with `autoreleasepool`, a `lifecycleLock` and manual run-loop management (`SwitcherAppSwitcher.swift:386-400`, `:432`), and several AX observers. The `clearEventTapThread()`/`installTap()` pair at `SwitcherAppSwitcher.swift:397` restarts a tap from inside its own callback path.
- Safe modification: Change one piece at a time and test the Cmd-Tab replacement with the system switcher disabled and enabled.

**Window management (`Sirena/Modules/WindowManagement/`):**
- Why fragile: Cooperative corner resize (`WindowManager+CooperativeCornerResize.swift` 1,545 lines, `CooperativeCornerResize.swift` 1,451 lines), animation with private AX (`DirectWindowAnimator.swift` 932 lines, `WindowAnimationElement.swift`), and 4 copies of observer setup for AX move/resize notifications (`TitleBarManager.swift:213`, `WindowAnimationRequest.swift:49`, `PinnedWindow.swift:339`, `SwitcherWindowUseTracker.swift:264`/`:328`). Each observer is added to a run loop; some to `.defaultMode`, others to `.commonModes`, so behavior differs while menus are open.
- Safe modification: Unify AX observer creation in one helper that always uses `.commonModes` and always removes the source on teardown.

**Shelf (`Sirena/Modules/Shelf/`):**
- Why fragile: `ShelfController.swift:61-65` installs global `leftMouseDown` and `leftMouseDragged` monitors that call `MainActor.assumeIsolated` into `mouseDown`/`mouseDragged`. These run on every click system-wide while the shelf is enabled. Verify the monitors are removed when the shelf is disabled.

**Tweaks (`Sirena/Modules/Tweaks/`):**
- Why fragile: A dedicated event-tap thread (`TweaksController.swift:169-190`), a 50-iteration 100 ms wait loop in `DMGInstaller.swift:141`, and an unverified app-replacement path. `TweaksSettings.swift:122-127` runs `pluginkit` fire-and-forget and ignores failures (`try? task.run()`).

**Menu bar hiding (`Sirena/Modules/MenuBar/`):**
- Why fragile: Moves other apps' status items with synthetic events and `defaults write`, depends on private menu bar layout, and has both a legacy and a current engine (`Features/StatusBar/Engine/Legacy/`). The AX inventory (`AccessibilityMenuBarInventory.swift`) uses a 0.1 s messaging timeout (`:17`).

**Large generated-looking strings and resource catalogs:**
- `Sirena/Resources/Localizable.xcstrings` and `Sirena/Resources/Sirena.xcstrings` are large string catalogs. Strings are referenced by `L("...")` and `SL("...")`. A typo in a key falls back to the key text silently. No check exists in the repo.

---

## Scaling Limits

**Clipboard history size:**
- Current capacity: Unbounded in code. `ClipboardKit/Storage.swift` stores each item and its contents in SwiftData with an orphan cleanup (`cleanupOrphanedContents`, line ~39). No maximum count was found in the first 60 lines of `Storage.swift`; verify the history limit setting exists in `ClipboardKit/Observables/History.swift`.
- Limit: Large images and rich text are stored in the same SQLite file, which grows with use.
- Scaling path: Store large payloads as files outside the database and keep only references.

**Window enumeration cost:**
- Current capacity: Each switcher open enumerates all windows of all apps (`SwitcherAppSwitcher.swift:907`), plus brute force when windows sit on other Spaces (`AXUIElement.swift:181-196`).
- Limit: With many apps and many Spaces, the enumeration can take well over 100 ms, which is visible as switcher lag.
- Scaling path: Cache per-PID window sets for the duration of one switcher session, and refresh only on `AXWindowCreated`/`AXUIElementDestroyed` notifications.

**Event taps:**
- Current capacity: At least 5 taps are created across the app: `DockKit/Utilities/KeybindHelper.swift`, `DockKit/Utilities/DockLocker.swift:427`, `DockKit/Utilities/DockObserver.swift:848`, `DockKit/Utilities/TrackpadSwipeTrigger.swift:154`, `DockKit/Utilities/Window Gestures/WindowGestureController.swift:110-124`, `Sirena/Modules/Switcher/SwitcherAppSwitcher.swift`, `Sirena/Modules/Tweaks/TweaksController.swift:212`, and `Sirena/Modules/WindowManagement/Utilities/EventMonitor.swift:124`.
- Limit: macOS applies a per-process and system-wide cost to each active tap. Several `.defaultTap` taps on `.cghidEventTap` all sit in the input path.
- Scaling path: Merge the keybinding and gesture taps into one tap with one dispatcher.

---

## Dependencies at Risk

**MASShortcut (pinned to a revision):**
- Risk: `Sirena.xcodeproj/project.pbxproj:938-943` pins `https://github.com/rxhanson/MASShortcut` to revision `2f9fbb3f959b7a683c6faaf9638d22afad37a235`. It is used in 28 files and is an older Objective-C library with Carbon-era hotkey code.
- Impact: Hotkey regressions on new macOS releases will be hard to patch, and the pin prevents upstream fixes.
- Migration plan: Move to `KeyboardShortcuts` (already a dependency, used in 5 files) and remove MASShortcut.

**Two shortcut libraries plus a third unused:**
- `KeyboardShortcuts`, `MASShortcut`, and `HotKey` are all declared. `HotKey` has no imports. Remove it, and plan the MASShortcut migration above.

**MediaRemoteAdapter:**
- Risk: It wraps the private MediaRemote framework. Apple's restrictions on MediaRemote changed in macOS 15.4, and the adapter depends on a workaround.
- Impact: Now-playing controls in the Dock and the notch stop working after an OS update until the adapter is updated.
- Migration plan: Keep the AppleScript fallback (see Performance) as the documented degraded mode and surface a notice when MediaRemote is unavailable.

**Unused and small packages:**
- `SwiftHEXColors` (no imports) and `Fuse` (1 import). Remove `SwiftHEXColors`; keep `Fuse` only if the search UI needs fuzzy matching.

**Unmaintained-looking packages:**
- `Sauce` (2.5.2, 8 files) is used for keyboard layout mapping, a concern on newer keyboard APIs. Verify it builds on macOS 27.

---

## Missing Critical Features

**Automated tests and CI:**
- Problem: No test target, no CI workflow. The only automation is `scripts/package-release.sh`, which does not run tests and does not notarize.
- Blocks: Confidently shipping fixes for the risks listed here.

**Crash and hang reporting:**
- Problem: No crash reporter or hang detection is present. `DebugLogger` only writes to a temp file when the user turns on debug mode.
- Blocks: Learning about field crashes and the Cmd-Tab or media CPU drain from real users.

**Permission onboarding for private features:**
- Problem: Several features silently degrade when a permission is missing (for example, Accessibility for the switcher, Input Monitoring for global keys, Automation for Music or Spotify). `DockKit/Components/PermissionsView/PermissionsChecker.swift` polls permissions on a timer (lines 13, 43).
- Blocks: Support requests that look like bugs.

**Recovery from corrupt or incompatible state:**
- Problem: Only the clipboard store can crash the app on bad data (see Known Bugs). Other persisted settings (`Defaults`, `Sirena/Modules/MenuBar/Common/Preferences.swift:15`, which decodes `Data` from `UserDefaults` with `as? Data`) fall back to defaults, which is good, but no migration or reset path is documented.

---

## Test Coverage Gaps

**Everything:**
- What's not tested: All modules. No test target exists.
- Files: All of `Sirena/`, `DockKit/`, `ClipboardKit/`, `SirenaFinder/`.
- Risk: Every regression ships unnoticed.
- Priority: High.

**Pure logic that is easiest to test first:**
- `Sirena/Modules/Island/Services/NotchSupport.swift` (2,681 lines of decision logic for the notch, e.g., `NotchSupport.closesOnPointerExit`).
- `Sirena/Modules/Switcher/SwitcherSupport.swift` (2,039 lines, `isCurrentSessionStart`, `usesActivationClick`).
- `Sirena/Modules/WindowManagement/WindowCalculation/*.swift` (window frame math, `RepeatedExecutionsCalculation.swift`, `HalvesPreserveOtherAxisSize.swift`).
- `Sirena/Modules/Island/Support/IslandPeripheralBatterySupport.swift` (JSON parsing from `system_profiler`, `bluetoothDevices(fromSystemProfilerJSON:)` at line 196).
- `DockKit/Models/MediaInfo.swift` (lyrics timing and Levenshtein distance near lines 540-565).
- `Sirena/Modules/Island/Support/IslandBoundedProcessRunner.swift` (timeout and cancel behavior).
- `Sirena/Modules/Island/Services/NotchNotificationReaderCore.swift` (361 lines of parsing).

**Threading and timing:**
- `Sirena/Modules/Island/Support/IslandPeripheralBatterySampler.swift` already injects `currentTime`, which makes it testable. Add tests for the 15 s fast cache and 300 s Bluetooth cache.
- `Sirena/Modules/Switcher/SwitcherAppSwitcher.swift:907-925` has a generation check (`isCurrentSessionStart`) that is a good candidate for a race test.

**Private API:**
- No test can exercise SkyLight or SwiftUI private symbols in CI. Add a launch-time self-check with a log line and a manual checklist per macOS version (15, 26, 27).

---

## Positive Findings (for balance)

- `DockKit/Extensions/AXUIElement.swift:11-33`: `AXResponsiveness` avoids repeated calls to unresponsive apps.
- `DockKit/Utilities/Window Gestures/WindowGestureController.swift:148-152`, `Sirena/Modules/Tweaks/TweaksController.swift:532-537`, `Sirena/Modules/WindowManagement/Utilities/EventMonitor.swift:124-130`: event taps re-enable themselves after `tapDisabledByTimeout`.
- `Sirena/Modules/Island/Support/IslandPeripheralBatterySampler.swift`: Bluetooth and battery reads are cached (15 s and 300 s), run on a dedicated queue, and are bounded by `IslandBoundedProcessRunner`.
- `Sirena/Modules/Island/Services/NotchMusicService.swift:612-630` and `NotchShuffleService.swift:100-110`: Automation consent prompts are shown on a background queue, not the main thread.
- `ClipboardKit/Clipboard.swift:27-30`, `:236-241`: concealed, transient and auto-generated pasteboard types are excluded from history. Password-manager types are also in the default ignore list (`ClipboardKit/Extensions/Defaults.Keys+Names.swift:29-39`).
- `DockKit/Utilities/DockLocker.swift:360-385`: the Dock relocation animation runs off the main thread and hops back for state.
- `Sirena/Modules/Tweaks/DMGInstaller.swift:110-120`: `hdiutil` output is read before `waitUntilExit`, avoiding the classic full-pipe deadlock. `runDitto` does the same (line 170-172).
- Most `NSEvent` monitor and observer registrations use `[weak self]` and are removed in matching teardown code (for example `ScreenBrushController.swift:112-113`).

---

*Concerns audit: 2026-10-20*
