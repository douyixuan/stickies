import Foundation
import Darwin

/// Immutable segment inventory is published only inside notes.json. Unreferenced
/// files are harmless staging remnants; published history is never deleted.
enum SegmentedCommandLedger {
    typealias Core = SerializedNoteCommands
    struct Segment: Codable, Equatable {
        var name: String
        var digest: String
        var size: Int
        var count: Int
    }
    struct Manifest: Codable, Equatable {
        var profile: UUID
        var generation: UInt64
        var segments: [Segment]
    }
    enum Stage: String { case staged, published }
    static let maximumSegmentBytes = 16 * 1024 * 1024
    static func manifest(_ data: Data?) throws -> Manifest? {
        do { return try decodeManifest(data) }
        catch { throw Core.Failure.invalidState }
    }
    private static func decodeManifest(_ data: Data?) throws -> Manifest? {
        guard let data else { return nil }
        let raw = try LosslessJSON.parse(data)
        guard case .scalar("3")? = raw.object?["schemaVersion"] else { return nil }
        guard let value = raw.object?["commandLedger"], let document = raw.object?["document"] else { throw Core.Failure.invalidState }
        if case .scalar("3")? = document.object?["schemaVersion"] { throw Core.Failure.invalidState }
        _ = try CompatibleNoteFile.decode(document.data())
        return try JSONDecoder().decode(Manifest.self, from: value.data())
    }
    static func replacing(_ data: Data, manifest: Manifest) throws -> Data {
        var raw = try LosslessJSON.parse(data).object ?? [:]
        guard case .scalar("3")? = raw["schemaVersion"] else { throw Core.Failure.invalidState }
        raw["commandLedger"] = try LosslessJSON.parse(Core.encoded(manifest))
        return try LosslessJSON.object(raw).data()
    }
    static func records(_ manifest: Manifest, in directory: URL) throws -> [String: Core.Record] {
        var records: [String: Core.Record] = [:]
        var names = Set<String>()
        for segment in manifest.segments {
            guard segment.name == "command-segment-\(manifest.profile.uuidString)-\(segment.digest).json",
                  segment.digest.count == 64, segment.digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  names.insert(segment.name).inserted,
                  (1...128).contains(segment.count), (1...maximumSegmentBytes).contains(segment.size),
                  let bytes = try Core.read(directory.appendingPathComponent(segment.name)),
                  bytes.count == segment.size, Core.digest(bytes) == segment.digest else { throw Core.Failure.invalidState }
            let ledger = try Core.decodeLedger(bytes)
            guard ledger.records.count == segment.count else { throw Core.Failure.invalidState }
            for (id, record) in ledger.records {
                guard records.updateValue(record, forKey: id) == nil else { throw Core.Failure.invalidState }
            }
        }
        return records
    }
    static func validate(_ data: Data?, in directory: URL) throws {
        if let manifest = try manifest(data) { _ = try records(manifest, in: directory) }
    }
    static func stage(_ records: [String: Core.Record], profile: UUID, in directory: URL) throws -> Segment {
        let bytes = try Core.encoded(Core.Ledger(records: records))
        guard !records.isEmpty, records.count <= 128, bytes.count <= maximumSegmentBytes else { throw Core.Failure.ledgerFull }
        let digest = Core.digest(bytes)
        let name = "command-segment-\(profile.uuidString)-\(digest).json"
        let url = directory.appendingPathComponent(name)
        if let existing = try Core.read(url) {
            guard existing == bytes else { throw Core.Failure.invalidState }
        } else {
            // Atomic publication with exclusive destination creation. Never replace history.
            let staging = directory.appendingPathComponent(".command-stage-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try bytes.write(to: staging, options: .withoutOverwriting)
            guard renamex_np(staging.path, url.path, UInt32(RENAME_EXCL)) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        guard try Core.read(url) == bytes else { throw Core.Failure.invalidState }
        return Segment(name: name, digest: digest, size: bytes.count, count: records.count)
    }
    static func append(_ record: Core.Record, to manifest: Manifest, in directory: URL) throws -> Manifest {
        guard manifest.generation < UInt64.max else { throw Core.Failure.ledgerFull }
        var next = manifest
        var tail: [String: Core.Record] = [:]
        if let last = next.segments.last, last.count < 128 {
            guard let bytes = try Core.read(directory.appendingPathComponent(last.name)) else { throw Core.Failure.invalidState }
            tail = try Core.decodeLedger(bytes).records
            let candidate = tail.merging([record.result.requestID.uuidString: record]) { _, new in new }
            if try Core.encoded(Core.Ledger(records: candidate)).count <= maximumSegmentBytes {
                next.segments.removeLast()
            } else { tail = [:] }
        }
        tail[record.result.requestID.uuidString] = record
        next.segments.append(try stage(tail, profile: manifest.profile, in: directory))
        next.generation += 1
        return next
    }
    /// Caller owns notes.lock. No automatic migration, no rollback after publication.
    static func migrate(in directory: URL, checkpoint: (Stage) throws -> Void = { _ in }) throws {
        try Core.recover(in: directory)
        let url = directory.appendingPathComponent("notes.json")
        guard let original = try Core.read(url) else { throw Core.Failure.invalidState }
        if let manifest = try manifest(original) { _ = try records(manifest, in: directory); return }
        _ = try CompatibleNoteFile.decode(original)
        if let trash = try Core.read(directory.appendingPathComponent("trash.json")) { _ = try LocalNoteTrash.decode(trash) }
        let old = try Core.ledger(in: directory)
        var manifest = Manifest(profile: UUID(), generation: 0, segments: [])
        var chunk: [String: Core.Record] = [:]
        for id in old.records.keys.sorted() {
            let record = old.records[id]!
            var candidate = chunk; candidate[id] = record
            let candidateBytes = try Core.encoded(Core.Ledger(records: candidate))
            if !chunk.isEmpty && (candidate.count > 128 || candidateBytes.count > maximumSegmentBytes) {
                manifest.segments.append(try stage(chunk, profile: manifest.profile, in: directory)); chunk = [:]
            }
            chunk[id] = record
        }
        if !chunk.isEmpty { manifest.segments.append(try stage(chunk, profile: manifest.profile, in: directory)) }
        let restored = try records(manifest, in: directory)
        guard try Core.encoded(Core.Ledger(records: restored)) == Core.encoded(old) else { throw Core.Failure.invalidState }
        let wrapper = try LosslessJSON.object(["schemaVersion": .scalar("3"), "document": LosslessJSON.parse(original),
                                               "commandLedger": LosslessJSON.parse(Core.encoded(manifest))]).data()
        guard wrapper.count <= 64 * 1024 * 1024 else { throw Core.Failure.ledgerFull }
        try checkpoint(.staged)
        try wrapper.write(to: url, options: .atomic) // The sole migration commit point.
        try? checkpoint(.published)
    }
}
