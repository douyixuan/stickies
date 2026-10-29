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

The CLI is a separate build; `build-app.sh` does not bundle it in the app.
With the macOS command-line developer tools installed, run these commands from
this checkout. Nothing is installed in PATH or added to your shell configuration.

```sh
bash scripts/build-cli.sh
build/bin/istk help
build/bin/istk version
profile="$(mktemp -d -t istk-demo)"
build/bin/istk --dir "$profile" add 'Example note'
build/bin/istk --dir "$profile" list
build/bin/istk --dir "$profile" search 'Example'
# Copy the returned id into this command:
build/bin/istk --dir "$profile" get '<id>'
```

Each invocation is a new process. Repeating `list` or `get` reads the saved notes
from the same temporary directory. `add` without text reads UTF-8 from stdin,
including multiple lines. The executable remains at `build/bin/istk`; use that
path (or its absolute equivalent), not a bare `istk` command.

The data commands are `list`, `search <query>`, `get <id>` and `add [text]`;
their successful responses are JSON. `help` prints plain-text usage, while
`version` prints JSON. This CLI reports version `1.0`, schema `10`; that is not an app build
number or commit identifier. It uses `--dir`, whereas the older 0.3 CLI bundled
in 0.3.105 uses `--data-dir` and has a different command contract. Do not
interchange the examples or binaries.

It takes the app's exclusive lock: reads remain available while the app owns the
folder, but writes are refused. An incompletely readable profile fails rather
than returning partial results. These examples use synthetic data only.

Older profiles can be read without rewriting notes, but the first successful
note write converts them to schema 10. The 0.3 CLI cannot read that format.
Before any real upgrade, keep a verified complete, quiescent profile backup;
rollback requires restoring that profile as well as the old app. Preserve newer
edits separately before rollback. A pending old command journal must be resolved
by the old version, not deleted or bypassed.

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
  The one exception is a 0.3 command-line change that was interrupted halfway: its
  `command-journal.json` blocks writing until 0.3 is opened once to finish it.

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
