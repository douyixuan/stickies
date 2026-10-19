# Sync notes between Macs

## Sync folder

This mode uses a folder that you select in the system file picker.
The app reads and writes only its sync folder.
The app does not search your cloud drive.
This mode does not require an Apple developer account.
A local folder also works, but a cloud drive must transfer files between Macs.
The app starts with sync off.

1. On the first Mac, open **Sync Folder…**.
2. Select **Create Sync Folder…**.
3. Select a parent folder in your cloud drive, such as iCloud Drive.
4. Select the local notes that you want to sync.
5. Select **Enable Sync for Selected Notes**.
6. On the other Mac, wait for the new folder to appear in Finder.
7. Select **Open Existing Sync Folder…**.
8. Select the same sync folder.
9. Select **Enable Sync for Selected Notes**.

An empty selection downloads existing notes without uploading old local notes.
After you enable sync, new notes also sync.
Only note text and colors sync.
Each Mac keeps its window positions, layouts, visibility, and floating mode.

Each app launch requires you to enable folder sync again.
Folder access does not prove a cloud account identity.
Before you enable sync, make sure that the selected folder belongs to the intended account.
The app pauses sync after an account-change notification.
A request that the app already sent can finish after you turn sync off.

The status reports a local folder save.
It does not prove that the cloud drive finished an upload or another Mac received a change.
Your cloud drive controls transfer timing.
If the status reports a missing revision, wait for your cloud drive to download the folder.
Then select **Sync Now**.

## Conflicts and deletion

Concurrent offline edits retain separate revisions.
The conflict view shows each version.
Select the version that you want to keep.
The app records that choice as a new revision.

Closing a note hides it on that Mac.
**Delete Everywhere** removes the note from active synced notes.
Offline Macs receive the deletion after they reconnect.
The app retains a recovery copy for notes that existed on this Mac before deletion.
Select **Restore Deleted Note** to restore that copy.
Enable sync to send the restored note to other Macs.
Historical files retain previous note text.
Deletion does not securely erase history or provider backups.

Keep the sync folder private.
Anyone with access to that folder can read its note revisions.
Do not remove individual revision files.
Missing or damaged revisions pause sync.

## CloudKit

CloudKit support requires a signed app with a valid Team and CloudKit container.
The container in the app plist must match its signed entitlements.
The adapter uses a private custom zone and conditional record writes.
The app blocks this route before it creates a CloudKit container without those prerequisites.
The ad-hoc delivery package uses the folder route.

## Evidence and limits

Tests use a simulated transport and temporary local folders.
Tests cover offline edits, concurrent revisions, conflicts, deletion, damaged files, restart recovery, and storage locks.
These tests do not prove live iCloud transfer.
No real note upload or two-Mac acceptance occurred during implementation.

For acceptance, use new test notes on two Macs.
Test transfer in both directions.
Test offline edits and a conflict choice.
Test deletion and restart.
Keep real notes unselected until those tests pass.
