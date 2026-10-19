import Foundation
import CryptoKit

/// Only the explicitly selected sync folder is accessed. Immutable, content-addressed
/// events survive concurrent iCloud Drive copies; no shared notes.json is overwritten.
enum SyncFolder {
    struct Manifest: Codable { var version = 1; var id = UUID() }
    struct Event: Codable { var version = 1; var value: SyncValue; var parents: [String] }
    static func coordinated<T>(_ folder: URL, writing: Bool, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let accessor: (URL) -> Void = { url in result = Result { try body(url) } }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if writing { coordinator.coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError, byAccessor: accessor) }
        else { coordinator.coordinate(readingItemAt: folder, options: .withoutChanges, error: &coordinationError, byAccessor: accessor) }
        if let coordinationError { throw coordinationError }
        guard let result else { throw SyncCoordinator.Failure.blocked("The selected folder is unavailable.") }
        return try result.get()
    }
    static func requireCloud(_ folder: URL) throws {
        guard try folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true else {
            throw SyncCoordinator.Failure.blocked("Choose a folder in iCloud Drive. This location is not confirmed as an iCloud item.")
        }
    }
    static func checkedFile(_ url: URL, maximum: Int = 1_048_576) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= maximum else { throw SyncCoordinator.Failure.blocked("A sync file is unsafe or too large.") }
        let data = try Data(contentsOf: url)
        guard data.count <= maximum else { throw SyncCoordinator.Failure.blocked("A sync file is too large.") }
        return data
    }
    static func manifest(_ folder: URL) throws -> Manifest {
        let value = try JSONDecoder().decode(Manifest.self, from: checkedFile(folder.appendingPathComponent("istickies-sync.json"), maximum: 4096))
        guard value.version == 1 else { throw SyncCoordinator.Failure.blocked("Unsupported sync folder version.") }
        return value
    }
    static func create(in parent: URL, requireICloud: Bool = true) throws -> URL {
        if requireICloud { try requireCloud(parent) }
        return try coordinated(parent, writing: true) { parent in
            let value = Manifest()
            let folder = parent.appendingPathComponent("iStickies2-" + value.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("events"), withIntermediateDirectories: false)
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("istickies-sync.json"), options: .atomic)
            return folder
        }
    }
    static func snapshot(_ folder: URL, id: UUID) throws -> [CloudNote] {
        guard try manifest(folder).id == id else { throw SyncCoordinator.Failure.blocked("The selected sync folder identity changed.") }
        let eventsURL = folder.appendingPathComponent("events", isDirectory: true)
        guard try eventsURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw SyncCoordinator.Failure.blocked("Sync events must be a real directory.") }
        let files = try FileManager.default.contentsOfDirectory(at: eventsURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        guard files.count <= 20_000 else { throw SyncCoordinator.Failure.blocked("Sync history reached its safe limit. No notes were removed; contact support before continuing.") }
        var events: [String: Event] = [:]
        for file in files {
            guard file.pathExtension == "json", file.deletingPathExtension().lastPathComponent.count == 64 else { throw SyncCoordinator.Failure.blocked("Unexpected file in sync history. No notes were replaced.") }
            let data = try checkedFile(file)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == file.deletingPathExtension().lastPathComponent else { throw SyncCoordinator.Failure.blocked("A sync file is incomplete or changed. Wait for iCloud download to finish.") }
            let event = try JSONDecoder().decode(Event.self, from: data)
            guard event.version == 1, Set(event.parents).count == event.parents.count,
                  event.parents.count <= 1000 else { throw SyncCoordinator.Failure.blocked("Unsupported sync event.") }
            events[hash] = event
        }
        var referenced = Set<String>()
        for event in events.values {
            for parent in event.parents {
                guard let previous = events[parent], previous.value.id == event.value.id else { throw SyncCoordinator.Failure.blocked("Waiting for missing iCloud history. Local changes remain queued.") }
                referenced.insert(parent)
            }
        }
        // Content hashes make cycles infeasible, but reject a headless graph explicitly.
        let grouped = Dictionary(grouping: events.keys.filter { !referenced.contains($0) }, by: { events[$0]!.value.id })
        guard Set(grouped.keys) == Set(events.values.map { $0.value.id }) else { throw SyncCoordinator.Failure.blocked("Invalid sync history graph.") }
        return try grouped.map { _, keys in
            let heads = keys.sorted()
            var values: [SyncValue] = []
            for head in heads where !values.contains(events[head]!.value) { values.append(events[head]!.value) }
            return CloudNote(value: values[0], alternatives: values.count > 1 ? values : nil, systemFields: try JSONEncoder().encode(heads))
        }
    }
    static func save(_ value: SyncValue, replacing base: CloudNote?, folder: URL, id: UUID) throws -> CloudNote {
        try coordinated(folder, writing: true) { folder in
            let existing = try snapshot(folder, id: id).first { $0.value.id == value.id }
            guard existing?.systemFields == base?.systemFields else { throw SyncCoordinator.Failure.blocked("Another device changed this note. Sync again to compare versions.") }
            let parents = try base.map { try JSONDecoder().decode([String].self, from: $0.systemFields) } ?? []
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Event(value: value, parents: parents))
            guard data.count <= 1_048_576 else { throw SyncCoordinator.Failure.blocked("This note is too large to sync; its local copy is preserved.") }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let destination = folder.appendingPathComponent("events/" + hash + ".json")
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try checkedFile(destination) == data else { throw SyncCoordinator.Failure.blocked("A sync event changed unexpectedly.") }
            } else { try data.write(to: destination, options: .atomic) }
            return CloudNote(value: value, systemFields: try JSONEncoder().encode([hash]))
        }
    }
}

@MainActor final class FolderSyncTransport: SyncTransport {
    let folder: URL
    let id: UUID
    private let requireICloud: Bool
    private let access: Bool
    var scope: String { "iCloudDrive/" + id.uuidString }
    var availability: String? { nil }
    var requiresLaunchConsent: Bool { requireICloud }
    var completionMessage: String { "Saved to the selected folder. iCloud Drive manages upload and download when connected." }
    init(folder: URL, id: UUID, requireICloud: Bool = true) {
        self.folder = folder; self.id = id; self.requireICloud = requireICloud
        access = folder.startAccessingSecurityScopedResource()
    }
    deinit { if access { folder.stopAccessingSecurityScopedResource() } }
    func account() async throws -> String {
        let folder = folder, id = id, requireICloud = requireICloud
        return try await Task.detached {
            if requireICloud { try SyncFolder.requireCloud(folder) }
            return try SyncFolder.coordinated(folder, writing: false) { url in
                guard try SyncFolder.manifest(url).id == id else { throw SyncCoordinator.Failure.blocked("Sync folder identity changed. Reconnect the original folder.") }
                return id.uuidString
            }
        }.value
    }
    func fetch(createZoneIfMissing: Bool) async throws -> [CloudNote] {
        let folder = folder, id = id
        return try await Task.detached { try SyncFolder.coordinated(folder, writing: false) { try SyncFolder.snapshot($0, id: id) } }.value
    }
    func save(_ value: SyncValue, replacing base: CloudNote?) async throws -> CloudNote {
        let folder = folder, id = id
        return try await Task.detached { try SyncFolder.save(value, replacing: base, folder: folder, id: id) }.value
    }
}
