import AppKit
import SwiftUI

/// One place that owns the store and the windows, so views and menus share both.
final class AppServices {
    static let shared = AppServices()
    let store: NoteStore
    let windows: NoteWindowManager

    private init() {
        store = NoteStore(directory: NoteDataLocation.current)
        windows = NoteWindowManager(store: store)
    }
}

@main
struct StickiesApp: App {
    @ObservedObject private var store = AppServices.shared.store
    @NSApplicationDelegateAdaptor(StickiesDelegate.self) private var delegate

    private var windows: NoteWindowManager { AppServices.shared.windows }

    var body: some Scene {
        MenuBarExtra("iStickies2", systemImage: "note.text") {
            menuContents.environmentObject(store)
        }
        .commands {
            CommandMenu("Notes") {
                menuContents.environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private var menuContents: some View {
        Group {
            Button("New Note") { windows.createNote() }
                .keyboardShortcut("n")
            Button("Show All Notes") { windows.showAll() }
            Button("Hide All Notes") { windows.hideAll() }
            TrashMenu()
        }
        Divider()
        ArrangementMenu()
        Divider()
        WindowModeMenu()
        if let message = store.readOnlyReason ?? store.lastError {
            Divider()
            Text(message)
        }
        Divider()
        Button("Quit iStickies2") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class StickiesDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices { AppServices.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        services.windows.restoreWindows()
    }

    /// A failed save must not silently discard what is in memory.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if services.store.flushPendingChanges() { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some note changes have not been saved"
        alert.informativeText = "Keep editing to preserve the changes in memory, or quit and lose them. "
            + (services.store.lastError ?? "")
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)
        services.windows.showAll()
        return true
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        services.windows.recoverDisplayLayout()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        services.windows.refreshActivation(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        services.windows.refreshActivation(false)
    }
}
