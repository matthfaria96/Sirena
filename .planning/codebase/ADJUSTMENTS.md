<!-- refreshed: 2026-11-19 -->
# Dock, Monitores and settings shortcuts map

Once the "Ajustes" card (0.7 builds before release); now there is no card and no module switch.
Each part lives where people look for it:

| Part | Where | View |
|---|---|---|
| Dock on one display, spaces, Dock options (the backup is its last row) | Janela e Dock › Dock: Minimizar, Cliques no Dock, Dock em um monitor, Espaços, Opções do Dock, then the previews | `Sirena/App/Pages/DockSetupSections.swift` (`DockLockSection`, `DockLayoutSections`) |
| Displays, apps on their display | Janela e Dock › Monitores (`displays`): one group per connected display (main, resolution, refresh rate), Todos os monitores (mirroring, Displays settings), then Apps no monitor certo | `Sirena/App/Pages/DisplaysTab.swift` |
| Permission lists, System Settings panes | Geral, tabs Permissões dos apps (cards in two columns) and Ajustes do Sistema (panes by group), after the Sirena tab (Sirena's own permissions and settings, `SirenaSettingsTab.swift`). `SIRENA_OPEN_PAGE=general` (`mac-settings` still works), `SIRENA_OPEN_TAB=sirena|permissions|system`. History: a tab of Geral, then its own "Ajustes do Mac" sidebar row (0.7.0), back in Geral as tabs next to a Sirena tab (0.7.1) | `Sirena/App/Pages/GeneralPage.swift` |

Code: `Sirena/Modules/Adjustments/`. `DockAndDisplaysController` starts with the modules
(`ModuleManager.startEnabledModules`) and runs only what is switched on: the Dock lock while its
switch is on, `AppScreenEngine` observers only for apps with a rule. Update this file in the same
commit as any change to an option, key, default or owner.

## 1. Tabs → storage → reader

### Janela e Dock › Dock (`dock`)

| Option | Stored as (default) | Read by | Behavior / needs |
|---|---|---|---|
| Manter o Dock em um monitor | `adjustments.dockLock.enabled` (false; key name from the old card) | `DockAndDisplaysController.applyDockLock` → `DockLockService` (DockKit) → `DockLocker` | Event tap (`DockLocker`, mouse moved, session head insert) pushes the pointer back off the Dock edge of the other displays; if the Dock is found elsewhere it walks the pointer to the locked display's edge so macOS moves it back (synthetic mouse moves, then the pointer is put back). Needs Accessibility. Bottom/left/right Dock only |
| Monitor do Dock | DockKit `lockedDockScreenIdentifier` (empty → `system-main-display`, `DockLockService.mainDisplayIdentifier`) | `DockLocker` (observes the key itself) | “Monitor principal (name)” follows the display macOS has as main; or a display's hardware UUID. The picker shows even with the lock off (disabled) so the choice is visible first |
| Segurar para mudar o Dock | DockKit `dockLockOverrideModifier` (0 = ⌥) | `DockLocker` tap | Held: the Dock moves like macOS. The tap reads a cached copy (and its trigger zones) behind a lock, never UserDefaults per mouse move. `DockLockService.stop` keeps the locker alive until the tap thread has removed the tap |
| Espaços entre os apps | `com.apple.dock` `persistent-apps` tiles `spacer-tile` / `small-spacer-tile` | the Dock | `DockPreferences.insertSpacer/removeSpacer/removeAllSpacers`, then `killall Dock` (debounced 0.6 s) |
| Opções do Dock | `com.apple.dock` keys: `autohide`, `autohide-delay` (0 = no wait), `autohide-time-modifier` (0.15 fast / 0 instant / removed), `static-only`, `showhidden`, `show-recents`, `launchanim`, `contents-immutable`, `size-immutable` | the Dock | `DockOption`. Back to macOS's default = key removed, not written. `contents-immutable` is “Congelar os ícones do Dock” and says it does **not** keep the Dock on a display (it was mistaken for the lock as “Travar os ícones”) |
| Cópia de segurança | `~/Library/Application Support/Sirena/Dock backup.plist` (`defaults export com.apple.dock`) | `DockPreferences.restoreBackup` (`defaults import`) | Saved by itself before the first write; "Salvar agora" replaces it |

Not offered on purpose: `scroll-to-open` (DockKit has its own Dock scroll gesture) and
`single-app` (Dock clicks belong to Tweaks, see WINDOW-AND-DOCK.md §2).

### Janela e Dock › Monitores (`displays`)

| Option | Stored as | Read by | Behavior / needs |
|---|---|---|---|
| Apps no monitor certo | `adjustments.appScreens.rules` (JSON `[AppScreenRule]`: bundle id, display UUID + name, `mode` keep/fill/center, `onlyAtLaunch`) | `AppScreenEngine` | §2. Needs Accessibility |
| Tornar principal | system display configuration | `DisplayConfigurator.makeMain` | Moves every display's origin so the chosen one is at (0, 0) |
| Resolução / Taxa de atualização | system | `DisplayConfigurator.apply` | One entry per "looks like" size (HiDPI first). **Undone after 15 s unless "Manter"** (`pending`, `revertPending`) |
| Espelhar os monitores | system | `DisplayConfigurator.setMirroring` | Every other display mirrors the main one |

### Geral › Permissões dos apps / Ajustes do Sistema

Shortcuts only (`SettingsShortcuts.swift`): privacy lists by `Privacy_…` anchor, panes by their
extension bundle id (`ls /System/Library/ExtensionKit/Extensions` on the Mac at hand), Passwords
as an app. Sirena can't grant permissions; nothing here changes a setting.

## 2. Apps on their display (`AppScreenEngine`)

- No event tap. One `AXObserver` (`kAXWindowCreatedNotification`) per running app **that has a
  rule**; every AX call (observers, reading and writing frames) runs on the engine's own thread
  (`EngineThread`, a run loop). The main thread only sends snapshots (rules, displays in top-left
  coordinates, running apps) — it never waits for another app.
- A new window is moved once (`placed`, per pid): only `AXStandardWindow`, not full screen, not
  minimized; already on its display → left alone. Rechecked at 0.4 s and 1.2 s (apps that put
  their window back where it last was). A freshly launched app is also scanned at 0.3/1/2.5 s
  (its first window can come before the observer). "Só ao abrir": windows within 8 s of launch.
- Display not connected → nothing happens (the rule waits). Losing Accessibility drops the
  observers (`AccessibilityGuard.observe` → `sync`), getting it back recreates them.
- Geometry (`AppScreenPlacement.swift`, pure): tested by `scripts/test-app-screen-placement.sh`.
- `log stream --predicate 'category == "AppScreens"'` shows each move (no titles).

## 3. Who owns what

| Owner | Kind | Notes |
|---|---|---|
| `DockLocker` via `DockLockService` | tap (AccessibilityGuard name `DockLocker`) | Was created by `DockController` (Dock previews) when DockDoor's `enableDockLocking` was on; now only `DockAndDisplaysController` starts it. `SIRENA_TAP_CHECK` starts it too |
| `AppScreenEngine` | AX observers, own thread | — |
| `DockPreferences` | writes `com.apple.dock`, restarts the Dock | Showcase mode never writes |
| `DisplayConfigurator` | `CGCompleteDisplayConfiguration(.permanently)` | Showcase mode never writes |

## 4. Manual check before a release

- Dock lock (two displays): switch on → the Dock goes to the chosen display; push the pointer
  down on the other one (Dock stays); hold ⌥ and push (it moves); change the display; switch the
  switch off (the tap is gone: `log show --predicate 'category == "AccessibilityGuard"'`).
- Spacers: add small/large between two icons and at the end, remove one, remove all, restore the
  copy.
- Options: autohide + no wait + instant; show only open apps; back off (keys removed).
- Apps on display: a rule for an app, quit it, open it from another display (window lands on its
  display); "Só ao abrir"; "Mover as janelas agora"; unplug the display (nothing moves).
- Displays: change resolution and let it revert; change and keep; make another display main and
  back; mirror on/off.
