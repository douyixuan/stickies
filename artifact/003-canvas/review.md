# Canvas slice review and verification

Base: main 4b8a6b7. Independent checkout in task-4; no other task checkout modified.

Scope: one ordinary Canvas window, all-note list including hidden notes, multiword search, shared editor/color updates, explicit window visibility, hidden new notes and selected editor. No persistence schema or sync implementation changes. Canvas arrangement/card dragging, collapse and layout snapshots remain separate slices.

Independent reviewer: canvas_review (read-only agent). Reviewed window lifecycle, data mutations, search/selection, commands and PR #4 interfaces. Found duplicated Canvas/global Command-N handling; fixed through one active-window route. Search edits now explicitly explain a selected note that no longer matches. Reviewer independently compiled a temporary source copy and ran headless Canvas tests successfully. Found that initial tests required StickyNote Codable (incompatible with PR #4); replaced with independent legacy fixtures and fresh-process NoteStore restoration checks.

Validation: build-local.sh, test-layout.sh and test-canvas.sh on macOS. No app launch, GUI automation, real notes access, credential or permission changes. Original GUI/file-lock/installation QA remains owned by task 01a13e46-f46f-706f-a8e6-298c88efd00c; its approval is not bypassed.

GUI acceptance pending: open Canvas via menu and Shift-Command-0; Command-F focus; select/edit a hidden and visible note; verify the latter's open window updates; Command-N must create a selected hidden note in Canvas; Show/Hide Window must affect only that note; close/reopen/minimize/restore Canvas; verify window sizes and actual keyboard routing. Use isolated data with 20–50 notes, never real notes.

PR #4 remains owned by its original workflow. The UI uses its compatible projection API. Integration must preserve both workflows' build/test additions and include all non-App Swift sources in test-store.sh; no PR #4 merge is performed by this task.
