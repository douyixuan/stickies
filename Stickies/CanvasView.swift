import AppKit
import SwiftUI

/// A single, ordinary window for every note, including hidden notes.
@MainActor
final class CanvasWindowController: ObservableObject {
    @Published private(set) var newNoteRequest = UUID()
    static let shared = CanvasWindowController()
    private var window: NSWindow?

    func createNote() {
        if window?.isKeyWindow == true {
            newNoteRequest = UUID()
        } else {
            NoteStore.shared.createNote()
        }
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "iStickies2 — Manage Notes"
        window.minSize = NSSize(width: 620, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CanvasView())
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

struct CanvasView: View {
    @ObservedObject private var store = NoteStore.shared
    @ObservedObject private var controller = CanvasWindowController.shared
    @State private var query = ""
    @State private var showBoard = false
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    private var results: [StickyNote] {
        store.activeNotes.filter { CanvasQuery.matches($0.text, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Browse", selection: $showBoard) {
                    Text("List").tag(false)
                    Text("Board").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                .accessibilityLabel("View mode")
                Button {
                    query = ""
                    selection = store.createNote(showWindow: false)
                } label: {
                    Label("New Note", systemImage: "plus")
                }
                Spacer(minLength: 8)
                Button("Settings…") { CloudSyncController.shared.show() }
                    .fixedSize()
            }
            .padding(.horizontal, 12).padding(.top, 12)
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search all notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel("Search all notes")
                Menu("Window Layout") {
                    WindowModeCommands()
                    Divider()
                    ArrangementCommands()
                }
                Button("Search") { searchFocused = true }
                    .keyboardShortcut("f")
            }
            .padding(12)
            Text("Manage notes without moving their independent windows.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 8)
            if let error = store.commandServiceError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).accessibilityLabel(error)
            }
            if let error = store.trashError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(results.count) of \(store.activeNotes.count) notes")
                        .font(.caption).foregroundStyle(.secondary).padding(12)
                    if results.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No Notes" : "No Matching Notes",
                                               systemImage: "note.text",
                                               description: Text(query.isEmpty ? "Create a note to get started." : "Try different search words."))
                    } else if showBoard {
                        CanvasBoardView(selection: $selection, query: query)
                    } else {
                        List(selection: $selection) {
                            ForEach(results) { note in
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(nsColor: NotePalette.color(note.color)))
                                        .frame(width: 10, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(CanvasQuery.title(note.text)).font(.headline).lineLimit(1)
                                        Text(note.text.isEmpty ? "Empty note" : note.text)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text(note.visible ? "Window shown" : "Window hidden")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .tag(note.id)
                            }
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: showBoard ? 600 : 280, maxWidth: showBoard ? .infinity : 380)
                if let selection, !store.isTrashed(selection), let note = store.note(selection) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(CanvasQuery.title(note.text)).font(.headline).lineLimit(1)
                            Spacer()
                            Menu("Color: \(NotePalette.name(note.color))") {
                                NoteColorOptions(noteID: selection)
                            }
                            .accessibilityLabel("Note color")
                            .accessibilityValue(NotePalette.name(note.color))
                            .help("Note color: \(NotePalette.name(note.color))")
                            Button(note.visible ? "Hide Window" : "Show Window") {
                                if note.visible { store.hide(selection) } else { store.show(selection) }
                            }
                        }
                        .padding(12)
                        if !CanvasQuery.matches(note.text, query: query) {
                            Text("This note no longer matches your search. You can continue editing.")
                                .font(.caption).foregroundStyle(.secondary).padding(8)
                        }
                        Divider()
                        NoteView(noteID: selection).id(selection)
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Select a Note", systemImage: "note.text",
                                           description: Text("Browse and edit all your notes here, including hidden notes."))
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: controller.newNoteRequest) { _, _ in
            query = ""
            selection = store.createNote(showWindow: false)
        }
        .onChange(of: store.activeNotes.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .onChange(of: query) { _, _ in
            if let selection, !results.contains(where: { $0.id == selection }) { self.selection = nil }
        }
    }
}
