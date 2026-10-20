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
        var requestID = UUID()
        var directory: String?
        var values: [String] = []
        var text: String?
        var stdin = false
        var color: Int?
        var trash = false
    }
    static let commands = ["help", "version", "list", "get", "search", "add", "edit", "delete", "restore", "result"]
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
                case "--data-dir", "--text", "--color", "--request-id":
                    guard index < args.count else { throw Failure("usage", "Missing option value: " + item) }
                    let value = args[index]; index += 1
                    if item == "--data-dir" { request.directory = value }
                    if item == "--text" { request.text = value }
                    if item == "--request-id" {
                        guard let id = UUID(uuidString: value) else { throw Failure("usage", "Request ID must be a UUID.") }
                        request.requestID = id
                    }
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
        case "get", "search", "edit", "result": guard count == 1 else { throw Failure("usage", "This command requires one ID or search query.") }
        case "delete", "restore": guard count > 0 else { throw Failure("usage", "Provide one or more full note IDs.") }
        default: break
        }
        if request.command == "edit", request.text == nil && !request.stdin && request.color == nil {
            throw Failure("usage", "Edit requires --text, --stdin, or --color.")
        }
        if ["get", "edit", "delete", "restore", "result"].contains(request.command) {
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
                    "concurrency": "A running compatible app serializes local requests. Otherwise the CLI needs notes.lock. No force unlock.",
                    "deletion": "delete moves notes to this Mac's recoverable Trash. It does not delete cloud records or erase history.",
                    "output": "One JSON object on stdout for success; one on stderr for failure. schemaVersion is 1.",
                    "retries": "Use --request-id UUID for mutations. Query result UUID after an unknown outcome. Never change parameters for the same ID.",
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
        let coreRequest = SerializedNoteCommands.Request(
            id: request.requestID, command: request.command,
            ids: ["get", "edit", "delete", "restore", "result"].contains(request.command) ? request.values.map { UUID(uuidString: $0)! } : [],
            text: request.command == "search" ? request.values[0] : text, color: request.color,
            includeTrash: request.trash ? true : nil, visibleOnCreate: request.command == "add" ? true : nil)
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw Failure("io", "Cannot acquire the data lock.", 74) }
            return try liveRequest(coreRequest, request: request, directory: directory)
        }
        do {
            try SerializedNoteCommands.recover(in: directory)
        } catch is SerializedNoteCommands.Failure {
            throw Failure("invalid_data", "Command recovery data is invalid or conflicts with storage. No command was executed.", 65)
        }
        let file = directory.appendingPathComponent("notes.json")
        let trashFile = directory.appendingPathComponent("trash.json")
        try rejectLink(file); try rejectLink(trashFile)
        // Read failures retain the I/O exit code. Only decoded bytes can be invalid data.
        let noteData = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        let trashData = FileManager.default.fileExists(atPath: trashFile.path) ? try Data(contentsOf: trashFile) : nil
        var notes: [StickyNote]
        var trash: LocalNoteTrash
        do {
            notes = try noteData.map(CompatibleNoteFile.decode) ?? []
            trash = try trashData.map(LocalNoteTrash.decode) ?? LocalNoteTrash()
        } catch { throw Failure("invalid_data", "Cannot decode notes or Trash. Original files are unchanged.", 65) }
        do {
            let (result, _, _) = try SerializedNoteCommands.execute(coreRequest, notes: notes, trash: trash, in: directory)
            return try output(result, for: request)
        } catch let error as SerializedNoteCommands.Failure {
            throw map(error)
        } catch {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(SerializedNoteCommands.journalName).path) {
                throw Failure("outcome_unknown", "Storage requires recovery. Query or retry the same request ID.", 74)
            }
            throw error
        }
    }
    static func map(_ failure: SerializedNoteCommands.Failure) -> Failure {
        switch failure {
        case .notFound: return Failure("not_found", "The note or recorded request was not found.", 66)
        case .invalidRequest: return Failure("usage", "Invalid command parameters.")
        case .conflictingRequestID: return Failure("request_conflict", "Request ID already has different parameters.")
        case .ledgerFull: return Failure("capacity", "The durable request ledger is full. No command was accepted.", 75)
        case .recoveryRequired: return Failure("recovery_required", "Storage requires recovery before another mutation.", 75)
        default: return Failure("invalid_data", "Command storage is invalid. No command was accepted.", 65)
        }
    }
    static func output(_ result: SerializedNoteCommands.Result, for request: Request) throws -> Any {
        switch request.command {
        case "list", "search": return try result.notes.map { try record($0, trashed: request.trash) }
        case "get", "add", "edit":
            guard let note = result.notes.first else { throw Failure("invalid_data", "Missing command result.", 65) }
            return try record(note, trashed: request.trash)
        case "delete", "restore":
            return ["ids": result.notes.map { $0.id.uuidString }.sorted(), "count": result.notes.count,
                    "scope": "this_mac", "recoverable": true] as [String: Any]
        case "result": return try JSONSerialization.jsonObject(with: SerializedNoteCommands.encoded(result))
        default: throw Failure("usage", "Unknown command.")
        }
    }
    static func liveRequest(_ command: SerializedNoteCommands.Request, request: Request, directory: URL) throws -> Any {
        let data = try SerializedNoteCommands.encoded(LocalCommandSocket.Message(request: command))
        guard data.count <= LocalCommandSocket.maximumFrame else { throw Failure("usage", "Encoded request exceeds the 16 MiB local transport limit.") }
        let fd: Int32
        do { fd = try LocalCommandSocket.connect(to: directory) }
        catch LocalCommandSocket.Failure.unsafeEndpoint { throw Failure("unsafe_path", "The local command endpoint is unsafe.", 65) }
        catch { throw Failure("locked", "The app or another command owns this data folder. Quit it normally and retry, or use a compatible app.", 75) }
        defer { close(fd) }
        do { try LocalCommandSocket.writeFrame(data, to: fd) }
        catch { throw Failure("io", "The complete request was not sent. Preserve its request ID before retrying.", 74) }
        let reply: LocalCommandSocket.Reply
        do {
            reply = try JSONDecoder().decode(LocalCommandSocket.Reply.self, from: LocalCommandSocket.readFrame(fd))
            guard reply.version == 1 else { throw LocalCommandSocket.Failure.invalidFrame }
        } catch { throw Failure("outcome_unknown", "The response was lost or timed out. Query or retry the same request ID.", 74) }
        if let result = reply.result {
            let expected = request.command == "result" ? UUID(uuidString: request.values[0])! : command.id
            guard result.requestID == expected else { throw Failure("outcome_unknown", "The response ID did not match. Preserve the request ID.", 74) }
            return try output(result, for: request)
        }
        throw Failure(reply.code ?? "outcome_unknown", reply.message ?? "No command result was received.", reply.status ?? 74)
    }
    static func main() {
        var requestID: String?
        do {
            let request = try parse(Array(CommandLine.arguments.dropFirst()))
            requestID = request.requestID.uuidString
            let data = try run(request)
            emit(["schemaVersion": 1, "ok": true, "command": request.command, "requestID": request.requestID.uuidString, "data": data])
        } catch let failure as Failure {
            emit(["schemaVersion": 1, "ok": false, "requestID": requestID ?? "", "error": ["code": failure.code, "message": failure.message]], error: true)
            exit(failure.status)
        } catch {
            emit(["schemaVersion": 1, "ok": false, "requestID": requestID ?? "", "error": ["code": "io", "message": "Operation failed. No success was recorded. Check storage access and retry."]], error: true)
            exit(74)
        }
    }
}
