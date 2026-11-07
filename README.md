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
exclusive lock the app does, so it reads while the app is open but refuses to write
rather than racing it. A profile it cannot fully read fails every command instead of
answering with what it happened to load.

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

## CLI distribution preparation

CI retains a standalone `istk` ZIP with a manifest and usage instructions alongside
the App candidate. These archives are candidates, not stable Homebrew releases.
The independent [CLI 1.0.0 release](https://github.com/douyixuan/stickies/releases/tag/cli-v1.0.0)
is available for Apple Silicon through the [Homebrew tap](https://github.com/douyixuan/homebrew-tap):

```sh
brew install douyixuan/tap/istk
brew update && brew upgrade douyixuan/tap/istk
```

This installs only the CLI, not the GUI App. Every data command requires an explicit
`--dir`. Use a new synthetic directory first. The tap CI verifies installation and
isolated create/read/search; it does not operate on daily notes. See the release
for exact source, checksums, tested host and ad-hoc signature boundaries.

`scripts/prepare-cli-formula.py` prepares a formula only **after** an independently
accepted CLI release exists. It performs read-only network checks and never publishes,
installs, changes PATH, launches an App or opens a note profile. It refuses candidates,
draft/prerelease assets, wrong source/CI, mismatched hashes and unsupported architectures.
The generated formula includes an isolated create/read/search test.

The release contract is an exact `cli-vMAJOR.MINOR.PATCH` tag and uploaded assets
`istk-MAJOR.MINOR.PATCH-macos-arm64.zip` plus `verification.json`. Both must have GitHub
SHA-256 digests. The report must identify the successful exact-source repository CI
via `ciRunID`, and the verified archive and executable hashes via `standaloneCLI`.
The ZIP contains only `istk`, `manifest.json`, and `USAGE.txt`; its manifest must record
`releaseVersion`, `candidateOnly: false`, source/hash, ARM64, macOS 14 and schema 10.
The App candidate does not satisfy this stable-release contract. CI separately builds
versioned CLI release assets from the explicit CLI source version, verifies the final
ZIP using isolated profiles, and retains them without publishing. The generator
cannot approve or relabel an App candidate into a release.

After those release requirements are met, run the generator with the actual tag and
an unused formula output path, then review and test the result in the intended tap.
For subsequent versions, source versioning, exact main CI, release upload and tap
verification remain separate steps. CLI acceptance does not imply GUI or App upgrade acceptance.
