import CoreGraphics
import Foundation

func testNoteStoreContent() {
    let directory = Scratch.directory("content")
    let store = NoteStore(directory: directory, takingLock: false)
    Check.that(store.isWritable, "a fresh profile is writable")
    Check.equal(store.notes.count, 0, "a fresh profile has no notes")

    guard let id = store.createNote() else { return Check.that(false, "createNote returned nil") }
    store.setText(id, "Shopping\nmilk")
    store.setColor(id, 2)
    Check.equal(store.note(id)?.title, "Shopping", "the first line is the title")
    Check.equal(store.note(id)?.color, 2, "the color is stored")
    store.setColor(id, 9)
    Check.equal(store.note(id)?.color, NotePalette.normalizedIndex(9), "out-of-range colors wrap")
    Check.that(!store.hasUnsavedChanges, "a successful write clears the unsaved flag")

    let frame = CGRect(x: 40, y: 50, width: 300, height: 260)
    store.setFrame(id, expanded: frame)
    store.setVisible(id, false)
    Check.equal(store.visibleNotes.count, 0, "a hidden note is not visible")
    store.showAll()
    Check.equal(store.visibleNotes.count, 1, "Show All makes notes visible again")

    // Everything comes back in a fresh process.
    let reopened = NoteStore(directory: directory, takingLock: false)
    Check.equal(reopened.notes.count, 1, "the note survives a restart")
    Check.equal(reopened.note(id)?.text, "Shopping\nmilk", "the text survives a restart")
    Check.equal(reopened.note(id)?.frame, frame, "the frame survives a restart")
    Check.equal(reopened.note(id)?.color, NotePalette.normalizedIndex(9), "the color survives a restart")

    // Search.
    let other = store.createNote()
    store.setText(other!, "Call Ana about the invoice")
    Check.equal(store.search("ana invoice").count, 1, "search matches all terms in any order")
    Check.equal(store.search("ANA").count, 1, "search ignores case")
    Check.equal(store.search("absent").count, 0, "search reports no match")
    Check.equal(store.search("").count, 2, "an empty query lists every note")
}

func testTrash() {
    let directory = Scratch.directory("trash")
    let store = NoteStore(directory: directory, takingLock: false)
    guard let id = store.createNote() else { return Check.that(false, "createNote returned nil") }
    store.setText(id, "keep me")
    let frame = CGRect(x: 11, y: 12, width: 280, height: 240)
    store.setFrame(id, expanded: frame)

    Check.that(store.moveToTrash(id), "a note moves to the trash")
    Check.that(store.isTrashed(id), "the note is in the trash")
    Check.equal(store.activeNotes.count, 0, "a trashed note is not active")
    Check.equal(store.trashedNotes.count, 1, "a trashed note is listed in the trash")
    Check.that(!store.moveToTrash(id), "trashing twice changes nothing")

    let reopened = NoteStore(directory: directory, takingLock: false)
    Check.that(reopened.isTrashed(id), "the trash survives a restart")
    Check.equal(reopened.note(id)?.text, "keep me", "trashing preserves the content")
    Check.equal(reopened.note(id)?.frame, frame, "trashing preserves the geometry")

    Check.that(reopened.restoreFromTrash(id), "a note restores from the trash")
    Check.that(!reopened.isTrashed(id), "the note is active again")
    Check.equal(reopened.note(id)?.visible, true, "a restored note comes back visible")
    Check.equal(reopened.note(id)?.frame, frame, "restoring preserves the geometry")
}

func testLayout() {
    let directory = Scratch.directory("layout")
    let store = NoteStore(directory: directory, takingLock: false)
    let first = store.createNote()!
    let second = store.createNote()!
    let originals = [first: store.note(first)!.frame, second: store.note(second)!.frame]

    // An arrangement records a restore point and a session undo point.
    let arranged = [first: CGRect(x: 0, y: 0, width: 260, height: 220),
                    second: CGRect(x: 300, y: 0, width: 260, height: 220)]
    var change = NoteStore.LayoutChange(frames: arranged, arrangement: .grid)
    change.recordRestorePoint = true
    Check.that(store.apply(change), "an arrangement commits")
    Check.equal(store.note(first)?.frame, arranged[first], "the arranged frame is stored")
    Check.equal(store.layout.arrangement, .grid, "the arrangement is recorded")
    Check.that(store.canUndoLayout, "the arrangement can be undone")
    Check.that(store.canRestorePreviousLayout, "the arrangement left a restore point")

    Check.that(store.undoLayout(), "undo applies")
    Check.equal(store.note(first)?.frame, originals[first], "undo puts the first note back")
    Check.equal(store.note(second)?.frame, originals[second], "undo puts the second note back")
    Check.that(!store.canUndoLayout, "undo is spent after use")

    // The restore point outlives the undo point and a relaunch.
    Check.that(store.apply(change), "the arrangement can be applied again")
    let reopened = NoteStore(directory: directory, takingLock: false)
    Check.that(!reopened.canUndoLayout, "undo does not survive a restart")
    Check.that(reopened.canRestorePreviousLayout, "the restore point survives a restart")
    Check.that(reopened.restorePreviousLayout(), "restore applies after a restart")
    Check.equal(reopened.note(first)?.frame, originals[first], "restore puts the note back after a restart")
    Check.that(reopened.canRestorePreviousLayout, "the restore point is kept for repeated use")

    // Notes created after the arrangement are left alone by a restore.
    let later = reopened.createNote()!
    let laterFrame = reopened.note(later)!.frame
    Check.that(reopened.restorePreviousLayout(), "restore applies with newer notes present")
    Check.equal(reopened.note(later)?.frame, laterFrame, "a note created later is not moved")

    // Folding.
    Check.that(reopened.apply(NoteStore.LayoutChange(collapsed: Set([first]))), "folding commits")
    Check.that(reopened.isCollapsed(first), "the note is folded")
    let afterRestart = NoteStore(directory: directory, takingLock: false)
    Check.that(afterRestart.isCollapsed(first), "folding survives a restart")

    // Restoring onto a display the old frames are not on pulls them onto it.
    let elsewhere = CGRect(x: 3000, y: 3000, width: 1200, height: 800)
    Check.that(afterRestart.restorePreviousLayout(screens: [elsewhere]), "restore applies with displays given")
    Check.that(elsewhere.contains(afterRestart.note(first)!.frame), "restored frames land on a live display")
}

func testReadOnlyProfiles() {
    // A file we cannot parse makes the run read-only and is preserved untouched.
    let corrupt = Scratch.directory("corrupt")
    let notesURL = corrupt.appendingPathComponent(NoteFile.name)
    let garbage = Data("{ this is not a notes file".utf8)
    try? garbage.write(to: notesURL)
    let store = NoteStore(directory: corrupt, takingLock: false)
    Check.that(!store.isWritable, "a corrupt profile is read-only")
    Check.that(store.readOnlyReason != nil, "the reason is reported")
    Check.that(store.loadError != nil, "a corrupt profile reports that what it holds is incomplete")
    Check.that(store.createNote() == nil, "a read-only profile refuses new notes")
    store.showAll()
    Check.equal(try? Data(contentsOf: notesURL), garbage, "the unreadable file is left exactly as it was")

    // A newer schema is refused rather than downgraded.
    let future = Scratch.directory("future")
    try? Data(#"{"schemaVersion":999,"notes":[]}"#.utf8).write(to: future.appendingPathComponent(NoteFile.name))
    Check.that(!NoteStore(directory: future, takingLock: false).isWritable,
               "a profile from a newer version is read-only")

    // Two writers cannot share a directory.
    let shared = Scratch.directory("lock")
    let owner = NoteStore(directory: shared, takingLock: true)
    Check.that(owner.isWritable, "the first instance owns the directory")
    _ = owner.createNote()
    let second = NoteStore(directory: shared, takingLock: true)
    Check.that(!second.isWritable, "a second instance is read-only")
    Check.that(second.loadError == nil, "a profile that is only locked is still fully read")
    Check.equal(second.notes.count, 1, "a second instance still sees the notes")
    Check.that(second.createNote() == nil, "a second instance refuses to write")

    // A failed undo keeps its undo point, so it can be retried once writing works again.
    let undoDir = Scratch.directory("undo-retry")
    let undoStore = NoteStore(directory: undoDir, takingLock: false)
    let moved = undoStore.createNote()!
    let start = undoStore.note(moved)!.frame
    undoStore.markUndoPoint(ids: [moved])
    undoStore.setFrame(moved, expanded: CGRect(x: 600, y: 600, width: 260, height: 220))
    let layoutPath = undoDir.appendingPathComponent("layout.json")
    try? FileManager.default.removeItem(at: layoutPath)
    try? FileManager.default.createDirectory(at: layoutPath, withIntermediateDirectories: false)
    Check.that(!undoStore.undoLayout(), "undo reports a failed layout write")
    Check.that(undoStore.canUndoLayout, "a failed undo keeps its undo point")
    try? FileManager.default.removeItem(at: layoutPath)
    Check.that(undoStore.undoLayout(), "the undo succeeds once the write works again")
    Check.equal(undoStore.note(moved)?.frame, start, "the retried undo puts the note back")
    Check.that(!undoStore.canUndoLayout, "a successful undo spends its undo point")

    // A trash file we cannot read must not let trashed notes pass as active.
    let badTrash = Scratch.directory("bad-trash")
    let withTrash = NoteStore(directory: badTrash, takingLock: false)
    let trashed = withTrash.createNote()!
    withTrash.moveToTrash(trashed)
    try? Data("not a trash file".utf8).write(to: badTrash.appendingPathComponent("trash.json"))
    let reread = NoteStore(directory: badTrash, takingLock: false)
    Check.that(reread.loadError != nil, "an unreadable trash file is reported as an incomplete load")
    Check.that(!reread.isWritable, "an unreadable trash file makes the profile read-only")

    // A failing write keeps the edit in memory and says so.
    let blocked = Scratch.directory("blocked")
    let writable = NoteStore(directory: blocked, takingLock: false)
    let id = writable.createNote()!
    // A directory where the notes file belongs makes every save fail, for any user.
    let obstruction = blocked.appendingPathComponent(NoteFile.name)
    try? FileManager.default.removeItem(at: obstruction)
    try? FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: false)
    writable.setText(id, "this cannot be saved")
    Check.that(writable.hasUnsavedChanges, "a failed write is reported as unsaved")
    Check.that(writable.lastError != nil, "the failure is explained")
    Check.equal(writable.note(id)?.text, "this cannot be saved", "the edit stays in memory")
    Check.that(!writable.flushPendingChanges(), "quitting reports that changes are still unsaved")
    try? FileManager.default.removeItem(at: obstruction)
    Check.that(writable.flushPendingChanges(), "the retry succeeds once the write works again")
    Check.equal(NoteStore(directory: blocked, takingLock: false).note(id)?.text, "this cannot be saved",
                "the recovered write is on disk")
}

func testArrangeKeepsFoldedHeights() {
    let store = NoteStore(directory: Scratch.directory("arrange"), takingLock: false)
    let id = store.createNote()!
    let tall = CGRect(x: 100, y: 100, width: 260, height: 400)
    store.setFrame(id, expanded: tall)
    let area = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // An expanded note entering Compact folds but remembers how tall it was.
    Check.that(store.arrange(.compact, in: area), "compact applies")
    Check.that(store.isCollapsed(id), "compact folds the note")
    Check.equal(store.note(id)?.frame.height, 400, "a note entering Compact keeps its expanded height")
    let folded = store.layout.renderedFrame(id: id, expanded: store.note(id)!.frame)
    Check.equal(folded.height, LayoutState.collapsedHeight, "the folded note is one title bar high")
    Check.that(area.contains(folded), "the folded title bar is on screen")

    // A folded note entering Grid unfolds at the grid's size.
    Check.that(store.arrange(.grid, in: area), "grid applies")
    Check.that(!store.isCollapsed(id), "grid unfolds the note")
    Check.equal(store.note(id)?.frame.height, StickyNote.defaultSize.height,
                "a folded note entering Grid takes the grid's height")
    Check.that(area.contains(store.note(id)!.frame), "the grid frame is on screen")

    // Undo returns to the folded Compact state, with the height intact.
    Check.that(store.undoLayout(), "undo applies")
    Check.that(store.isCollapsed(id), "undo folds the note again")
    Check.equal(store.note(id)?.frame.height, 400, "undo keeps the remembered height")

    Check.that(store.arrange(.free, in: area), "free layout applies")
    Check.equal(store.layout.arrangement, .free, "free layout is recorded")
    Check.that(!NoteStore(directory: Scratch.directory("empty-arrange"), takingLock: false).arrange(.grid, in: area),
               "arranging no visible notes does nothing")
}
