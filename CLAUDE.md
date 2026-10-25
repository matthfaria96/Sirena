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
  is up), "Check for Updates…" in the app menu (`MainMenu.swift`) and a button in About
  (`AboutView.swift`, end of Geral; "About Sirena" opens Geral scrolled down to it).
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
