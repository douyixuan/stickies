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
- [ ] M5: CloudKit sync (local model separation and v1 migration implemented; real CloudKit still pending)

## Local preview (macOS 14+, Xcode command line tools)

```sh
bash scripts/preview.sh
```

This builds `build/Stickies.app` without XcodeGen, downloads, iCloud, or signing credentials. It opens a welcome note on first launch. The preview process is named Stickies Preview to distinguish it from Apple’s built-in Stickies. Edit the note, drag its title bar, resize a corner, and use the menu bar note icon for new notes, colors, grid/list arrangement and quit. Closing a note hides it; Show All Notes brings it back. Overflowing arrangements overlap within the current screen.

The preview script keeps notes in `build/preview-data/notes.json`, separate from normal app data. Quit and rerun the same script to verify text, color, visibility, window size and position restore. `preview.sh` launches through macOS LaunchServices with the isolated data directory. The app locks its data directory; another instance using that directory reports the conflict and exits without writing. Opening `build/Stickies.app` directly also uses `build/preview-data`. The regular Xcode-built app uses Application Support. Corrupt data is preserved and reported; saving is disabled for that run.

```sh
bash scripts/test-layout.sh
bash scripts/build-local.sh
```

Desktop-level/Spaces behavior and optional CloudKit sync remain future milestones. The repository currently contains no detailed PRD defining `display:both` or `layout:both`; this milestone uses the existing independent-window and grid/list behavior from PR #1.

On a logged-in Mac, `bash scripts/test-store.sh` additionally checks real AppKit window move callbacks and exact frame/text/color restoration in a second process. It uses a fresh temporary data directory and does not require Accessibility or iCloud permissions. CI runs geometry tests and both build paths; it does not claim to exercise interactive dragging.

The native **Notes** menu and each note’s **Note actions** menu provide New Note, Show All Notes, Hide, and Grid/List arrangement. The first text line becomes the window title. Closing a window hides its note without deleting text. Hidden notes remain hidden across launches until Show All Notes is used. **Keep Notes on Top** switches between ordinary windows and floating windows and persists across launches; it does not implement desktop-level or all-Spaces attachment. Long notes scroll in the native text editor.

The real UI check confirmed new/edit/long-text/close/reopen and the native Window → Zoom command, then quit/relaunch with both notes and exact stored frames unchanged. CUA corner-drag positioning remains unreliable; repeated title-drag calls sometimes returned success without changing the saved frame. Do not treat this as complete verification of mouse edge resizing or arbitrary mouse dragging.

The compact header keeps the native title-bar drag area and traffic-light controls. A subtle grip and two existing menus share that row; there is no separate toolbar above the text. The controls use 22pt-high accessories within the native title bar, whose system hit region stays larger. Text remains selectable, including when dragging across the editor. Native Notes menu shortcuts remain available.


## Sync data foundation

Note content (`id`, `text`, `color`) is separated from device-local frame/visibility.
The local versioned `notes.json` atomically stores both partitions; legacy arrays migrate
with an exact `notes.json.legacy-v1.bak` backup. Keep-on-top remains local.
Run `bash scripts/test-model.sh` for migration, isolation, conflict and store integration tests.
See [sync foundation and CloudKit verification gates](docs/SYNC-FOUNDATION.md).
This does not enable cloud sync or require an iCloud account.
