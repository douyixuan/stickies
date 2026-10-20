# iStickies2

Native macOS spatial sticky notes, built with SwiftUI and AppKit. Local-first, with optional folder sync and a CloudKit adapter. Real cloud and two-device acceptance remain pending.

## Development

The prototype uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate an Xcode project:

```sh
brew install xcodegen
xcodegen generate
open Stickies.xcodeproj
```

Requires a Mac with Xcode. Independent windows, Canvas, layout recovery, local persistence, local Trash, and a live CLI channel are implemented. GUI/Spaces and real cloud acceptance remain pending.

## Implementation and acceptance status

- [x] Repository bootstrap
- [x] M1: Native note window implementation (current GUI gestures still require QA)
- [x] M2: Free/Grid/List/Compact/Restore implementation and isolated tests
- [x] M3: Local persistence and process-crash recovery tests
- [ ] M4: Real Desktop/Spaces, Stage Manager, and display attach/detach acceptance
- [ ] M5: Real CloudKit signing/container and two-device acceptance; adapter and folder-sync code exist

## Local preview (macOS 14+, Xcode command line tools)

```sh
bash scripts/preview.sh
```

The preview command explicitly builds `build/preview.noindex/iStickies2 Preview.app` without XcodeGen, downloads, iCloud, or signing credentials. It opens a welcome note on first launch. The preview process is named iStickies2 Preview to distinguish it from Apple’s built-in Stickies. Edit the note, drag its title bar, resize a corner, and use the menu bar note icon for new notes, colors, grid/list arrangement and quit. Closing a note hides it; Show All Notes brings it back. Overflowing arrangements overlap within the current screen.

The preview script keeps notes in `build/preview-data/notes.json`, separate from normal app data. Quit and rerun the same script to verify text, color, visibility, window size and position restore. `preview.sh` launches through macOS LaunchServices with the isolated data directory. The app locks its data directory; another instance using that directory reports the conflict and exits without writing. Opening the explicit preview app directly also uses `build/preview-data`. The regular Xcode-built app uses Application Support. Corrupt data is preserved and reported; saving is disabled for that run.

```sh
bash scripts/test-layout.sh
bash scripts/build-local.sh
```

The recovered PRD V0.2 defines Desktop, Floating and Canvas presentation, with free dragging and one-click arrangement. Canvas, per-note Floating overrides, and local Trash are implemented. Current GUI acceptance remains incomplete; CloudKit adapter code is not proof of real CloudKit operation.

`bash scripts/test-store.sh` compiles the GUI harness without launching it. The separate `--run-gui` route requires the existing QA workflow approval and uses a guarded temporary profile. CI compiles the harness and tests its isolation guard; it does not exercise interactive dragging.

The native **Notes** menu and each note’s **Note actions** menu provide New Note, Show All Notes, Hide, and Grid/List arrangement. The first text line becomes the window title. Closing a window hides its note without deleting text. Hidden notes remain hidden on launch; Show All Notes explicitly reopens them. **Default Note Window Mode** selects Ordinary, Desktop (behind apps) or Floating (keep on top), and persists across launches. Single-note overrides take precedence. Desktop windows request all Spaces; actual Spaces behavior remains pending GUI QA. Long notes scroll in the native text editor.

Historical prototype UI checks confirmed new/edit/long-text/close/reopen and the native Window → Zoom command, then quit/relaunch with both notes and exact stored frames unchanged. CUA corner-drag positioning remains unreliable; repeated title-drag calls sometimes returned success without changing the saved frame. Do not treat this as complete verification of mouse edge resizing or arbitrary mouse dragging.

The compact header keeps the native title-bar drag area and traffic-light controls. A subtle grip, an actions menu, and a settings button share that row; there is no separate toolbar above the text. The controls use 22pt-high accessories within the native title bar, whose system hit region stays larger. Text remains selectable, including when dragging across the editor. Native Notes menu shortcuts remain available.

## Canvas browser and editor

Open **Canvas** from the menu bar or Notes menu (**Shift-Command-0**). It lists every note, including hidden notes, with live multiword search (**Command-F**), color and visibility status. Select a row to edit the same note; edits also appear in its independent window. **New Note / Command-N** while Canvas is active creates and selects a hidden note in Canvas, without opening another window. **Show Window / Hide Window** changes only the selected note’s window visibility. Closing Canvas does not close or hide any notes.

Search matches all whitespace-separated words, ignoring case and accents. Editing a note so it no longer matches keeps the editor open with a message; changing the search clears a selection that no longer matches. Canvas is a single ordinary resizable window, independent of Keep Notes on Top. Switch List/Board to use either the searchable list or draggable spatial cards alongside the shared editor.

`bash scripts/test-canvas.sh` runs without opening windows and uses temporary data. It covers 50 notes (25 hidden), search, new hidden notes, edits, colors, unchanged existing frames/content and fresh-process restoration. GUI focus, shortcuts, close/reopen, actual editing and visibility interactions still require the existing authorized QA workflow; headless results do not establish GUI acceptance.

## Collapse and layout recovery

Double-click the native title bar/grip, or choose **Collapse Note / Expand Note** in a note's actions menu. A folded note keeps its title and controls; dragging it preserves the expanded size. Grid and List expand notes; Compact arranges 32pt folded title windows. **Free Layout** leaves positions alone so you can drag freely. Command-Option-0/1/2/3 select Free/Grid/List/Compact; Command-Option-R restores the previous arrangement.

Every arrangement first saves a device-local snapshot to `layout.json`. **Restore Previous Layout** restores frame and folded state only, including across app restarts, while preserving subsequent edits, colors, visibility and new notes. Only currently visible notes participate in an arrangement. A display change constrains restored visible frames to available screens. Overflow stays on screen and overlaps when there is insufficient room; Canvas remains available to browse every note.

The snapshot and notes file are separate atomic writes, not a transaction. A failed snapshot write prevents arrangement; if the later notes write fails, the saved before-image remains available for Restore. Corrupt or future-version layout data is preserved and layout-changing actions are disabled. `bash scripts/test-layout-store.sh` exercises isolated 50-note/restart/failed-write behavior without opening windows. Actual double-click/fold rendering remains pending GUI QA.


## Desktop and Floating

Use **Default Note Window Mode** in the menu bar, Notes menu, note actions or Canvas's Window Layout menu. **Desktop — Behind Apps** places note windows above the desktop background/icons and below ordinary applications, requesting all Spaces. **Floating — Keep on Top** keeps notes above normal windows. **Ordinary Windows** retains conventional window behavior. Canvas always stays an ordinary resizable window for editing every note, even while independent note windows are hidden behind apps.

Modes and per-note Floating overrides are device-local in `preferences.json`; existing Keep Notes on Top preferences migrate automatically. A note can explicitly stay on top or stay below the global Floating default. Reset it with **Use Global Window Default**. Changing the global default preserves explicit overrides. Failed writes leave the previous mode active. `bash scripts/test-window-mode.sh` checks preferences, restart, constants and failure protection without windows. Actual click-through/occlusion, Spaces, fullscreen, Stage Manager, display attach/detach, and Mission Control behavior are **not yet GUI-verified**.


## Single-note actions and local Trash

The note body and title controls have a context menu for color, per-note keep-on-top, and **Move to Trash on This Mac**.
The title action menu provides the same commands. Closing a window still only hides the note.
**Restore from Trash on This Mac**, available from the app menus, restores one selected note and opens its window.
Deletion preserves content, frame, color, local pin, and sync identity. It does not delete cloud records.
New remote content can still update a trashed note; restore keeps that newer content.
Unsaved edits must save before deletion. A failed save leaves the note active.

`bash scripts/test-single-note-actions.sh` tests migration, restart, failed writes, unsaved edits, deletion/restore, and local pin isolation without windows.
The text editor's actual context-menu routing and preservation of native text actions still require GUI QA.
UI multiselection remains undecided and is not implemented by these single-note commands.


## Canvas Board

Switch **List / Board** in Canvas. Click a card to edit it on the right; drag cards to organize them freely. **Arrange Board** offers Free/Grid/List/Compact and Restore Board. Unlike desktop arrangements, the scrollable board expands to keep all 20–50 cards accessible without overlapping its generated layouts. Hidden notes remain included.

Board positions are independent of desktop note frames and live in `canvas-layout.json`. Each arrangement commits its previous positions and resulting layout together. Restore retains notes created later. Search displays temporary result positions without modifying the board; clear the search to resume dragging/arranging. Failed writes leave the previous layout active, and corrupt data is preserved. `bash scripts/test-canvas-board.sh` covers 50 cards, restart/Restore and failure cases without windows. See `artifact/006-canvas-board/qa-handoff.md` for outstanding real-GUI acceptance across all slices.

## Delivery candidate

After committing a reviewed clean tree, run `bash scripts/package-delivery.sh` to create a ZIP containing one `iStickies2.app` under `build/releases`, with full commit metadata and SHA-256 checksums. This builds and ad-hoc signs only; it does not install, launch, notarize, or use signing credentials. The delivery app uses its own stable `Application Support/Stickies Delivery` profile across copies. See [launch, backup and rollback instructions](docs/DELIVERY.md).

`bash scripts/test-delivery-recovery.sh` exercises isolated failed-save retry, corrupt/future data preservation, concurrent lock exclusion, and restart after terminating only its own test process. Normal quit retries unsaved note changes and asks to keep editing if saving still fails. The dialog and installation remain subject to authorized GUI QA. See [independent review boundaries](artifact/007-delivery/review.md).


## App identity and launcher hygiene

The user-facing app is **iStickies2**, with a bundled multi-resolution icon distinct from Apple's Stickies. Existing bundle IDs and data directories are intentionally retained. A new name does not migrate your notes.

`build-local.sh` now compiles only a binary; it does not create a discoverable app. Do not run that bare binary: it has no preview bundle identity. Use the explicit preview script for isolated development. `preview.sh` is the explicit opt-in to build and launch a developer preview, preserving `build/preview-data`. Release staging uses a non-`.app` payload in a private `.noindex` directory and retains only ZIP/checksum artifacts. Packaging does not install, launch, unregister apps or clean existing copies. `.noindex` is not a guarantee about third-party launcher caches. See [the reversible cleanup and switch plan](docs/LAUNCHER-CLEANUP.md).

The icon source is `Assets/iStickies2.png`; `scripts/build-icon.sh` regenerates the checked-in ICNS at 16–1024 pixels. `verify-delivery.py` validates archived metadata, icon representations, hashes, executable permissions and universal signature without producing a discoverable `.app` or launching anything.


## CLI development candidate

`bash scripts/build-cli.sh` builds `build/bin/istk` without opening the app.
The CLI supports JSON help/version, list/get/search, add/edit, and recoverable local delete/restore.
All data commands require an explicit directory. A compatible running app serializes requests through its live store.
Otherwise, the CLI requires the exclusive data lock. The CLI never enables sync.
Explicit offline `migrate-ledger` upgrades a selected profile to schema 3, retaining request history beyond 4096 results. Older clients then reject that profile; migration is never automatic.
See [CLI commands, local Trash semantics, and exit codes](docs/CLI.md).
This development candidate is not installed and does not establish full product acceptance.


## Integration evidence

PRs #16, #17, #18, and #19 passed CI at their recorded heads.
Their combined commit `d4e48f8ebdfee3da4446b23970f7d3d9e447c1af` passed [the full integration CI](https://github.com/douyixuan/stickies/actions/runs/39399721540).
That evidence predates [the single-note interaction slice, PR #20](https://github.com/douyixuan/stickies/pull/20).
Use [PR #20 head checks](https://github.com/douyixuan/stickies/pull/20/checks) for its current CI status.
Local independent reviews are separate from CodeRabbit, which skipped draft reviews.
No candidate CI result establishes final main acceptance, GUI acceptance, or installation approval.
