# Canvas slice review and verification

Base: main 4b8a6b7. Independent checkout in task-4; no other task checkout modified.

Scope: one ordinary Canvas window, all-note list including hidden notes, multiword search, shared editor/color updates, explicit window visibility, hidden new notes and selected editor. No persistence schema or sync implementation changes. Canvas arrangement/card dragging, collapse and layout snapshots remain separate slices.

Independent reviewer: canvas_review (read-only agent). Reviewed window lifecycle, data mutations, search/selection, commands and PR #4 interfaces. Found duplicated Canvas/global Command-N handling; fixed through one active-window route. Search edits now explicitly explain a selected note that no longer matches. Reviewer independently compiled a temporary source copy and ran headless Canvas tests successfully. Found that initial tests required StickyNote Codable (incompatible with PR #4); replaced with independent legacy fixtures and fresh-process NoteStore restoration checks.

Validation: build-local.sh, test-layout.sh and test-canvas.sh on macOS. No app launch, GUI automation, real notes access, credential or permission changes. Original GUI/file-lock/installation QA remains owned by task 01a13e46-f46f-706f-a8e6-298c88efd00c; its approval is not bypassed.

GUI acceptance pending: open Canvas via menu and Shift-Command-0; Command-F focus; select/edit a hidden and visible note; verify the latter's open window updates; Command-N must create a selected hidden note in Canvas; Show/Hide Window must affect only that note; close/reopen/minimize/restore Canvas; verify window sizes and actual keyboard routing. Use isolated data with 20–50 notes, never real notes.

PR #4 remains owned by its original workflow. The UI uses its compatible projection API. The initial integration simulation found PR #4’s explicit headless build source list did not include Canvas. Removed the optional per-note Canvas menu entry so existing NoteView/store test targets remain independent of Canvas; the menu bar and native Notes menu still open Canvas. This also removes the test-store.sh merge conflict. No PR #4 merge is performed by this task.

Final independent follow-up review confirmed the fixture/fresh-process tests solve StickyNote Codable compatibility.

Final integration rehearsal: Canvas code b9a18bf plus PR #4 369e65b, generated via git merge-tree and archived to /tmp/stickies-canvas-final.fgq10f. No branches or real data changed. Only README has conflict markers; all Swift/CI sources auto-merged. In that temporary tree, test-canvas.sh (including fresh process), test-model.sh (model plus headless NoteStore), test-layout.sh and build-local.sh all passed. No GUI/file-lock smoke was run. Integration owner should resolve README by retaining both sync-foundation documentation and Canvas usage/limitations.
