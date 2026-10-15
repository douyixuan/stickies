import AppKit
import Darwin

@main
struct StoreSmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = NoteStore.shared
        if CommandLine.arguments.contains("--hold") {
            let ready = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!).appendingPathComponent("ready")
            try! Data("ready".utf8).write(to: ready)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 8))
            return
        }
        if CommandLine.arguments.contains("--lock-probe") {
            precondition(store.persistenceError?.contains("already open") == true)
            print("PASS: simultaneous instance cannot write locked storage")
            return
        }
        store.restoreWindows()
        guard let note = store.notes.first else { fatalError("No startup note") }
        if CommandLine.arguments.contains("--restore") {
            precondition(NSApplication.shared.windows.contains { $0.frame == note.frame })
            precondition(note.text == "Persistence smoke test")
            precondition(note.color == 2)
            precondition(store.keepOnTop)
            precondition(NSApplication.shared.windows.contains { $0.level == .floating })
            precondition(note.frame.size == CGSize(width: 310, height: 240))
            precondition(NSScreen.screens.contains { $0.visibleFrame.contains(note.frame) })
            print("PASS: process restart restored text, color and exact window outer size")
        } else {
            store.updateText(note.id, "Persistence smoke test")
            store.setColor(note.id, 2)
            store.setKeepOnTop(true)
            store.arrange(.grid)
            let screen = NSScreen.main!.visibleFrame
            let frame = LayoutEngine.constrain(CGRect(x: screen.minX + 50, y: screen.minY + 50, width: 310, height: 240), to: screen)
            let window = NSApplication.shared.windows.first { $0.title == "Persistence smoke test" }!
            window.setFrame(frame, display: true)
            precondition(store.note(note.id)?.frame == frame)
            window.miniaturize(nil)
            store.showAll()
            precondition(!window.isMiniaturized)
            precondition(store.note(note.id)?.frame == frame)
            store.hide(note.id)
            precondition(store.note(note.id)?.visible == false)
            store.showAll()
            precondition(store.note(note.id)?.visible == true)
            precondition(store.persistenceError == nil)
            print("PASS: startup, text/color updates, arrangement, frame persistence, hide/show")
        }
    }
}
