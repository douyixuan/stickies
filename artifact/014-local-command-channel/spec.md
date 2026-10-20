# Local command channel

A running compatible app owns `notes.lock` and handles CLI commands through its MainActor store.
An offline CLI uses the same command core under the exclusive lock.
The CLI requires an explicit profile and never starts the app or sync.

The profile contains a same-user AF_UNIX endpoint with mode 0600.
No credentials, network listener, system service, or permission change is required.
Unsafe directories and endpoint types are rejected.
The app removes a stale owned socket only while holding its data lock.

Frames contain a four-byte length followed by versioned JSON.
Frames are limited to 16 MiB; eight connections can be active.
A monotonic five-second deadline covers each complete read or write frame.
Connection establishment is nonblocking and bounded.
Incomplete frames never reach the store.

Mutation requests carry a stable UUID and use the existing durable journal and ledger.
Identical retries return the original result; changed payloads with that UUID fail.
The `result` command retrieves a recorded mutation after response loss or restart.
The CLI reports `outcome_unknown` when a complete request has no trustworthy response.
It does not retry automatically.

Normal app exit stops acceptance before the profile lock is released.
An interrupted commit recovers at the next exclusive startup.
App window presentation follows successful new add/restore commands and skips duplicate requests.
This presentation path requires separate authorized GUI acceptance.

The endpoint replaces the earlier proposed file queue and session marker.
The owned socket lifecycle rejects stale connections without an additional session file.
Process-crash recovery does not establish power-loss durability.
