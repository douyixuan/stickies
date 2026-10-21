import Foundation

@main struct LayoutUndoTests {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let original = CGRect(x: 100, y: 200, width: 260, height: 220)
    static let bounds = CGRect(x: 0, y: 0, width: 1400, height: 1000)
    @MainActor static func main() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let file = dir.appendingPathComponent("notes.json")
        let phase = CommandLine.arguments[1]
        if phase == "setup" || phase == "failure" {
            try JSONEncoder().encode([StickyNote(id: id, text: "initial", color: 1, frame: original, visible: true),
                                      StickyNote(text: "other visible", frame: CGRect(x: 800, y: 300, width: 260, height: 220))]).write(to: file)
        }
        let store = NoteStore.shared
        if phase == "blocked" {
            precondition(!store.localStateWritable && !store.canUndoLayout)
            let before = try Data(contentsOf: file)
            store.beginLayoutGesture(id); store.moved(id, frame: .zero); store.undoLastLayout(screens: [bounds])
            let after = try Data(contentsOf: file); precondition(after == before)
            precondition(!CanvasBoardStore(notes: store).canUndo)
            print("PASS: locked instance cannot undo or write")
            return
        }
        if phase == "restart" {
            precondition(!store.canUndoLayout, "Session undo is intentionally cleared at restart")
            precondition(store.canRestoreLayout, "Durable arrangement Restore must remain available")
            precondition(store.note(id)!.text == "edited" && store.note(id)!.color == 2)
            precondition(store.note(id)!.frame == original)
            precondition(!CanvasBoardStore(notes: store).canUndo)
            print("PASS: restart retains data and durable Restore, not session undo")
            return
        }
        precondition(!store.canUndoLayout)
        store.undoLastLayout(screens: [bounds])
        // A click without movement must not create undo; an entire drag/resize is one operation.
        store.beginLayoutGesture(id);store.endLayoutGesture(id)
        precondition(!store.canUndoLayout)
        store.beginLayoutGesture(id)
        store.moved(id, frame: CGRect(x: 300, y: 300, width: 300, height: 250))
        store.moved(id, frame: CGRect(x: 400, y: 400, width: 340, height: 270))
        store.endLayoutGesture(id)
        precondition(store.canUndoLayout)
        store.updateText(id, "edited");store.setColor(id, 2)
        let added = store.createNote(showWindow: false)!
        let newFrame = store.note(added)!.frame
        if phase == "failure" {
            let saved = dir.appendingPathComponent("saved.json")
            try FileManager.default.moveItem(at: file, to: saved)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            store.undoLastLayout(screens: [bounds])
            precondition(store.hasUnsavedChanges && store.canUndoLayout)
            precondition(store.note(id)!.text == "edited")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: saved, to: file)
            store.undoLastLayout(screens: [bounds])
            precondition(!store.hasUnsavedChanges && !store.canUndoLayout)
            precondition(store.note(id)!.frame == original)
            print("PASS: failed undo save retains content and retry history")
            return
        }
        store.undoLastLayout(screens: [bounds])
        precondition(store.note(id)!.frame == original && !store.canUndoLayout)
        precondition(store.note(id)!.text == "edited" && store.note(id)!.color == 2)
        precondition(store.note(added)!.frame == newFrame)
        store.arrange(.grid, in: bounds)
        store.arrange(.grid, in: bounds) // A no-op must not replace the useful undo.
        let durable = try Data(contentsOf: dir.appendingPathComponent("layout.json"))
        store.undoLastLayout(screens: [bounds])
        precondition(store.note(id)!.frame == original)
        let afterLayout = try Data(contentsOf: dir.appendingPathComponent("layout.json")); precondition(afterLayout == durable)
        // Undo geometry does not restore folded state or hidden visibility.
        store.arrange(.compact, in: bounds);store.hide(id)
        store.undoLastLayout(screens: [bounds])
        precondition(store.isCollapsed(id) && !store.note(id)!.visible)
        precondition(store.note(id)!.frame == original)
        // Build a changed layout, restore it twice, then undo the one meaningful restore.
        store.arrange(.list, in: bounds)
        let beforeRestore = store.notes.map(\.frame)
        store.restoreLayout(screens: [bounds]);precondition(store.canUndoLayout)
        store.restoreLayout(screens: [bounds])
        store.undoLastLayout(screens: [bounds]);precondition(!store.canUndoLayout)
        precondition(store.notes.map(\.frame) == beforeRestore)
        let board = CanvasBoardStore(notes: store)
        board.ensureEntries(store.activeNotes.map(\.id))
        let firstBoardFrame = board.state.frames[id]!
        let bytes = try Data(contentsOf: file)
        board.move(id, to: CGPoint(x: 700, y: 700));precondition(board.canUndo)
        board.undo();precondition(board.state.frames[id] == firstBoardFrame && !board.canUndo)
        board.arrange(.compact, ids: store.activeNotes.map(\.id), columns: 2)
        let later = store.createNote(showWindow: false)!
        board.ensureEntries(store.activeNotes.map(\.id));let laterFrame = board.state.frames[later]
        board.undo();precondition(board.state.frames[id] == firstBoardFrame && board.state.frames[later] == laterFrame)
        // Board write failure keeps both current geometry and pending undo.
        board.move(id, to: CGPoint(x: 600, y: 600))
        let boardFile = dir.appendingPathComponent("canvas-layout.json")
        let boardBackup = dir.appendingPathComponent("board-backup.json")
        try FileManager.default.moveItem(at: boardFile, to: boardBackup)
        try FileManager.default.createDirectory(at: boardFile, withIntermediateDirectories: false)
        board.undo();precondition(board.canUndo && board.state.frames[id]!.minX == 600)
        try FileManager.default.removeItem(at: boardFile)
        try FileManager.default.moveItem(at: boardBackup, to: boardFile)
        let noteBytes = try Data(contentsOf: file)
        board.undo();precondition(!board.canUndo && board.state.frames[id] == firstBoardFrame)
        let afterBoardUndo = try Data(contentsOf: file); precondition(afterBoardUndo == noteBytes)
        precondition(!bytes.isEmpty)
        // Arrange before a new card's onChange initialization still has a complete before-image.
        let fallbackID = store.createNote(showWindow: false)!
        let fallback = CanvasBoardState.frames(for: store.activeNotes.map(\.id), strategy: .grid, columns: 2)[fallbackID]!
        board.arrange(.compact, ids: store.activeNotes.map(\.id), columns: 2)
        board.undo(); precondition(board.state.frames[fallbackID] == fallback)
        // A failed durable arrangement must not replace a prior successful gesture undo.
        store.beginLayoutGesture(id)
        let rendered = store.layoutState.renderedFrame(id: id, expanded: CGRect(x: 200, y: 200, width: 260, height: 220))
        store.moved(id, frame: rendered);store.endLayoutGesture(id)
        let layout = dir.appendingPathComponent("layout.json")
        let savedLayout = dir.appendingPathComponent("layout-backup.json")
        try FileManager.default.moveItem(at: layout, to: savedLayout)
        try FileManager.default.createDirectory(at: layout, withIntermediateDirectories: false)
        store.arrange(.grid, in: bounds)
        precondition(store.layoutError != nil && store.canUndoLayout)
        try FileManager.default.removeItem(at: layout)
        try FileManager.default.moveItem(at: savedLayout, to: layout)
        store.undoLastLayout(screens: [bounds]);precondition(store.note(id)!.frame == original)
        // A second process must respect the original writer's lock.
        let child = Process();child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]);child.arguments = ["blocked"]
        try child.run();child.waitUntilExit();precondition(child.terminationStatus == 0)
        print("PASS: gesture coalescing, arrangement undo, content/new-note preservation, board undo/failure and lock")
    }
}
