import Foundation
import Darwin

@main struct CommandChannelHost {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("Isolated host startup failed: \(error)\n", stderr); exit(74) }
    }
    @MainActor static func run() async throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"], path.contains("istk-channel-") else { exit(64) }
        let store = NoteStore.shared
        guard store.syncStorageOwned else { exit(75) }
        let mode = CommandLine.arguments.dropFirst().first ?? "normal"
        var server: LocalCommandServer?
        if mode == "normal" {
            try store.startCommandService()
        } else {
            server = try LocalCommandServer(directory: store.localDataDirectory) { request in
                if mode == "delay" { Thread.sleep(forTimeInterval: 6) }
                return try store.executeCommand(request) { stage in
                    if mode == "crash-" + stage.rawValue { _exit(91) }
                }
            }
        }
        print("ready"); fflush(stdout)
        _ = await Task.detached { readLine() }.value
        server?.stop()
        store.stopCommandService()
        print("stopped"); fflush(stdout)
    }
}
