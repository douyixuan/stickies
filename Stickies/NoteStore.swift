import AppKit
import SwiftUI

struct StickyNote: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var color: Int = 0
    var frame: CGRect = CGRect(x: 120, y: 180, width: 260, height: 220)
    var visible: Bool = true
}

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [StickyNote] = []
    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: NoteWindowDelegate] = [:]
    private var isArranging = false
    @Published private(set) var persistenceError: String?
    private var canSave = true

    private let fileURL: URL = {
        if let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("notes.json")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stickies", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }()

    private init() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            notes = try JSONDecoder().decode([StickyNote].self, from: Data(contentsOf: fileURL))
        } catch {
            canSave = false
            persistenceError = "Could not read notes. Original file preserved at \(fileURL.path). \(error.localizedDescription)"
        }
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
        save()
    }

    func setColor(_ id: UUID, _ color: Int) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].color = color
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
        }
    }

    func show(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].visible = true
        if let existing = windows[id] {
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
        window.title = "Sticky Note"
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
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
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
