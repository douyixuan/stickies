import Foundation
import Darwin

@main
struct Istk {
    struct Failure: Error {
        let code: String
        let message: String
        let status: Int32
        init(_ code: String, _ message: String, _ status: Int32 = 64) {
            self.code = code; self.message = message; self.status = status
        }
    }
    struct Request {
        var command = "help"
        var directory: String?
        var values: [String] = []
        var text: String?
        var stdin = false
        var color: Int?
        var trash = false
    }
    static let commands = ["help", "version", "list", "get", "search", "add", "edit", "delete", "restore"]
    static func emit(_ object: [String: Any], error: Bool = false) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data("{}".utf8)
        let handle = error ? FileHandle.standardError : FileHandle.standardOutput
        handle.write(data + Data([10]))
    }
    static func parse(_ args: [String]) throws -> Request {
        var request = Request()
        var command: String?
        var seen = Set<String>()
        var index = 0
        while index < args.count {
            let item = args[index]; index += 1
            if item.hasPrefix("--") {
                guard seen.insert(item).inserted else { throw Failure("usage", "Duplicate option: " + item) }
                switch item {
                case "--help": request.command = "help"; return request
                case "--version": request.command = "version"; return request
                case "--stdin": request.stdin = true
                case "--trash": request.trash = true
                case "--data-dir", "--text", "--color":
                    guard index < args.count else { throw Failure("usage", "Missing option value: " + item) }
                    let value = args[index]; index += 1
                    if item == "--data-dir" { request.directory = value }
                    if item == "--text" { request.text = value }
                    if item == "--color" {
                        guard let color = Int(value), (0...3).contains(color) else { throw Failure("usage", "Color must be 0, 1, 2, or 3.") }
                        request.color = color
                    }
                default: throw Failure("usage", "Unknown option: " + item)
                }
            } else if command == nil {
                command = item
            } else { request.values.append(item) }
        }
        request.command = command ?? "help"
        guard commands.contains(request.command) else { throw Failure("usage", "Unknown command. Use istk help.") }
        guard !(request.stdin && request.text != nil) else { throw Failure("usage", "Use either --stdin or --text.") }
        let editing = ["add", "edit"].contains(request.command)
        guard editing || (request.text == nil && !request.stdin && request.color == nil) else { throw Failure("usage", "Text and color options require add or edit.") }
        guard !request.trash || ["list", "get", "search"].contains(request.command) else { throw Failure("usage", "--trash requires list, get, or search.") }
        let count = request.values.count
        switch request.command {
        case "help", "version", "list", "add": guard count == 0 else { throw Failure("usage", "Unexpected positional argument.") }
        case "get", "search", "edit": guard count == 1 else { throw Failure("usage", "This command requires one ID or search query.") }
        case "delete", "restore": guard count > 0 else { throw Failure("usage", "Provide one or more full note IDs.") }
        default: break
        }
        if request.command == "edit", request.text == nil && !request.stdin && request.color == nil {
            throw Failure("usage", "Edit requires --text, --stdin, or --color.")
        }
        if ["get", "edit", "delete", "restore"].contains(request.command) {
            guard request.values.allSatisfy({ UUID(uuidString: $0) != nil }), Set(request.values.map { $0.lowercased() }).count == count else {
                throw Failure("usage", "Provide unique full UUIDs.")
            }
        }
        return request
    }
    static func record(_ note: StickyNote, trashed: Bool) throws -> [String: Any] {
        var result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as! [String: Any]
        result["trashed"] = trashed
        return result
    }
    static func rejectLink(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { throw Failure("unsafe_path", "Data files must be regular files, not links or directories.", 65) }
        } else if errno != ENOENT { throw Failure("io", "Cannot inspect the data file.", 74) }
    }
    static func run(_ request: Request) throws -> Any {
        if request.command == "help" {
            return ["usage": "istk --data-dir PATH COMMAND [OPTIONS]", "commands": commands,
                    "read": "list [--trash]; get UUID [--trash]; search QUERY [--trash]",
                    "write": "add [--text TEXT | --stdin] [--color 0..3]; edit UUID [--text TEXT | --stdin] [--color 0..3]; delete UUID...; restore UUID...",
                    "dataDirectory": "Required: --data-dir or STICKIES_DATA_DIR. No automatic profile selection.",
                    "concurrency": "All data commands need the exclusive notes.lock. Quit the app normally first. No force unlock.",
                    "deletion": "delete moves notes to this Mac's recoverable Trash. It does not delete cloud records or erase history.",
                    "output": "One JSON object on stdout for success; one on stderr for failure. schemaVersion is 1.",
                    "exitCodes": ["0": "success", "64": "usage", "65": "invalid data", "66": "not found", "74": "I/O failure", "75": "data locked"]] as [String: Any]
        }
        if request.command == "version" {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let info = NSDictionary(contentsOf: executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist"))
            return ["name": "istk", "version": info?["CFBundleShortVersionString"] as? String ?? "0.3.0-dev",
                    "build": info?["CFBundleVersion"] as? String ?? "development",
                    "commit": info?["StickiesGitCommit"] as? String ?? "unpackaged", "protocolVersion": 1] as [String: Any]
        }
        guard let path = request.directory ?? ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], !path.isEmpty else {
            throw Failure("usage", "Specify --data-dir or STICKIES_DATA_DIR. The app must be closed normally.")
        }
        var text = request.text
        if request.stdin {
            var bytes = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: min(65536, 8 * 1024 * 1024 + 1 - bytes.count)), !chunk.isEmpty {
                bytes.append(chunk)
                if bytes.count > 8 * 1024 * 1024 { break }
            }
            guard bytes.count <= 8 * 1024 * 1024, let input = String(data: bytes, encoding: .utf8) else {
                throw Failure("usage", "stdin must contain UTF-8 text of at most 8 MiB.")
            }
            text = input
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard request.command == "add" else { throw Failure("not_found", "Data directory does not exist.", 66) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else if !isDirectory.boolValue { throw Failure("usage", "Data directory must be a directory.") }
        let lock = directory.appendingPathComponent("notes.lock")
        try rejectLink(lock)
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure("io", "Cannot open the data lock.", 74) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Failure("locked", "The app or another command owns this data folder. Quit it normally and retry.", 75) }
        let file = directory.appendingPathComponent("notes.json")
        let trashFile = directory.appendingPathComponent("trash.json")
        try rejectLink(file); try rejectLink(trashFile)
        var notes: [StickyNote]
        var trash: LocalNoteTrash
        do {
            notes = FileManager.default.fileExists(atPath: file.path) ? try CompatibleNoteFile.decode(Data(contentsOf: file)) : []
            trash = try LocalNoteTrash.load(from: trashFile)
        } catch { throw Failure("invalid_data", "Cannot decode notes or Trash. Original files are unchanged.", 65) }
        let candidates = notes.filter { trash.ids.contains($0.id) == request.trash }
        switch request.command {
        case "list": return try candidates.map { try record($0, trashed: request.trash) }
        case "search":
            let query = request.values[0].split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return try candidates.filter { note in query.allSatisfy { note.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }.map { try record($0, trashed: request.trash) }
        case "get":
            guard let note = candidates.first(where: { $0.id == UUID(uuidString: request.values[0])! }) else { throw Failure("not_found", "Note was not found in the selected view.", 66) }
            return try record(note, trashed: request.trash)
        case "add":
            let note = StickyNote(text: text ?? "", color: request.color ?? 0)
            notes.append(note)
            try CompatibleNoteFile.save(notes, to: file)
            return try record(note, trashed: false)
        case "edit":
            let id = UUID(uuidString: request.values[0])!
            guard let index = notes.firstIndex(where: { $0.id == id && !trash.ids.contains(id) }) else { throw Failure("not_found", "Active note was not found. Restore it before editing.", 66) }
            if let text { notes[index].text = text }
            if let color = request.color { notes[index].color = color }
            try CompatibleNoteFile.save(notes, to: file)
            return try record(notes[index], trashed: false)
        case "delete", "restore":
            let ids = Set(request.values.map { UUID(uuidString: $0)! })
            let restoring = request.command == "restore"
            let eligible = Set(notes.filter { trash.ids.contains($0.id) == restoring }.map(\.id))
            guard ids.isSubset(of: eligible) else { throw Failure("not_found", "At least one note is missing or in the wrong Trash state. No notes changed.", 66) }
            if restoring { trash.ids.subtract(ids); trash.lastBatch.subtract(ids) }
            else { trash.ids.formUnion(ids); trash.lastBatch = ids }
            // One atomic metadata write commits the whole batch. Note bytes never change.
            try trash.save(to: trashFile)
            return ["ids": ids.map(\.uuidString).sorted(), "count": ids.count, "scope": "this_mac", "recoverable": true] as [String: Any]
        default: throw Failure("usage", "Unknown command.")
        }
    }
    static func main() {
        do {
            let request = try parse(Array(CommandLine.arguments.dropFirst()))
            let data = try run(request)
            emit(["schemaVersion": 1, "ok": true, "command": request.command, "data": data])
        } catch let failure as Failure {
            emit(["schemaVersion": 1, "ok": false, "error": ["code": failure.code, "message": failure.message]], error: true)
            exit(failure.status)
        } catch {
            emit(["schemaVersion": 1, "ok": false, "error": ["code": "io", "message": "Operation failed. No success was recorded. Check storage access and retry."]], error: true)
            exit(74)
        }
    }
}
