import Foundation

/// Read-only executable: no AppKit, no lock creation and no migration or save.
@main struct NoteDataCheck {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let notes = try CompatibleNoteFile.decode(data)
            let saved = try CompatibleNoteFile.encode(notes, preserving: data)
            let restored = try CompatibleNoteFile.decode(saved)
            guard notes.count == restored.count,
                  zip(notes, restored).allSatisfy({ a, b in a.id == b.id && a.text == b.text && a.color == b.color && a.frame == b.frame && a.visible == b.visible }) else { exit(2) }
            print("PASS: compatible read/save/reload in memory; source untouched")
        } catch {
            // Never log decoded text, file bytes, or decoder descriptions containing values.
            fputs("FAIL: unsupported or invalid note data; installation must stop\n", stderr)
            exit(1)
        }
    }
}
