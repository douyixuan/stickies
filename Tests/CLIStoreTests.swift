import Foundation
import Darwin

@main struct CLIStoreTests {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("istk-cli-") else {
            fatalError("An isolated CLI fixture is required")
        }
        let store = NoteStore.shared
        if CommandLine.arguments.dropFirst().first == "hold" {
            print("ready"); fflush(stdout)
            _ = readLine()
        }
        if CommandLine.arguments.dropFirst().first == "remote-edit", let note = store.notes.first {
            try store.applySync(SyncValue(content: NoteContent(id: note.id, text: "Remote update while locally trashed", color: note.color)))
        }
        let info: [String: Any] = ["active": store.activeNotes.count, "trashed": store.trashedNotes.count,
                                  "syncValues": store.syncValues.count, "writable": store.trashWritable,
                                  "trashError": store.trashError != nil]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
