# Klip

A native macOS clipboard manager with a beautiful, minimal history panel, a small notch-style copy notification, and optional audio feedback.

Klip takes inspiration from Pastebot's compact clipboard workflow while developing its own visual identity. The core experience is: **copy → receive feedback → find an item → copy it again**.

## Development plan

Start with the [product direction and architecture](docs/README.md), then follow these phases in order:

1. [History panel UI](docs/01-history-panel-ui.md)
2. [Clipboard functionality](docs/02-clipboard-functionality.md)
3. [Copy feedback](docs/03-copy-feedback.md)
4. [Storage and settings](docs/04-storage-and-settings.md)
5. [Polish and verification](docs/05-polish-and-verification.md)

Each phase defines its scope, implementation prompt, and completion criteria. Review the panel's appearance after Phase 1 before connecting live clipboard data.

## Current status

Phases 1–4 and expanded clipboard-format support are implemented. The rounded glass history panel now captures text, links, rich text, code, images, PDFs, files/folders, and available app-native representations, supports configurable retention and optional saved history, search and keyboard navigation, and copies items back without recording Klip's own writes.

Run the Klip scheme in Xcode. Open the panel with **⌘⇧V**, the menu bar's **Show Clipboard**, the Dock, or **File → Show Clipboard** (⌘0). If the global shortcut is occupied, Klip reports it in the menu and gear panel.

- Single-click selects. Double-click opens the full preview.
- Return, **⌘1–9** for the first nine search results, the right-click **Copy** command, or the preview's **Copy** button copies an item and dismisses the panel. Paste into the destination app yourself with ⌘V.
- Share is the only inline row action. Delete is in the preview and right-click menu.
- The menu bar and title menu provide pause/resume and clear history. The gear opens Settings with History, Privacy, Feedback, and General sections.
- Drag blank header space to move the panel; resize from its edges. Its frame is remembered. Escape or an outside click dismisses it.

**History saving is on by default at first launch.** Manage it in the gear → **History** → **Save history between launches**. Copies are saved locally and restored after relaunch. Turning saving off deletes the saved file while keeping the current list in memory until you quit. An explicitly saved off choice remains off after updates.

Settings include item/age limits (defaults: 1,000 items, 7 days), pause/resume, application exclusions, hidden previews with deliberate reveal, appearance, global shortcut choices, notch duration, feedback mode, and optional launch at login. Hidden previews do not stop capture or change storage policy. Clear History removes both current and saved entries. Storage failures are shown in the panel and Settings.

Klip preserves original representations and multiple clipboard items for copy-back and saved history. Images/PDFs have previews; Finder-copied image files also show their actual image pixels. Other file groups have native macOS item icons, names, and Finder reveal. Files are stored as references with bookmarks where possible, rather than duplicating file contents. Missing files fail visibly without clearing the current clipboard. Existing saved text history migrates to the new versioned archive.

Sensitive markers, excluded apps, pause, and blocked access still suppress capture. The preview is separate from the original bytes; large text previews do not truncate what gets copied back. Some source-app-dependent promises/private formats cannot be made universally reusable simply by archiving their bytes; incomplete captures are reported. See [expanded clipboard support](docs/06-expanded-clipboard.md) for limits and per-app manual checks.

The black notch extension stays icon-only until clicked, then expands in place to a compact, fixed-height copied-content preview with ten-point side padding (photos use ten points on all sides). Its width hugs the content up to the measured notch-width maximum. **Settings → Feedback → Preview duration** adjusts its saved timer from 1–30 seconds (default: four). Enable **Settings → Feedback → Show preview automatically after copying** to open it immediately. Hidden-preview settings conceal the content. The extension and optional sound support Visual only, Sound only, Visual and sound, or Off. History and feedback retain their nonactivating fullscreen presentation. Launch at login reports actual macOS registration/approval status; using it requires a signed app build. The temporary unsigned development preview can report an unavailable/signature error rather than pretending registration succeeded.

Deleted rows shrink away with a single short deletion tap. Settings → **Feedback** includes a saved **Copy sound volume** slider (0–100%, initially 50%), a **Preview** button, and a separate deletion-sound toggle. Zero volume mutes copy audio. Reduce Motion removes the shrinking animation.

## Verification

Run `scripts/check-phase2.sh` from Terminal on macOS with Xcode installed. It uses a private named pasteboard, never the user's general clipboard. It verifies capture, copy-back, privacy gates, generation races, bounds, timers, panel keyboard/mouse interactions, and system hotkey registration/conflicts.

Run `scripts/check-phase3.sh` for feedback modes, timer/focus behavior, display geometry, and private-pasteboard integration; it does not play audible audio.

Follow the [Phase 2 manual checklist](docs/02-clipboard-functionality.md#manual-checklist) for capture/permissions and the [Phase 3 checklist](docs/03-copy-feedback.md#manual-checklist) for feedback, real fullscreen apps, sound, and physical display behavior.

Run `scripts/check-phase4.sh` for cross-process save/restore, retention, clear/disable semantics, corrupted storage and failure recovery, settings/privacy wiring, and fake login-service status tests. Tests use temporary history files and isolated defaults; they never read the general clipboard or register a real login item.

Follow the [Phase 4 checklist](docs/04-storage-and-settings.md#manual-checklist) to verify your saved history and Settings in the app.

Run `scripts/check-expanded.sh` for native-format, multi-item, image/PDF, file/bookmark, and binary-storage round trips. Expanded support is part of the current core implementation and will be included in Phase 5 polish.

Run `scripts/check-interactions.sh` for saved audio preferences, volume routing, deletion cues, immediate durable deletion, Reduce Motion, and native animation/Settings rendering. Audio players are mocked; no audible playback or general clipboard access occurs.

The copy cue is normalized and uses a stronger low-end volume curve: 1% maps to 10% playback gain, while 0% remains silent. Deletion uses a separate, prepared 45 ms mono tap.
