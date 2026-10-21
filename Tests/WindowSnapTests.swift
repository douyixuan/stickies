import Foundation

@main struct WindowSnapTests {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let screen = CGRect(x: -1200, y: 40, width: 1200, height: 800)
    static let right = CGRect(x: 0, y: 0, width: 1400, height: 1000)
    static let original = CGRect(x: -900, y: 300, width: 260, height: 220)
    @MainActor static func main() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let notes = dir.appendingPathComponent("notes.json"), prefs = dir.appendingPathComponent("preferences.json")
        let phase = CommandLine.arguments[1]
        if phase == "setup" || phase == "failure" || phase == "corrupt" {
            try JSONEncoder().encode([StickyNote(id: id, text: "unchanged", color: 2, frame: original)]).write(to: notes)
            try Data((phase == "corrupt" ? "broken" : "{\"keepOnTop\":false,\"windowMode\":\"desktop\"}").utf8).write(to: prefs)
        }
        let store = NoteStore.shared
        if phase == "blocked" {
            let before = try Data(contentsOf: prefs)
            store.setSnapToScreenEdges(true)
            precondition(!store.canChangeWindowPreferences)
            let after = try Data(contentsOf: prefs);precondition(after == before)
            print("PASS: lock blocks Snap preference writes");return
        }
        if phase == "restart" {
            precondition(store.snapToScreenEdges && store.windowMode == .desktop)
            precondition(store.note(id)!.frame.minX == screen.minX)
            precondition(store.note(id)!.text == "edited after drag")
            precondition(!store.canUndoLayout)
            print("PASS: Snap preference and geometry persist without durable undo");return
        }
        precondition(!store.snapToScreenEdges)
        if phase == "corrupt" {
            store.setSnapToScreenEdges(true)
            precondition(!store.snapToScreenEdges && !store.canChangeWindowPreferences)
            let preserved = try Data(contentsOf: prefs);precondition(preserved == Data("broken".utf8))
            print("PASS: corrupt preferences remain untouched");return
        }
        if phase == "failure" {
            let old = dir.appendingPathComponent("prefs-backup.json")
            try FileManager.default.moveItem(at: prefs, to: old)
            try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: false)
            store.setSnapToScreenEdges(true);precondition(!store.snapToScreenEdges && store.preferenceError != nil)
            print("PASS: failed preference write retains disabled Snap");return
        }
        let near = CGRect(x: -1193, y: 44, width: 260, height: 220)
        let expected = CGRect(x: -1200, y: 40, width: 260, height: 220)
        precondition(LayoutEngine.snapToScreenEdges(near, screens: [right, screen]) == expected)
        precondition(LayoutEngine.snapToScreenEdges(near, screens: [screen, right]) == expected)
        let top = CGRect(x: -265, y: 615, width: 260, height: 220)
        precondition(LayoutEngine.snapToScreenEdges(top, screens: [screen]).origin == CGPoint(x: -260, y: 620))
        let far = CGRect(x: -1187, y: 100, width: 260, height: 220)
        precondition(LayoutEngine.snapToScreenEdges(far, screens: [screen]) == far)
        let off = CGRect(x: -3000, y: 100, width: 260, height: 220)
        precondition(LayoutEngine.snapToScreenEdges(off, screens: [screen]) == off)
        let oversized = CGRect(x: -1200, y: 40, width: 1300, height: 900)
        precondition(LayoutEngine.snapToScreenEdges(oversized, screens: [screen]) == oversized)
        precondition(LayoutEngine.snapToScreenEdges(near, screens: []) == near)
        let boundary = CGRect(x: -130, y: 100, width: 260, height: 220)
        precondition(LayoutEngine.snapToScreenEdges(boundary, screens: [right, screen]) == LayoutEngine.snapToScreenEdges(boundary, screens: [screen, right]))
        // Disabled by default and ordinary programmatic geometry stays free.
        store.beginLayoutGesture(id);store.moved(id, frame: near);store.endLayoutGesture(id, screens: [screen])
        precondition(store.note(id)!.frame == near)
        store.undoLastLayout(screens: [screen])
        let beforeToggle = try Data(contentsOf: notes)
        store.setSnapToScreenEdges(true);precondition(store.snapToScreenEdges)
        let afterToggle = try Data(contentsOf: notes);precondition(afterToggle == beforeToggle)
        store.setNoteFloating(id, true);precondition(store.snapToScreenEdges)
        store.setNoteFloating(id, nil);store.setWindowMode(.desktop);precondition(store.snapToScreenEdges)
        store.moved(id, frame: near);precondition(store.note(id)!.frame == near)
        store.moved(id, frame: original)
        for _ in 0..<3 {
            store.beginLayoutGesture(id);store.moved(id, frame: near);store.endLayoutGesture(id, screens: [screen, right])
            precondition(store.note(id)!.frame == expected)
            store.updateText(id, "edited after drag")
            store.undoLastLayout(screens: [screen]);precondition(store.note(id)!.frame == original)
            precondition(store.note(id)!.text == "edited after drag" && store.note(id)!.color == 2)
        }
        // Resizing cannot acquire snapping even when an edge is near.
        let resized = CGRect(x: -1195, y: 100, width: 300, height: 240)
        store.beginLayoutGesture(id);store.moved(id, frame: resized);store.endLayoutGesture(id, screens: [screen])
        precondition(store.note(id)!.frame == resized)
        store.undoLastLayout(screens: [screen]);precondition(store.note(id)!.frame == original)
        // A folded note snaps by its rendered title without changing its expanded dimensions.
        store.toggleCollapse(id, screens: [screen])
        let folded = CGRect(x: -1194, y: 805, width: 260, height: 32)
        store.beginLayoutGesture(id);store.moved(id, frame: folded);store.endLayoutGesture(id, screens: [screen])
        precondition(store.note(id)!.frame.width == 260 && store.note(id)!.frame.height == 220)
        precondition(store.layoutState.renderedFrame(id: id, expanded: store.note(id)!.frame).maxY == screen.maxY)
        store.undoLastLayout(screens: [screen]);store.toggleCollapse(id, screens: [screen])
        // Arrangement stays deterministic and its undo ignores the Snap toggle.
        store.arrange(.grid, in: screen)
        precondition(store.note(id)!.frame == LayoutEngine.arrange(count: 1, in: screen, strategy: .grid)[0])
        store.undoLastLayout(screens: [screen]);precondition(store.note(id)!.frame == original)
        store.beginLayoutGesture(id);store.moved(id, frame: near);store.endLayoutGesture(id, screens: [screen])
        // A failed final snap save keeps memory edits, the before-image and retry state.
        store.undoLastLayout(screens: [screen])
        store.beginLayoutGesture(id);store.moved(id, frame: near)
        let savedNotes = dir.appendingPathComponent("notes-backup.json")
        try FileManager.default.moveItem(at: notes, to: savedNotes)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: false)
        store.endLayoutGesture(id, screens: [screen])
        precondition(store.hasUnsavedChanges && store.canUndoLayout && store.note(id)!.frame == expected)
        precondition(store.note(id)!.text == "edited after drag")
        try FileManager.default.removeItem(at: notes)
        try FileManager.default.moveItem(at: savedNotes, to: notes)
        precondition(store.flushPendingChanges() && !store.hasUnsavedChanges)
        let child = Process();child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]);child.arguments = ["blocked"]
        try child.run();child.waitUntilExit();precondition(child.terminationStatus == 0)
        print("PASS: edge threshold, negative/multiple screens, free/resize paths, repeated drags, folded dimensions, Undo and arrangement")
    }
}
