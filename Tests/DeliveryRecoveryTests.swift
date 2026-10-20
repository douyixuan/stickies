import Foundation
import Darwin

@main
struct DeliveryRecoveryTests {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] else { fatalError("isolated data required") }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let file = root.appendingPathComponent("notes.json")
        let phase = CommandLine.arguments[1]
        let fixture = Data("""
        [{"id":"\(id)","text":"original","color":2,"frame":[[100,200],[260,220]],"visible":true}]
        """.utf8)
        if phase == "retry" || phase == "hold" { try fixture.write(to: file) }
        if phase == "corrupt" { try Data("{broken notes".utf8).write(to: file) }
        if phase == "future" { try Data("{\"schemaVersion\":999}".utf8).write(to: file) }
        let store = NoteStore.shared
        verifyPaths(root)
        if phase == "retry" {
            let backup = root.appendingPathComponent("original.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            store.updateText(id, "latest edit after transient failure")
            precondition(store.hasUnsavedChanges && store.persistenceError != nil)
            precondition(!store.flushPendingChanges(), "A failing exit flush must refuse automatic termination")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: backup, to: file)
            precondition(store.flushPendingChanges())
            precondition(!store.hasUnsavedChanges && store.persistenceError == nil)
        } else if phase == "verify_retry" {
            precondition(store.note(id)?.text == "latest edit after transient failure")
            precondition(!store.hasUnsavedChanges)
        } else if phase == "hold" {
            store.updateText(id, "saved before forced exit")
            store.setWindowMode(.desktop)
            store.arrange(.compact, in: bounds)
            let board = CanvasBoardStore(notes: store)
            board.ensureEntries([id])
            board.arrange(.grid, ids: [id], columns: 3)
            precondition(!store.hasUnsavedChanges && store.persistenceError == nil)
            try Data("ready".utf8).write(to: root.appendingPathComponent("ready"))
            while true { usleep(100_000) }
        } else if phase == "probe" {
            precondition(!store.localStateWritable && store.persistenceError != nil)
            let names = ["notes.json", "layout.json", "canvas-layout.json", "preferences.json"]
            let before = try names.map { try Data(contentsOf: root.appendingPathComponent($0)) }
            let newID = store.createNote(showWindow: false)!
            store.updateText(newID, "must not reach disk")
            store.setWindowMode(.floating)
            store.toggleCollapse(newID, screens: [bounds])
            let board = CanvasBoardStore(notes: store)
            board.ensureEntries([newID])
            board.move(id, to: .zero)
            precondition(!store.flushPendingChanges())
            let after = try names.map { try Data(contentsOf: root.appendingPathComponent($0)) }
            precondition(before == after, "Concurrent instance must not mutate any persisted partition")
        } else if phase == "recover" {
            precondition(store.localStateWritable && store.note(id)?.text == "saved before forced exit")
            precondition(store.windowMode == .desktop && store.isCollapsed(id))
            precondition(CanvasBoardStore(notes: store).state.frames.count == 1)
            store.restoreLayout(screens: [bounds])
            precondition(store.note(id)?.frame == CGRect(x: 100, y: 200, width: 260, height: 220))
            store.hide(id)
            precondition(store.notes.count == 1 && store.note(id)?.visible == false)
            precondition(store.note(id)?.text == "saved before forced exit")
            precondition(store.flushPendingChanges())
        } else if phase == "corrupt" || phase == "future" {
            let before = try Data(contentsOf: file)
            precondition(!store.localStateWritable && store.persistenceError != nil)
            let newID = store.createNote(showWindow: false)!
            store.updateText(newID, "not saved")
            store.setWindowMode(.desktop)
            CanvasBoardStore(notes: store).ensureEntries([newID])
            precondition(!store.flushPendingChanges())
            let after = try Data(contentsOf: file)
            precondition(before == after)
        }
        print("PASS: delivery recovery \(phase) without NSApplication or windows")
    }
    static func verifyPaths(_ root: URL) {
        let a = root.appendingPathComponent("A/Stickies.app")
        let b = root.appendingPathComponent("B/Stickies.app")
        let support = root.appendingPathComponent("Application Support")
        func path(_ id: String, _ bundle: URL, _ environment: [String: String] = [:]) -> URL {
            NoteDataLocation.directory(environment: environment, bundleID: id, bundleURL: bundle, applicationSupport: support)
        }
        precondition(path("dev.douyixuan.stickies.delivery", a) == path("dev.douyixuan.stickies.delivery", b))
        precondition(path("dev.douyixuan.stickies.delivery", a).lastPathComponent == "Stickies Delivery")
        precondition(path("dev.douyixuan.stickies", a).lastPathComponent == "Stickies")
        precondition(path("dev.douyixuan.stickies.local-preview", a) != path("dev.douyixuan.stickies.local-preview", b))
        precondition(path("dev.douyixuan.stickies.delivery", b, ["STICKIES_DATA_DIR": root.path]) == root)
    }
}
