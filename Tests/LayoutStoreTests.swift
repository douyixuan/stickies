import Foundation

@main
struct LayoutStoreTests {
    struct Fixture: Codable {
        var id: UUID
        var text: String
        var color: Int
        var frame: CGRect
        var visible: Bool
    }
    static let bounds = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    static var fixture: [Fixture] {
        (0..<50).map { index -> Fixture in
            let frame = CGRect(x: CGFloat(-1400 + index * 12), y: CGFloat(40 + index * 7), width: 260, height: 220)
            return Fixture(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                    text: "Note \(index)\nUnchanged body", color: index % 5,
                    frame: frame,
                    visible: index < 45)
        }
    }
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] else { fatalError("isolated directory required") }
        let directory = URL(fileURLWithPath: path)
        let url = directory.appendingPathComponent("notes.json")
        let layoutURL = directory.appendingPathComponent("layout.json")
        let phase = CommandLine.arguments.dropFirst().first ?? "setup"
        if phase == "setup" || phase == "corrupt" || phase == "failure" || phase == "notes_failure" {
            try JSONEncoder().encode(fixture).write(to: url)
        }
        if phase == "corrupt" { try Data("invalid layout".utf8).write(to: layoutURL) }
        let store = NoteStore.shared
        let first = fixture[0].id
        if phase == "setup" {
            store.toggleCollapse(first, screens: [bounds])
            precondition(store.note(first)!.frame == fixture[0].frame)
            precondition(store.isCollapsed(first))
            let rendered = store.layoutState.renderedFrame(id: first, expanded: fixture[0].frame)
            precondition(rendered.height == 32 && rendered.maxY == fixture[0].frame.maxY)
            store.arrange(.compact, in: bounds)
            precondition(store.canRestoreLayout)
            precondition(store.layoutState.collapsed.count == 45)
            precondition(store.layoutState.snapshot?.entries.count == 45)
            for note in store.notes {
                if note.visible { precondition(bounds.contains(store.layoutState.renderedFrame(id: note.id, expanded: note.frame))) }
                precondition(note.text == fixture.first { $0.id == note.id }!.text)
            }
            // Later edits and note creation must survive Restore.
            store.updateText(first, "Edited after arrangement")
            let id = store.createNote(showWindow: false)
            store.updateText(id, "New hidden note")
            store.moved(first, frame: CGRect(x: -500, y: 500, width: 260, height: 32))
            precondition(store.note(first)!.frame.height == 220)
            precondition(store.note(first)!.frame.maxY == 532)
        } else if phase == "restore" {
            precondition(store.layoutState.collapsed.count == 45 && store.canRestoreLayout)
            store.restoreLayout(screens: [bounds])
            verifyRestored(store)
        } else if phase == "verify" {
            verifyRestored(store)
            let frames = store.notes.map(\.frame)
            store.arrange(.free, in: bounds)
            precondition(store.notes.map(\.frame) == frames && store.canRestoreLayout)
            for strategy in [Arrangement.grid, .list, .compact] {
                store.arrange(strategy, in: bounds)
                precondition(store.notes.prefix(45).allSatisfy { bounds.contains(store.layoutState.renderedFrame(id: $0.id, expanded: $0.frame)) })
                store.restoreLayout(screens: [bounds])
                verifyRestored(store)
            }
            let small = CGRect(x: -1440, y: 0, width: 1440, height: 400)
            store.arrange(.compact, in: small)
            let compactFrames = store.notes.prefix(45).map { store.layoutState.renderedFrame(id: $0.id, expanded: $0.frame) }
            precondition(store.notes.prefix(45).contains { $0.frame.minY < 0 })
            store.arrange(.grid, in: small)
            store.restoreLayout(screens: [small])
            precondition(store.notes.prefix(45).map { store.layoutState.renderedFrame(id: $0.id, expanded: $0.frame) } == compactFrames,
                         "Restore must retain bottom-edge folded title positions")
        } else if phase == "corrupt" {
            precondition(store.layoutError != nil)
            store.arrange(.compact, in: bounds)
            store.toggleCollapse(first, screens: [bounds])
            precondition(store.notes.map(\.frame) == fixture.map(\.frame))
            precondition(tryRead(layoutURL) == Data("invalid layout".utf8))
        } else if phase == "notes_failure" {
            let backup = directory.appendingPathComponent("original-notes.json")
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            store.arrange(.compact, in: bounds)
            precondition(store.persistenceError != nil && store.canRestoreLayout)
            precondition(store.layoutState.snapshot?.entries.count == 45)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
            print("PASS: note write failure retains durable pre-arrangement snapshot")
            return
        } else if phase == "recover_notes_failure" {
            store.restoreLayout(screens: [bounds])
            precondition(store.notes.map(\.frame) == fixture.map(\.frame))
            precondition(store.notes.map(\.text) == fixture.map(\.text))
            precondition(store.layoutState.collapsed.isEmpty)
        } else if phase == "failure" {
            // A directory at the destination reliably rejects the atomic file write.
            try FileManager.default.createDirectory(at: layoutURL, withIntermediateDirectories: false)
            store.arrange(.compact, in: bounds)
            precondition(store.layoutError != nil && !store.canRestoreLayout)
            precondition(store.notes.map(\.frame) == fixture.map(\.frame))
        }
        precondition(store.persistenceError == nil)
        print("PASS: layout \(phase) — isolated 50-note snapshot/collapse/restore without windows")
    }
    static func tryRead(_ url: URL) -> Data { try! Data(contentsOf: url) }
    @MainActor static func verifyRestored(_ store: NoteStore) {
        precondition(store.notes.count == 51)
        for (before, after) in zip(fixture, store.notes) {
            precondition(before.id == after.id && before.frame == after.frame)
            precondition(before.color == after.color && before.visible == after.visible)
            precondition(after.text == (before.id == fixture[0].id ? "Edited after arrangement" : before.text))
            precondition(store.isCollapsed(after.id) == (after.id == fixture[0].id))
        }
        precondition(store.notes.last!.text == "New hidden note" && !store.notes.last!.visible)
    }
}
