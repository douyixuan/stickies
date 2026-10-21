import Foundation
import CoreGraphics

@main struct DisplayRecoveryTests {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let folded = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let hidden = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let trash = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let screen = CGRect(x: 0, y: 40, width: 1200, height: 800)
    static let removed = CGRect(x: -1400, y: 0, width: 1400, height: 1000)
    static let original = CGRect(x: 300, y: 300, width: 260, height: 220)
    static let offscreen = CGRect(x: -1000, y: 200, width: 260, height: 220)
    @MainActor static func main() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let file = dir.appendingPathComponent("notes.json")
        let phase = CommandLine.arguments[1]
        if phase == "setup" || phase == "failure" {
            try JSONEncoder().encode([StickyNote(id: id, text: "original", frame: original),
                StickyNote(id: folded, text: "folded", frame: offscreen),
                StickyNote(id: hidden, text: "hidden", frame: offscreen, visible: false),
                StickyNote(id: trash, text: "trash", frame: offscreen)]).write(to: file)
        }
        let store = NoteStore.shared
        if phase == "blocked" {
            let before = try Data(contentsOf: file)
            store.recoverDisplayLayout(screens: [screen])
            let after = try Data(contentsOf: file); precondition(before == after && !store.localStateWritable)
            print("PASS: display recovery respects writer lock"); return
        }
        if phase == "restart" {
            precondition(screen.contains(store.note(id)!.frame) && store.note(id)!.text == "edited")
            precondition(store.note(hidden)!.frame == offscreen && !store.note(hidden)!.visible)
            precondition(store.isTrashed(trash) && store.isCollapsed(folded))
            precondition(store.workspaceLayouts.items.count == 1 && store.snapToScreenEdges)
            print("PASS: recovered geometry persists; hidden/trash/folded and named layout remain intact"); return
        }
        precondition(store.moveToTrash(trash))
        store.arrange(.grid, in: removed)
        store.moved(id, frame: original);store.moved(folded, frame: offscreen)
        store.toggleCollapse(folded, screens: [removed])
        store.setSnapToScreenEdges(true)
        _ = store.createWorkspace(name: "Before display removal")!
        let sidecars = ["layout.json", "workspaces.json", "preferences.json", "trash.json"]
        let before = try sidecars.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
        store.beginLayoutGesture(id);store.moved(id, frame: offscreen);store.endLayoutGesture(id, screens: [removed])
        store.updateText(id, "edited")
        precondition(store.canUndoLayout)
        store.recoverDisplayLayout(screens: [removed, screen])
        precondition(store.note(id)!.frame == offscreen, "Already reachable notes must stay where they are")
        store.recoverDisplayLayout(screens: [.zero]);precondition(store.note(id)!.frame == offscreen)
        if phase == "failure" {
            let backup = dir.appendingPathComponent("backup-notes.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            store.recoverDisplayLayout(screens: [screen])
            precondition(store.hasUnsavedChanges && store.canUndoLayout && store.note(id)!.text == "edited")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: backup, to: file)
            store.recoverDisplayLayout(screens: [screen])
            precondition(!store.hasUnsavedChanges && store.canUndoLayout)
            print("PASS: repeated screen notification retries failed persistence without losing content/history"); return
        }
        store.recoverDisplayLayout(screens: [screen])
        precondition(screen.contains(store.note(id)!.frame))
        let expanded = store.note(folded)!.frame
        precondition(screen.contains(store.layoutState.renderedFrame(id: folded, expanded: expanded)))
        precondition(expanded.height == offscreen.height && store.isCollapsed(folded))
        precondition(store.note(hidden)!.frame == offscreen && store.note(trash)!.frame == offscreen)
        let after = try sidecars.map { try Data(contentsOf: dir.appendingPathComponent($0)) };precondition(after == before)
        let stable = try Data(contentsOf: file)
        store.recoverDisplayLayout(screens: [screen])
        let again = try Data(contentsOf: file);precondition(again == stable)
        store.undoLastLayout(screens: [screen]);precondition(store.note(id)!.frame == original)
        // Existing recovery policy makes the entire rendered window fit one display.
        store.moved(id, frame: CGRect(x: -130, y: 200, width: 260, height: 220))
        store.recoverDisplayLayout(screens: [removed, screen])
        precondition([removed, screen].contains(where: { $0.contains(store.note(id)!.frame) }))
        let reduced = CGRect(x: 0, y: 40, width: 400, height: 300)
        store.recoverDisplayLayout(screens: [reduced])
        precondition(reduced.contains(store.note(id)!.frame) && store.note(id)!.text == "edited")
        let child = Process();child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]);child.arguments = ["blocked"]
        try child.run();child.waitUntilExit();precondition(child.terminationStatus == 0)
        print("PASS: removal/usable-area recovery, empty screen deferral, no-op, content/history/sidecar preservation")
    }
}
