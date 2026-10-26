import Foundation

/// How note windows sit relative to other apps. Device-local, never synced.
enum NoteWindowMode: String, Codable, CaseIterable {
    case standard, desktop, floating
}

/// Device-local settings in `preferences.json`. Decoding accepts the 0.2 and 0.3 files.
struct Preferences: Codable, Equatable {
    var windowMode: NoteWindowMode = .standard
    /// Per-note overrides of `windowMode`, keyed by note id string.
    var floatingOverrides: [String: Bool] = [:]
    var snapToScreenEdges = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 0.2 only had a global `keepOnTop` flag.
        let keepOnTop = try container.decodeIfPresent(Bool.self, forKey: .keepOnTop) ?? false
        windowMode = try container.decodeIfPresent(NoteWindowMode.self, forKey: .windowMode)
            ?? (keepOnTop ? .floating : .standard)
        floatingOverrides = try container.decodeIfPresent([String: Bool].self, forKey: .floatingOverrides) ?? [:]
        snapToScreenEdges = try container.decodeIfPresent(Bool.self, forKey: .snapToScreenEdges) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowMode, forKey: .windowMode)
        try container.encode(floatingOverrides, forKey: .floatingOverrides)
        try container.encode(snapToScreenEdges, forKey: .snapToScreenEdges)
    }

    /// `keepOnTop` is read-only legacy input and is not written back.
    private enum CodingKeys: String, CodingKey {
        case keepOnTop, windowMode, floatingOverrides, snapToScreenEdges
    }

    func mode(for id: UUID) -> NoteWindowMode {
        guard let override = floatingOverrides[id.uuidString] else { return windowMode }
        return override ? .floating : .standard
    }

    func hasOverride(_ id: UUID) -> Bool { floatingOverrides[id.uuidString] != nil }
}
