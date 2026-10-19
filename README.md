# Sirena

**English** · [Português](README.pt-BR.md)

A menu bar app for macOS 15 or later that brings your everyday tools into one place: window management, a ⌘ Tab switcher with previews, clipboard history, text capture, a Pomodoro timer, a color picker, screen drawing and more. The interface is in Brazilian Portuguese.

## Features

**Shortcuts** (⚡ menu and Home)
- **Clipboard** — a searchable history of what you copied.
- **Pin Window** — keeps a window above all others.
- **Capture Text** — copies text from anywhere on screen (OCR), plus QR codes and barcodes.
- **Screenshot** — a shortcut to Apple's Screenshot tool: area, full screen or recording, already in the mode you pick.
- **Pomodoro** — a focus timer with breaks and a countdown in the menu bar.
- **Color Picker** — picks colors from the screen, with history, palettes and several formats.
- **Free Drawing** — draw, highlight and point on top of the screen; take a screenshot with the drawing.
- **Mirror** — a quick look at your camera before a call.

**Controls** — Keep screen on, Turn off display (blanks the screen after a countdown you can cancel) and a sound mixer (per-app volume, output and microphone).

**Background features** — Window and Dock (window shortcuts, Dock previews, ⌘ Tab), Hidden Icons, Shelf (drag and drop) and Dynamic Island.

## Compatibility

Works on **macOS 15 (Sequoia)** and later. On macOS 26+ it uses the Liquid Glass look; on earlier versions Sirena detects the version and uses the system's classic translucent materials and buttons, and Hidden Icons uses Hidden Bar's separator technique instead of the native macOS 27 feature.

## Installation

1. Download the `.dmg` (or `Sirena.zip`) from the [Releases](../../releases) page and move `Sirena.app` to **/Applications** (some features only work from that folder).
2. The app is not notarized by Apple, so the first time macOS shows "Sirena can't be verified" with a **Move to Trash** button. Click **OK** (not Move to Trash), then either:
   - open **System Settings › Privacy & Security**, scroll to the bottom and click **Open Anyway** next to the Sirena notice; or
   - in Terminal, run `xattr -dr com.apple.quarantine /Applications/Sirena.app` and open the app as usual.

   Since macOS 15, right-click › Open no longer skips this notice.
3. Follow the onboarding to allow **Accessibility** and **Screen Recording**.

## Building

Requires Xcode 27. The resulting app runs on macOS 15 or later.

```sh
xcodebuild -scheme Sirena -configuration Release -derivedDataPath build/DerivedData \
  -skipMacroValidation -skipPackagePluginValidation build
```

This build signs with the local "Sirena Local Dev" certificate, which is only trusted on the Mac that created it. To produce the files that go to Releases, use `scripts/package-release.sh`: it signs ad hoc, without Hardened Runtime, so the app opens on any Mac without a paid developer account.

## Credits and license

Sirena is distributed under the **GPL-3.0** (see [LICENSE](LICENSE)) because it includes GPL-3.0 code. Parts come from open source projects, each under its own license:

| Feature | Based on | License |
|---|---|---|
| Windows | [Rectangle](https://github.com/rxhanson/Rectangle) | MIT |
| Dock and previews | [DockDoor](https://github.com/ejbills/DockDoor) | GPL-3.0 |
| ⌘ Tab, Dynamic Island, mixer | [Vorssaint](https://github.com/vorssaint/vorssaint-utils) | GPL-3.0 |
| Clipboard | [Maccy](https://github.com/p0deje/Maccy) | MIT |
| Hidden Icons | [Hidden Bar](https://github.com/dwarvesf/hidden) | MIT |
| Keep screen on | [Caffeine](https://github.com/domzilla/Caffeine) | MIT |
| Mirror | [Iris](https://github.com/ahmetb/Iris) | MIT |
| Sound | [Fader](https://github.com/pantafive/fader) | MIT |

Pin Window, Capture Text, Enhancements, Shelf, Pomodoro, Color Picker and Free Drawing were written from scratch, inspired by the feature lists of Floaty, TextSniper, Supercharge, Yoink, Flow, Pastel and ScreenBrush. No code from those commercial apps was used.
