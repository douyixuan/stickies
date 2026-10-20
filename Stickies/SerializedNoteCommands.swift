import Foundation
import CryptoKit
import Darwin

/// The caller holds notes.lock and serializes all calls without suspension.
/// The journal supports process-crash recovery, not a power-loss durability claim.
enum SerializedNoteCommands {
    struct Request: Codable {
        var id: UUID
        var command: String
        var ids: [UUID] = []
        var text: String?
        var color: Int?
        var includeTrash: Bool?
        var visibleOnCreate: Bool?
    }
    struct Result: Codable {
        var requestID: UUID
        var notes: [StickyNote]
    }
    struct Record: Codable {
        var fingerprint: String
        var result: Result
    }
    struct Ledger: Codable {
        var version = 1
        var records: [String: Record] = [:]
    }
    struct Journal: Codable {
        var version = 1
        var notes: Data
        var trash: Data
        var ledger: Data
        var previousNotes: String?
        var previousTrash: String?
        var previousLedger: String?
        var profile: UUID?
        var generation: UInt64?
        var previousManifest: SegmentedCommandLedger.Manifest?
    }
    enum Failure: Error { case invalidRequest, notFound, conflictingRequestID, ledgerFull, unsafeFile, invalidState, recoveryRequired }
    enum Stage: String { case prepared, notesWritten, trashWritten, ledgerWritten, completed }
    static let journalName = "command-journal.json"
    static let ledgerName = "command-results.json"
    static let maximumRecords = 4096
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func read(_ url: URL) throws -> Data? {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadUnknown)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { throw Failure.unsafeFile }
        guard info.st_size <= 64 * 1024 * 1024 else { throw Failure.invalidState }
        return try Data(contentsOf: url)
    }
    static func ledger(in directory: URL) throws -> Ledger {
        if let manifest = try SegmentedCommandLedger.manifest(read(directory.appendingPathComponent("notes.json"))) {
            return Ledger(records: try SegmentedCommandLedger.records(manifest, in: directory))
        }
        guard let data = try read(directory.appendingPathComponent(ledgerName)) else { return Ledger() }
        return try decodeLedger(data)
    }
    static func decodeLedger(_ data: Data) throws -> Ledger {
        do { return try decodeLegacyLedger(data) }
        catch { throw Failure.invalidState }
    }
    private static func decodeLegacyLedger(_ data: Data) throws -> Ledger {
        _ = try LosslessJSON.parse(data)
        let value = try JSONDecoder().decode(Ledger.self, from: data)
        guard value.version == 1, value.records.count <= maximumRecords,
              value.records.allSatisfy({ $0.key == $0.value.result.requestID.uuidString && $0.value.fingerprint.count == 64 }) else {
            throw Failure.invalidState
        }
        return value
    }
    /// Replay only under the exclusive lock, before loading mutable application state.
    static func recover(in directory: URL, checkpoint: (Stage) throws -> Void = { _ in }) throws {
        let url = directory.appendingPathComponent(journalName)
        guard let data = try read(url) else {
            try SegmentedCommandLedger.validate(read(directory.appendingPathComponent("notes.json")), in: directory)
            return
        }
        let journal: Journal
        do {
            _ = try LosslessJSON.parse(data)
            journal = try JSONDecoder().decode(Journal.self, from: data)
            guard [1, 2].contains(journal.version) else { throw Failure.invalidState }
            _ = try CompatibleNoteFile.decode(journal.notes)
            _ = try LocalNoteTrash.decode(journal.trash)
        } catch { throw Failure.invalidState }
        let current = try read(directory.appendingPathComponent("notes.json"))
        let before = try SegmentedCommandLedger.manifest(current)
        let after = try SegmentedCommandLedger.manifest(journal.notes)
        if journal.version == 1 {
            guard before == nil, after == nil else { throw Failure.invalidState }
            _ = try decodeLedger(journal.ledger)
        } else {
            guard let before, let after, let prior = journal.previousManifest, let generation = journal.generation,
                  generation < UInt64.max, journal.profile == before.profile,
                  after.profile == before.profile, prior.profile == before.profile, prior.generation == generation,
                  after.generation == generation + 1,
                  (before == prior || current == journal.notes),
                  journal.ledger.isEmpty, journal.previousLedger == nil else { throw Failure.invalidState }
            let previousRecords = try SegmentedCommandLedger.records(prior, in: directory)
            let nextRecords = try SegmentedCommandLedger.records(after, in: directory)
            guard nextRecords.count == previousRecords.count + 1 else { throw Failure.invalidState }
            for (id, record) in previousRecords {
                guard let next = nextRecords[id], try encoded(record) == encoded(next) else { throw Failure.invalidState }
            }
        }
        for (name, previous, after) in [
            ("notes.json", journal.previousNotes, journal.notes),
            ("trash.json", journal.previousTrash, journal.trash),
            (ledgerName, journal.previousLedger, journal.ledger)
        ] {
            if journal.version == 2 && name == ledgerName { continue }
            let current = try read(directory.appendingPathComponent(name))
            guard current.map(digest) == previous || current == after else { throw Failure.invalidState }
        }
        try journal.notes.write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
        try checkpoint(.notesWritten)
        try journal.trash.write(to: directory.appendingPathComponent("trash.json"), options: .atomic)
        try checkpoint(.trashWritten)
        if journal.version == 1 { try journal.ledger.write(to: directory.appendingPathComponent(ledgerName), options: .atomic) }
        try checkpoint(.ledgerWritten)
        try FileManager.default.removeItem(at: url)
        // Commit already completed. An observation failure cannot undo its result.
        try? checkpoint(.completed)
    }
    static func execute(_ request: Request, notes: [StickyNote], trash: LocalNoteTrash,
                        in directory: URL, checkpoint: (Stage) throws -> Void = { _ in }) throws -> (Result, [StickyNote], LocalNoteTrash) {
        guard try read(directory.appendingPathComponent(journalName)) == nil else { throw Failure.recoveryRequired }
        if request.command == "result" {
            guard request.ids.count == 1, request.text == nil, request.color == nil else { throw Failure.invalidRequest }
            guard let record = try ledger(in: directory).records[request.ids[0].uuidString] else { throw Failure.notFound }
            return (record.result, notes, trash)
        }
        if ["list", "get", "search"].contains(request.command) {
            guard request.color == nil, request.visibleOnCreate == nil else { throw Failure.invalidRequest }
            let candidates = notes.filter { trash.ids.contains($0.id) == (request.includeTrash == true) }
            var found = candidates
            switch request.command {
            case "list":
                guard request.ids.isEmpty, request.text == nil else { throw Failure.invalidRequest }
            case "get":
                guard request.ids.count == 1, request.text == nil else { throw Failure.invalidRequest }
                found = candidates.filter { $0.id == request.ids[0] }
                guard !found.isEmpty else { throw Failure.notFound }
            default:
                guard request.ids.isEmpty, let text = request.text else { throw Failure.invalidRequest }
                let terms = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                found = candidates.filter { note in terms.allSatisfy {
                    note.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                } }
            }
            return (Result(requestID: request.id, notes: found), notes, trash)
        }
        guard ["add", "edit", "delete", "restore"].contains(request.command),
              request.text.map({ $0.utf8.count <= 8 * 1024 * 1024 }) ?? true,
              request.color.map({ (0...3).contains($0) }) ?? true,
              request.includeTrash != true,
              Set(request.ids).count == request.ids.count else { throw Failure.invalidRequest }
        let fingerprint = digest(try encoded(request))
        var ledger = try ledger(in: directory)
        if let existing = ledger.records[request.id.uuidString] {
            guard existing.fingerprint == fingerprint else { throw Failure.conflictingRequestID }
            return (existing.result, notes, trash)
        }
        let original = try read(directory.appendingPathComponent("notes.json"))
        let segmented = try SegmentedCommandLedger.manifest(original)
        guard segmented != nil || ledger.records.count < maximumRecords else { throw Failure.ledgerFull }
        var updated = notes
        var updatedTrash = trash
        var affected: [StickyNote]
        switch request.command {
        case "add":
            guard request.ids.isEmpty else { throw Failure.invalidRequest }
            let note = StickyNote(text: request.text ?? "", color: request.color ?? 0, visible: request.visibleOnCreate == true)
            updated.append(note)
            affected = [note]
        case "edit":
            guard request.ids.count == 1, request.text != nil || request.color != nil else { throw Failure.invalidRequest }
            guard let index = updated.firstIndex(where: { $0.id == request.ids[0] && !trash.ids.contains($0.id) }) else { throw Failure.notFound }
            if let text = request.text { updated[index].text = text }
            if let color = request.color { updated[index].color = color }
            affected = [updated[index]]
        default:
            let ids = Set(request.ids)
            let restoring = request.command == "restore"
            guard !ids.isEmpty, request.text == nil, request.color == nil else { throw Failure.invalidRequest }
            guard ids.isSubset(of: Set(notes.filter { trash.ids.contains($0.id) == restoring }.map(\.id))) else { throw Failure.notFound }
            if restoring { updatedTrash.ids.subtract(ids); updatedTrash.lastBatch.subtract(ids) }
            else { updatedTrash.ids.formUnion(ids); updatedTrash.lastBatch = ids }
            affected = notes.filter { ids.contains($0.id) }
        }
        let result = Result(requestID: request.id, notes: affected)
        ledger.records[request.id.uuidString] = Record(fingerprint: fingerprint, result: result)
        let originalTrash = try read(directory.appendingPathComponent("trash.json"))
        let originalLedger = try read(directory.appendingPathComponent(ledgerName))
        var noteData: Data
        if let original, request.command == "delete" || request.command == "restore" {
            noteData = original
        } else {
            noteData = try CompatibleNoteFile.encode(updated, preserving: original)
        }
        if let segmented {
            let next = try SegmentedCommandLedger.append(ledger.records[request.id.uuidString]!, to: segmented, in: directory)
            noteData = try SegmentedCommandLedger.replacing(noteData, manifest: next)
        }
        let journal = Journal(version: segmented == nil ? 1 : 2, notes: noteData, trash: try encoded(updatedTrash), ledger: segmented == nil ? try encoded(ledger) : Data(),
                              previousNotes: original.map(digest), previousTrash: originalTrash.map(digest),
                              previousLedger: segmented == nil ? originalLedger.map(digest) : nil,
                              profile: segmented?.profile, generation: segmented?.generation, previousManifest: segmented)
        let data = try encoded(journal)
        guard data.count <= 64 * 1024 * 1024 else { throw Failure.ledgerFull }
        try data.write(to: directory.appendingPathComponent(journalName), options: .atomic)
        // After preparation, errors mean that recovery must complete the accepted command.
        try checkpoint(.prepared)
        try recover(in: directory, checkpoint: checkpoint)
        return (result, updated, updatedTrash)
    }
}
