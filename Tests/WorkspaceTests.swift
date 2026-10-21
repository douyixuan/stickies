import Foundation

@main struct WorkspaceTests {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let deleted = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let original = CGRect(x: -900, y: 200, width: 260, height: 220)
    static let moved = CGRect(x: -600, y: 400, width: 300, height: 250)
    static let screen = CGRect(x: -1200, y: 40, width: 1200, height: 800)
    static let right = CGRect(x: 0, y: 0, width: 1400, height: 1000)
    @MainActor static func main() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let file = dir.appendingPathComponent("notes.json")
        let catalog = dir.appendingPathComponent("workspaces.json")
        let phase = CommandLine.arguments[1]
        if ["setup", "failure", "corrupt", "stale", "invalid"].contains(phase) {
            try JSONEncoder().encode([StickyNote(id: id, text: "initial", color: 1, frame: original),
                                      StickyNote(id: deleted, text: "trash me", frame: moved)]).write(to: file)
        }
        if phase == "corrupt" { try Data("broken".utf8).write(to: catalog) }
        if phase == "invalid" {
            try JSONEncoder().encode(WorkspaceLayouts(schemaVersion: 9)).write(to: catalog)
        }
        if phase == "stale" {
            let item = WorkspaceLayouts.Item(id: stale, name: "Imported local layout", placements: [
                .init(id: stale, frame: original), .init(id: deleted, frame: original), .init(id: id, frame: moved)])
            try JSONEncoder().encode(WorkspaceLayouts(items: [item])).write(to: catalog)
        }
        let store = NoteStore.shared
        if phase == "blocked" {
            let before = try Data(contentsOf: catalog)
            precondition(!store.canUseWorkspaces && store.createWorkspace(name: "locked") == nil)
            precondition(!store.saveWorkspace(stale) && !store.switchWorkspace(stale, screens: [screen]))
            let after = try Data(contentsOf: catalog); precondition(before == after)
            print("PASS: second process cannot modify workspaces"); return
        }
        if ["corrupt", "invalid"].contains(phase) {
            let before = try Data(contentsOf: catalog)
            precondition(!store.canUseWorkspaces && store.workspaceError != nil)
            precondition(store.createWorkspace(name: "replacement") == nil)
            let after = try Data(contentsOf: catalog); precondition(before == after)
            precondition(store.note(id)!.text == "initial")
            print("PASS: corrupt/future workspace data preserved"); return
        }
        if phase == "restart" {
            precondition(store.workspaceLayouts.items.map(\.name) == ["Desk", "Focus"])
            precondition(store.note(id)!.frame == original && store.note(id)!.text == "edited")
            precondition(store.note(id)!.color == 2 && !store.note(id)!.visible && store.isCollapsed(id))
            precondition(store.snapToScreenEdges && store.canRestoreLayout && !store.canUndoLayout)
            let focus = store.workspaceLayouts.items[1].id
            precondition(store.switchWorkspace(focus, screens: [screen]))
            precondition(store.note(id)!.frame == moved)
            print("PASS: named layouts/current geometry survive restart; selection does not auto-overwrite geometry"); return
        }
        if phase == "stale" {
            precondition(store.moveToTrash(deleted))
            precondition(store.switchWorkspace(stale, screens: [screen]))
            precondition(store.notes.count == 2 && store.note(stale) == nil && store.isTrashed(deleted))
            precondition(store.note(deleted)!.frame == moved && store.note(id)!.frame == moved)
            print("PASS: missing and trashed IDs skipped without recreating content"); return
        }
        precondition(store.canUseWorkspaces && store.workspaceLayouts.items.isEmpty)
        let notesBefore = try Data(contentsOf: file)
        precondition(store.createWorkspace(name: "  ") == nil)
        let desk = store.createWorkspace(name: " Desk ")!
        precondition(store.createWorkspace(name: "desk") == nil)
        precondition(!store.renameWorkspace(desk, name: String(repeating: "x", count: 81)))
        let afterCreate = try Data(contentsOf: file); precondition(afterCreate == notesBefore)
        store.moved(id, frame: moved)
        let focus = store.createWorkspace(name: "Second")!
        precondition(!store.renameWorkspace(focus, name: "DESK"))
        precondition(store.renameWorkspace(focus, name: "Focus"))
        if phase == "failure" {
            let backup = dir.appendingPathComponent("workspaces-backup.json")
            try FileManager.default.moveItem(at: catalog, to: backup)
            try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
            precondition(!store.renameWorkspace(desk, name: "Failed"))
            precondition(!store.saveWorkspace(desk) && store.createWorkspace(name: "Failed new") == nil)
            precondition(store.workspaceLayouts.items[0].name == "Desk")
            precondition(store.workspaceLayouts.items[0].placements[0].frame == original)
            try FileManager.default.removeItem(at: catalog)
            try FileManager.default.moveItem(at: backup, to: catalog)
            precondition(store.renameWorkspace(desk, name: "Desk"))
            precondition(store.saveWorkspace(focus))
            precondition(store.createWorkspace(name: "Recovered") != nil)
            let saved = dir.appendingPathComponent("notes-backup.json")
            try FileManager.default.moveItem(at: file, to: saved)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            precondition(!store.switchWorkspace(desk, screens: [screen]))
            precondition(store.hasUnsavedChanges && store.canUndoLayout && store.note(id)!.frame == original)
            store.updateText(id, "unsaved edit")
            precondition(!store.switchWorkspace(focus, screens: [screen]))
            precondition(store.note(id)!.text == "unsaved edit" && store.note(id)!.frame == original)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: saved, to: file)
            precondition(store.switchWorkspace(desk, screens: [screen]))
            precondition(!store.hasUnsavedChanges && store.note(id)!.text == "unsaved edit")
            store.undoLastLayout(screens: [screen]); precondition(store.note(id)!.frame == moved)
            let disk = try CompatibleNoteFile.decode(Data(contentsOf: file))
            precondition(disk.first(where: { $0.id == id })!.text == "unsaved edit")
            print("PASS: catalog atomic failures and note-write failure retry preserve content and Undo"); return
        }
        store.moved(id, frame: original)
        precondition(store.saveWorkspace(focus))
        precondition(store.workspaceLayouts.items[1].placements[0].frame == original)
        store.moved(id, frame: moved); precondition(store.saveWorkspace(focus))
        store.updateText(id, "edited"); store.setColor(id, 2)
        let added = store.createNote(showWindow: false)!
        let addedFrame = store.note(added)!.frame
        store.arrange(.grid, in: screen)
        let restoreBytes = try Data(contentsOf: dir.appendingPathComponent("layout.json"))
        store.moved(id, frame: moved)
        precondition(store.switchWorkspace(desk, screens: [right, screen]))
        precondition(store.note(id)!.frame == original)
        precondition(store.switchWorkspace(desk, screens: [screen, right])) // no-op preserves Undo
        store.undoLastLayout(screens: [screen]); precondition(store.note(id)!.frame == moved)
        let restoreAfter = try Data(contentsOf: dir.appendingPathComponent("layout.json")); precondition(restoreAfter == restoreBytes)
        // A newly created note is never moved by an older saved layout.
        store.moved(added, frame: addedFrame)
        precondition(store.switchWorkspace(desk, screens: [screen]))
        precondition(store.note(added)!.frame == addedFrame && store.note(id)!.text == "edited" && store.note(id)!.color == 2)
        // Removed display recovery uses existing bounds logic, not Snap's threshold.
        store.setSnapToScreenEdges(true)
        precondition(store.switchWorkspace(desk, screens: [right]))
        precondition(right.contains(store.note(id)!.frame))
        precondition(store.switchWorkspace(desk, screens: [.zero, screen]))
        precondition(store.note(id)!.frame == original)
        store.hide(id); store.toggleCollapse(id, screens: [screen])
        precondition(store.switchWorkspace(focus, screens: [screen]))
        precondition(store.isCollapsed(id) && !store.note(id)!.visible && store.note(id)!.frame == moved)
        precondition(store.switchWorkspace(desk, screens: []))
        precondition(store.note(id)!.frame == original)
        let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["blocked"]
        try child.run(); child.waitUntilExit(); precondition(child.terminationStatus == 0)
        let encoded = try String(contentsOf: catalog, encoding: .utf8)
        precondition(!encoded.contains("edited") && !encoded.contains("color") && !encoded.contains("visible"))
        print("PASS: create/rename/save/switch, content separation, no-op Undo, Restore/Snap, folded/hidden/new notes, screen recovery")
    }
}
