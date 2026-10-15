import AppKit
import SwiftUI

@main
struct StickiesApp: App {
    @ObservedObject private var store = NoteStore.shared
    @NSApplicationDelegateAdaptor(StickiesDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Stickies", systemImage: "note.text") {
            Button("New Note") { CanvasWindowController.shared.createNote() }
                .keyboardShortcut("n")
            Button("Open Canvas") { CanvasWindowController.shared.show() }.keyboardShortcut("0", modifiers: [.command, .shift])
            Button("Show All Notes") { NoteStore.shared.showAll() }
            Button("Hide All Notes") { store.hideAll() }
            Toggle("Keep Notes on Top", isOn: Binding(
                get: { store.keepOnTop }, set: { store.setKeepOnTop($0) }
            ))
            Divider()
            ArrangementCommands()
            Divider()
            Button("Quit Stickies") { NSApplication.shared.terminate(nil) }
        }
        .commands {
            CommandMenu("Notes") {
                Button("New Note") { CanvasWindowController.shared.createNote() }.keyboardShortcut("n")
                Button("Open Canvas") { CanvasWindowController.shared.show() }.keyboardShortcut("0", modifiers: [.command, .shift])
                Button("Show All Notes") { store.showAll() }
                Button("Hide All Notes") { store.hideAll() }
                Divider()
                ArrangementCommands()
                Toggle("Keep Notes on Top", isOn: Binding(
                    get: { store.keepOnTop }, set: { store.setKeepOnTop($0) }
                ))
            }
        }
    }
}

final class StickiesDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in NoteStore.shared.showAll() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in NoteStore.shared.restoreWindows() }
    }
}
