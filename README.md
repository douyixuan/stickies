# Stickies

Native macOS spatial sticky notes, built with SwiftUI and AppKit. Local-first, with iCloud sync planned.

## Development

The prototype uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate an Xcode project:

```sh
brew install xcodegen
xcodegen generate
open Stickies.xcodeproj
```

Requires a Mac with Xcode. Current milestone: independent note windows, drag/resize, local persistence and grid/list arrangement. iCloud sync and desktop-level attachment are subsequent milestones.

## Roadmap

- [x] Repository bootstrap
- [ ] M1: Native note windows
- [ ] M2: Grid/list layout
- [ ] M3: Persistence and crash recovery
- [ ] M4: Desktop/Spaces compatibility validation
- [ ] M5: CloudKit sync

## Local preview (macOS 14+, Xcode command line tools)

```sh
bash scripts/preview.sh
```

This builds `build/Stickies.app` without XcodeGen, downloads, iCloud, or signing credentials. It opens a welcome note on first launch. Edit the note, drag its title bar, resize a corner, and use the menu bar note icon for new notes, colors, grid/list arrangement and quit. Closing a note hides it; Show All Notes brings it back. Overflowing arrangements overlap within the current screen.

The preview script keeps notes in `build/preview-data/notes.json`, separate from normal app data. Quit and rerun the same script to verify text, color, visibility, window size and position restore. Do not run two instances against the same data directory. To launch the built bundle with normal Application Support storage, use `open build/Stickies.app`. Corrupt data is preserved and reported; saving is disabled for that run.

```sh
bash scripts/test-layout.sh
bash scripts/build-local.sh
```

Desktop-level/Spaces behavior and optional CloudKit sync remain future milestones. The repository currently contains no detailed PRD defining `display:both` or `layout:both`; this milestone uses the existing independent-window and grid/list behavior from PR #1.

On a logged-in Mac, `bash scripts/test-store.sh` additionally checks real AppKit window move callbacks and exact frame/text/color restoration in a second process. It uses a fresh temporary data directory and does not require Accessibility or iCloud permissions. CI runs geometry tests and both build paths; it does not claim to exercise interactive dragging.
