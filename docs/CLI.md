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

The CLI first tries the same exclusive `notes.lock` as the app.
If a compatible app owns the lock, requests use its local `istk.sock` endpoint.
The app serializes commands through its live store, including unsaved reads.
Mutations require a successful save before acceptance.
If the endpoint is unavailable, the command exits with code 75.
For an older app, close it normally before the command.
The CLI does not stop the app, remove the lock, or write around it.
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

## Request results and retries

Each output includes a `requestID`. Use `--request-id UUID` to supply a stable ID.
For a mutation retry, preserve the ID and all original parameters.
The same ID and parameters return the original result without repeating the mutation.
Changed parameters with an existing ID fail with code 64.
Use `istk --data-dir PATH result REQUEST-UUID` to query a recorded mutation.
Read commands do not create ledger records.

If a response is lost or times out, code 74 with `outcome_unknown` means the mutation might have committed.
Query the result or retry with the same ID. The CLI does not retry automatically.
Results survive normal exit and process crashes through the command journal.
An unmigrated profile keeps 4096 mutation results without eviction. A full ledger rejects new mutations with code 75.

For an explicit offline upgrade, close every app using the selected profile normally, back up the entire folder, and run:

```sh
istk --data-dir /path/to/profile migrate-ledger
```

This command upgrades `notes.json` to schema 3 and retains every request fingerprint and original result. Old app and CLI versions cannot read or write this profile. There is no automatic migration or downgrade. The command does not route through a running app; a held lock returns 75.

Migration stages immutable segments and publishes their inventory inside `notes.json` in one atomic replacement. A process interruption before publication leaves the old profile authoritative; interruption after publication leaves the complete new inventory authoritative. Retrying migration is safe. The original `command-results.json` remains untouched, but is no longer authoritative after migration. Never replace schema 3 notes with that stale ledger or delete segment files.

Schema 3 removes the fixed 4096-record limit. Segments contain at most 128 results and 16 MiB. Each mutation retains all prior results and publishes a new inventory through a journal bound to the profile and previous generation. A missing notes inventory with retained history, or missing, altered, or duplicate segment records, stops writes. Individual oversized results, disk exhaustion, and the complete encoded journal limit of 64 MiB can still stop mutations. Validation currently reads all referenced history into memory: time and memory grow with history. Superseded immutable files are retained; no compaction or eviction is implemented. Recovery is tested for process crashes, not sudden power loss.
Back up the whole profile, including command journal and ledger files.
These guarantees do not establish power-loss durability.

The endpoint uses a same-user Unix socket, with mode 0600 and no network port.
The profile must belong to the current user and reject group or other-user writes.
A profile path must fit the macOS Unix socket path limit of 104 bytes, including the endpoint and terminator.
Each frame has a 16 MiB limit and a five-second absolute deadline for reading or writing.
The server accepts at most eight concurrent connections. Saturated connections can lose their response.

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
`{"schemaVersion":1,"ok":true,"command":"list","requestID":"UUID","data":[]}`.
Failure writes one JSON object to stderr, with `ok:false` and `error.code` / `error.message`.
No note text is printed in an error message.
`help` and `version` do not open a data directory.

| Exit code | Meaning |
| --- | --- |
| 0 | Success |
| 64 | Invalid command, option, ID, or input |
| 65 | Invalid data, unsupported schema, or unsafe file type |
| 66 | Missing directory, note, or recorded request |
| 74 | Storage/transport failure, including an unknown mutation outcome |
| 75 | Unavailable owner, pending recovery, or full request ledger |

Tests use temporary data and a headless app-store probe.
They cover round trips, slow stdin, legacy/v2 extensions, concurrent processes, failure handling, and local Trash with sync identity preserved.
These tests do not establish GUI or real cloud acceptance.
