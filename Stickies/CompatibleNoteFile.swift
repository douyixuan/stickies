import Foundation
import CoreGraphics
import CoreFoundation


/// Delivery bridge to PR #4's on-disk schema, not a sync or migration engine.
/// Existing files retain their format and extension fields. Caller owns notes.lock.
enum CompatibleNoteFile {
    enum Failure: Error { case invalidDocument, unsupportedVersion, duplicateIdentity }
    private struct LocalEntry: Decodable { let id: UUID; let state: LocalState }
    private struct LocalState: Decodable { let frame: CGRect; let visible: Bool }
    private struct Content: Decodable { let id: UUID; let text: String; let color: Int }
    private struct Envelope: Decodable {
        let schemaVersion: Int
        let contents: [Content]
        let localStates: [LocalEntry]
    }

    static func decode(_ data: Data) throws -> [StickyNote] {
        let raw = try JSONSerialization.jsonObject(with: data)
        let decoder = JSONDecoder()
        let notes: [StickyNote]
        if raw is [Any] {
            notes = try decoder.decode([StickyNote].self, from: data)
        } else {
            guard let object = raw as? [String: Any],
                  let version = object["schemaVersion"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(), version == NSNumber(value: 2) else {
                throw Failure.unsupportedVersion
            }
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard Set(envelope.localStates.map(\.id)).count == envelope.localStates.count,
                  Set(envelope.contents.map(\.id)) == Set(envelope.localStates.map(\.id)) else {
                throw Failure.invalidDocument
            }
            let states = Dictionary(uniqueKeysWithValues: envelope.localStates.map { ($0.id, $0.state) })
            notes = envelope.contents.map {
                let state = states[$0.id]!
                return StickyNote(id: $0.id, text: $0.text, color: $0.color, frame: state.frame, visible: state.visible)
            }
        }
        guard Set(notes.map(\.id)).count == notes.count else { throw Failure.duplicateIdentity }
        return notes
    }

    static func encode(_ notes: [StickyNote], preserving original: Data?) throws -> Data {
        guard Set(notes.map(\.id)).count == notes.count else { throw Failure.duplicateIdentity }
        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(notes)) as! [[String: Any]]
        guard let original else { return try JSONSerialization.data(withJSONObject: fresh, options: [.sortedKeys]) }
        _ = try decode(original) // Unknown/corrupt formats must never be overwritten.
        let raw = try JSONSerialization.jsonObject(with: original)
        func indexed(_ entries: [[String: Any]]) -> [UUID: [String: Any]] {
            Dictionary(uniqueKeysWithValues: entries.map { (UUID(uuidString: $0["id"] as! String)!, $0) })
        }
        func overlay(_ base: [String: Any], _ values: [String: Any]) -> [String: Any] {
            base.merging(values) { _, new in new }
        }
        let result: Any
        if let legacy = raw as? [[String: Any]] {
            let previous = indexed(legacy)
            result = zip(notes, fresh).map { note, fields in overlay(previous[note.id] ?? [:], fields) }
        } else {
            var envelope = raw as! [String: Any]
            let contents = indexed(envelope["contents"] as! [[String: Any]])
            let locals = indexed(envelope["localStates"] as! [[String: Any]])
            envelope["contents"] = zip(notes, fresh).map { note, fields in
                overlay(contents[note.id] ?? [:], ["id": fields["id"]!, "text": fields["text"]!, "color": fields["color"]!])
            }
            envelope["localStates"] = zip(notes, fresh).map { note, fields in
                var entry = locals[note.id] ?? [:]
                entry["id"] = fields["id"]
                entry["state"] = overlay(entry["state"] as? [String: Any] ?? [:], ["frame": fields["frame"]!, "visible": fields["visible"]!])
                return entry
            }
            result = envelope
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    static func save(_ notes: [StickyNote], to url: URL) throws {
        // Re-read under the caller's lock, preserving extensions even after a retry.
        let original = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        try encode(notes, preserving: original).write(to: url, options: .atomic)
    }
}
