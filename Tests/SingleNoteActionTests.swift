import Foundation

@main struct SingleNoteActionTests {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("stickies-single-") else { fatalError("isolated profile required") }
        let directory = URL(fileURLWithPath: path)
        let notesURL = directory.appendingPathComponent("notes.json")
        let prefsURL = directory.appendingPathComponent("preferences.json")
        let phase = CommandLine.arguments[1]
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        if phase != "restart" {
            try Data("""
            [{"id":"\(first)","text":"first","color":2,"frame":[[120,180],[260,220]],"visible":false},{"id":"\(second)","text":"second","color":1,"frame":[[420,180],[260,220]],"visible":false}]
            """.utf8).write(to: notesURL)
        }
        if phase == "legacy" { try Data("{\"keepOnTop\":true}".utf8).write(to: prefsURL) }
        if phase == "corrupt" { try Data("{\"keepOnTop\":false,\"floatingOverrides\":{\"invalid\":true}}".utf8).write(to: prefsURL) }
        let store = NoteStore.shared
        let baseline = try Data(contentsOf: notesURL)
        switch phase {
        case "setup":
            store.setWindowMode(.desktop)
            store.setNoteFloating(first, true)
            precondition(store.effectiveWindowMode(first) == .floating)
            precondition(store.effectiveWindowMode(second) == .desktop)
            store.setWindowMode(.floating)
            store.setNoteFloating(second, false)
            precondition(store.effectiveWindowMode(second) == .standard)
            store.setWindowMode(.desktop)
            precondition(store.effectiveWindowMode(first) == .floating && store.effectiveWindowMode(second) == .desktop)
            store.setNoteFloating(second, nil)
            precondition(!store.hasWindowModeOverride(second))
            precondition(tryData(notesURL) == baseline)
        case "restart":
            precondition(store.windowMode == .desktop && store.effectiveWindowMode(first) == .floating)
            precondition(store.effectiveWindowMode(second) == .desktop)
            let oldFrame = store.note(first)!.frame
            var remote = store.syncValues.first { $0.id == first }!
            remote.content.text = "new remote content"
            try store.applySync(remote)
            precondition(store.effectiveWindowMode(first) == .floating && store.note(first)!.frame == oldFrame)
            let wire = String(data: try JSONEncoder().encode(store.syncValues), encoding: .utf8)!
            precondition(!wire.contains("floating") && !wire.contains("frame") && !wire.contains("visible"))
            let saved = tryData(notesURL)
            precondition(store.moveToTrash(first))
            precondition(store.isTrashed(first) && !store.isTrashed(second))
            precondition(tryData(notesURL) == saved)
            remote.content.text = "newer while in Trash"; try store.applySync(remote)
            let newer = tryData(notesURL)
            precondition(store.restoreFromTrash(first, showWindow: false))
            precondition(tryData(notesURL) == newer && store.note(first)!.text == "newer while in Trash")
            precondition(store.effectiveWindowMode(first) == .floating)
        case "legacy":
            precondition(store.effectiveWindowMode(first) == .floating && !store.hasWindowModeOverride(first))
            store.setNoteFloating(first, false)
            precondition(store.effectiveWindowMode(first) == .standard && store.effectiveWindowMode(second) == .floating)
            store.setNoteFloating(first, nil)
            precondition(store.effectiveWindowMode(first) == .floating)
            precondition(tryData(notesURL) == baseline)
        case "failure":
            try FileManager.default.createDirectory(at: prefsURL, withIntermediateDirectories: false)
            store.setNoteFloating(first, true)
            precondition(store.preferenceError != nil && !store.hasWindowModeOverride(first))
            precondition(store.effectiveWindowMode(first) == .standard && tryData(notesURL) == baseline)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("trash.json"), withIntermediateDirectories: false)
            precondition(!store.moveToTrash(first) && !store.isTrashed(first))
            precondition(store.trashError != nil && tryData(notesURL) == baseline)
        case "unsaved":
            let backup = directory.appendingPathComponent("saved-notes")
            try FileManager.default.moveItem(at: notesURL, to: backup)
            try FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: false)
            store.updateText(first, "latest unsaved text")
            precondition(store.hasUnsavedChanges && !store.moveToTrash(first) && !store.isTrashed(first))
            precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("trash.json").path))
            try FileManager.default.removeItem(at: notesURL)
            try FileManager.default.moveItem(at: backup, to: notesURL)
            precondition(store.moveToTrash(first))
            precondition(store.restoreFromTrash(first, showWindow: false))
            precondition(store.note(first)!.text == "latest unsaved text")
        case "corrupt":
            let before = tryData(prefsURL)
            precondition(store.preferenceError != nil)
            store.setNoteFloating(first, true)
            precondition(!store.hasWindowModeOverride(first) && tryData(prefsURL) == before)
        case "import":
            // This separate profile receives content only, without the sender's local pin.
            let remote = SyncValue(content: NoteContent(id: first, text: "remote", color: 3))
            try store.applySync(remote)
            precondition(store.effectiveWindowMode(first) == .standard && !store.hasWindowModeOverride(first))
            precondition(store.note(first)!.text == "remote")
        default: fatalError("unknown phase")
        }
        print("PASS: single-note \(phase), isolated without windows")
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
