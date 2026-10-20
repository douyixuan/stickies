import Foundation
import Darwin
import Combine

@main struct CommandCoreProbe {
    @MainActor static func main() async throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("istk-core-") else { exit(64) }
        let store = NoteStore.shared
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "parallel" {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<20 {
                    group.addTask { @MainActor in
                        _ = try! store.executeCommand(.init(id: UUID(), command: "add", text: "parallel \(index)"))
                    }
                }
            }
            print(store.notes.count)
            return
        }
        if arguments.first == "unsaved" {
            let id = store.createNote(showWindow: false)!
            chmod(path, 0o500)
            defer { chmod(path, 0o700) }
            store.updateText(id, "unsaved text")
            precondition(store.hasUnsavedChanges)
            let result = try store.executeCommand(.init(id: UUID(), command: "list"))
            precondition(result.notes.first?.text == "unsaved text")
            do {
                _ = try store.executeCommand(.init(id: UUID(), command: "add", text: "blocked"))
                fatalError("Unsaved content was ignored")
            } catch { print("PASS: live read and mutation refusal preserve unsaved content") }
            return
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let request = try JSONDecoder().decode(SerializedNoteCommands.Request.self, from: input)
        if arguments.first == "sync" {
            let note = store.notes.first!
            try store.applySync(SyncValue(content: NoteContent(id: note.id, text: request.text!, color: note.color)))
            return
        }
        var rejections = 0
        var observation: AnyCancellable?
        if arguments.first == "reentrant" {
            observation = store.objectWillChange.sink {
                do {
                    _ = try store.executeCommand(.init(id: UUID(), command: "add", text: "nested"))
                    fatalError("Reentrant mutation succeeded")
                } catch { rejections += 1 }
                store.updateText(store.notes.first?.id ?? UUID(), "nested edit")
            }
        }
        do {
            let result = try store.executeCommand(request) { stage in
                if arguments == ["crash", stage.rawValue] { _exit(91) }
                if arguments == ["freeze", stage.rawValue] { throw CocoaError(.fileWriteUnknown) }
            }
            if arguments.first == "reentrant" {
                precondition(rejections > 0)
                withExtendedLifetime(observation) {}
            }
            print(String(decoding: try SerializedNoteCommands.encoded(result), as: UTF8.self))
        } catch {
            if arguments.first == "freeze" {
                let before = try SerializedNoteCommands.encoded(store.notes)
                if let id = store.notes.first?.id {
                    store.updateText(id, "must not overwrite")
                    store.setColor(id, 3)
                    store.hide(id)
                    store.moved(id, frame: .zero)
                }
                precondition(store.createNote(showWindow: false) == nil)
                precondition(store.commandRecoveryRequired && !store.contentEditingAllowed)
                precondition(!store.hasUnsavedChanges && store.flushPendingChanges())
                let after = try SerializedNoteCommands.encoded(store.notes)
                precondition(after == before)
                print("PASS: pending recovery freezes later edits and permits normal exit")
                return
            }
            fputs("\(error)\n", stderr)
            exit(74)
        }
    }
}
