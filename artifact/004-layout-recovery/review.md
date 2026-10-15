# Collapse and layout recovery

Base: main 88ddcf3 (Canvas #5, main CI 38756603341 passed).

Implemented title double-click/menu collapse, 32pt compact title windows, Free/Grid/List/Compact and one-level durable Restore. layout.json contains only device-local collapsed IDs, arrangement mode and before-layout snapshots (IDs, frames, collapsed flags). No body/color/visibility is captured or overwritten. Grid/List expand; Compact folds; Free leaves geometry untouched. Restore retains edits, newly created notes and current visibility. Hidden notes are excluded from arrangements. Snapshot write must succeed before any frame change.

Independent read-only reviewer canvas_review found folded notes near a lower display edge jumped when restored using their expanded backing frame. Fixed show and Restore to constrain the rendered title before reconstructing the expanded frame. Added Compact→Grid→Restore regression with off-screen expanded backing frames. Independent temporary-source five-phase tests passed; no remaining static blocker reported.

Headless tests cover 50 notes/45 visible, negative-coordinate screen, collapse top anchoring, Grid/List/Compact/Free, retained text/color/visibility and new notes, separate-process restart/Restore, invalid layout preservation and failed snapshot writes. Additional note-write failure test verifies a successful snapshot remains recoverable on a fresh process. Two files are not a transaction: crash/write failure may leave presentation partially applied, but Restore's before-image remains durable. Errors are shown to the user; no cloud behavior is claimed.

No GUI was launched. Actual title double-click hit testing, title/controls at 32pt, native window callbacks, dragging/resizing and visible recovery require original QA task approval. These tests do not satisfy GUI acceptance. No real notes, credentials or security settings changed.
