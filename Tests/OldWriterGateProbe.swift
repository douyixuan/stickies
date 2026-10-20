import Foundation
@main struct OldWriterGateProbe {
    @MainActor static func main() {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("istk-ledger-") else { exit(64) }
        let store = NoteStore.shared
        precondition(!store.syncStorageOwned)
        _ = store.createNote(showWindow: false)
        store.updateText(UUID(), "must not write")
        store.setWindowMode(.floating)
        print("PASS: old app rejected schema 3 storage")
    }
}
