# Klip

**Your clipboard, within reach.**

Klip is a native macOS clipboard manager built with SwiftUI and AppKit. Search your copy history, bring back an earlier item, and get a quiet confirmation from a compact notch popup.

[Features](#features) · [Getting started](#getting-started) · [Usage](#usage) · [Development](#development) · [Contributing](#contributing)

## Features

- **Searchable clipboard history** — find text, links, rich text, code, images, PDFs, files, and folders.
- **Native copy-back** — preserve available clipboard formats and grouped items for pasting into compatible apps.
- **Compact history panel** — a glass background, keyboard navigation, sharing, and a remembered window position and size.
- **Notch previews** — click the copy indicator to see a preview, or choose to show only the preview automatically. Also works on displays without a notch.
- **Real previews** — view copied images and image files, PDF pages, and native macOS file icons.
- **Local persistence** — keep history between launches, with configurable item and age limits.
- **Adjustable feedback** — choose visual feedback, sound, both, or neither. Set copy volume and preview duration separately.
- **Privacy controls** — pause capture, exclude apps, and hide previews. Recognized sensitive clipboard markers are respected.

## Getting started

### Requirements

- macOS **15.4 or later**.
- **Xcode 27 or later**, with the macOS SDK. Development has been verified with Xcode 27.1.

### Build with Xcode

```sh
git clone https://github.com/zeeshan2k2/Klip.git
cd Klip
open Klip.xcodeproj
```

1. Select the **Klip** scheme and **My Mac** destination.
2. Choose your own development team under **Signing & Capabilities** if prompted.
3. Press **⌘R** to build and run.

### Build from Terminal

For a local unsigned development build:

```sh
xcodebuild \
  -project Klip.xcodeproj \
  -scheme Klip \
  -configuration Debug \
  -derivedDataPath /tmp/klip-build \
  CODE_SIGNING_ALLOWED=NO \
  build

open /tmp/klip-build/Build/Products/Debug/Klip.app
```

Launch at login requires an installed, signed build. Its status and any registration errors appear in Settings.

## Usage

Copy something as usual, then press **⌘⇧V** to open your history. You can also open it from the menu bar or Dock.

| Action | Control |
| --- | --- |
| Open history | **⌘⇧V** |
| Move through results | **↑ / ↓** |
| Copy the selected item | **Return** |
| Copy one of the first nine results | **⌘1–9** |
| Inspect an item | Double-click its row |
| Share an item | Share button on the row |
| Delete an item | Right-click → **Delete**, or use the inspector |
| Close the panel | **Escape** or click outside |
| Open Settings | Gear button, or **⌘,** while history has focus |

Selecting an item copies it back to the clipboard. Use **⌘V** in the destination app to paste it.

Click the notch indicator to preview the latest copy. The preview stays centered beneath the notch, fits short content horizontally, and uses the notch width as its maximum. Photos retain their proportions and have 10-point padding on all sides.

### Preferences

Open the gear button to configure **History**, **Privacy**, **Feedback**, and **General** settings.

| Setting | Default |
| --- | --- |
| Save history between launches | On |
| Maximum history items | 1,000 |
| Retention | 7 days |
| Copy feedback | Visual only |
| Show expanded preview automatically | Off |
| Expanded preview duration | **1.0 second**, adjustable from 1–30 seconds |
| Copy sound volume | **50%** |
| Delete sound | On |

The global shortcut, appearance, copy-indicator duration, excluded apps, and launch-at-login preference are configurable too. Saved choices remain in place after restarting.

## Privacy and storage

History is saved locally on your Mac as a JSON archive containing the captured clipboard representations. No account or cloud service is required.

- Turn off **Save history between launches** to delete the saved archive and keep only the current in-memory list until quitting.
- **Clear History** removes both current and saved entries.
- Paused monitoring and excluded apps suppress capture.
- Hidden previews conceal content in the interface; capture and storage still follow your history settings.

Copied files are stored as references, with bookmarks where available, rather than as duplicate file contents. Deleted or unavailable source files can make an entry unavailable. Some app-specific or promised formats require the originating app to remain usable; Klip reports incomplete captures.

## Development

The project uses native macOS frameworks and has no third-party package dependencies.

```text
Klip/
├── App/          App lifecycle and coordination
├── Clipboard/    Capture, classification, and native copy-back
├── History/      History model, persistence, panel, and previews
├── MenuBar/      Menu bar controls and global shortcut
├── Popup/        Notch presentation and audio feedback
├── Privacy/      Capture rules and app exclusions
└── Settings/     Preferences and launch-at-login integration
Tests/            Standalone verification programs
scripts/          Verification entry points
```

### Run checks

From the repository root, with Xcode selected as the active developer directory:

```sh
./scripts/check-phase2.sh
./scripts/check-phase3.sh
./scripts/check-phase4.sh
./scripts/check-expanded.sh
./scripts/check-interactions.sh
```

The checks cover clipboard round trips, privacy rules, persistence, keyboard interactions, notch geometry, preview timers, and audio behavior. They use private pasteboards, temporary archives, isolated preferences, and silent audio checks. UI checks may open temporary windows; run the scripts sequentially.

Physical notch behavior, fullscreen Spaces, multi-display layouts, and perceived sound levels also benefit from manual testing.

## Contributing

Bug reports and focused pull requests are welcome.

For a bug report, include your macOS and Xcode versions, steps to reproduce, and the expected and actual behavior. Use sample clipboard content when sharing a reproduction.

For code changes, explain the behavior being changed, run the relevant checks, and include before-and-after screenshots or a recording for interface changes.

## License

A license file has not yet been added to this repository.
