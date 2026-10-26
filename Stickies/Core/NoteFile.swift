import CoreGraphics
import Foundation

/// `notes.json` reading and writing. Reads every shape earlier versions wrote,
/// always writes the current one, and never partially overwrites a file it cannot parse.
enum NoteFile {
    static let currentVersion = 10
    static let name = "notes.json"

    enum Failure: Error, LocalizedError {
        case unsupportedVersion
        case corrupt
        case duplicateIdentity

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "The notes file was written by a newer version of iStickies2."
            case .corrupt: return "The notes file could not be read."
            case .duplicateIdentity: return "The notes file contains duplicate note identifiers."
            }
        }
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var notes: [StickyNote]
    }

    // MARK: Reading

    static func load(from url: URL) throws -> [StickyNote] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [StickyNote] {
        let notes = try parse(data)
        guard Set(notes.map(\.id)).count == notes.count else { throw Failure.duplicateIdentity }
        return notes
    }

    private static func parse(_ data: Data) throws -> [StickyNote] {
        let decoder = JSONDecoder()
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw Failure.corrupt }

        // 0.1: a bare array of notes.
        if root is [Any] { return try decoder.decode([StickyNote].self, from: data) }

        guard let object = root as? [String: Any], let version = object["schemaVersion"] as? Int else {
            throw Failure.corrupt
        }
        switch version {
        case currentVersion:
            return try decoder.decode(Envelope.self, from: data).notes
        case 3:
            // 0.3 wrapped the document in a command ledger. Read the document, drop the ledger.
            guard let document = object["document"] else { throw Failure.corrupt }
            return try parse(try JSONSerialization.data(withJSONObject: document))
        case 2:
            return try decodeSplitEnvelope(data)
        default:
            throw Failure.unsupportedVersion
        }
    }

    /// 0.2 stored content and device state in parallel arrays.
    private static func decodeSplitEnvelope(_ data: Data) throws -> [StickyNote] {
        struct Content: Decodable { let id: UUID; let text: String; let color: Int }
        struct State: Decodable { let frame: CGRect; let visible: Bool }
        struct Entry: Decodable { let id: UUID; let state: State }
        struct Split: Decodable { let contents: [Content]; let localStates: [Entry] }

        let split = try JSONDecoder().decode(Split.self, from: data)
        guard Set(split.localStates.map(\.id)).count == split.localStates.count,
              Set(split.contents.map(\.id)) == Set(split.localStates.map(\.id)) else { throw Failure.corrupt }
        let states = Dictionary(uniqueKeysWithValues: split.localStates.map { ($0.id, $0.state) })
        return split.contents.map { content in
            let state = states[content.id]
            return StickyNote(id: content.id, text: content.text, color: content.color,
                              frame: state?.frame ?? CGRect(x: 120, y: 180,
                                                            width: StickyNote.defaultSize.width,
                                                            height: StickyNote.defaultSize.height),
                              visible: state?.visible ?? true)
        }
    }

    // MARK: Writing

    static func encode(_ notes: [StickyNote]) throws -> Data {
        guard Set(notes.map(\.id)).count == notes.count else { throw Failure.duplicateIdentity }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(schemaVersion: currentVersion, notes: notes))
    }

    static func save(_ notes: [StickyNote], to url: URL) throws {
        try encode(notes).write(to: url, options: .atomic)
    }
}

/// Small JSON side files (`layout.json`, `preferences.json`, `trash.json`) share one path.
enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
