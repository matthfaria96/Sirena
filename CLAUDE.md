# Sirena

Menu bar app for macOS 15+ (universal, `LSUIElement`). Xcode project with file-system synchronized
groups: new files inside `Sirena/`, `DockKit/`, `ClipboardKit/` or `SirenaFinder/` are picked up
without touching the project. Sirena's own strings go through `L("…")` into
`Sirena/Resources/Sirena.xcstrings` (English keys, pt-BR translations). GSD planning lives in `.planning/`.

## Version and release build

- Version: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Sirena.xcodeproj/project.pbxproj`
  (8 occurrences each, all targets). The build number is what Sparkle compares: always increase it.
- Release: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/package-release.sh`
  → `build/DerivedData-release/Build/Products/Release/Sirena.app` (plus `build/release/`).
- Download DMG (the file users get and Sparkle installs):
  `~/Documents/witchmymac-release/make-dmg.sh <Sirena.app> Sirena-<version> ~/Documents/witchmymac-release/dist`.

## Code signing

- The build is ad hoc and without Hardened Runtime (no paid developer account, not notarized).
- `package-release.sh` then runs `~/Documents/witchmymac-release/sign-app.sh` when it exists: everything
  (frameworks, Sparkle's helpers, the Finder extension) is re-signed with the self-signed
  "witchmymac Code Signing" certificate, keeping each component's entitlements and flags. The designated
  requirement becomes `identifier "com.matheusfaria.Sirena" and certificate root = H"ff83cea4…"`, the same
  in every build, so macOS keeps Accessibility, Screen Recording, etc. across updates (ad hoc signatures
  changed every build and reset them). Without the script (another Mac) the app stays ad hoc.
- Check: `codesign -dr - Sirena.app` and `codesign -d --entitlements - Sirena.app` (also on the
  `.appex` and frameworks). The first install after switching from ad hoc (0.5.2) still needs the
  permissions granted once more.
- The certificate and keys live in `~/Documents/witchmymac-release/signing/` — never in this repo.

## In-app updates (Sparkle 2)

- Sparkle via Swift Package Manager (product `Sparkle`, embedded automatically). Code:
  `Sirena/App/Updates/AppUpdater.swift` (controller, menu validation, Dock icon while an update window
  is up), "Check for Updates…" in the app menu (`MainMenu.swift`) and a button on the Sobre page
  (`AboutView.swift`, its own sidebar item after Geral; "About Sirena" in the app menu opens it).
- Info.plist: `SUFeedURL` = `https://witchmymac.com/appcast/sirena.xml`, `SUPublicEDKey` (shared
  witchmymac EdDSA key), `SUEnableAutomaticChecks` = YES (no permission prompt), `SUScheduledCheckInterval`
  = 86400 (daily), `SUAutomaticallyUpdate` = NO (Sparkle asks before downloading; the user can tick
  automatic installs in its window).
- Publishing an update: build, make the DMG, then
  `~/Documents/witchmymac-release/make-appcast-item.sh <dmg> <version> <build> 15.0 <github download url> <notes.html>`
  and add the printed `<item>` at the top of `appcast/sirena.xml` in the site repo, after the GitHub
  release with that exact DMG is up. See `~/Documents/witchmymac-release/UPDATES.md`.
- Testing updates without touching the installed app: run a renamed copy (other bundle id, no
  `PlugIns/`, no `NSServices`/`CFBundleURLTypes`/`UTExportedTypeDeclarations`, `SUFeedURL` pointing to a
  local server, `LSEnvironment` `SIRENA_UPDATES_ONLY=1`). In that mode Sirena starts only the menus, the
  updater and (with `SIRENA_OPEN_PAGE=about`) the About page: no modules, no menu bar icon, no onboarding.
  Clean up its prefs/caches and `lsregister -u` it afterwards.

## Event taps and Accessibility (safety rule)

Revoking Accessibility while Sirena ran froze the whole Mac (0.5.2): taps were re-enabled without
trust. **Never create or re-enable a CGEvent tap without trust.** `DockKit/Utilities/AccessibilityGuard.swift`
polls `AXIsProcessTrusted()` every second off the main thread; on loss it disables every registered tap
at once and tells the owners (via `observe`) to tear down, on regain to recreate. For every tap:
- `AccessibilityGuard.shared.mayCreateTap(name)` before `tapCreate`; `register(tap, name:)` after the
  initial `tapEnable(true)`; `unregister(tap)` before switching it off / invalidating.
- In the callback: disable notices go to `AccessibilityGuard.shared.tapDisabled` (or
  `passthroughIfTapUnsafe`), never `tapEnable(…, true)`; pass every event straight through while
  `!AccessibilityGuard.isTrusted`; no synchronous main-thread/AX waits on that path.
- Policy (timeouts re-enabled only while trusted, max 3 per minute per tap) lives in
  `EventTapPolicy.swift`, tested by `scripts/test-event-tap-policy.sh` (no app, no TCC).
- Checking without Accessibility: a renamed copy (other bundle id, no `PlugIns/`) with `LSEnvironment`
  `SIRENA_TAP_CHECK=1` starts only the tap modules and the guard (no menu bar icon, onboarding, mixer or
  Finder extension). Launch with `open -g`, count its taps with `CGGetEventTapList` (must be 0) and read
  `/usr/bin/log show --predicate 'category == "AccessibilityGuard"'` (`log` alone is a zsh builtin).
  Its prefs land in `~/Library/Preferences/<id>.plist` even with `CFFIXED_USER_HOME`: delete them,
  `tccutil reset All <id>` and `lsregister -u` the copy afterwards.

## Showcase mode (site screenshots)

`SIRENA_SHOWCASE=1` (`Sirena/App/Showcase.swift`) is for the witchmymac.com screenshots. Nothing
starts: no modules, event taps (`AccessibilityGuard.mayCreateTap` refuses), mixer, updater, menu
bar icon or onboarding, and no permission is asked. Pages show permissions as granted and the
clipboard history gets fictional entries (`ClipboardKit/ShowcaseHistory.swift`, only into an
empty store). `SIRENA_OPEN_PAGE=<module id|general|about|home>` (+ `SIRENA_OPEN_TAB`) picks the
page; `SIRENA_SHOW_PANEL=1` shows the menu bar panel in a popover instead, with
`SIRENA_PANEL_INLINE=clipboard|pomodoro|screenCapture` for an inline panel;
`SIRENA_SHOWCASE_SCREEN=left` uses the leftmost display. Run a renamed copy (bundle id
`com.matheusfaria.Sirena.showcase`, no `PlugIns/`, no `NSServices`/`CFBundleURLTypes`/
`UTExportedTypeDeclarations`/`SUFeedURL`, ad hoc signed) with `CFFIXED_USER_HOME=<temp home>` and
`--args -AppleLanguages "(en)"`. Its prefs land in `~/Library/Preferences/<id>.plist`: delete them,
the temp home, and `lsregister -u` the copy afterwards.

