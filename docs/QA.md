# The ten-minute pass

The only acceptance that counts for this app. Run it on a real Mac, with a mouse, before
you trust a build. Use the preview so your real notes are never at risk:

```sh
rm -rf build/preview-data && bash scripts/preview.sh
```

Each step is one observation. If a step fails, that is the bug report — note what you saw.

## Notes

1. A welcome note opens on first launch.
2. Type in it. Close and relaunch (`bash scripts/preview.sh`): the text is still there.
3. ⌘N opens a second note that does not sit exactly on the first.
4. The window title follows the first line as you type it.
5. Pick a color from the note's title-bar menu. The window background changes.
6. Drag the title bar. The note moves and stays where you dropped it.
7. Drag a corner. The note resizes. Relaunch: both the position and the size are kept.
8. Close a note with its red button. It disappears but is not deleted.
9. **Show All Notes** brings it back, in the same place, with its text.
10. Relaunch: a note you hid stays hidden until you ask for it.

## Fold

11. Double-click a note's title bar. It collapses to a title bar and stays draggable.
12. Double-click again. It returns to exactly its previous size.
13. Drag a folded note, then unfold it. It unfolds where you dropped it.

## Tidy

14. With four notes open, ⌘⌥1 (Grid). They lay out in a grid, none off screen.
15. ⌘⌥Z (Undo Last Layout). Every note returns to where it was.
16. ⌘⌥2 (List), then ⌘⌥R (Restore Previous Layout). The pre-list positions come back.
17. ⌘⌥3 (Compact). Every note folds into a row of title bars.
18. Relaunch after an arrangement, then ⌘⌥R. The old positions still come back.
19. Drag a note to within a few points of a screen edge and release. It snaps flush.
20. Turn **Snap to Screen Edges** off and repeat. It does not snap.
21. Turn snapping back on and resize a note by dragging its corner to within a few
    points of a screen edge. On release the note does not jump.
22. With a tall note open, ⌘⌥3 (Compact), then double-click its title. It unfolds at
    its old height, not the minimum.

## Layer

23. Set **Desktop — Behind Apps**. Notes sit above the wallpaper and behind other apps.
    Click one: while iStickies2 is active it comes forward and you can edit it, and it
    drops back behind other apps when you switch away. A note you hid stays hidden.
24. Switch Spaces. Desktop notes are on the new Space too.
25. Set **Floating — Keep on Top**. Notes stay above a full-screen-ish window.
26. Set one note to **Keep This Note on Top** while the default is ordinary. Only that
    note floats. **Use Global Window Default** gives it back.
27. Open Mission Control and Stage Manager with notes in each layer. Nothing vanishes
    permanently or lands off screen.

## Trash

28. **Move to Trash on This Mac** on one note. Its window closes.
29. **Restore from Trash on This Mac**. The note comes back with its text, color,
    size and position.

## Displays

30. With a second display attached, move a note onto it, then disconnect it. The note
    reappears fully on the remaining display.
31. Reattach the display. Nothing is lost or stacked off screen.

## Data safety

32. Launch a second copy while the first runs. It says it will not save, and the first
    copy keeps working.
33. Quit normally with unsaved edits in a note. Nothing is lost.
34. Corrupt `build/preview-data/notes.json` by hand and launch. The app says it is not
    saving, and the file is unchanged when you quit.

## Upgrade and rollback gate (issue #36)

Keep this separate from the GUI pass above. Never rehearse on a user's profile.
A backup is complete only if it includes every profile file and subdirectory,
including notes, layout, trash, preferences, old command journals and ledger
segments, and any unknown extension files. `notes.lock` is runtime coordination,
not saved content: never remove or replace a lock to obtain access.

1. Identify the exact old executable, source commit and profile path. Confirm
   normal exit and absence of an active writer; obtain the existing exclusive
   lock before taking a real backup. If that is not possible, stop.
2. Copy the complete quiescent profile into a new staging backup, preserving file
   metadata. Compare the relative file inventory and every file's hash. Publish
   the verified backup by renaming staging on the same filesystem; an interrupted
   staging copy is not a usable backup. Keep the old executable separately.
3. Restore the backup to a separate synthetic rehearsal directory and verify the
   same inventory and hashes before using either executable. Record the old and
   new binary hashes, schema, and every command's exit status.
4. Read with the new version, then write a synthetic note and reopen it in a new
   process. Confirm old text, colors, geometry, visibility and trash membership.
   A successful notes write upgrades the file to schema 10.
5. Before rollback, separately back up and verify the post-upgrade profile so new
   edits are retained. Restore the original complete backup into another empty
   directory; do not overlay old notes onto new side files. Verify all hashes,
   then use the old executable to read the original notes and trash again.
6. A real replacement is a separate authorized installation operation, performed
   only after both applications have stopped normally and the backup/restore
   rehearsal passes. Never run an older writer against the schema 10 profile.

Failure handling: unreadable files and unknown schemas remain untouched. A
pending `command-journal.json` must be resolved with the matching old version;
copying it away or deleting it is not recovery. Failed writes, interrupted copies,
lock conflicts or hash mismatches stop the upgrade before replacement. Retain the
original and failed staging materials for diagnosis.

Existing evidence: the isolated combined candidate `1d76386993aab0149b72ccfd6b6df195182dfc03`
passed [CI](https://github.com/douyixuan/stickies/actions/runs/40300233097).
The local `daily-update-105/rollback-verification.json` record from that rehearsal
used the actual 0.3.105 packaged CLI to create synthetic v2/v3 profiles, upgraded
with the combined CLI, preserved newer edits separately, restored byte-identical
original files, and read notes/trash with the old CLI. The old CLI refused schema
10 with exit 65. This is existing evidence, not a new test run or GUI acceptance.

Still unverified: an actual 0.1 executable/fixture provenance, interruption during
backup publication, the real-user installation, and the full GUI pass. A successful
synthetic rollback or CLI input test alone does not close issue #36 or #42.
