import Foundation

@main
struct CanvasBoardTests {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] else { fatalError("isolated directory required") }
        let directory = URL(fileURLWithPath: path)
        let url = directory.appendingPathComponent("canvas-layout.json")
        let phase = CommandLine.arguments.dropFirst().first ?? "setup"
        let store = NoteStore.shared
        if phase != "restore" {
            for index in 0..<50 {
                let id = store.createNote(showWindow: false)
                store.updateText(id, "Board note \(index)")
            }
        }
        if phase == "corrupt" { try Data("invalid board".utf8).write(to: url) }
        let board = CanvasBoardStore(notes: store)
        let ids = store.notes.map(\.id)
        precondition(CanvasBoardState.frames(for: ids + ids, strategy: .grid, columns: 0).count == ids.count)
        let notesURL = directory.appendingPathComponent("notes.json")
        let baseline = try Data(contentsOf: notesURL)
        if phase == "setup" {
            board.ensureEntries(ids)
            precondition(board.state.frames.count == 50)
            let original = board.state.frames
            for a in ids.indices {
                for b in ids.indices where b > a { precondition(!original[ids[a]]!.intersects(original[ids[b]]!)) }
            }
            for strategy in [Arrangement.grid, .list, .compact] {
                board.arrange(strategy, ids: ids, columns: 4)
                precondition(board.state.frames.count == 50)
                precondition(board.state.snapshot?.frames == original)
                board.restore()
                precondition(board.state.frames == original)
            }
            board.move(ids[0], to: CGPoint(x: -10, y: -20))
            precondition(board.state.frames[ids[0]]!.origin == .zero)
            board.move(ids[0], to: CGPoint(x: 1800, y: 1100))
            board.arrange(.compact, ids: ids, columns: 4)
            precondition(board.state.frames.values.allSatisfy { $0.height == 54 })
            precondition(board.state.snapshot?.frames[ids[0]]?.origin == CGPoint(x: 1800, y: 1100))
        } else if phase == "restore" {
            precondition(board.state.frames.count == 50)
            precondition(board.state.frames.values.allSatisfy { $0.height == 54 })
            // Restore keeps a note created after the arrangement.
            let id = store.createNote(showWindow: false)
            board.ensureEntries(store.notes.map(\.id))
            let newFrame = board.state.frames[id]
            let afterCreation = try Data(contentsOf: notesURL)
            board.restore()
            precondition(board.state.frames.count == 51 && board.state.frames[id] == newFrame)
            precondition(board.state.frames[ids[0]]?.origin == CGPoint(x: 1800, y: 1100))
            precondition(board.state.frames[ids[0]]?.height == 170)
            let afterRestore = try Data(contentsOf: notesURL)
            precondition(afterRestore == afterCreation, "Board Restore must not rewrite notes after creation")
            print("PASS: Canvas board restart and Restore preserve later note creation")
            return
        } else if phase == "corrupt" {
            precondition(board.error != nil && !board.writable)
            board.ensureEntries(ids)
            board.arrange(.grid, ids: ids, columns: 4)
            let preserved = try Data(contentsOf: url)
            precondition(preserved == Data("invalid board".utf8))
        } else if phase == "failure" {
            board.ensureEntries(ids)
            let oldState = board.state.frames
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            board.arrange(.compact, ids: ids, columns: 4)
            precondition(board.error != nil && board.state.frames == oldState && board.state.snapshot == nil)
        }
        let after = try Data(contentsOf: notesURL)
        precondition(after == baseline, "Board must not mutate note content or desktop window frames")
        print("PASS: Canvas board \(phase), 50 notes and independent local positions")
    }
}
