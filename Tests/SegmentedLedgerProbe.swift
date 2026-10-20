import Foundation
import Darwin
@main struct SegmentedLedgerProbe {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2, args[0].contains("istk-ledger-") else { exit(64) }
        let directory = URL(fileURLWithPath: args[0])
        let fd = open(directory.appendingPathComponent("notes.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { exit(75) }
        defer { close(fd) }
        if args[1] == "no-space" {
            do {
                try SegmentedCommandLedger.migrate(in: directory) { stage in
                    if stage == .staged { throw CocoaError(.fileWriteOutOfSpace) }
                }
            } catch { exit(74) }
            return
        }
        if args[1] == "migrate" {
            try SegmentedCommandLedger.migrate(in: directory) { stage in
                if args.last == stage.rawValue { _exit(91) }
            }
        } else {
            try SerializedNoteCommands.recover(in: directory)
            let notes = try CompatibleNoteFile.decode(Data(contentsOf: directory.appendingPathComponent("notes.json")))
            let trash = try LocalNoteTrash.load(from: directory.appendingPathComponent("trash.json"))
            let request = try JSONDecoder().decode(SerializedNoteCommands.Request.self, from: FileHandle.standardInput.readDataToEndOfFile())
            _ = try SerializedNoteCommands.execute(request, notes: notes, trash: trash, in: directory) { stage in
                if args.last == stage.rawValue { _exit(91) }
            }
        }
    }
}
