# iStickies2: reversible launcher cleanup and installation switch

Status: proposed only. No existing app has been moved, removed, unregistered or terminated. No global LaunchServices reset is permitted. macOS's `/System/Applications/Stickies.app` (`com.apple.Stickies`) is excluded from every operation.

Read-only inventory on 2026-10-19, host `starlabs-112.local`: all eight project apps below exist and are registered in LaunchServices. Every original Info.plist lacks CFBundleIconFile. Only the original QA app is running (PID 94433 at inspection; never reuse that PID without checking). It holds `task-3/stickies/build/deadline-qa/data/notes.lock`. Its notes and memory edits must be preserved. The system Stickies also runs separately.

Paths below are relative to `/Users/cedric/Documents/Codex/2026-10-15/`:

| Exact relative app path | Bundle ID suffix (prefix dev.douyixuan.stickies) | Version | Proposed action after approval |
| --- | --- | --- | --- |
| task-3/stickies/build/Stickies.app | .local-preview | no metadata | Archive, verify archive, remove only expanded app, unregister exact path |
| task-4/stickies/build/Stickies.app | .local-preview | no metadata | Same |
| task-3/stickies/build/deadline-qa/StickiesQA.app | .deadline-qa | no metadata; running | Keep untouched until saved, normally exited and replacement approved |
| task-4/install-update-59b2fc6/rollback/StickiesQA.app | .deadline-qa | no metadata | Archive, verify archive, remove only expanded app, unregister exact path |
| task-4/install-update-59b2fc6/staged/StickiesQA.app | .deadline-qa | 0.2.34 | Same; superseded staging copy |
| task-4/stickies/build/releases/Stickies-0.2.0-42b18c1338f4-universal2/Stickies Delivery.app | .delivery | 0.2.31 | Verify existing ZIP and retain it, remove only expanded app, unregister exact path |
| task-4/stickies/build/releases/Stickies-0.2.0-626b86736209-universal2/Stickies Delivery.app | .delivery | 0.2.32 | Same |
| task-4/stickies/build/releases/Stickies-0.2.0-59b2fc6e5635-universal2/Stickies Delivery.app | .delivery | 0.2.34 | Same |

One additional stale registration points to the already absent `task-4/stickies/build/release-stage.LcPMI5/Stickies-0.2.0-82466647a596-universal2/Stickies Delivery.app`. Propose unregistering only that exact path after approval; no disk deletion is needed.

## Minimum safe cleanup

Approval group A: seven non-running app paths above plus the one stale registration. Recheck processes and open data locks first; stop if any is in use. Preserve executable permissions, metadata and a verified archive of each build, then remove only the expanded bundle and unregister that exact path. Do not remove surrounding build folders, preview-data, deadline-qa/data, notes.lock, notes.json or preferences. Reversible archive retention is required; unregister-only will not prevent rediscovery while the duplicate .app remains on disk. Never reset global LaunchServices or touch other applications. Launcher cache refresh and actual visual verification require separate coordination.

## Single user entry and data-preserving switch

Approval group B: after the user confirms edits saved and normally quits the original QA app, verify the process is gone and no process holds its data lock. Do not force quit. The legacy app has no reliable query for unsaved memory edits. A stable file timestamp alone is not proof of saved memory state.

1. Back up the complete original data directory and old QA bundle, verify the backups, keep rollback as ZIP.
2. Prepare one `~/Applications/iStickies2.app` from the reviewed code. For this existing QA installation retain `dev.douyixuan.stickies.deadline-qa` and its original `LSEnvironment.STICKIES_DATA_DIR` absolute path. Rename only the user-facing app and metadata, embed the icon, and re-sign the prepared bundle ad-hoc. Do not silently switch to the public Delivery profile or production profile.
3. Verify the prepared version, icon, signature, bundle identity and exact data path before installing. Check that the destination is absent or matches the approved app. No overwriting an unrelated app.
4. After approval, replace the old user entry with the single prepared app, retain the old archive, unregister the old exact QA path and register only the chosen user entry. Preserve all original data in place.
5. Launch only with authorization, verify the process uses the expected executable and data lock, then verify old notes, current color names, menu icon and launcher entry with the user/authorized QA. Do not claim GUI success from archive tests.

Public fresh-install packages retain `dev.douyixuan.stickies.delivery` and `~/Library/Application Support/Stickies Delivery`; Xcode production builds retain `dev.douyixuan.stickies`. Those are compatibility choices, not instructions to create multiple user installations. No CloudKit/signing credentials/security settings are changed.
