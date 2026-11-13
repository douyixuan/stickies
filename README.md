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

The CLI can be built separately; `build-app.sh` also bundles it at
`build/iStickies2.app/Contents/MacOS/istk`.
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
`version` prints JSON. This CLI reports version `1.0.1`, schema `10`; that is not an app build
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

## Roadmap evidence

[ROADMAP.md](ROADMAP.md) is the feature progress entry. Checkmarks apply only to
the named capability, not to every build or the complete original product.

- The user accepted basic Preview operation and confirmed text and positions
  survived normal quit/reopen. This supports the new/edit and save/reopen leaves;
  it does not close the [full Mac GUI pass](docs/QA.md).
- Daily 0.4.0 build 107 (source `f92d674ad06a`) was installed on 2026-11-08 after
  normal-exit confirmation, process/lock checks, full-profile backup restoration
  and old-app archive verification. The installation record retains archive
  hashes and a version/source deduplication key. Installation did not launch
  the app or migrate the profile; a real post-upgrade rollback remains untested.
- [CLI release CI](https://github.com/douyixuan/stickies/actions/runs/42389530538)
  exercised the extracted package against synthetic profiles.
  [Tap CI](https://github.com/douyixuan/homebrew-tap/actions/runs/42389854866)
  installed and tested CLI 1.0.0 on ARM64 macOS 26. A real version-to-version
  Homebrew upgrade has not yet been exercised. App installation is separate.
- [Backup tests](https://github.com/douyixuan/stickies/pull/52) and
  [historical-writer fixtures](https://github.com/douyixuan/stickies/pull/53)
  cover isolated whole-profile restore, failures and old-format compatibility.
  They do not establish GUI or power-loss acceptance.
- Canvas/search/workspace restoration, grouping, bulk deletion and sync retain
  their unresolved scope boundaries after the PR #31 rewrite. The roadmap does
  not authorize their implementation or declare the original requirements removed.
  Optional Canvas remains the recorded direction, not a mandatory startup screen.
