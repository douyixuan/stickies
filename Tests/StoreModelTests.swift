import Foundation

@main
struct StoreModelTests {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let url = directory.appendingPathComponent("notes.json")
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let fixture = Data("""
        [{"id":"\(id.uuidString)","text":"original","color":2,
        "frame":[[-800,50],[310,240]],"visible":false}]
        """.utf8)
        try fixture.write(to: url)
        let store = NoteStore.shared
        precondition(store.persistenceError == nil)
        precondition(store.note(id)?.visible == false)
        let originalState = store.note(id)!.local
        store.updateText(id, "updated")
        store.setColor(id, 1)
        precondition(store.note(id)!.local == originalState)
        let content = store.note(id)!.content
        store.moved(id, frame: CGRect(x: 30, y: 40, width: 320, height: 250))
        store.hide(id)
        store.setKeepOnTop(true)
        precondition(store.note(id)!.content == content)
        precondition(store.persistenceError == nil)
        let disk = try NotePersistence.load(from: url)
        precondition(disk == store.notes)
        let preserved = try Data(contentsOf: url.appendingPathExtension("legacy-v1.bak"))
        precondition(preserved == fixture)
        print("PASS: NoteStore migration, text/color updates, local movement/visibility/preferences, disk persistence without windows")
    }
}
