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
        _ = try LosslessJSON.parse(data)
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
        let fresh = try LosslessJSON.parse(JSONEncoder().encode(notes)).array!
        guard let original else { return try LosslessJSON.array(fresh).data() }
        _ = try decode(original)
        let raw = try LosslessJSON.parse(original)
        func indexed(_ entries: [LosslessJSON]) -> [UUID: [String: LosslessJSON]] {
            Dictionary(uniqueKeysWithValues: entries.map { (UUID(uuidString: $0.object!["id"]!.string!)!, $0.object!) })
        }
        func overlay(_ base: [String: LosslessJSON], _ values: [String: LosslessJSON]) -> LosslessJSON {
            .object(base.merging(values) { _, new in new })
        }
        if let legacy = raw.array {
            let previous = indexed(legacy)
            return try LosslessJSON.array(zip(notes, fresh).map { note, fields in overlay(previous[note.id] ?? [:], fields.object!) }).data()
        }
        var envelope = raw.object!
        let contents = indexed(envelope["contents"]!.array!)
        let locals = indexed(envelope["localStates"]!.array!)
        envelope["contents"] = .array(zip(notes, fresh).map { note, value in
            let fields = value.object!
            return overlay(contents[note.id] ?? [:], ["id": fields["id"]!, "text": fields["text"]!, "color": fields["color"]!])
        })
        envelope["localStates"] = .array(zip(notes, fresh).map { note, value in
            let fields = value.object!
            var entry = locals[note.id] ?? [:]
            entry["id"] = fields["id"]
            entry["state"] = overlay(entry["state"]?.object ?? [:], ["frame": fields["frame"]!, "visible": fields["visible"]!])
            return .object(entry)
        })
        return try LosslessJSON.object(envelope).data()
    }

    static func save(_ notes: [StickyNote], to url: URL) throws {
        // Re-read under the caller's lock, preserving extensions even after a retry.
        let original = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        try encode(notes, preserving: original).write(to: url, options: .atomic)
    }
}
