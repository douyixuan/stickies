import Foundation
import CoreGraphics

@main struct CompatibilityTests {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"]!)
        let file = root.appendingPathComponent("notes.json")
        let mode = CommandLine.arguments[1]
        if mode == "unit" {
            let id = UUID()
            let legacy = try JSONEncoder().encode([StickyNote(id: id, text: "fixture", color: 2)])
            var array = try JSONSerialization.jsonObject(with: legacy) as! [[String: Any]]
            array[0]["extension"] = ["future": [NSNull(), 9223372036854775807, true]] as [String: Any]
            let v1 = try JSONSerialization.data(withJSONObject: array)
            let v2: [String: Any] = ["schemaVersion": 2, "extension": ["root": "preserved"],
                "contents": [["id": id.uuidString, "text": "fixture", "color": 2, "extension": array[0]["extension"]!]],
                "localStates": [["id": id.uuidString, "extension": "entry", "state": ["frame": array[0]["frame"]!, "visible": true, "extension": "state"]]]]
            let data2 = try JSONSerialization.data(withJSONObject: v2)
            for data in [v1, data2] {
                let decoded = try CompatibleNoteFile.decode(data)
                let saved = try CompatibleNoteFile.encode(decoded, preserving: data)
                let before = try JSONSerialization.jsonObject(with: data) as AnyObject
                let after = try JSONSerialization.jsonObject(with: saved) as AnyObject
                precondition(before.isEqual(after), "Round trip must preserve unknown fields")
                try data.write(to: file)
                var edited = decoded; edited[0].text = "edited"; edited[0].visible = false
                try CompatibleNoteFile.save(edited, to: file)
                let reread = try CompatibleNoteFile.decode(Data(contentsOf: file)); precondition(reread[0].text == "edited")
                let editedRaw = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                if let rows = editedRaw as? [[String: Any]] {
                    precondition((rows[0]["extension"] as! NSDictionary).isEqual(array[0]["extension"]))
                } else {
                    let object = editedRaw as! [String: Any]
                    precondition((object["extension"] as! NSDictionary).isEqual(v2["extension"]))
                    let content = (object["contents"] as! [[String: Any]])[0]
                    precondition((content["extension"] as! NSDictionary).isEqual(array[0]["extension"]))
                    let local = (object["localStates"] as! [[String: Any]])[0]
                    precondition(local["extension"] as? String == "entry")
                    precondition((local["state"] as! [String: Any])["extension"] as? String == "state")
                }
            }
            var mismatched = v2; mismatched["localStates"] = []
            var duplicate = v2; duplicate["contents"] = (v2["contents"] as! [[String: Any]]) + (v2["contents"] as! [[String: Any]])
            for unsafe in [mismatched, duplicate] {
                do { _ = try CompatibleNoteFile.decode(JSONSerialization.data(withJSONObject: unsafe)); fatalError("Accepted invalid identities") } catch { }
            }
            let precise = "1.123456789012345678901234567890123456789012345678901234567890"
            let preciseData = Data("{\"schemaVersion\":2,\"contents\":[],\"localStates\":[],\"extension\":\(precise)}".utf8)
            let exact = try CompatibleNoteFile.encode([], preserving: preciseData)
            precondition(String(decoding: exact, as: UTF8.self).contains(precise))
            for duplicateKey in ["{\"schemaVersion\":2,\"schemaVersion\":2,\"contents\":[],\"localStates\":[]}", "{\"schemaVersion\":2,\"contents\":[],\"localStates\":[],\"x\":{\"a\":1,\"a\":2}}"] {
                do { _ = try CompatibleNoteFile.decode(Data(duplicateKey.utf8)); fatalError("Accepted duplicate keys") } catch { }
            }
            for token in ["1e400", "-1e9999", "1e-9999"] {
                let large = Data(("{\"schemaVersion\":2,\"contents\":[],\"localStates\":[],\"extension\":" + token + "}").utf8)
                let saved = try CompatibleNoteFile.encode([], preserving: large)
                precondition(String(decoding: saved, as: UTF8.self).contains(token))
            }
            for malformed in ["{", "{ ", "[1,]", "{\"a\":1,}", "01", "1.", "1e", "+1", "NaN", "\"unterminated", "\"bad\\q\""] {
                do { _ = try LosslessJSON.parse(Data(malformed.utf8)); fatalError("Accepted invalid JSON") } catch { }
            }
            // Install gates must reject future, malformed and ambiguous identities.
            for data in [Data("{\"schemaVersion\":3}".utf8), Data("{\"schemaVersion\":2.00000000000000000000000000000000000000000000000001,\"contents\":[],\"localStates\":[]}".utf8), Data("{broken".utf8), try JSONEncoder().encode([StickyNote(id:id), StickyNote(id:id)])] {
                do { _ = try CompatibleNoteFile.decode(data); fatalError("Accepted unsafe data") } catch { }
                try data.write(to: file)
                do { try CompatibleNoteFile.save([], to: file); fatalError("Overwrote unsafe data") } catch { }
                let unchanged = try Data(contentsOf:file); precondition(unchanged == data)
            }
            try data2.write(to: file)
        } else {
            let store = NoteStore.shared
            precondition(store.localStateWritable && store.persistenceError == nil && store.notes.count > 0)
            let note = store.notes[0]
            if mode == "sync" {
                let frame = note.frame
                let visible = note.visible
                let before = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
                try store.applySync(SyncValue(content: NoteContent(id: note.id, text: "remote test", color: 4)))
                let changed = store.note(note.id)!
                precondition(changed.frame == frame && changed.visible == visible)
                let after = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
                precondition((before["localStates"] as! NSArray).isEqual(after["localStates"]))
                precondition((before["extension"] as! NSDictionary).isEqual(after["extension"]))
                let imported = SyncValue(content: NoteContent(text: "imported test"))
                try store.applySync(imported)
                precondition(store.note(imported.id)?.visible == false)
                let memory = store.notes
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                do {
                    try store.applySync(SyncValue(content: NoteContent(id: note.id, text: "must not apply", color: 1)))
                    fatalError("Accepted failed disk write")
                } catch { }
                precondition(store.notes.count == memory.count && zip(store.notes, memory).allSatisfy { a, b in a.id == b.id && a.text == b.text && a.color == b.color && a.frame == b.frame && a.visible == b.visible })
                try FileManager.default.removeItem(at: file)
                try CompatibleNoteFile.save(memory, to: file)
                try store.applySync(SyncValue(content: NoteContent(id: imported.id, text: ""), deleted: true))
                precondition(store.note(imported.id) == nil)
            } else if mode == "edit" {
                store.updateText(note.id, note.text + "\ncompatibility isolated regression")
                store.hide(note.id)
                store.toggleCollapse(note.id, screens: [CGRect(x:0,y:0,width:1200,height:800)])
                precondition(store.flushPendingChanges())
            } else {
                precondition(note.text.hasSuffix("compatibility isolated regression") && !note.visible && store.isCollapsed(note.id))
            }
        }
        print("PASS: compatibility " + mode + " (no windows)")
    }
}
