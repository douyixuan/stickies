# Canvas board

List/Board switch adds spatial cards for all notes including hidden notes. Cards select the shared editor and drag independently of desktop windows. Arrange Board offers Free/Grid/List/Compact/Restore. canvas-layout.json stores only device-local card positions, mode and one before-image, committed together atomically. Restore preserves notes created later. Search uses temporary compacted result positions and cannot drag/arrange or initialize persisted positions until search clears.

Independent reviewer canvas_review verified data boundaries, atomic commit, Restore/new-entry handling and permissions. Found search onAppear/ID changes initialized missing persisted positions; fixed to skip while searching and initialize when search clears. Added missing-entry before-images before Arrange so a newly rendered fallback card can be restored. Reviewer confirmed fixes without further static blockers.

Independent temporary-source four-phase board tests and full compilation passed. Tests cover 50 cards, nonoverlapping initial positions, Grid/List/Compact/Restore, clamp and free movement, fresh-process restore, post-arrangement note creation, corrupt file preservation and failed-write state preservation. Notes bytes remain unchanged by board operations, including after Restore. Duplicate frame input IDs are normalized safely. Canvas activation is explicit only when the user invokes Open Canvas.

GUI remains unverified: drag/scroll gesture behavior, click/editor selection, focus and keyboard interactions need the existing authorized QA workflow. No window or app was launched here. Local tests cannot substitute for that acceptance.
