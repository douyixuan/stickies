import Combine
import CoreGraphics
import Foundation

/// Everything that is persisted: note content, device layout, trash and preferences.
/// Deliberately free of AppKit so the whole data story is testable without a window server.
/// Main-thread only, like the UI that drives it.
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = []
    @Published private(set) var layout = LayoutState()
    @Published private(set) var preferences = Preferences()
    @Published private(set) var trashedIDs: Set<UUID> = []

    /// Non-nil when this run must not write at all: another instance owns the directory,
    /// or a file on disk could not be read and is preserved untouched.
    @Published private(set) var readOnlyReason: String? = nil
    /// The most recent failed write. Cleared by the next successful one.
    @Published private(set) var lastError: String? = nil
    /// True when memory holds note edits that are not on disk.
    @Published private(set) var hasUnsavedChanges = false
    /// Set while the last layout change can be taken back in this session.
    @Published private(set) var undoSnapshot: LayoutState.Snapshot? = nil

    let directory: URL
    private let lock: DirectoryLock?

    private var notesURL: URL { directory.appendingPathComponent(NoteFile.name) }
    private var layoutURL: URL { directory.appendingPathComponent("layout.json") }
    private var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }
    private var trashURL: URL { directory.appendingPathComponent("trash.json") }

    private struct TrashFile: Codable {
        var version = 1
        var ids: Set<UUID> = []
    }

    // MARK: Lifecycle

    /// Loads the profile. Any unreadable file makes the whole run read-only, so a
    /// file we cannot understand is never half-overwritten.
    init(directory: URL, takingLock: Bool = true) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if takingLock {
            lock = DirectoryLock(directory: directory)
            if lock == nil {
                readOnlyReason = "Another copy of iStickies2 is using this notes folder. This window will not save."
            }
        } else {
            lock = nil
        }

        // Read whole or not at all: a file we cannot parse stops the load and blocks writing,
        // so nothing on disk is ever half-overwritten by a version that misunderstood it.
        var reading = "notes"
        do {
            notes = try NoteFile.load(from: notesURL)
            reading = "layout"
            if let state = try JSONFile.load(LayoutState.self, from: layoutURL) {
                try state.validate()
                layout = state
            }
            reading = "preferences"
            if let value = try JSONFile.load(Preferences.self, from: preferencesURL) {
                preferences = value
            }
            reading = "trash"
            if let file = try JSONFile.load(TrashFile.self, from: trashURL) {
                guard file.version == 1 else { throw NoteFile.Failure.unsupportedVersion }
                trashedIDs = file.ids
            }
        } catch {
            readOnlyReason = "The \(reading) file could not be read and is preserved as-is: "
                + error.localizedDescription + " This window will not save."
        }
    }

    var isWritable: Bool { readOnlyReason == nil }

    // MARK: Reading

    var activeNotes: [StickyNote] { notes.filter { !trashedIDs.contains($0.id) } }
    var trashedNotes: [StickyNote] { notes.filter { trashedIDs.contains($0.id) } }
    var visibleNotes: [StickyNote] { activeNotes.filter(\.visible) }

    func note(_ id: UUID) -> StickyNote? { notes.first { $0.id == id } }
    func isTrashed(_ id: UUID) -> Bool { trashedIDs.contains(id) }
    func isCollapsed(_ id: UUID) -> Bool { layout.collapsed.contains(id) }
    func windowMode(for id: UUID) -> NoteWindowMode { preferences.mode(for: id) }

    var canRestorePreviousLayout: Bool { isWritable && layout.snapshot != nil }
    var canUndoLayout: Bool { isWritable && undoSnapshot != nil }

    func search(_ query: String) -> [StickyNote] {
        query.isEmpty ? activeNotes : activeNotes.filter { $0.matches(query) }
    }

    // MARK: Content

    @discardableResult
    func createNote(visible: Bool = true) -> UUID? {
        guard isWritable else { return nil }
        let offset = CGFloat(notes.count % 8) * 28
        let note = StickyNote(frame: CGRect(x: 120 + offset, y: 220 + offset,
                                            width: StickyNote.defaultSize.width,
                                            height: StickyNote.defaultSize.height),
                              visible: visible)
        notes.append(note)
        saveNotes()
        return note.id
    }

    func setText(_ id: UUID, _ text: String) {
        mutate(id) { $0.text = text }
    }

    func setColor(_ id: UUID, _ color: Int) {
        mutate(id) { $0.color = NotePalette.normalizedIndex(color) }
    }

    func setVisible(_ id: UUID, _ visible: Bool) {
        mutate(id) { $0.visible = visible }
    }

    func showAll() {
        guard isWritable else { return }
        for index in notes.indices where !trashedIDs.contains(notes[index].id) { notes[index].visible = true }
        saveNotes()
    }

    func hideAll() {
        guard isWritable else { return }
        for index in notes.indices { notes[index].visible = false }
        saveNotes()
    }

    /// Records the window's current geometry. `frame` is the expanded frame,
    /// so folding and unfolding a note does not lose its height.
    func setFrame(_ id: UUID, expanded frame: CGRect) {
        mutate(id) { $0.frame = frame }
    }

    private func mutate(_ id: UUID, _ change: (inout StickyNote) -> Void) {
        guard isWritable, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let before = notes[index]
        change(&notes[index])
        guard notes[index] != before else { return }
        saveNotes()
    }

    // MARK: Trash

    /// Device-local. Content, frame, color and identity are all preserved.
    @discardableResult
    func moveToTrash(_ id: UUID) -> Bool { setTrashed(id, true) }

    @discardableResult
    func restoreFromTrash(_ id: UUID) -> Bool { setTrashed(id, false) }

    private func setTrashed(_ id: UUID, _ trashed: Bool) -> Bool {
        guard isWritable, note(id) != nil, trashedIDs.contains(id) != trashed else { return false }
        var updated = trashedIDs
        if trashed { updated.insert(id) } else { updated.remove(id) }
        guard write("trash", { try JSONFile.save(TrashFile(ids: updated), to: trashURL) }) else { return false }
        trashedIDs = updated
        // A restored note comes back visible; a trashed note's window is closed by the caller.
        if !trashed { setVisible(id, true) }
        return true
    }

    // MARK: Preferences

    @discardableResult
    func setWindowMode(_ mode: NoteWindowMode) -> Bool {
        var updated = preferences
        updated.windowMode = mode
        return savePreferences(updated)
    }

    /// `nil` drops the per-note override and returns the note to the global default.
    @discardableResult
    func setNoteFloating(_ id: UUID, _ floating: Bool?) -> Bool {
        var updated = preferences
        if let floating { updated.floatingOverrides[id.uuidString] = floating }
        else { updated.floatingOverrides.removeValue(forKey: id.uuidString) }
        return savePreferences(updated)
    }

    @discardableResult
    func setSnapToScreenEdges(_ enabled: Bool) -> Bool {
        var updated = preferences
        updated.snapToScreenEdges = enabled
        return savePreferences(updated)
    }

    private func savePreferences(_ updated: Preferences) -> Bool {
        guard isWritable, updated != preferences else { return false }
        guard write("preferences", { try JSONFile.save(updated, to: preferencesURL) }) else { return false }
        preferences = updated
        return true
    }

    // MARK: Layout

    /// One layout mutation: new frames, a new folded set, a new arrangement, or any mix.
    struct LayoutChange {
        /// Expanded frames, by note id. Notes that are absent keep their frame.
        var frames: [UUID: CGRect] = [:]
        /// Replaces the folded set when non-nil.
        var collapsed: Set<UUID>?
        var arrangement: Arrangement?
        /// Persist the frames being replaced, so Restore Previous Layout survives a relaunch.
        var recordRestorePoint = false
        /// Keep a session undo point for the frames being replaced.
        var recordUndo = true
    }

    /// `layout.json` is written before `notes.json`: the before-image is durable before any
    /// frame moves, so a failed note write still leaves Restore Previous Layout usable.
    @discardableResult
    func apply(_ change: LayoutChange) -> Bool {
        guard isWritable else { return false }
        let touched = Set(change.frames.keys).union(change.collapsed.map { $0.symmetricDifference(layout.collapsed) } ?? [])
        let before = snapshot(of: touched)

        var state = layout
        if let arrangement = change.arrangement { state.arrangement = arrangement }
        if let collapsed = change.collapsed { state.collapsed = collapsed }
        if change.recordRestorePoint { state.snapshot = before }
        guard saveLayout(state) else { return false }

        var changed = false
        for (id, frame) in change.frames {
            guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].frame != frame else { continue }
            notes[index].frame = frame
            changed = true
        }
        if changed { saveNotes() }
        if change.recordUndo, changed || change.collapsed != nil { undoSnapshot = before }
        return true
    }

    /// Captures the current geometry of `ids` so a drag or resize can be taken back.
    func markUndoPoint(ids: Set<UUID>) {
        guard isWritable else { return }
        undoSnapshot = snapshot(of: ids)
    }

    /// Puts the notes back where the last layout change found them.
    /// `clamping` pulls each frame onto an available display; the core never looks at screens.
    @discardableResult
    func undoLayout(clamping: (CGRect) -> CGRect = { $0 }) -> Bool {
        guard let snapshot = undoSnapshot else { return false }
        undoSnapshot = nil
        return apply(change(restoring: snapshot, clamping: clamping, recordUndo: false))
    }

    /// Restores the frames an arrangement replaced. The restore point is kept, so this
    /// still works after a relaunch and can be used more than once.
    @discardableResult
    func restorePreviousLayout(clamping: (CGRect) -> CGRect = { $0 }) -> Bool {
        guard let snapshot = layout.snapshot else { return false }
        return apply(change(restoring: snapshot, clamping: clamping, recordUndo: true))
    }

    private func change(restoring snapshot: LayoutState.Snapshot,
                        clamping: (CGRect) -> CGRect,
                        recordUndo: Bool) -> LayoutChange {
        var collapsed = layout.collapsed
        var frames: [UUID: CGRect] = [:]
        for entry in snapshot.entries where !isTrashed(entry.id) && note(entry.id) != nil {
            frames[entry.id] = clamping(entry.frame)
            if entry.collapsed { collapsed.insert(entry.id) } else { collapsed.remove(entry.id) }
        }
        return LayoutChange(frames: frames, collapsed: collapsed, arrangement: snapshot.arrangement,
                            recordUndo: recordUndo)
    }

    private func snapshot(of ids: Set<UUID>) -> LayoutState.Snapshot {
        LayoutState.Snapshot(entries: notes.filter { ids.contains($0.id) }.map {
            LayoutState.Entry(id: $0.id, frame: $0.frame, collapsed: isCollapsed($0.id))
        }, arrangement: layout.arrangement)
    }

    // MARK: Persistence

    /// Called on normal quit; a failed write must not silently discard memory edits.
    @discardableResult
    func flushPendingChanges() -> Bool {
        if hasUnsavedChanges { saveNotes() }
        return !hasUnsavedChanges
    }

    private func saveNotes() {
        hasUnsavedChanges = true
        guard isWritable else { return }
        if write("notes", { try NoteFile.save(notes, to: notesURL) }) { hasUnsavedChanges = false }
    }

    private func saveLayout(_ state: LayoutState) -> Bool {
        guard write("layout", { try state.validate(); try JSONFile.save(state, to: layoutURL) }) else { return false }
        layout = state
        return true
    }

    private func write(_ what: String, _ body: () throws -> Void) -> Bool {
        guard isWritable else { return false }
        do {
            try body()
            lastError = nil
            return true
        } catch {
            lastError = "The \(what) file could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
