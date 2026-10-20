# istk command line

The delivery package contains `iStickies2.app/Contents/MacOS/istk`.
This CLI does not install a shell alias or change your PATH.
For a local build, run `bash scripts/build-cli.sh`, then use `build/bin/istk`.
Do not run the GUI executable as a command line tool.

## Select the data folder

Use `--data-dir PATH` or set `STICKIES_DATA_DIR`.
The CLI does not guess which app profile you want.
The normal delivery profile is `~/Library/Application Support/Stickies Delivery`.
An existing installation can use a different folder through its app metadata.
Use its exact data directory. Do not create a second profile by mistake.

Close the app normally before a data command.
Every data command takes the same exclusive `notes.lock` as the app.
If another process owns the lock, the command exits with code 75.
It does not wait, stop the app, remove the lock, or write around it.
The lock file remains after exit. Its presence alone does not mean the folder is locked.

## Commands

Examples below use a new test folder, not existing notes.

```sh
ISTK="/path/to/iStickies2.app/Contents/MacOS/istk"
"$ISTK" help
"$ISTK" version
"$ISTK" --data-dir /tmp/istk-test-profile add --text "Test note" --color 1
"$ISTK" --data-dir /tmp/istk-test-profile list
"$ISTK" --data-dir /tmp/istk-test-profile search "Test"
"$ISTK" --data-dir /tmp/istk-test-profile get FULL-UUID
printf 'New text\nSecond line\n' | "$ISTK" --data-dir /tmp/istk-test-profile edit FULL-UUID --stdin
"$ISTK" --data-dir /tmp/istk-test-profile delete FULL-UUID ANOTHER-UUID
"$ISTK" --data-dir /tmp/istk-test-profile list --trash
"$ISTK" --data-dir /tmp/istk-test-profile restore FULL-UUID ANOTHER-UUID
```

Use full UUIDs from command output. Duplicate IDs are rejected.
`add` accepts `--text` or `--stdin`, plus optional `--color` from 0 through 3.
`edit` requires at least one text or color option.
Stdin is UTF-8 plain text, limited to 8 MiB. Newlines remain intact.
`get`, `list`, and `search` accept `--trash` to read only trashed notes.
Search matches every query word, ignoring case and diacritics.
An empty query matches all notes in the selected view.

## Recoverable local deletion

`delete` moves the selected notes to this Mac's Trash.
It hides them from independent windows and the active manager list.
`restore` returns them to the active view. On app launch, their saved visibility applies.
There is no permanent-delete command.
The full note records stay in `notes.json`; `trash.json` stores local Trash membership.
A batch changes one metadata file atomically. Invalid IDs reject the whole batch.
A successful delete or restore does not change note text, colors, frames, or extension fields.
Back up the whole data directory, including `trash.json`.

Trash does not delete cloud records or remove sync membership.
Other Macs keep their copies. Existing sync can still update a locally trashed note.
Restore keeps the latest available content, including those updates.
If another device deletes the cloud note, use the existing sync recovery flow.
Local Trash is not a secure erase or an independent backup of cloud deletions.
The CLI never starts a cloud transport or enables sync.

## Output and errors

Success writes one JSON object to stdout:
`{"schemaVersion":1,"ok":true,"command":"list","data":[]}`.
Failure writes one JSON object to stderr, with `ok:false` and `error.code` / `error.message`.
No note text is printed in an error message.
`help` and `version` do not open a data directory.

| Exit code | Meaning |
| --- | --- |
| 0 | Success |
| 64 | Invalid command, option, ID, or input |
| 65 | Invalid data, unsupported schema, or unsafe file type |
| 66 | Missing directory or note |
| 74 | File or storage operation failed |
| 75 | Another process owns the data lock |

Tests use temporary data and a headless app-store probe.
They cover round trips, slow stdin, legacy/v2 extensions, concurrent processes, failure handling, and local Trash with sync identity preserved.
These tests do not establish GUI or real cloud acceptance.
