# Stickies

Native macOS spatial sticky notes, built with SwiftUI and AppKit. Local-first, with iCloud sync planned.

## Development

The prototype uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate an Xcode project:

```sh
brew install xcodegen
xcodegen generate
open Stickies.xcodeproj
```

Requires a Mac with Xcode. Current milestone: independent note windows, drag/resize, local persistence and grid/list arrangement. iCloud sync remains a subsequent milestone; Desktop/Floating modes are implemented with GUI/Spaces acceptance still pending.

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

This builds `build/Stickies.app` without XcodeGen, downloads, iCloud, or signing credentials. It opens a welcome note on first launch. The preview process is named Stickies Preview to distinguish it from Apple’s built-in Stickies. Edit the note, drag its title bar, resize a corner, and use the menu bar note icon for new notes, colors, grid/list arrangement and quit. Closing a note hides it; Show All Notes brings it back. Overflowing arrangements overlap within the current screen.

The preview script keeps notes in `build/preview-data/notes.json`, separate from normal app data. Quit and rerun the same script to verify text, color, visibility, window size and position restore. `preview.sh` launches through macOS LaunchServices with the isolated data directory. The app locks its data directory; another instance using that directory reports the conflict and exits without writing. Opening `build/Stickies.app` directly also uses `build/preview-data`. The regular Xcode-built app uses Application Support. Corrupt data is preserved and reported; saving is disabled for that run.

```sh
bash scripts/test-layout.sh
bash scripts/build-local.sh
```

The recovered PRD V0.2 defines Desktop, Floating and Canvas presentation, with free dragging and one-click arrangement. This slice adds the Canvas browser/editor. GUI/Spaces validation remains follow-up work; optional CloudKit is not implemented.

On a logged-in Mac, `bash scripts/test-store.sh` additionally checks real AppKit window move callbacks and exact frame/text/color restoration in a second process. It uses a fresh temporary data directory and does not require Accessibility or iCloud permissions. CI runs geometry tests and both build paths; it does not claim to exercise interactive dragging.

The native **Notes** menu and each note’s **Note actions** menu provide New Note, Show All Notes, Hide, and Grid/List arrangement. The first text line becomes the window title. Closing a window hides its note without deleting text. Hidden notes remain hidden on launch; Show All Notes explicitly reopens them. **All Note Windows** selects Ordinary, Desktop (behind apps) or Floating (keep on top), and persists across launches. Desktop windows request all Spaces; actual Spaces behavior remains pending GUI QA. Long notes scroll in the native text editor.

The real UI check confirmed new/edit/long-text/close/reopen and the native Window → Zoom command, then quit/relaunch with both notes and exact stored frames unchanged. CUA corner-drag positioning remains unreliable; repeated title-drag calls sometimes returned success without changing the saved frame. Do not treat this as complete verification of mouse edge resizing or arbitrary mouse dragging.

The compact header keeps the native title-bar drag area and traffic-light controls. A subtle grip and two existing menus share that row; there is no separate toolbar above the text. The controls use 22pt-high accessories within the native title bar, whose system hit region stays larger. Text remains selectable, including when dragging across the editor. Native Notes menu shortcuts remain available.

## Canvas browser and editor

Open **Canvas** from the menu bar or Notes menu (**Shift-Command-0**). It lists every note, including hidden notes, with live multiword search (**Command-F**), color and visibility status. Select a row to edit the same note; edits also appear in its independent window. **New Note / Command-N** while Canvas is active creates and selects a hidden note in Canvas, without opening another window. **Show Window / Hide Window** changes only the selected note’s window visibility. Closing Canvas does not close or hide any notes.

Search matches all whitespace-separated words, ignoring case and accents. Editing a note so it no longer matches keeps the editor open with a message; changing the search clears a selection that no longer matches. Canvas is a single ordinary resizable window, independent of Keep Notes on Top. Switch List/Board to use either the searchable list or draggable spatial cards alongside the shared editor.

`bash scripts/test-canvas.sh` runs without opening windows and uses temporary data. It covers 50 notes (25 hidden), search, new hidden notes, edits, colors, unchanged existing frames/content and fresh-process restoration. GUI focus, shortcuts, close/reopen, actual editing and visibility interactions still require the existing authorized QA workflow; headless results do not establish GUI acceptance.

## Collapse and layout recovery

Double-click the native title bar/grip, or choose **Collapse Note / Expand Note** in a note's actions menu. A folded note keeps its title and controls; dragging it preserves the expanded size. Grid and List expand notes; Compact arranges 32pt folded title windows. **Free Layout** leaves positions alone so you can drag freely. Command-Option-0/1/2/3 select Free/Grid/List/Compact; Command-Option-R restores the previous arrangement.

Every arrangement first saves a device-local snapshot to `layout.json`. **Restore Previous Layout** restores frame and folded state only, including across app restarts, while preserving subsequent edits, colors, visibility and new notes. Only currently visible notes participate in an arrangement. A display change constrains restored visible frames to available screens. Overflow stays on screen and overlaps when there is insufficient room; Canvas remains available to browse every note.

The snapshot and notes file are separate atomic writes, not a transaction. A failed snapshot write prevents arrangement; if the later notes write fails, the saved before-image remains available for Restore. Corrupt or future-version layout data is preserved and layout-changing actions are disabled. `bash scripts/test-layout-store.sh` exercises isolated 50-note/restart/failed-write behavior without opening windows. Actual double-click/fold rendering remains pending GUI QA.


## Desktop and Floating

Use **All Note Windows** in the menu bar, Notes menu, note actions or Canvas's Window Layout menu. **Desktop — Behind Apps** places note windows above the desktop background/icons and below ordinary applications, requesting all Spaces. **Floating — Keep on Top** keeps notes above normal windows. **Ordinary Windows** retains conventional window behavior. Canvas always stays an ordinary resizable window for editing every note, even while independent note windows are hidden behind apps.

Modes are device-local in `preferences.json`; existing Keep Notes on Top preferences migrate automatically. Failed writes leave the previous mode active. `bash scripts/test-window-mode.sh` checks preferences, restart, constants and failure protection without windows. Actual click-through/occlusion, Spaces, fullscreen and Mission Control behavior are **not yet GUI-verified**.


## Canvas Board

Switch **List / Board** in Canvas. Click a card to edit it on the right; drag cards to organize them freely. **Arrange Board** offers Free/Grid/List/Compact and Restore Board. Unlike desktop arrangements, the scrollable board expands to keep all 20–50 cards accessible without overlapping its generated layouts. Hidden notes remain included.

Board positions are independent of desktop note frames and live in `canvas-layout.json`. Each arrangement commits its previous positions and resulting layout together. Restore retains notes created later. Search displays temporary result positions without modifying the board; clear the search to resume dragging/arranging. Failed writes leave the previous layout active, and corrupt data is preserved. `bash scripts/test-canvas-board.sh` covers 50 cards, restart/Restore and failure cases without windows. See `artifact/006-canvas-board/qa-handoff.md` for outstanding real-GUI acceptance across all slices.

## Delivery candidate

After committing a reviewed clean tree, run `bash scripts/package-delivery.sh` to create a universal app and ZIP under `build/releases`, with full commit metadata and SHA-256 checksums. This builds and ad-hoc signs only; it does not install, launch, notarize, or use signing credentials. The delivery app uses its own stable `Application Support/Stickies Delivery` profile across copies. See [launch, backup and rollback instructions](docs/DELIVERY.md).

`bash scripts/test-delivery-recovery.sh` exercises isolated failed-save retry, corrupt/future data preservation, concurrent lock exclusion, and restart after terminating only its own test process. Normal quit retries unsaved note changes and asks to keep editing if saving still fails. The dialog and installation remain subject to authorized GUI QA. See [independent review boundaries](artifact/007-delivery/review.md).
