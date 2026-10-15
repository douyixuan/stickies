# Device-local Desktop and Floating modes

The All Note Windows picker offers Ordinary, Desktop (behind ordinary apps) and Floating (keep on top). Desktop uses desktop-icon level + 1, below normal windows, with canJoinAllSpaces/stationary/ignoresCycle. Canvas is an independent ordinary window and is never added to the note-window collection. Mode changes preserve note content, frame, visibility and collapsed state.

Preferences retain legacy keepOnTop compatibility and add an optional windowMode field. Preference writes succeed before changing model/window state; failures retain the old mode. Corrupt preferences are preserved and mode changes are disabled, with a visible error. No extra permission, helper process, cloud credential or system setting is required by this code.

Independent read-only reviewer canvas_review found no static blockers. In a temporary-source copy, four-phase mode tests (legacy migration, mode/restart, corrupt file, failed write) and arm64 macOS14 full compilation passed. Current branch also passed layout recovery and Canvas restart tests. These headless checks assert the requested AppKit properties; they do not establish that macOS rendered or interacted with them correctly.

Original QA task retains GUI acceptance: switch Ordinary/Desktop/Floating; verify ordinary app occlusion, click/edit Desktop notes, Spaces transitions, Mission Control, hide/show and launch restoration, plus Canvas staying ordinary while note modes change. No GUI was launched and real notes were not touched.
