import Foundation

/// Device-local trash. Content stays in notes.json and retains its sync identity.
struct LocalNoteTrash: Codable {
    var version = 1
    var ids = Set<UUID>()
    var lastBatch = Set<UUID>()

    static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.lastBatch.isSubset(of: value.ids) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    func save(to url: URL) throws {
        guard version == 1, lastBatch.isSubset(of: ids) else { throw CocoaError(.fileWriteUnknown) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
