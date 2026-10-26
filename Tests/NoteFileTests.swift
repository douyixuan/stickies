import CoreGraphics
import Foundation

/// CGRect's own Codable layout, so fixtures match whatever the platform writes.
private func frameJSON(_ rect: CGRect) -> String {
    guard let data = try? JSONEncoder().encode(rect), let text = String(data: data, encoding: .utf8) else {
        return "null"
    }
    return text
}

func testNoteFile() {
    let directory = Scratch.directory("file")
    let url = directory.appendingPathComponent(NoteFile.name)

    // Round trip.
    let notes = [StickyNote(text: "one", color: 2, frame: CGRect(x: 1, y: 2, width: 300, height: 400)),
                 StickyNote(text: "two", visible: false)]
    try? NoteFile.save(notes, to: url)
    Check.equal(try? NoteFile.load(from: url), notes, "notes survive a save and load")
    Check.that((try? NoteFile.load(from: directory.appendingPathComponent("absent.json")))?.isEmpty == true,
               "a missing file reads as an empty profile")

    // 0.1 wrote a bare array.
    let legacyFrame = CGRect(x: 5, y: 6, width: 260, height: 220)
    let legacy = Data("""
        [{"id":"\(UUID().uuidString)","text":"legacy","color":1,"visible":true,"frame":\(frameJSON(legacyFrame))}]
        """.utf8)
    let fromLegacy = try? NoteFile.decode(legacy)
    Check.equal(fromLegacy?.count, 1, "a bare array still reads")
    Check.equal(fromLegacy?.first?.text, "legacy", "legacy content is preserved")
    Check.equal(fromLegacy?.first?.frame.origin, CGPoint(x: 5, y: 6), "legacy geometry is preserved")

    // 0.2 split content and device state.
    let id = UUID().uuidString
    let split = Data("""
        {"schemaVersion":2,
         "contents":[{"id":"\(id)","text":"split","color":3}],
         "localStates":[{"id":"\(id)","state":{"frame":\(frameJSON(CGRect(x: 7, y: 8, width: 200, height: 150))),"visible":false}}]}
        """.utf8)
    let fromSplit = try? NoteFile.decode(split)
    Check.equal(fromSplit?.first?.text, "split", "the 0.2 envelope still reads")
    Check.equal(fromSplit?.first?.color, 3, "0.2 colors are preserved")
    Check.equal(fromSplit?.first?.visible, false, "0.2 visibility is preserved")
    Check.equal(fromSplit?.first?.frame.width, 200, "0.2 geometry is preserved")

    // 0.3 wrapped that envelope in a command ledger that no longer exists.
    let wrapped = Data("""
        {"schemaVersion":3,"records":{},"document":{"schemaVersion":2,
         "contents":[{"id":"\(id)","text":"wrapped","color":0}],
         "localStates":[{"id":"\(id)","state":{"frame":\(frameJSON(CGRect(x: 9, y: 9, width: 260, height: 220))),"visible":true}}]}}
        """.utf8)
    Check.equal((try? NoteFile.decode(wrapped))?.first?.text, "wrapped",
                "a 0.3 ledger file reads its document and drops the ledger")

    // Refusals.
    Check.that((try? NoteFile.decode(Data("not json".utf8))) == nil, "garbage is refused")
    Check.that((try? NoteFile.decode(Data(#"{"schemaVersion":999}"#.utf8))) == nil,
               "a newer schema is refused rather than guessed at")
    let duplicate = StickyNote(id: notes[0].id, text: "clash")
    Check.that((try? NoteFile.encode([notes[0], duplicate])) == nil, "duplicate ids are refused")

    // A refused write leaves the previous file intact.
    try? NoteFile.save(notes, to: url)
    let before = try? Data(contentsOf: url)
    try? NoteFile.save([notes[0], duplicate], to: url)
    Check.equal(try? Data(contentsOf: url), before, "a refused write does not touch the file")
}

func testPreferencesMigration() {
    // 0.2 only had a global keep-on-top flag.
    let legacy = Data(#"{"keepOnTop":true}"#.utf8)
    let migrated = try? JSONDecoder().decode(Preferences.self, from: legacy)
    Check.equal(migrated?.windowMode, .floating, "keepOnTop becomes the floating window mode")
    Check.equal(migrated?.snapToScreenEdges, true, "edge snapping defaults on")

    let empty = try? JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    Check.equal(empty?.windowMode, .standard, "an empty file means ordinary windows")

    var preferences = Preferences()
    let id = UUID()
    preferences.floatingOverrides[id.uuidString] = true
    Check.equal(preferences.mode(for: id), .floating, "a per-note override wins over the default")
    Check.that(preferences.hasOverride(id), "the override is reported")
    Check.equal(preferences.mode(for: UUID()), .standard, "other notes keep the default")

    // keepOnTop is read-only input and is not written back.
    let encoded = try? JSONEncoder().encode(preferences)
    let round = encoded.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
    Check.equal(round, preferences, "preferences survive a round trip")
}
