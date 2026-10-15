import AppKit

@main
struct StoreSmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = NoteStore.shared
        store.restoreWindows()
        guard let note = store.notes.first else { fatalError("No startup note") }
        if CommandLine.arguments.contains("--restore") {
            precondition(NSApplication.shared.windows.contains { $0.frame == note.frame })
            precondition(note.text == "Persistence smoke test")
            precondition(note.color == 2)
            precondition(note.frame.size == CGSize(width: 310, height: 240))
            precondition(NSScreen.screens.contains { $0.visibleFrame.contains(note.frame) })
            print("PASS: process restart restored text, color and exact window outer size")
        } else {
            store.updateText(note.id, "Persistence smoke test")
            store.setColor(note.id, 2)
            store.arrange(.grid)
            let screen = NSScreen.main!.visibleFrame
            let frame = LayoutEngine.constrain(CGRect(x: screen.minX + 50, y: screen.minY + 50, width: 310, height: 240), to: screen)
            let window = NSApplication.shared.windows.first { $0.title == "Sticky Note" }!
            window.setFrame(frame, display: true)
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
