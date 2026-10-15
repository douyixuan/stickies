import Foundation
import CoreGraphics

/// The only model eligible for a future cloud record. No device presentation state.
struct NoteContent: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var color: Int = 0

    enum MergeError: Error, Equatable {
        case identityMismatch
        case conflict(String)
    }

    /// Three-way merge against a known common ancestor. Never use wall clocks
    /// or an arbitrary last-writer winner to discard concurrent text edits.
    static func merge(base: Self, local: Self, remote: Self) throws -> Self {
        guard base.id == local.id, base.id == remote.id else {
            throw MergeError.identityMismatch
        }
        func field<T: Equatable>(_ base: T, _ local: T, _ remote: T, _ name: String) throws -> T {
            if local == remote || remote == base { return local }
            if local == base { return remote }
            throw MergeError.conflict(name)
        }
        return try Self(id: base.id,
                        text: field(base.text, local.text, remote.text, "text"),
                        color: field(base.color, local.color, remote.color, "color"))
    }
}

struct NoteLocalState: Codable, Equatable {
    var frame: CGRect = CGRect(x: 120, y: 180, width: 260, height: 220)
    var visible: Bool = true
}

/// UI projection, intentionally not Codable: callers must choose the content
/// export or the versioned local persistence envelope explicitly.
struct StickyNote: Identifiable, Equatable {
    var content: NoteContent
    var local: NoteLocalState
    var id: UUID { content.id }
    var text: String {
        get { content.text }
        set { content.text = newValue }
    }
    var color: Int {
        get { content.color }
        set { content.color = newValue }
    }
    var frame: CGRect {
        get { local.frame }
        set { local.frame = newValue }
    }
    var visible: Bool {
        get { local.visible }
        set { local.visible = newValue }
    }

    init(id: UUID = UUID(), text: String = "", color: Int = 0,
         frame: CGRect = NoteLocalState().frame, visible: Bool = true) {
        content = NoteContent(id: id, text: text, color: color)
        local = NoteLocalState(frame: frame, visible: visible)
    }

    mutating func mergeContent(base: NoteContent, remote: NoteContent) throws {
        // Assignment happens only after the entire merge succeeds.
        content = try NoteContent.merge(base: base, local: content, remote: remote)
    }
}

enum NotePersistence {
    enum StorageError: Error { case unsupportedVersion(Int), invalidIdentities, backupMismatch }

    private struct LocalEntry: Codable {
        var id: UUID
        var state: NoteLocalState
    }

    /// Local file only. A single atomic write commits both partitions together.
    private struct Snapshot: Codable {
        var schemaVersion: Int = 2
        var contents: [NoteContent]
        var localStates: [LocalEntry]
    }

    private struct Header: Decodable { var schemaVersion: Int }
    private struct LegacyNote: Decodable {
        var id: UUID
        var text: String
        var color: Int
        var frame: CGRect
        var visible: Bool
    }

    static func encode(_ notes: [StickyNote]) throws -> Data {
        guard Set(notes.map(\.id)).count == notes.count else { throw StorageError.invalidIdentities }
        return try JSONEncoder().encode(Snapshot(
            contents: notes.map(\.content),
            localStates: notes.map { LocalEntry(id: $0.id, state: $0.local) }))
    }

    static func decode(_ data: Data) throws -> (notes: [StickyNote], migrated: Bool) {
        let decoder = JSONDecoder()
        // Only an actual array is legacy; malformed/future objects must not fall back.
        if data.first(where: { ![UInt8(32), 9, 10, 13].contains($0) }) == UInt8(91) {
            let legacy = try decoder.decode([LegacyNote].self, from: data)
            let notes = legacy.map { StickyNote(id: $0.id, text: $0.text, color: $0.color,
                                               frame: $0.frame, visible: $0.visible) }
            _ = try encode(notes) // Reject duplicate identities before migration.
            return (notes, true)
        }
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion == 2 else { throw StorageError.unsupportedVersion(header.schemaVersion) }
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        let ids = snapshot.contents.map(\.id)
        let localIDs = snapshot.localStates.map(\.id)
        guard Set(ids).count == ids.count, Set(localIDs).count == localIDs.count,
              Set(ids) == Set(localIDs) else { throw StorageError.invalidIdentities }
        let states = Dictionary(uniqueKeysWithValues: snapshot.localStates.map { ($0.id, $0.state) })
        return (snapshot.contents.map {
            let state = states[$0.id]!
            return StickyNote(id: $0.id, text: $0.text, color: $0.color,
                              frame: state.frame, visible: state.visible)
        }, false)
    }

    /// Caller must own the existing notes.lock for the whole load/save lifetime.
    static func load(from url: URL) throws -> [StickyNote] {
        let original = try Data(contentsOf: url)
        let result = try decode(original)
        if result.migrated {
            let backup = url.appendingPathExtension("legacy-v1.bak")
            if FileManager.default.fileExists(atPath: backup.path) {
                guard try Data(contentsOf: backup) == original else { throw StorageError.backupMismatch }
            } else {
                try original.write(to: backup, options: .atomic)
            }
            try save(result.notes, to: url)
        }
        return result.notes
    }

    static func save(_ notes: [StickyNote], to url: URL) throws {
        try encode(notes).write(to: url, options: .atomic)
    }
}
