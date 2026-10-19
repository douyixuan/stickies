import Foundation

@main struct FolderSyncTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("istickies-folder-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let first = try SyncFolder.create(in: root, requireICloud: false)
        let id = try SyncFolder.manifest(first).id
        let original = SyncValue(content: NoteContent(text: "base"))
        let base = try SyncFolder.save(original, replacing: nil, folder: first, id: id)
        let second = root.appendingPathComponent("second-mac")
        try fm.copyItem(at: first, to: second)
        var left = original; left.content.text = "left offline"
        var right = original; right.content.text = "right offline"
        _ = try SyncFolder.save(left, replacing: base, folder: first, id: id)
        _ = try SyncFolder.save(right, replacing: base, folder: second, id: id)
        func exchange(_ a: URL, _ b: URL) throws {
            for file in try fm.contentsOfDirectory(at: a.appendingPathComponent("events"), includingPropertiesForKeys: nil) {
                let target = b.appendingPathComponent("events").appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: file, to: target) }
            }
        }
        try exchange(first, second); try exchange(second, first)
        let heads = try SyncFolder.snapshot(first, id: id)
        precondition(heads.count == 1 && heads[0].alternatives?.count == 2, "Concurrent writes preserve both heads")
        let local = TestLocal([left])
        let transport = FolderSyncTransport(folder: first, id: id, requireICloud: false)
        let sync = SyncCoordinator(local: local, transport: transport, file: root.appendingPathComponent("ledger.json"))
        sync.enable(selected: [left.id]); await sync.cycle()
        precondition(sync.conflicts.contains(left.id), "Concurrent folder branches require a choice")
        sync.resolve(left.id, useCloud: true, variant: right); await sync.cycle()
        let resolved = try SyncFolder.snapshot(first, id: id)
        precondition(resolved[0].value == right && resolved[0].alternatives == nil, "Resolution joins every observed parent")
        try exchange(first, second)
        precondition(tryRead(second, id: id)[0].value == right, "Second simulated device converges")
        sync.deleteEverywhere(left.id); await sync.cycle(); try exchange(first, second)
        precondition(tryRead(second, id: id)[0].value.deleted, "Deletion marker reaches second replica")
        precondition(sync.recoverableIDs.contains(left.id), "Deletion retains a recovery copy")
        sync.restoreDeleted(left.id); await sync.cycle(); try exchange(first, second)
        precondition(tryRead(second, id: id)[0].value == right, "Restored note reaches other replica")
        sync.deleteEverywhere(left.id); await sync.cycle(); try exchange(first, second)
        // Provider reordering must fail closed until a referenced parent arrives.
        let files = try fm.contentsOfDirectory(at: second.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        let baseHead = try JSONDecoder().decode([String].self, from: base.systemFields)[0]
        let parent = second.appendingPathComponent("events/" + baseHead + ".json")
        let bytes = try Data(contentsOf: parent); try fm.removeItem(at: parent)
        do { _ = try SyncFolder.snapshot(second, id: id); fatalError("Missing parent accepted") } catch { }
        try bytes.write(to: parent)
        precondition(tryRead(second, id: id)[0].value.deleted)
        // Changed bytes cannot masquerade as a content-addressed event.
        let victim = files[0]; let saved = try Data(contentsOf: victim)
        try Data("{}".utf8).write(to: victim)
        do { _ = try SyncFolder.snapshot(second, id: id); fatalError("Tampered event accepted") } catch { }
        try saved.write(to: victim)
        // A stale revision cannot overwrite current heads.
        do { _ = try SyncFolder.save(original, replacing: base, folder: first, id: id); fatalError("Stale overwrite accepted") } catch { }
        print("PASS: coordinated local-folder replicas, concurrent offline heads, explicit resolution, deletion, missing-parent recovery, tamper and stale-write rejection. No real iCloud used.")
    }
    static func tryRead(_ folder: URL, id: UUID) -> [CloudNote] { try! SyncFolder.snapshot(folder, id: id) }
}
