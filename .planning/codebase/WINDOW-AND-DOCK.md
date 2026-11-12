<!-- refreshed: 2026-11-12 -->
# Window & Dock map ("Janela e Dock")

**Analysis Date:** 2026-11-12

Every option on the Janela e Dock page, where it is stored, which code reads it, and what it
does — plus who owns which mouse/keyboard event, the minimize modes, the snap layouts and the
macOS 27 caveats. Read this before changing anything on that page. Update it in the same commit
when an option, a key, a default or an owner changes.

## 1. The page

`Sirena/App/Pages/WindowsPage.swift` → `ModulePage(module: .windows, tabs: …, switchable: false)`.
The page has no global switch; each feature keeps its own inside the page.

| Tab | View | Features in it |
|---|---|---|
| Janelas (`windows`) | `WindowsTab` (same file) | Arrange windows (Rectangle), green button, dragging to the edges, snap layouts, ⌘ Tab switcher |
| Dock (`dock`) | `DockTab` (same file) | Minimize mode, Dock clicks, Dock previews (DockDoor) |
| Finder (`finder`) | `Sirena/App/Pages/FinderTab.swift` | Finder improvements (Tweaks) |
| Atalhos (`shortcuts`) | `Sirena/App/Pages/ShortcutsTab.swift` | Every window-action and switcher shortcut |

Module switches (`FeatureSwitch`) write `sirena.module.<id>.enabled` (`ModuleID.isEnabled`, on by
default except `island`). Turning a module **on** starts it right away
(`ModuleManager.setEnabled`); turning `windows` or `dock` **off** needs a relaunch
(`pendingRestart`, "Reiniciar agora"); `switcher`, `shelf`, `menuBar`, `island` stop at once.

## 2. Options → storage → reader

Defaults columns show the value used when the key was never written. The UI default and the
reader's default must always match (a mismatch shows an option on that behaves off).

### Janelas

| Option (pt-BR UI) | Stored as (default) | Read by | Behavior / needs |
|---|---|---|---|
| Organizar janelas | `sirena.module.windows.enabled` (true) | `ModuleManager.start(.windows)` → `WindowManagementModule.start` | Rectangle port. Needs Accessibility; everything below hangs off `accessibilityTrusted()` |
| Botão verde: Tela cheia / Preencher a tela | `tweaks.greenButtonFills` (true) → mirrored into Rectangle's `greenButtonOverride` by `TweaksSettings.applyGreenButton` (on Tweaks start and on change; off on terminate) | `GreenButtonManager` (`ActiveEventMonitor` tap, mouse down/up) | Click on the green button maximizes (or restores, if Sirena maximized it) instead of native full screen. See §6 for macOS 27 |
| Encaixar janelas ao arrastar | Rectangle `windowSnapping` | `SnappingManager` (+ `WindowManagementModule`, `MacTilingDefaults`) | Drag to an edge/corner → snap area action. Off: the drag monitor stops, **and the snap layouts panel too** (the Windows tab warns) |
| Restaurar tamanho da janela quando desencaixado | `unsnapRestore` | `SnappingManager.unsnapRestore` | Dragging a snapped window gives back its pre-snap size (`windowHistory.restoreRects` / `lastRectangleActions`) |
| Ajustar as áreas de encaixe | `windowsAdvancedMode` (false) | UI only (`SnapAreaSettingsView(showsDetails:)`) | Shows the sub-sections below |
| Resposta tátil | `hapticFeedbackOnSnap` | `SnappingManager` | Trackpad tap entering a snap area |
| Animar a prévia | `footprintAnimationDurationMultiplier` (0.75 when on, 0 off) | `SnappingManager`, `FootprintWindow` | |
| Desfocar a prévia / aparência | `footprintBlur`, `blurAppearance` | `FootprintWindow`, `SnappingManager` | Hidden with Reduce Transparency |
| Encaixar antes de chegar à borda da tela | `snapBeforeReachingEdges` (20 pt when on, 0 off; imported values kept) | `SnappingManager` | |
| Impedir o Mission Control ao arrastar janelas | `missionControlDragging` (disabled = prevent) | `SnappingManager.startEventMonitor` | On → `ActiveEventMonitor` (a tap; handler still delivered on main) instead of `PassiveEventMonitor`. Toggle only shown once the key was touched |
| Áreas de encaixe (paisagem/retrato) | `SnapAreaModel` (landscape/portrait configs) | `SnappingManager.snapAreaContainingCursor` | Portrait grid only with a portrait display |
| Layouts para a janela da frente (atalho) | MASShortcut `snapLayoutsShortcut` (⌃⌥0, `ZoneController.defaultShortcut`) | `ZoneController.bindShortcut` (bound only while the switch below is on; steps aside while any shortcut is recorded) | Opens the panel for the focused window (Win+Z). Listed by `SirenaShortcutValidator`. Recorder in the Layouts section |
| Layouts no topo da tela | `snapLayouts.enabled` (true) | `ZoneController.isEnabled` | §5. Drawn right after "Arrastar até as bordas" (passed into `SnapAreaSettingsView(showsDetails:afterMain:)`), before its details, because it needs drag-to-snap on |
| Alternador de janelas (⌘ Tab) | `sirena.module.switcher.enabled` + `SwitcherDefaultsKey.*` (defaults registered once in `SwitcherSupportShims.swift`) | `SwitcherAppSwitcher`, `SwitcherWindowEnumerator`, `SwitcherView` | Settings view: `Sirena/Modules/Switcher/WindowSwitcherSettingsView.swift`. All 22 keys have readers with the registered defaults |

### Dock

| Option | Stored as (default) | Read by | Behavior / needs |
|---|---|---|---|
| Minimizar janelas (3 cards) | `minimizeHidesAllWindows` (false) + `minimizeRestoresAllWindows` (true) → `SirenaMinimize.mode` | `TweaksSnapshot` (Tweaks tap), `MinimizeHidesApp` (hide mode only) | §4. Picker: `Sirena/App/Pages/MinimizeModePicker.swift` |
| Clicar no app em uso | follows the mode | `TweaksEngine.dockClick` | "Esconde todas as janelas" in Tudo junto / Ocultar tudo; macOS otherwise |
| Pasta do Dock abre no Finder | `tweaks.dockFoldersOpenInFinder` (true) | `TweaksEngine.dockClick` | Holds the click, opens the folder |
| ⌘ + clique direito fecha o app | DockKit `enableCmdRightClickQuit` | `DockObserver` tap | Only while Dock previews run |
| Prévias do Dock | `sirena.module.dock.enabled` | `DockModule.start` → `DockController` | DockDoor port. Screen Recording for thumbnails (titles/icons without it) |
| Quando aparecem / O que mostram / Botões das janelas / Aparência | DockKit `Defaults.Keys` in `DockKit/consts.swift` (the key carries its default) | `DockObserver`, `SharedPreviewWindowCoordinator`, hover views | View: `DockKit/SirenaDockSettings.swift` (`SirenaDockSettingsSections`). Every key there has a reader (`lockAspectRatio` is UI-only by design) |

DockDoor's own Dock-click handling is switched off (`Defaults[.shouldHideOnDockItemClick] = false`
in `DockController.start`): **Dock clicks belong to Tweaks**, so one click is never handled twice.

### Finder

| Option | Stored as (default) | Read by |
|---|---|---|
| Melhorias do Finder | `sirena.module.tweaks.enabled` (true) (`TweaksController.finderTweaksOn`) | Tweaks always runs (Dock/window parts); this switch gates only the Finder parts |
| Recortar e colar arquivos (+ som) | `tweaks.finderCutAndPaste`, `tweaks.finderCutSound` (true) | `TweaksEngine.keyDown` (Finder in front, not editing text) |
| ⌫ move para o Lixo | `tweaks.finderDeleteMovesToTrash` (true) | `TweaksEngine.keyDown` |
| Copiar caminho | `tweaks.finderCopyPath` (true) | `FinderCopyPathExtension.setEnabled` (Finder Sync extension `SirenaFinder/`) |
| Instalar a partir de DMG | `tweaks.installFromDMG` (true) | `DMGInstaller` |
| Ponteiro nas capturas | system `com.apple.screencapture showsCursor` | `ScreenshotPreferences` |

### Atalhos

Window actions: MASShortcut keys named after `WindowAction.name`, bound by `ShortcutManager`
(defaults: Rectangle's recommended set, `alternateDefaultShortcuts`). Switcher shortcuts:
`SwitcherShortcutsSection`. "Remover restrições" = `allowAnyShortcut`. Restore/Import/Export go
through `AppSettingsViewModel` (JSON with every Rectangle setting, snap areas included).

## 3. Who owns which input

Every CGEvent tap goes through `AccessibilityGuard` (`mayCreateTap` → `register` → `unregister`;
see CLAUDE.md). Names as they appear in the `AccessibilityGuard` log:

| Owner | File | Kind / thread | Events | Does |
|---|---|---|---|---|
| `Tweaks` | `Sirena/Modules/Tweaks/TweaksController.swift` | tap, own thread | left mouse, keys | Dock clicks (hide app, bring windows back, folders), yellow button and ⌘M in hide mode, Finder keys, ⌃⌥⇧⌘⎋ fallback |
| `ActiveEventMonitor` | `Sirena/Modules/WindowManagement/Utilities/EventMonitor.swift` | tap, own thread; handler re-dispatched to main | per user | `GreenButtonManager` (mouse down/up), `MouseButtonShortcut` (other buttons), `SnappingManager` when Mission Control prevention is on |
| (passive) | same file, `PassiveEventMonitor` | NSEvent global monitor, main | per user | `SnappingManager` (default), `TitleBarManager` |
| `DockObserver` | `DockKit/Utilities/DockObserver.swift` | tap | mouse | Dock hover previews, ⌘ + right click quit (not Dock left clicks) |
| `Switcher` | `Sirena/Modules/Switcher/SwitcherAppSwitcher.swift` | tap | keys | ⌘ Tab |
| `KeybindHelper`, `WindowGestureController`, `TrackpadSwipeTrigger`, `DockLocker` | `DockKit/Utilities/…` | taps | | DockDoor switcher keys, window gestures, swipes, Dock locking |

The drag of a window (any snapping, snap layouts) is seen only through `SnappingManager.handle`
(mouse down/dragged/up and Esc). Snap layouts hook into it; they add no monitor of their own.

## 4. Minimize modes and Dock clicks

`SirenaMinimize` (`DockKit/Utilities/Window Management/MinimizeHidesApp.swift`):
`hidesApp` wins, then `dockTogether`.

| Mode (card) | `minimizeHidesAllWindows` | `minimizeRestoresAllWindows` | Yellow button / ⌘M | Click on the app in front (Dock) | Click to show it |
|---|---|---|---|---|---|
| Como o macOS | false | false | macOS (one window) | macOS | macOS |
| **Tudo junto pelo Dock** (default) | false | true | macOS (one window) | hides the app (`app.hide()`) | macOS unhides; then every window minimized one by one is brought back (`afterClickAction`, 0.35 s after mouse-up) |
| Ocultar tudo | true | — | hides the app (Tweaks holds the click / ⌘M) | hides the app | unhides; `MinimizeHidesApp` already brought the minimized windows back behind the hidden app |

- Tweaks reads the mode at every click (`TweaksSnapshot.current`): changes apply at once.
- "Ocultar tudo" also has an after-the-fact path: the AX "window minimized" notification
  (`WindowManipulationObservers` → `MinimizeHidesApp.windowMinimized`) hides the app for Minimize
  from the menu, ⌥-click, Minimize All. That observer lives in DockKit, which is why the Dock tab
  asks for Dock previews in that mode.
- Electron and Catalyst apps put restored windows back on screen while hidden; `MinimizeHidesApp`
  learns them (`minimizeHidesApp.restoreOnShow`) and restores on show instead.

## 5. Snap layouts (Layouts no topo)

Files: `Sirena/Modules/WindowManagement/Zones/`

| File | Role |
|---|---|
| `ZoneLayout.swift` | Pure geometry: `ZoneNode` (tree of column/row splits with shares), `ZoneGeometry` (regions, frames with gaps, dividers, moving a line, resizing, evening), `ZoneTemplate` (the 6 layouts of the panel) |
| `ZonePopup.swift` | `ZonePopupGeometry` (one geometry for drawing and hit-testing), the glass panel, `ZoneHint` (the pill at the top middle while dragging), `ZonePreview` (where the window will go) |
| `ZoneAssist.swift` | Snap Assist: the other zones with the open windows (previews from `SwitcherWindowPreviewProvider.captureViaWindowServer`, grouped by app). Keyboard: arrows move, Tab / ⇧ Tab change zone, Return picks, Esc closes |
| `ZoneGroupDecor.swift` | Dashed group outlines, grips (drag = resize both, click = the grip's menu), "Juntar de novo" bubble |
| `ZoneController.swift` | The engine: drag hooks, placing, groups, timer, last group per display |

Geometry tests: `scripts/test-zone-layout.sh` (`scripts/tests/zone-layout/main.swift`).

Flow:
1. `SnappingManager` `.leftMouseDragged` (window moving) → `ZoneController.dragMoved()`. While a
   window is dragged, `ZoneHint` shows a small pill at the top middle of the display under the
   pointer (where the panel drops from). The panel opens when the pointer is in the top band of
   a display (menu bar bottom + 36 pt, middle 60%) **and** rose ≥ 24 pt during this drag (a
   window already at the top doesn't pop it at once). While open it returns true, so Rectangle's
   snap areas stand aside. Only the row of drawings picks a zone (`ZonePopupGeometry.hit`): the
   top of the card is where the window arrives, and letting go there must do nothing.
2. `.leftMouseUp` → `ZoneController.dragEnded(element:id:cancelled:)`: over a zone → `place` +
   Snap Assist; over the "Último grupo" card → `relink`; elsewhere over the panel → nothing.
   Esc (`SnappingManager` keyDown) → `cancelDrag()`.
3. A drop elsewhere of a window in a group → `release`: out of the group, own size back.
4. Resize by an edge (mouse up without moving) → `resizeEnded`: the lines it touched move
   (`ZoneGeometry.resizing`), the other members follow.
5. `WindowManager.execute` (any Rectangle action) → `noteWindowAction`: the window leaves its group.
7. A click on a grip → its menu (`gripClicked`, an `NSMenu` of `ZoneMenuItem`s):
   - **Trocar app…** (`startReplace`): Snap Assist over the group's own zones ("No lugar de …");
     the pick replaces that zone's window, which leaves the group where it is. The only way a
     window from outside comes into a group.
   - **Inverter lados** (`swapSides` → `ZoneGeometry.swappingSides`): the two sides of that line
     trade places in the tree, windows and room included (the layout's shape is kept per
     display in `roots`, like resized proportions).
   - **Alterar divisórias…** (`openRelayout`): the panel in keyboard mode choosing a whole layout
     (`Session.relayout`); Return applies it (`applyLayout`: windows keep their order, extras
     leave, empty zones get Snap Assist), Esc keeps the current one.
   - **Dividir igualmente** (`evenSides`), **Desvincular** (`unlink`: the group is forgotten,
     no "Último grupo" card; "Juntar de novo" undoes it for 5 s), **Cancelar**.
   In the ⌃⌥0 panel the "Último grupo" card has a × (or Delete) that forgets it.
6. ⌃⌥0 → `openForFrontWindow`: the same panel in keyboard mode, on the display of the focused
   window (`Session.target` holds it). The panel takes the keyboard (nonactivating, so the app
   stays in front) and the pointer: ← → walk every zone, ↑ ↓ change layout, Return or a click
   snaps (`commitKeyboard`, then Snap Assist), Esc, ⌃⌥0 again or a click elsewhere cancel. A
   drag closes it. `ZoneController.start()` (from `WindowManagementModule.accessibilityTrusted`)
   binds the shortcut; `enabledChanged()` rebinds when the switch changes.

State is in memory only (lost on quit): `placements` (window → display, layout, zone, frame, pid),
`ownSizes`, `roots` (proportions per display + layout), `lastGroups` (per display). Placing never
writes Rectangle's `lastRectangleActions`, otherwise Rectangle would restore the size as soon as
a drag starts. A 0.35 s timer runs only while a group exists; it never asks the app in front
anything unless that app owns a group window (0.25 s AX timeout).

## 6. macOS 27 notes

- **Traffic-light hit-test:** from macOS 27, `AXUIElementCopyElementAtPosition` over the red,
  yellow and green buttons answers their group (`AXGroup`, `AXLandmarkRegion`…) or the window,
  not the button. Never match a click by the hit element's subrole alone: also take its window
  (`kAXWindowAttribute`, or the element itself if it is an `AXWindow`) and check the point
  against that window's button frame. Done in `GreenButtonManager.greenButtonFrame` and
  `TweaksEngine.minimizeButtonFrame`.
- Cheap filter first: every click on the Mac passes those taps; only clicks in the top-left
  corner of the clicked window (window server bounds, no AX) are worth an AX call
  (`GreenButtonManager.isInButtonsCorner`, `TweaksEngine.minimizeButtonClick`).
- Still subrole-based (low impact): `TitleBarTabButtonPress.isTabButton` (veto that keeps
  closing two tabs from counting as a title-bar double click) and `WindowGestureZone`
  (`AXTabButton`).

## 7. Adding or changing an option

1. Key: Rectangle-side → `Sirena/Modules/WindowManagement/Defaults.swift`; DockKit → `DockKit/consts.swift`
   (`Defaults.Keys`, default in the key); switcher → `SwitcherDefaultsKey` + its registered default;
   other → a named constant next to its reader (never a bare string in two places).
2. UI in the tab's view; the UI default must equal the reader's default.
3. Reader in the feature, read where it acts (taps read a snapshot per event; don't cache in the tap).
4. Strings through `L("…")` with the pt-BR value in `Sirena/Resources/Sirena.xcstrings`
   (DockKit's own strings use `SL`).
5. Anything that takes clicks, keys or windows: say in §3 who owns the event; never a second
   handler for the same click.
6. Update this file (option table, owner, flow) in the same commit.

## 8. Manual check before a release

- Janelas: ⌃⌥← (Rectangle action); drag to the left edge (snap + footprint); drag a snapped window
  out (size restored); green button with "Preencher a tela" (fills, click again restores).
- Snap layouts: ⌃⌥0 with a window in front → panel; arrows, ↑ ↓, Return snaps; again with Esc.
  Drag up to the top middle → panel; hover a zone (preview), drop; Snap Assist shows
  previews by app, pick one; outlines and grip appear; drag the grip, double click it, click it
  ("Juntar de novo" for 5 s); drag up again → "Último grupo" card; Esc while the panel is open.
- ⌘ Tab: open, cycle, release; with "Substituir ⌘Tab e ⌘` do macOS" on and off.
- Dock, each minimize mode: yellow button, ⌘M, click the app in front in the Dock twice, with an
  app that has a minimized window (VS Code covers Electron).
- Dock previews: hover, click a preview, ⌘ + right click quit.
- Finder: ⌘X/⌘V of a file, ⌫ to Trash, Copy Path in the context menu.

## 9. Known gaps

- Snap layouts keep groups and proportions only while Sirena runs.
- No unit tests for the page's wiring (see `.planning/codebase/TESTING.md` for the planned
  SirenaTests target). The snap layouts' geometry has its own: `scripts/test-zone-layout.sh`
  (no app, no AX), next to `scripts/test-event-tap-policy.sh`. Run both after touching
  `ZoneLayout.swift` or any event tap.
- The tab-button veto (§6) may let a fast double close of two tabs count as a title-bar double
  click on macOS 27, only when the title-bar double-click action is set in Sirena.
