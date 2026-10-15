import AppKit
import SwiftUI

struct StickyNote: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var color: Int = 0
    var frame: CGRect = CGRect(x: 120, y: 180, width: 260, height: 220)
    var visible: Bool = true
}

enum Arrangement {
    case grid, list
}

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [StickyNote] = []
    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: NoteWindowDelegate] = [:]
    private var isArranging = false

    private let fileURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stickies", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([StickyNote].self, from: data) {
            notes = stored
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
        for note in notes where note.visible { show(note.id) }
    }

    func show(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].visible = true
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            save()
            return
        }
        let note = notes[index]
        let window = NSWindow(
            contentRect: note.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
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
            windows[id]?.setFrame(frame, display: true, animate: true)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Stickies save failed: %@", error.localizedDescription)
        }
    }
}

final class NoteWindowDelegate: NSObject, NSWindowDelegate {
    private let id: UUID
    private weak var store: NoteStore?

    init(id: UUID, store: NoteStore) {
        self.id = id
        self.store = store
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor [weak store] in store?.hide(self.id) }
        return false
    }

    func windowDidMove(_ notification: Notification) { persistFrame(notification) }
    func windowDidResize(_ notification: Notification) { persistFrame(notification) }

    private func persistFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor [weak store] in store?.moved(self.id, frame: window.frame) }
    }
}
