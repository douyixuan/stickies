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

## Layer

21. Set **Desktop — Behind Apps**. Notes sit above the wallpaper and behind other apps.
22. Switch Spaces. Desktop notes are on the new Space too.
23. Set **Floating — Keep on Top**. Notes stay above a full-screen-ish window.
24. Set one note to **Keep This Note on Top** while the default is ordinary. Only that
    note floats. **Use Global Window Default** gives it back.
25. Open Mission Control and Stage Manager with notes in each layer. Nothing vanishes
    permanently or lands off screen.

## Trash

26. **Move to Trash on This Mac** on one note. Its window closes.
27. **Restore from Trash on This Mac**. The note comes back with its text, color,
    size and position.

## Displays

28. With a second display attached, move a note onto it, then disconnect it. The note
    reappears fully on the remaining display.
29. Reattach the display. Nothing is lost or stacked off screen.

## Data safety

30. Launch a second copy while the first runs. It says it will not save, and the first
    copy keeps working.
31. Quit normally with unsaved edits in a note. Nothing is lost.
32. Corrupt `build/preview-data/notes.json` by hand and launch. The app says it is not
    saving, and the file is unchanged when you quit.
