import AppKit
import SwiftUI

@main
struct StickiesApp: App {
    @NSApplicationDelegateAdaptor(StickiesDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Stickies", systemImage: "note.text") {
            Button("New Note") { NoteStore.shared.createNote() }
                .keyboardShortcut("n")
            Button("Show All Notes") { NoteStore.shared.showAll() }
            Divider()
            Button("Arrange Grid") { NoteStore.shared.arrange(.grid) }
            Button("Arrange List") { NoteStore.shared.arrange(.list) }
            Divider()
            Button("Quit Stickies") { NSApplication.shared.terminate(nil) }
        }
    }
}

final class StickiesDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in NoteStore.shared.restoreWindows() }
    }
}
