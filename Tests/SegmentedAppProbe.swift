import Foundation
@main struct SegmentedAppProbe {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("istk-ledger-") else { exit(64) }
        let directory = URL(fileURLWithPath: path)
        let store = NoteStore.shared
        precondition(store.syncStorageOwned)
        let url = directory.appendingPathComponent("notes.json")
        let before = try Data(contentsOf: url)
        let manifest = try SegmentedCommandLedger.manifest(before)!
        if CommandLine.arguments.last == "damage" {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(manifest.segments[0].name))
            store.updateText(store.notes[0].id, "must not save")
            store.setWindowMode(.floating)
            precondition(store.hasUnsavedChanges)
            let after = try Data(contentsOf: url)
            precondition(after == before)
            precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("preferences.json").path))
        } else {
            let id = store.notes[0].id
            store.updateText(id, "normal edit")
            try store.applySync(SyncValue(content: NoteContent(id: id, text: "remote edit", color: 2)))
            store.setWindowMode(.floating)
            let afterManifest = try SegmentedCommandLedger.manifest(Data(contentsOf: url))
            precondition(afterManifest == manifest)
        }
        print("PASS: schema 3 app write path")
    }
}
