import AppKit

@main
struct WindowModeTests {
    @MainActor static func main() throws {
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] else { fatalError("isolated directory required") }
        let directory = URL(fileURLWithPath: path)
        let notesURL = directory.appendingPathComponent("notes.json")
        let preferencesURL = directory.appendingPathComponent("preferences.json")
        let phase = CommandLine.arguments.dropFirst().first ?? "setup"
        if phase != "restore" {
            try Data("""
            [{"id":"00000000-0000-0000-0000-000000000001","text":"unchanged","color":2,"frame":[[120,180],[260,220]],"visible":false}]
            """.utf8).write(to: notesURL)
        }
        if phase == "setup" { try Data("{\"keepOnTop\":true}".utf8).write(to: preferencesURL) }
        if phase == "corrupt" { try Data("invalid preferences".utf8).write(to: preferencesURL) }
        let store = NoteStore.shared
        let baseline = try Data(contentsOf: notesURL)
        precondition(NoteWindowMode.desktop.level.rawValue < NSWindow.Level.normal.rawValue)
        precondition(NoteWindowMode.desktop.level.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow)))
        precondition(NoteWindowMode.floating.level == .floating)
        precondition(NoteWindowMode.desktop.collectionBehavior.contains(.canJoinAllSpaces))
        precondition(NoteWindowMode.desktop.collectionBehavior.contains(.stationary))
        precondition(!NoteWindowMode.standard.collectionBehavior.contains(.canJoinAllSpaces))
        if phase == "setup" {
            precondition(store.windowMode == .floating && store.keepOnTop)
            store.setWindowMode(.desktop)
            precondition(store.windowMode == .desktop && !store.keepOnTop)
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: preferencesURL)) as! [String: Any]
            precondition(saved["windowMode"] as? String == "desktop")
            precondition(saved["keepOnTop"] as? Bool == false)
        } else if phase == "restore" {
            precondition(store.windowMode == .desktop && !store.keepOnTop)
            store.setKeepOnTop(true)
            precondition(store.windowMode == .floating && store.keepOnTop)
            store.setKeepOnTop(false)
            precondition(store.windowMode == .standard && !store.keepOnTop)
        } else if phase == "corrupt" {
            precondition(store.preferenceError != nil)
            store.setWindowMode(.desktop)
            precondition(store.windowMode == .standard)
            let preserved = try Data(contentsOf: preferencesURL)
            precondition(preserved == Data("invalid preferences".utf8))
        } else if phase == "failure" {
            try FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: false)
            store.setWindowMode(.desktop)
            precondition(store.preferenceError != nil && store.windowMode == .standard)
        }
        let after = try Data(contentsOf: notesURL)
        precondition(after == baseline, "Window mode must not rewrite note content/frame/visibility")
        print("PASS: window mode \(phase), local preference/levels without opening windows")
    }
}
