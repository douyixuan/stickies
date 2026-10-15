# Delivery recovery review

Independent reviewer reproduced a lost-edit risk on normal quit after a failed save. The fix retries pending note changes on quit and defaults to Keep Editing if persistence still fails; discarding requires an explicit GUI choice.

Headless verification passes: failed-write retry and fresh-process reload; corrupt/future data preservation; concurrent process exclusion across notes, layout, Canvas layout and preferences; SIGKILL of only the isolated test process after completed writes and subsequent lock/recovery; hide retains body; stable delivery data location across app copies. SIGKILL tests do not simulate power failure during an atomic write.

Independent review also compiled the complete source and ran the recovery suite. A separate legacy probe compiled commit 23f4443, read current schema-v1 data, edited a test body, then reloaded with current code: body survived and all three sidecars remained byte-identical. This does not establish schema-v2 rollback compatibility with PR #4.

Delivery uses a dedicated bundle ID and Application Support/Stickies Delivery, preserving production and preview profiles. Packaging creates a universal arm64/x86_64 app with version, full commit and checksums, ad-hoc signed without credentials. Packaging never launches or installs the app. Developer ID signing and notarization are not provided.

Pending acceptance: all real GUI interactions, save-failure quit dialog, LaunchServices installation/relocation, permissions, window layering/Spaces, keyboard focus and Intel execution. The existing QA workflow owns these checks. Duplicate-note-ID validation belongs to PR #4's persistence foundation and remains an integration dependency; do not claim all malformed v1 payloads are validated.
