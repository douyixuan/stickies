# iStickies2

Sticky notes that live on your macOS desktop. Independent windows you drag where you
want, one-click Grid/List tidying, and a window layer that keeps notes above or behind
everything else. Local files only — no accounts, no cloud, no network.

Requires macOS 14 or later.

## Use it

```sh
bash scripts/build-app.sh     # build/iStickies2.app — drag it to /Applications
```

The app is ad-hoc signed, not notarized, so the first launch needs right-click → **Open**.
Notes live in `~/Library/Application Support/Stickies`.

To try a change without touching your real notes:

```sh
bash scripts/preview.sh       # runs with its own notes in build/preview-data
```

## What it does

- **Notes.** New Note (⌘N), type in the window, pick one of four colors, drag the title
  bar to move, drag a corner to resize. Closing a note hides it; **Show All Notes**
  brings it back. The first line becomes the window title.
- **Fold.** Double-click the title bar to collapse a note to its title, and again to
  expand it at its old size.
- **Tidy.** Free / Grid / List / Compact (⌘⌥0–3), **Restore Previous Layout** (⌘⌥R) and
  **Undo Last Layout** (⌘⌥Z). Only visible notes take part. Overflow overlaps on screen
  instead of walking off it. Dragging snaps to the display edges, which you can turn off.
- **Layer.** Ordinary windows, **Desktop** (behind every app, on all Spaces) or
  **Floating** (above every app), globally or per note.
- **Trash.** **Move to Trash on This Mac** keeps the text, frame and color, and
  **Restore from Trash on This Mac** brings the note back.
- **Displays.** Notes left on a disconnected display are pulled back onto a live one.

Everything is per-Mac. There is no sync, by design.

## Command line

```sh
bash scripts/build-cli.sh
build/bin/istk --dir ~/Library/Application\ Support/Stickies list
```

`list`, `search <query>`, `get <id>` and `add [text]`, all JSON. It takes the same
exclusive lock the app does, so it refuses to write while the app is open rather than
racing it.

## How it is put together

| Layer | Where | Rule |
| --- | --- | --- |
| Core | `Stickies/Core` | Notes, layout geometry, files, preferences. No AppKit, no windows, no screens — so all of it is testable in a second. |
| App | `Stickies/App` | `NoteWindowManager` owns the windows and every decision that needs a display; SwiftUI views and menus sit on top. |
| CLI | `Tools/istk.swift` | Same core, same lock. |
| Tests | `Tests` | Plain assertions, one `swiftc` invocation, no window server. |

Two rules keep the data safe, both enforced in one place:

- **One writer per folder.** A second copy of the app, or the CLI while the app is open,
  takes the lock, fails, and goes read-only instead of overwriting.
- **A file we cannot read is never half-written.** Anything unparseable — corrupt, or
  from a newer version — makes the whole run read-only and says so in the menu and on
  the note. Older `notes.json` files (0.1, 0.2 and 0.3) are read and migrated forward.

A layout change writes `layout.json` before it moves anything, so the frames it replaced
are on disk before the first window moves and **Restore Previous Layout** still works if
the note write then fails.

## Develop

```sh
bash scripts/test.sh        # core suite: data, migration, layout, recovery
bash scripts/preview.sh     # run it
```

CI runs the core suite, compiles the app shell, builds the CLI and builds the app.

**CI cannot verify this app.** Dragging, folding, Spaces, layering and display changes
only exist on a real Mac with a real mouse, and no headless test will ever prove they
work. [`docs/QA.md`](docs/QA.md) is the ten-minute pass that does. Run it before you
trust a build.
