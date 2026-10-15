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
    @Published private(set) var persistenceError: String?
    private var canSave = true
    private var lockFD: Int32 = -1
    private var isLockedByAnotherInstance = false
    @Published private(set) var keepOnTop = false
    private var preferencesURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("preferences.json") }

    private struct Preferences: Codable { var keepOnTop: Bool }


    private let fileURL: URL = {
        if let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("notes.json")
        }
        if Bundle.main.bundleIdentifier == "dev.douyixuan.stickies.local-preview" {
            let directory = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("preview-data", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("notes.json")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stickies", isDirectory: true)
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
        if let data = try? Data(contentsOf: preferencesURL),
           let preferences = try? JSONDecoder().decode(Preferences.self, from: data) {
            keepOnTop = preferences.keepOnTop
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            notes = try NotePersistence.load(from: fileURL)
        } catch {
            canSave = false
            persistenceError = "Could not read notes. Original file preserved at \(fileURL.path). \(error.localizedDescription)"
        }
    }

    deinit {
        if lockFD >= 0 { close(lockFD) }
    }

    func setKeepOnTop(_ enabled: Bool) {
        keepOnTop = enabled
        for window in windows.values { window.level = enabled ? .floating : .normal }
        guard canSave else { return }
        do {
            try JSONEncoder().encode(Preferences(keepOnTop: enabled)).write(to: preferencesURL, options: .atomic)
        } catch {
            persistenceError = "Window preference could not be saved: \(error.localizedDescription)"
        }
    }

    func hideAll() {
        for id in notes.map(\.id) { hide(id) }
    }

    func createNote() {
        let offset = CGFloat(notes.count % 8) * 28
        let note = StickyNote(frame: CGRect(x: 120 + offset, y: 220 + offset, width: 260, height: 220))
        notes.append(note)
        save()
        show(note.id)
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
        for note in notes { show(note.id) }
    }

    func restoreWindows() {
        if notes.isEmpty && canSave {
            createNote()
            if let id = notes.first?.id {
                updateText(id, "Welcome to Stickies\n\nWrite here. Drag the title bar to move this note, or drag a corner to resize.\n\nUse the menu bar note icon to create notes, change layout, or show hidden notes. Your changes stay on this Mac.")
            }
        } else {
            for note in notes where note.visible { show(note.id) }
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
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].visible = true
        if let existing = windows[id] {
            let restoredFrame = LayoutEngine.restore(existing.frame, screens: NSScreen.screens.map(\.visibleFrame))
            existing.setFrame(restoredFrame, display: true)
            notes[index].frame = existing.frame
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            save()
            return
        }
        notes[index].frame = LayoutEngine.restore(notes[index].frame, screens: NSScreen.screens.map(\.visibleFrame))
        let note = notes[index]
        let window = NSWindow(
            contentRect: note.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.setFrame(note.frame, display: false)
        window.title = windowTitle(for: note)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NotePalette.color(note.color)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let header = NSHostingView(rootView: NoteHeaderControls(noteID: id))
        header.frame = NSRect(x: 0, y: 0, width: 60, height: 22)
        header.toolTip = "Note actions and colors. Drag the empty title bar to move this note."
        accessory.view = header
        window.addTitlebarAccessoryViewController(accessory)
        let dragAccessory = NSTitlebarAccessoryViewController()
        dragAccessory.layoutAttribute = .left
        let dragHint = NoteDragHint(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        dragHint.toolTip = "Drag this title bar to move the note. Select text below to edit."
        dragAccessory.view = dragHint
        window.addTitlebarAccessoryViewController(dragAccessory)
        window.level = keepOnTop ? .floating : .normal
        window.minSize = NSSize(width: 180, height: 120)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NoteView(noteID: id))
        let delegate = NoteWindowDelegate(id: id, store: self)
        window.delegate = delegate
        windows[id] = window
        delegates[id] = delegate
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
        notes[index].frame = frame
        save()
    }

    func arrange(_ strategy: Arrangement) {
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let ids = notes.filter(\.visible).map(\.id)
        let frames = LayoutEngine.arrange(count: ids.count, in: area, strategy: strategy)
        isArranging = true
        defer { isArranging = false; save() }
        for (id, frame) in zip(ids, frames) {
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].frame = frame
            }
            windows[id]?.setFrame(frame, display: true, animate: false)
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            try NotePersistence.save(notes, to: fileURL)
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

