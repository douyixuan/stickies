import Darwin
import AppKit
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [StickyNote] = []
    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: NoteWindowDelegate] = [:]
    private var isArranging = false
    @Published private(set) var layoutState = NoteLayoutState()
    @Published private(set) var layoutError: String?
    private var canSaveLayout = true
    private var layoutURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("layout.json") }
    var canRestoreLayout: Bool { layoutState.snapshot != nil && canSave && canSaveLayout }
    func isCollapsed(_ id: UUID) -> Bool { layoutState.collapsed.contains(id) }

    @discardableResult
    private func persistLayout(_ state: NoteLayoutState) -> Bool {
        guard canSave, canSaveLayout else { return false }
        do {
            try state.validate()
            try JSONEncoder().encode(state).write(to: layoutURL, options: .atomic)
            layoutState = state
            layoutError = nil
            return true
        } catch {
            layoutError = "Layout could not be saved. No layout changes were applied: \(error.localizedDescription)"
            return false
        }
    }
    @Published private var trash = LocalNoteTrash()
    @Published private(set) var trashError: String?
    private var canSaveTrash = true
    private var trashURL: URL { localDataDirectory.appendingPathComponent("trash.json") }
    var activeNotes: [StickyNote] { notes.filter { !trash.ids.contains($0.id) } }
    var trashedNotes: [StickyNote] { notes.filter { trash.ids.contains($0.id) } }
    var trashWritable: Bool { canSave && canSaveTrash && !hasUnsavedChanges }
    func isTrashed(_ id: UUID) -> Bool { trash.ids.contains(id) }

    @Published private(set) var persistenceError: String?
    @Published private(set) var hasUnsavedChanges = false
    private var canSave = true
    var localStateWritable: Bool { canSave }
    var localDataDirectory: URL { fileURL.deletingLastPathComponent() }
    private var lockFD: Int32 = -1
    private var isLockedByAnotherInstance = false
    @Published private(set) var keepOnTop = false
    @Published private(set) var windowMode: NoteWindowMode = .standard
    @Published private(set) var preferenceError: String?
    private var canSavePreferences = true
    private var preferencesURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("preferences.json") }

    private struct Preferences: Codable { var keepOnTop: Bool; var windowMode: NoteWindowMode? }


    private let fileURL: URL = {
        let directory = NoteDataLocation.directory(
            environment: ProcessInfo.processInfo.environment,
            bundleID: Bundle.main.bundleIdentifier,
            bundleURL: Bundle.main.bundleURL,
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }()

    private init() {
        let lockURL = fileURL.deletingLastPathComponent().appendingPathComponent("notes.lock")
        lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            canSave = false
            isLockedByAnotherInstance = true
            persistenceError = "This notes folder is already open or cannot be locked. Close its other Stickies instance before reopening. No notes were changed."
            return
        }
        if FileManager.default.fileExists(atPath: preferencesURL.path) {
            do {
                let preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL))
                windowMode = preferences.windowMode ?? (preferences.keepOnTop ? .floating : .standard)
                keepOnTop = windowMode == .floating
            } catch {
                canSavePreferences = false
                preferenceError = "Could not read window preferences. Original file preserved; window mode changes are disabled."
            }
        }
        if FileManager.default.fileExists(atPath: layoutURL.path) {
            do {
                let state = try JSONDecoder().decode(NoteLayoutState.self, from: Data(contentsOf: layoutURL))
                try state.validate()
                layoutState = state
            } catch {
                canSaveLayout = false
                layoutError = "Could not read layout.json. Original file preserved; arrangement and collapse are disabled."
            }
        }
        if FileManager.default.fileExists(atPath: trashURL.path) {
            do {
                let state = try LocalNoteTrash.load(from: trashURL)
                trash = state
            } catch {
                canSaveTrash = false
                trashError = "Could not read Trash. Original file preserved; trash changes are disabled. All notes remain available."
            }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            notes = try CompatibleNoteFile.decode(Data(contentsOf: fileURL))
        } catch {
            canSave = false
            persistenceError = "Could not read notes. Original file preserved at \(fileURL.path). \(error.localizedDescription)"
        }
    }

    deinit {
        if lockFD >= 0 { close(lockFD) }
    }

    func setKeepOnTop(_ enabled: Bool) {
        setWindowMode(enabled ? .floating : .standard)
    }

    func setWindowMode(_ mode: NoteWindowMode) {
        guard canSave, canSavePreferences else { return }
        do {
            try JSONEncoder().encode(Preferences(keepOnTop: mode == .floating, windowMode: mode))
                .write(to: preferencesURL, options: .atomic)
            windowMode = mode
            keepOnTop = mode == .floating
            for window in windows.values {
                window.level = mode.level
                window.collectionBehavior = mode.collectionBehavior
            }
            preferenceError = nil
        } catch {
            preferenceError = "Window mode could not be saved; the previous mode is unchanged: \(error.localizedDescription)"
        }
    }

    func hideAll() {
        for id in activeNotes.map(\.id) { hide(id) }
    }

    @discardableResult
    func createNote(showWindow: Bool = true) -> UUID {
        let offset = CGFloat(notes.count % 8) * 28
        let note = StickyNote(frame: CGRect(x: 120 + offset, y: 220 + offset, width: 260, height: 220), visible: showWindow)
        notes.append(note)
        save()
        if showWindow { show(note.id) }
        return note.id
    }

    func updateText(_ id: UUID, _ text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        windows[id]?.title = windowTitle(for: notes[index])
        save()
    }

    func setColor(_ id: UUID, _ color: Int) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].color = color
        windows[id]?.backgroundColor = NotePalette.color(color)
        save()
    }

    func note(_ id: UUID) -> StickyNote? {
        notes.first(where: { $0.id == id })
    }

    func showAll() {
        for note in activeNotes { show(note.id) }
    }

    func restoreWindows() {
        if notes.isEmpty && canSave {
            createNote()
            if let id = notes.first?.id {
                updateText(id, "Welcome to Stickies\n\nWrite here. Drag the title bar to move this note, or drag a corner to resize.\n\nUse the note menu to open Canvas or arrange notes. Use the gear button for Settings and optional folder sync. Notes stay on this Mac until you enable sync.")
            }
        } else {
            for note in activeNotes where note.visible { show(note.id) }
        }
        if let persistenceError {
            let alert = NSAlert()
            alert.messageText = "Stickies could not load your notes"
            alert.informativeText = persistenceError
            alert.runModal()
            if isLockedByAnotherInstance { NSApplication.shared.terminate(nil) }
        }
    }

    private func windowTitle(for note: StickyNote) -> String {
        let firstLine = note.text.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "New Note" : String(firstLine.prefix(60))
    }

    func show(_ id: UUID) {
        guard !isTrashed(id) else { return }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].visible = true
        if let existing = windows[id] {
            let expandedFrame = restoredPresentation(id: id, frame: notes[index].frame, screens: NSScreen.screens.map(\.visibleFrame))
            let restoredFrame = layoutState.renderedFrame(id: id, expanded: expandedFrame)
            existing.setFrame(restoredFrame, display: true)
            notes[index].frame = layoutState.expandedFrame(id: id, rendered: existing.frame, previous: notes[index].frame)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            save()
            return
        }
        notes[index].frame = restoredPresentation(id: id, frame: notes[index].frame, screens: NSScreen.screens.map(\.visibleFrame))
        let note = notes[index]
        let window = NoteWindow(
            contentRect: note.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.onTitleDoubleClick = { [weak self] in self?.toggleCollapse(id) }
        window.setFrame(note.frame, display: false)
        window.title = windowTitle(for: note)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NotePalette.color(note.color)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let header = NSHostingView(rootView: NoteHeaderControls(noteID: id))
        header.frame = NSRect(x: 0, y: 0, width: 60, height: 22)
        header.toolTip = "Note actions, colors, and settings. Drag the empty title bar to move this note."
        accessory.view = header
        window.addTitlebarAccessoryViewController(accessory)
        let dragAccessory = NSTitlebarAccessoryViewController()
        dragAccessory.layoutAttribute = .left
        let dragHint = NoteDragHint(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        dragHint.onDoubleClick = { [weak self] in self?.toggleCollapse(id) }
        dragHint.toolTip = "Drag this title bar to move the note. Select text below to edit."
        dragAccessory.view = dragHint
        window.addTitlebarAccessoryViewController(dragAccessory)
        window.level = windowMode.level
        window.collectionBehavior = windowMode.collectionBehavior
        window.minSize = NSSize(width: 180, height: 120)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NoteView(noteID: id))
        let delegate = NoteWindowDelegate(id: id, store: self)
        window.delegate = delegate
        windows[id] = window
        delegates[id] = delegate
        applyPresentation(id)
        window.makeKeyAndOrderFront(nil)
        save()
    }

    func hide(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].visible = false
        windows[id]?.orderOut(nil)
        save()
    }

    func moved(_ id: UUID, frame: CGRect) {
        guard !isArranging,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].frame = layoutState.expandedFrame(id: id, rendered: frame, previous: notes[index].frame)
        save()
    }

    private func restoredPresentation(id: UUID, frame: CGRect, screens: [CGRect]) -> CGRect {
        let rendered = layoutState.renderedFrame(id: id, expanded: frame)
        let restored = LayoutEngine.restore(rendered, screens: screens,
                                            minimumHeight: isCollapsed(id) ? NoteLayoutState.collapsedHeight : 120)
        return layoutState.expandedFrame(id: id, rendered: restored, previous: frame)
    }

    private func applyPresentation(_ id: UUID) {
        guard let note = note(id), let window = windows[id] else { return }
        let wasArranging = isArranging
        isArranging = true
        defer { isArranging = wasArranging }
        let collapsed = isCollapsed(id)
        window.minSize = NSSize(width: 180, height: collapsed ? NoteLayoutState.collapsedHeight : 120)
        if collapsed { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
        window.titleVisibility = collapsed ? .visible : .hidden
        window.contentView?.isHidden = collapsed
        window.setFrame(layoutState.renderedFrame(id: id, expanded: note.frame), display: true, animate: false)
    }

    func toggleCollapse(_ id: UUID, screens: [CGRect]? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var state = layoutState
        if state.collapsed.contains(id) { state.collapsed.remove(id) } else { state.collapsed.insert(id) }
        guard persistLayout(state) else { return }
        // Only expanding may need to recover a frame moved to a different screen while folded.
        if !isCollapsed(id), windows[id] != nil || screens != nil {
            notes[index].frame = LayoutEngine.restore(notes[index].frame, screens: screens ?? NSScreen.screens.map(\.visibleFrame))
        }
        applyPresentation(id)
        save()
    }

    func arrange(_ strategy: Arrangement, in bounds: CGRect? = nil) {
        var state = layoutState
        if strategy == .free {
            state.arrangement = .free
            persistLayout(state)
            return
        }
        let ids = activeNotes.filter(\.visible).map(\.id)
        guard !ids.isEmpty else { return }
        let area = bounds ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frames = LayoutEngine.arrange(count: ids.count, in: area, strategy: strategy)
        guard frames.count == ids.count else { return }
        state.snapshot = NoteLayoutState.Snapshot(entries: activeNotes.filter(\.visible).map {
            NoteLayoutState.Entry(id: $0.id, frame: $0.frame, collapsed: isCollapsed($0.id))
        }, arrangement: layoutState.arrangement)
        state.arrangement = strategy
        for id in ids {
            if strategy == .compact { state.collapsed.insert(id) } else { state.collapsed.remove(id) }
        }
        // Durably store the before-image before touching any note frame or live window.
        guard persistLayout(state) else { return }
        isArranging = true
        defer { isArranging = false; save() }
        for (id, frame) in zip(ids, frames) {
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].frame = layoutState.expandedFrame(id: id, rendered: frame, previous: notes[index].frame)
                applyPresentation(id)
            }
        }
    }

    func restoreLayout(screens: [CGRect]? = nil) {
        guard let snapshot = layoutState.snapshot else { return }
        var state = layoutState
        state.arrangement = snapshot.arrangement
        for entry in snapshot.entries {
            if entry.collapsed { state.collapsed.insert(entry.id) } else { state.collapsed.remove(entry.id) }
        }
        guard persistLayout(state) else { return }
        isArranging = true
        defer { isArranging = false; save() }
        for entry in snapshot.entries {
            guard !isTrashed(entry.id), let index = notes.firstIndex(where: { $0.id == entry.id }) else { continue }
            notes[index].frame = restoredPresentation(id: entry.id, frame: entry.frame, screens: screens ?? NSScreen.screens.map(\.visibleFrame))
            applyPresentation(entry.id)
        }
    }

    /// Used by normal termination; a failed write must not silently discard memory edits.
    @discardableResult
    func flushPendingChanges() -> Bool {
        if hasUnsavedChanges { save() }
        return !hasUnsavedChanges
    }

    var syncValues: [SyncValue] { notes.map { SyncValue(content: NoteContent(id: $0.id, text: $0.text, color: $0.color)) } }
    var syncStorageOwned: Bool { canSave }
    var syncWritable: Bool { canSave && !hasUnsavedChanges }
    func applySync(_ value: SyncValue) throws {
        guard syncWritable else { throw SyncCoordinator.Failure.blocked("Local notes have unsaved changes or are read-only.") }
        var updated = notes
        if value.deleted { updated.removeAll { $0.id == value.id } }
        else if let index = updated.firstIndex(where: { $0.id == value.id }) {
            updated[index].text = value.content.text; updated[index].color = value.content.color
        } else { updated.append(StickyNote(id: value.id, text: value.content.text, color: value.content.color, visible: false)) }
        // Commit before publishing. Failed remote applies never replace in-memory edits.
        try CompatibleNoteFile.save(updated, to: fileURL)
        notes = updated
        if value.deleted { windows[value.id]?.orderOut(nil) }
        else if let note = note(value.id) {
            windows[value.id]?.title = windowTitle(for: note)
            windows[value.id]?.backgroundColor = NotePalette.color(note.color)
        }
    }

    private func save() {
        hasUnsavedChanges = true
        guard canSave else { return }
        do {
            try CompatibleNoteFile.save(notes, to: fileURL)
            hasUnsavedChanges = false
            if persistenceError != nil { persistenceError = nil }
        } catch {
            persistenceError = "Changes could not be saved: \(error.localizedDescription)"
            NSLog("Stickies save failed: %@", error.localizedDescription)
        }
    }
}

@MainActor
final class NoteWindowDelegate: NSObject, NSWindowDelegate {
    private let id: UUID
    private weak var store: NoteStore?

    init(id: UUID, store: NoteStore) {
        self.id = id
        self.store = store
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        store?.hide(id)
        return false
    }

    func windowDidMove(_ notification: Notification) { persistFrame(notification) }
    func windowDidResize(_ notification: Notification) { persistFrame(notification) }

    private func persistFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        store?.moved(id, frame: window.frame)
    }
}


/// Delivery and developer previews never implicitly adopt the user's production notes.
enum NoteDataLocation {
    static func directory(environment: [String: String], bundleID: String?, bundleURL: URL,
                          applicationSupport: URL) -> URL {
        if let path = environment["STICKIES_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if bundleID == "dev.douyixuan.stickies.local-preview" {
            return bundleURL.deletingLastPathComponent().appendingPathComponent("preview-data", isDirectory: true)
        }
        let name = bundleID == "dev.douyixuan.stickies.delivery" ? "Stickies Delivery" : "Stickies"
        return applicationSupport.appendingPathComponent(name, isDirectory: true)
    }
}

extension NoteStore: SyncLocalStore {}
