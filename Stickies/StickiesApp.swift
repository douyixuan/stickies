import AppKit
import SwiftUI

@main
struct StickiesApp: App {
    @ObservedObject private var store = NoteStore.shared
    @NSApplicationDelegateAdaptor(StickiesDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("iStickies2", systemImage: "note.text") {
            Button("New Note") { CanvasWindowController.shared.createNote() }
                .keyboardShortcut("n")
            AppNavigationCommands()
            Button("Show All Notes") { NoteStore.shared.showAll() }
            Button("Hide All Notes") { store.hideAll() }
            WindowModeCommands()
            Divider()
            ArrangementCommands()
            Divider()
            Button("Quit iStickies2") { NSApplication.shared.terminate(nil) }
        }
        .commands {
            CommandMenu("Notes") {
                Button("New Note") { CanvasWindowController.shared.createNote() }.keyboardShortcut("n")
                AppNavigationCommands()
                Button("Show All Notes") { store.showAll() }
                Button("Hide All Notes") { store.hideAll() }
                Divider()
                ArrangementCommands()
                WindowModeCommands()
            }
        }
    }
}

final class StickiesDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if CloudSyncController.shared.coordinator.pendingDisable {
            CloudSyncController.shared.show()
            return .terminateCancel
        }
        if NoteStore.shared.flushPendingChanges() { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some note changes have not been saved"
        alert.informativeText = "Keep editing to preserve the changes in memory, or explicitly discard them by quitting. " + (NoteStore.shared.persistenceError ?? "")
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
            NoteStore.shared.showAll()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in NoteStore.shared.restoreWindows(); CloudSyncController.shared.start() }
    }
}
