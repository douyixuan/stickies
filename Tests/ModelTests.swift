import Foundation

@main
struct ModelTests {
    static func rejects(_ body: () throws -> Void) {
        do { try body() } catch { return }
        fatalError("Expected rejection")
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        // Literal v1 fixture, independent of the v2 encoder; includes hidden note,
        // Unicode, negative monitor coordinates and nondefault size/color.
        let legacy = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","text":"你好 🌱","color":3,
          "frame":[[-1500,42],[310,240]],"visible":false},
         {"id":"00000000-0000-0000-0000-000000000002","text":"","color":0,
          "frame":[[120,180],[260,220]],"visible":true}]
        """.utf8)
        try legacy.write(to: url)
        let preferences = directory.appendingPathComponent("preferences.json")
        let preferenceData = Data("{\"keepOnTop\":true}".utf8)
        try preferenceData.write(to: preferences)
        let migrated = try NotePersistence.load(from: url)
        precondition(migrated.count == 2 && migrated[0].text == "你好 🌱")
        precondition(migrated[0].id.uuidString == "00000000-0000-0000-0000-000000000001")
        precondition(migrated[0].color == 3 && !migrated[0].visible)
        precondition(migrated[0].frame == CGRect(x: -1500, y: 42, width: 310, height: 240))
        precondition(migrated[1].visible && migrated[1].text.isEmpty)
        let backup = url.appendingPathExtension("legacy-v1.bak")
        let backupData = try Data(contentsOf: backup)
        precondition(backupData == legacy)
        let secondLoad = try NotePersistence.load(from: url)
        precondition(secondLoad == migrated)
        let unchangedPreferences = try Data(contentsOf: preferences)
        precondition(unchangedPreferences == preferenceData)
        let encoded = try Data(contentsOf: url)
        precondition(tryDecode(encoded) == migrated)
        let decoded = try NotePersistence.decode(encoded)
        precondition(decoded.migrated == false)

        var a = migrated[0]
        var b = a
        b.frame = CGRect(x: 20, y: 30, width: 400, height: 200)
        b.visible = true
        let aState = a.local
        let bState = b.local
        let base = a.content
        a.text = "Edited on A"
        b.color = 1
        try b.mergeContent(base: base, remote: a.content)
        try a.mergeContent(base: base, remote: b.content)
        precondition(a.content == b.content && b.text == "Edited on A" && a.color == 1)
        precondition(a.local == aState && b.local == bState)
        try NotePersistence.save([b], to: url)
        let reloaded = try NotePersistence.load(from: url)
        precondition(reloaded == [b])
        let exported = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b.content)) as! [String: Any]
        precondition(Set(exported.keys) == Set(["id", "text", "color"]))
        let beforeRepeat = b
        try b.mergeContent(base: base, remote: a.content)
        precondition(b == beforeRepeat)
        var conflicting = a.content
        conflicting.text = "Concurrent alternative"
        let beforeConflict = b
        do {
            try b.mergeContent(base: base, remote: conflicting)
            fatalError("Text conflict was silently overwritten")
        } catch NoteContent.MergeError.conflict("text") {}
        precondition(b == beforeConflict)
        var colorConflict = a.content
        colorConflict.color = 2
        rejects { try b.mergeContent(base: base, remote: colorConflict) }
        precondition(b == beforeConflict)
        rejects { try b.mergeContent(base: base, remote: NoteContent()) }
        let unchanged = try NoteContent.merge(base: base, local: base, remote: base)
        precondition(unchanged == base)

        // Corrupt/future/inconsistent data must remain byte-for-byte untouched.
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        object["schemaVersion"] = 2
        object["localStates"] = []
        let missingStates = try JSONSerialization.data(withJSONObject: object)
        for bad in [Data("{broken".utf8), future, missingStates] {
            try bad.write(to: url)
            rejects { _ = try NotePersistence.load(from: url) }
            let preserved = try Data(contentsOf: url)
            precondition(preserved == bad)
        }
        rejects { _ = try NotePersistence.encode([a, a]) }
        let duplicateLegacy = Data("[\(String(data: legacy, encoding: .utf8)!.dropFirst().dropLast()),\(String(data: legacy, encoding: .utf8)!.dropFirst().dropLast())]".utf8)
        rejects { _ = try NotePersistence.decode(duplicateLegacy) }
        // Interrupted migration: existing matching backup is safe to retry.
        try legacy.write(to: url)
        let retried = try NotePersistence.load(from: url)
        precondition(retried == migrated)
        try legacy.write(to: url)
        try Data("other backup".utf8).write(to: backup)
        rejects { _ = try NotePersistence.load(from: url) }
        let intact = try Data(contentsOf: url)
        precondition(intact == legacy)
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        rejects { _ = try NotePersistence.load(from: url) }
        let afterBackupFailure = try Data(contentsOf: url)
        precondition(afterBackupFailure == legacy)
        let empty = try NotePersistence.decode(Data("[]".utf8))
        precondition(empty.migrated && empty.notes.isEmpty)
        print("PASS: migration, backup/retry/failure, round-trip, updates, device independence, content export, three-way conflicts, invalid data")
    }

    static func tryDecode(_ data: Data) -> [StickyNote] {
        try! NotePersistence.decode(data).notes
    }
}
