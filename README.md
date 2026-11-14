<p align="center">
  <img src="assets/app-icon-source.png" width="128" height="128" alt="Klip app icon">
</p>

<h1 align="center">Klip</h1>

<p align="center">
  Your clipboard, within reach.<br>
  A native macOS clipboard manager with searchable history and subtle notch previews.
</p>

<p align="center">
  <a href="https://github.com/zeeshan2k2/Klip/releases/latest/download/Klip.dmg"><strong>Download for macOS</strong></a><br>
  macOS 15.4+ · Apple Silicon &amp; Intel
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#contributing">Contributing</a>
</p>

## Features

- **Find what you copied.** Search text, links, code, rich text, images, PDFs, files, and folders in one history.
- **Keep the original formats.** Copy items back with their available native clipboard representations, including grouped files.
- **A quiet confirmation.** Get a small animated copy indicator beneath the notch, or show a content preview automatically. Displays without a notch work too.
- **Preview before pasting.** See image thumbnails, PDF previews, and native macOS file icons. Double-click an entry for a closer look.
- **Stay on the keyboard.** Open history with a global shortcut, navigate results, and copy an item without reaching for the mouse.
- **Keep recent items handy.** Reusing an entry moves it to the top without creating a duplicate.
- **Pick up where you left off.** History is saved between launches by default, with up to 1,000 entries and configurable retention.
- **Make it yours.** Adjust sounds, volume, preview duration, appearance, and the global shortcut. Resize and move the history panel; Klip remembers it.
- **Control what gets captured.** Pause monitoring, exclude apps, hide previews, or turn off saved history.

Built with SwiftUI and AppKit. Requires **macOS 15.4 or later**.

## Installation

### Download

**[Download Klip.dmg](https://github.com/zeeshan2k2/Klip/releases/latest/download/Klip.dmg)** — universal app for Apple Silicon and Intel Macs running macOS 15.4 or later.

1. Open the DMG and drag **Klip** into **Applications**.
2. Launch Klip from Applications.
3. Allow **Accessibility** access when prompted to paste directly into other apps.

To update, quit Klip, drag the new app into Applications, and choose **Replace**. Your saved history and settings are stored separately from the app.

The current download is ad-hoc signed and **not notarized by Apple**. If macOS blocks it, follow [Apple’s instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). Only proceed if you trust the download.

### Build from source

You’ll need **Xcode 27 or later**. Development has been verified with Xcode 27.1.

```sh
git clone https://github.com/zeeshan2k2/Klip.git
cd Klip
open Klip.xcodeproj
```

1. Select the **Klip** scheme and **My Mac** destination.
2. Select your development team under **Signing & Capabilities**, if prompted.
3. Press **⌘R** to build and run.

Launch at login requires an installed, signed build. Registration status appears in Settings.

## Usage

Copy something as usual, then press **⌘⇧V** or choose **Show Clipboard** from the menu bar. Search for an entry, select it, and press **Return** to paste it into the app you were using. On first use, allow Klip in **System Settings → Privacy & Security → Accessibility**. Until permission is granted, the item is copied and you can paste it manually with **⌘V**.

| Action | Shortcut or control |
| --- | --- |
| Open clipboard history | ⌘⇧V, configurable in Settings |
| Move through results | ↑ / ↓ |
| Paste the selected item into the previous app | Return |
| Paste one of the first nine results | ⌘1–9 |
| Inspect an item | Double-click its row |
| Share an item | Row’s share button |
| Delete an item | Right-click → Delete, or use the inspector |
| Close history | Escape or click outside |
| Open Settings | Gear button, or ⌘, while history has focus |

Content previews appear automatically after copying by default, without showing the copy indicator first. Turn off automatic previews in Settings to use the compact indicator instead; click it to preview your latest copy.

### Defaults

| Setting | Default |
| --- | --- |
| Save history between launches | On |
| History limit | 1,000 items |
| Retention | Until deleted |
| Copy feedback | Visual only |
| Automatic content previews | On |
| Content preview duration | 1 second; adjustable from 1–30 seconds |
| Copy icon duration | 1 second |
| Copy sound volume | 50% |
| Delete sound | On |
| Open Klip at login | On, subject to macOS approval |

## Privacy

Your history stays on your Mac. Klip saves captured clipboard data in a local archive; no account or cloud service is required.

- Pause monitoring at any time from the menu bar.
- Exclude apps from capture. Common password managers and Keychain Access are excluded by default, and recognized sensitive clipboard markers are respected.
- Turn off **Save history between launches** to remove the saved archive and keep history only until you quit.
- Use **Clear History** to remove current and saved entries.

Hiding previews conceals content in the interface; it does not stop capture or storage.

## FAQ

### Does selecting an item paste it automatically?

Yes. Press Return or ⌘1–9 to paste into the previous app, after granting Accessibility permission. Explicit **Copy** actions in the context menu or inspector only copy the item to the clipboard.

### Does Klip work without a notch?

Yes. Copy feedback appears at the top of the display.

### Are copied files backed up?

No. File entries keep references and bookmarks where available, rather than duplicating the files. Moving or deleting the originals can make them unavailable.

### Does every app-specific clipboard format work?

Klip preserves available native representations, but some app-specific or promised formats depend on the originating app. Incomplete captures are reported, and restoring a format depends on support in the destination app.

## Development

Klip uses native macOS frameworks and has no third-party package dependencies.

Run the existing checks from the repository root with Xcode selected as your active developer directory:

```sh
./scripts/check-phase2.sh
./scripts/check-phase3.sh
./scripts/check-phase4.sh
./scripts/check-expanded.sh
./scripts/check-interactions.sh
```

Run these sequentially. They cover clipboard round trips, privacy rules, persistence, keyboard interactions, preview timing, and audio behavior using private pasteboards, temporary archives, and isolated preferences. Some checks open temporary windows.

Physical notch animations, fullscreen Spaces, multiple displays, and sound levels should also be checked manually.

## Contributing

[Bug reports](https://github.com/zeeshan2k2/Klip/issues) and focused pull requests are welcome.

For bugs, include your macOS version, steps to reproduce, and what you expected to happen. Use sample clipboard content rather than personal data.

For changes, describe the resulting behavior and run the relevant checks. Include screenshots or a short recording for UI changes.

## License

A license has not yet been added to this repository.
