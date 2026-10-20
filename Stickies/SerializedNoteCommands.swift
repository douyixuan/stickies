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
    }
    enum Failure: Error { case invalidRequest, conflictingRequestID, ledgerFull, unsafeFile, invalidState, recoveryRequired }
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
        guard let data = try read(directory.appendingPathComponent(ledgerName)) else { return Ledger() }
        return try decodeLedger(data)
    }
    private static func decodeLedger(_ data: Data) throws -> Ledger {
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
        guard let data = try read(url) else { return }
        let journal: Journal
        do {
            journal = try JSONDecoder().decode(Journal.self, from: data)
            guard journal.version == 1 else { throw Failure.invalidState }
            _ = try CompatibleNoteFile.decode(journal.notes)
            _ = try LocalNoteTrash.decode(journal.trash)
            _ = try decodeLedger(journal.ledger)
        } catch { throw Failure.invalidState }
        for (name, previous, after) in [
            ("notes.json", journal.previousNotes, journal.notes),
            ("trash.json", journal.previousTrash, journal.trash),
            (ledgerName, journal.previousLedger, journal.ledger)
        ] {
            let current = try read(directory.appendingPathComponent(name))
            guard current.map(digest) == previous || current == after else { throw Failure.invalidState }
        }
        try journal.notes.write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
        try checkpoint(.notesWritten)
        try journal.trash.write(to: directory.appendingPathComponent("trash.json"), options: .atomic)
        try checkpoint(.trashWritten)
        try journal.ledger.write(to: directory.appendingPathComponent(ledgerName), options: .atomic)
        try checkpoint(.ledgerWritten)
        try FileManager.default.removeItem(at: url)
        // Commit already completed. An observation failure cannot undo its result.
        try? checkpoint(.completed)
    }
    static func execute(_ request: Request, notes: [StickyNote], trash: LocalNoteTrash,
                        in directory: URL, checkpoint: (Stage) throws -> Void = { _ in }) throws -> (Result, [StickyNote], LocalNoteTrash) {
        guard try read(directory.appendingPathComponent(journalName)) == nil else { throw Failure.recoveryRequired }
        if request.command == "list" {
            guard request.ids.isEmpty, request.text == nil, request.color == nil else { throw Failure.invalidRequest }
            return (Result(requestID: request.id, notes: notes.filter { !trash.ids.contains($0.id) }), notes, trash)
        }
        guard ["add", "edit", "delete", "restore"].contains(request.command),
              request.text.map({ $0.utf8.count <= 8 * 1024 * 1024 }) ?? true,
              request.color.map({ (0...3).contains($0) }) ?? true,
              Set(request.ids).count == request.ids.count else { throw Failure.invalidRequest }
        let fingerprint = digest(try encoded(request))
        var ledger = try ledger(in: directory)
        if let existing = ledger.records[request.id.uuidString] {
            guard existing.fingerprint == fingerprint else { throw Failure.conflictingRequestID }
            return (existing.result, notes, trash)
        }
        guard ledger.records.count < maximumRecords else { throw Failure.ledgerFull }
        var updated = notes
        var updatedTrash = trash
        var affected: [StickyNote]
        switch request.command {
        case "add":
            guard request.ids.isEmpty else { throw Failure.invalidRequest }
            let note = StickyNote(text: request.text ?? "", color: request.color ?? 0, visible: false)
            updated.append(note)
            affected = [note]
        case "edit":
            guard request.ids.count == 1, request.text != nil || request.color != nil,
                  let index = updated.firstIndex(where: { $0.id == request.ids[0] && !trash.ids.contains($0.id) }) else { throw Failure.invalidRequest }
            if let text = request.text { updated[index].text = text }
            if let color = request.color { updated[index].color = color }
            affected = [updated[index]]
        default:
            let ids = Set(request.ids)
            let restoring = request.command == "restore"
            guard !ids.isEmpty, request.text == nil, request.color == nil,
                  ids.isSubset(of: Set(notes.filter { trash.ids.contains($0.id) == restoring }.map(\.id))) else { throw Failure.invalidRequest }
            if restoring { updatedTrash.ids.subtract(ids); updatedTrash.lastBatch.subtract(ids) }
            else { updatedTrash.ids.formUnion(ids); updatedTrash.lastBatch = ids }
            affected = notes.filter { ids.contains($0.id) }
        }
        let result = Result(requestID: request.id, notes: affected)
        ledger.records[request.id.uuidString] = Record(fingerprint: fingerprint, result: result)
        let original = try read(directory.appendingPathComponent("notes.json"))
        let originalTrash = try read(directory.appendingPathComponent("trash.json"))
        let originalLedger = try read(directory.appendingPathComponent(ledgerName))
        let noteData: Data
        if let original, request.command == "delete" || request.command == "restore" {
            noteData = original
        } else {
            noteData = try CompatibleNoteFile.encode(updated, preserving: original)
        }
        let journal = Journal(notes: noteData, trash: try encoded(updatedTrash), ledger: try encoded(ledger),
                              previousNotes: original.map(digest), previousTrash: originalTrash.map(digest),
                              previousLedger: originalLedger.map(digest))
        let data = try encoded(journal)
        guard data.count <= 64 * 1024 * 1024 else { throw Failure.ledgerFull }
        try data.write(to: directory.appendingPathComponent(journalName), options: .atomic)
        // After preparation, errors mean that recovery must complete the accepted command.
        try checkpoint(.prepared)
        try recover(in: directory, checkpoint: checkpoint)
        return (result, updated, updatedTrash)
    }
}
