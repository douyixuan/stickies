import Foundation

/// A deliberately small CLI over one notes profile: list, search, get, add.
/// It talks to the same core the app uses, and takes the same exclusive lock,
/// so it refuses to run rather than write behind a running app's back.
@main
struct Istk {
    static let usage = """
        istk --dir <notes-directory> <command>

          list                 every active note as JSON
          search <query>       notes matching all whitespace-separated terms
          get <id>             one note as JSON
          add [text]           create a note (reads stdin when text is omitted)
          help | version

        Exit codes: 0 ok, 64 usage, 69 directory unavailable, 70 write failed, 66 note not found.
        """

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var directory: String?

        if let index = arguments.firstIndex(of: "--dir") {
            guard index + 1 < arguments.count else { fail(64, "--dir needs a path") }
            directory = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }

        guard let command = arguments.first else { fail(64, usage) }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "help", "--help", "-h":
            print(usage)
            return
        case "version", "--version":
            emit(["version": "1.0", "schemaVersion": NoteFile.currentVersion])
            return
        default:
            break
        }

        guard let directory else { fail(64, "every data command needs --dir <notes-directory>") }
        let store = NoteStore(directory: URL(fileURLWithPath: directory, isDirectory: true))
        if let reason = store.readOnlyReason, command == "add" { fail(69, reason) }

        switch command {
        case "list":
            emit(["notes": store.activeNotes.map(describe)])
        case "search":
            guard let query = rest.first else { fail(64, "search needs a query") }
            emit(["notes": store.search(query).map(describe)])
        case "get":
            guard let id = rest.first.flatMap(UUID.init(uuidString:)) else { fail(64, "get needs a note id") }
            guard let note = store.note(id), !store.isTrashed(id) else { fail(66, "no note with id \(id)") }
            emit(describe(note))
        case "add":
            let text = rest.isEmpty
                ? String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
                : rest.joined(separator: " ")
            guard let id = store.createNote(visible: false) else { fail(70, store.lastError ?? "could not create a note") }
            store.setText(id, text)
            guard !store.hasUnsavedChanges, let note = store.note(id) else {
                fail(70, store.lastError ?? "the note could not be saved")
            }
            emit(describe(note))
        default:
            fail(64, usage)
        }
    }

    private static func describe(_ note: StickyNote) -> [String: Any] {
        ["id": note.id.uuidString, "title": note.title, "text": note.text,
         "color": note.color, "colorName": NotePalette.name(note.color), "visible": note.visible]
    }

    private static func emit(_ value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            fail(70, "could not encode the result")
        }
        print(text)
    }

    private static func fail(_ code: Int32, _ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
