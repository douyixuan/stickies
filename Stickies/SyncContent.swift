import Foundation

// NoteContent and its merge policy originate in PR #4 (369e65b).
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


struct SyncValue: Codable, Equatable, Identifiable {
    var content: NoteContent
    var deleted = false
    var id: UUID { content.id }
    static func merge(base: Self?, local: Self, remote: Self) throws -> Self {
        if local == remote { return local }
        guard let base else { throw NoteContent.MergeError.conflict("first sync") }
        if local == base { return remote }
        if remote == base { return local }
        guard !local.deleted, !remote.deleted else { throw NoteContent.MergeError.conflict("edit versus delete") }
        return try Self(content: NoteContent.merge(base: base.content, local: local.content, remote: remote.content))
    }
}
struct CloudNote: Codable, Equatable {
    var value: SyncValue
    var alternatives: [SyncValue]? = nil
    var systemFields: Data
}
@MainActor protocol SyncTransport {
    var scope: String { get }
    var availability: String? { get }
    var completionMessage: String { get }
    var requiresLaunchConsent: Bool { get }
    func account() async throws -> String
    func fetch(createZoneIfMissing: Bool) async throws -> [CloudNote]
    func save(_ value: SyncValue, replacing: CloudNote?) async throws -> CloudNote
}
@MainActor protocol SyncLocalStore: AnyObject {
    var syncValues: [SyncValue] { get }
    var syncWritable: Bool { get }
    var syncStorageOwned: Bool { get }
    func applySync(_ value: SyncValue) throws
}

extension SyncTransport { var requiresLaunchConsent: Bool { false }; var completionMessage: String { "Up to date with iCloud." } }
