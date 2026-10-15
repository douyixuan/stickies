# Optional sync foundation (2026-10-15)

This change is a local model/persistence prerequisite for M5, not a CloudKit client.
No account, network access, signing, or sync toggle is needed for local use.

## Data boundary

| Data | Scope | Reason |
| --- | --- | --- |
| Stable UUID, text, color | `NoteContent`, eligible for future sync | Identity and authored note appearance/content |
| Frame (origin and size), visibility | `NoteLocalState`, this Mac only | Monitor geometry and window lifecycle are device-specific |
| Keep on top | Existing local `preferences.json` | Window behavior; no verified requirement to sync it |
| Array ordering | Local snapshot | No cross-device ordering contract yet |

`StickyNote` is an in-memory UI projection with separate content and local members.
It is deliberately not Codable. Future transport must encode `NoteContent` only;
never upload `notes.json` or place the app data directory in iCloud Drive.
Color is included as authored note appearance; changing that policy later is isolated
to the content boundary. Visibility/keep-on-top are not claimed to be user-approved
cross-device preferences.

## Persistence and migration

`notes.json` v2 contains `schemaVersion: 2`, ordered `contents`, and `localStates`
keyed by UUID. These logically separate partitions share a single atomic file write
to avoid a two-file partial commit. The existing lifetime `notes.lock` is retained.
There must be exactly one local entry per content ID; invalid/duplicate IDs fail closed.

On opening a legacy array, decode and validate the entire file, save the exact bytes
to `notes.json.legacy-v1.bak`, then atomically replace `notes.json` with v2. IDs,
Unicode text, colors, order, hidden state and raw frames survive unchanged. Existing
screen-clamping still happens when a window is shown. Preferences are untouched.
An identical existing backup permits retry after interruption; a different/unreadable
backup blocks migration without replacing the source. Corrupt or unknown-version
files disable saving through NoteStore's existing error path. Empty arrays remain empty
at the codec level; the existing app welcome-note behavior is unchanged.

Old binaries cannot read v2. To roll back, quit all instances, preserve the current
v2 file separately and restore the legacy backup to `notes.json`; this restores only
the pre-migration snapshot, not edits made since migration. Do not delete the backup
automatically.

## Conflict policy and limits

The pure three-way merge requires an actual common ancestor plus local and remote
content of the same UUID. Changes to different fields merge; equal edits are idempotent.
Different edits to the same field return an explicit conflict without mutating the
note or its device layout. Text is a single field, not a character-level CRDT.
There are no clocks, invented revision counters, or silent last-writer wins.

This helper is tested but intentionally has no remote ingestion/UI path yet. The
future transport must retain ancestor/server change tags and both conflicting versions,
persist its retry/conflict queue before acknowledging events, and offer resolution.
It must also define initial import, opt-in/off, account switching, new-note placement,
deletion/tombstones and recovery before being presented as working sync. Never apply
the three-way helper against a guessed ancestor. New remote notes must acquire local
placement on the receiving Mac; another device's frame is never an input.

## Repeatable verification

`bash scripts/test-model.sh` runs Foundation model tests plus headless NoteStore
integration on macOS. CI runs this alongside geometry tests and both build paths.
Coverage: v1 literal fixture, hidden/negative-position notes, v2 round-trip, backup
idempotency and failure, corrupt/future/inconsistent files, duplicate IDs, content
updates, independent device frames/visibility, export keys, disjoint/equal edits,
text/color conflicts and identity mismatch. `bash scripts/test-store.sh` retains the
separate logged-in Mac window restoration/file-lock smoke test; it is not a cloud test.

The implementation workspace has no Swift/Xcode; the macOS Actions result is the
compiler/test evidence. Interactive window smoke tests and real CloudKit tests must
be recorded separately from these deterministic local tests.

## Real CloudKit verification gate (still open)

Repository evidence: `project.yml` has `CODE_SIGNING_ALLOWED: NO`; no CloudKit
entitlements, container configuration or cloud transport is present. The user's
developer membership, team permissions, certificates and devices are not accessible
here and have not been verified.

Apple's [setup guide](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
and [SyncEngine sample](https://github.com/apple/sample-cloudkit-sync-engine) require
an active developer membership, a container and signed device builds. Before M5:

1. Verify developer team access; configure the app ID, iCloud/CloudKit container,
   entitlements and signing profile; inspect the signed app's entitlements.
2. Verify private database access and account status on two signed-in Macs against
   the same development container. Keep production deployment a separate gate.
3. Verify opt-in/off and offline local editing, reconnect/relaunch/retry, concurrent
   same-note edits, account logout/switch and error recovery without data loss.
4. Use different monitor configurations and local visibility/keep-on-top settings;
   confirm only content converges. Record app commit, OS/builds, container environment,
   actions and outcomes, with account details redacted.

Passing model simulations/build CI cannot close any of these real-cloud gates.
