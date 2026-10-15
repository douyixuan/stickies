# Authorized GUI QA handoff

Do not bypass the pending Stickies QA app-control permission. This document supplies acceptance steps after that workflow is authorized. Use an isolated STICKIES_DATA_DIR; do not load real notes.

1. Use 20–50 sample notes, including long text, Unicode, multiple colors and hidden notes. Open Canvas from menu/Shift-Command-0, exercise Command-F and Command-N; Canvas new note stays hidden and selected. Edit/select text and verify the independent note window updates without accidental drag.
2. Switch List/Board. Click cards to edit; drag cards; scroll both axes. Board Grid/List/Compact must expose every card without overlap. Search should compact result positions temporarily and prevent board mutations; clearing search must restore prior positions. Restore Board must retain later text edits and new notes. Close/reopen and relaunch to check persisted positions.
3. On note windows, double-click an empty title/grip to fold/unfold. Check traffic-light and title accessory clicks are not intercepted, title/menus fit a 32pt folded note, and folded dragging near the bottom edge retains its top edge and expanded size. Test ordinary title drag and edge resize. Close only hides.
4. With 45 visible/5 hidden notes, run Free/Grid/List/Compact and Restore Previous Layout. Only visible notes arrange. Later text/color edits and new/hidden notes survive Restore. Repeat after restart and a display/Space change. Overflow may overlap on a small desktop but must remain reachable; Canvas exposes all notes.
5. Switch All Note Windows between Ordinary/Desktop/Floating. Verify ordinary app occlusion, clicking/editing Desktop notes, Spaces/Mission Control/fullscreen behavior, hidden-window reopen and restart. Canvas must remain ordinary under every mode.
6. Original workflow owns simultaneous-instance file-lock and installation/recovery smoke. Headless test evidence here does not replace those GUI checks. CloudKit, signing/container and two-device sync remain separately unimplemented/unverified.

Current build path in this independent workspace: build/Stickies.app. Do not invoke preview.sh here until GUI approval and desktop scheduling are granted by the original workflow.
