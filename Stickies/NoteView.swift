import SwiftUI

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NoteStore.shared

    var body: some View {
        if let note = store.note(noteID) {
            TextEditor(text: Binding(
                get: { store.note(noteID)?.text ?? "" },
                set: { store.updateText(noteID, $0) }
            ))
            .disabled(!store.contentEditingAllowed)
            .font(.system(size: 15))
            .foregroundStyle(.black)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(nsColor: NotePalette.color(note.color)))
            .contextMenu { SingleNoteCommands(noteID: noteID) }
            .overlay(alignment: .bottom) {
                if let error = store.persistenceError ?? store.trashError ?? store.layoutError ?? store.preferenceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding(8).background(.regularMaterial)
                }
            }
        }
    }
}

/// Menus share the native title bar; no extra toolbar row covers the editor.
struct NoteHeaderControls: View {
    let noteID: UUID
    @ObservedObject private var store = NoteStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button("New Note") { store.createNote() }
                Button("Show All Notes") { store.showAll() }
                AppNavigationCommands()
                SingleNoteCommands(noteID: noteID)
                Button("Hide This Note") { store.hide(noteID) }
                Divider()
                Button(store.isCollapsed(noteID) ? "Expand Note" : "Collapse Note") { store.toggleCollapse(noteID) }
                ArrangementCommands()
                Divider()
                WindowModeCommands()
            } label: {
                Image(systemName: "note.text")
            }
            .accessibilityLabel("Note actions")
            .help("Note actions")
            Button { CloudSyncController.shared.show() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings and Sync")
            .help("Settings and Sync")
        }
        .contextMenu { SingleNoteCommands(noteID: noteID) }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 11))
        .foregroundStyle(.black.opacity(hovering ? 0.8 : 0.42))
        .frame(width: 52, height: 22)
        .onHover { hovering = $0 }
    }
}


/// Shared by the editor context menu and title-bar actions.
struct SingleNoteCommands: View {
    let noteID: UUID
    @ObservedObject private var store = NoteStore.shared
    var body: some View {
        Menu("Note Color") { NoteColorOptions(noteID: noteID) }
            .disabled(!store.contentEditingAllowed)
        Toggle("Keep This Note on Top", isOn: Binding(
            get: { store.effectiveWindowMode(noteID) == .floating },
            set: { store.setNoteFloating(noteID, $0) }
        ))
        .disabled(!store.localStateWritable)
        if store.hasWindowModeOverride(noteID) {
            Button("Use Global Window Default") { store.setNoteFloating(noteID, nil) }
                .disabled(!store.localStateWritable)
        }
        Divider()
        Button("Move to Trash on This Mac", role: .destructive) { store.moveToTrash(noteID) }
            .disabled(!store.localStateWritable || store.isTrashed(noteID))
    }
}

struct LocalTrashCommands: View {
    @ObservedObject private var store = NoteStore.shared
    var body: some View {
        Menu("Restore from Trash on This Mac") {
            if store.trashedNotes.isEmpty { Text("Trash is Empty") }
            ForEach(store.trashedNotes) { note in
                Button(note.text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "Untitled Note") {
                    store.restoreFromTrash(note.id)
                }
                .disabled(!store.localStateWritable)
            }
        }
        if let error = store.trashError { Text(error) }
    }
}


struct ArrangementCommands: View {
    @ObservedObject private var store = NoteStore.shared
    var body: some View {
        Button("Undo Last Layout") { store.undoLastLayout() }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(!store.canUndoLayout)
            .help("Undo the last window move, resize or arrangement in this session. Text is unchanged.")
        Button("Free Layout") { store.arrange(.free) }.keyboardShortcut("0", modifiers: [.command, .option])
        Button("Arrange Grid") { store.arrange(.grid) }.keyboardShortcut("1", modifiers: [.command, .option])
        Button("Arrange List") { store.arrange(.list) }.keyboardShortcut("2", modifiers: [.command, .option])
        Button("Arrange Compact") { store.arrange(.compact) }.keyboardShortcut("3", modifiers: [.command, .option])
        Button("Restore Previous Layout") { store.restoreLayout() }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!store.canRestoreLayout)
        if let error = store.layoutError { Text(error).font(.caption) }
    }
}


struct WindowModeCommands: View {
    @ObservedObject private var store = NoteStore.shared
    var body: some View {
        Picker("Default Note Window Mode", selection: Binding(get: { store.windowMode }, set: { store.setWindowMode($0) })) {
            Text("Ordinary Windows").tag(NoteWindowMode.standard)
            Text("Desktop — Behind Apps").tag(NoteWindowMode.desktop)
            Text("Floating — Keep on Top").tag(NoteWindowMode.floating)
        }
        if let error = store.preferenceError { Text(error).font(.caption) }
    }
}


/// Both menus use a native single-selection picker for checkmarks and selected semantics.
struct NoteColorOptions: View {
    let noteID: UUID
    @ObservedObject private var store = NoteStore.shared

    var body: some View {
        if let note = store.note(noteID) {
            Picker("Note color", selection: Binding(
                get: { NotePalette.normalizedIndex(store.note(noteID)?.color ?? note.color) },
                set: { store.setColor(noteID, $0) }
            )) {
                ForEach(NotePalette.colors.indices, id: \.self) { index in
                    Text(NotePalette.name(index))
                        .accessibilityLabel(NotePalette.name(index))
                        .accessibilityAddTraits(NotePalette.normalizedIndex(note.color) == index ? .isSelected : [])
                        .tag(index)
                }
            }
            .pickerStyle(.inline)
            .accessibilityLabel("Note color")
            .accessibilityValue(NotePalette.name(note.color))
        }
    }
}

/// Keep app-wide destinations available from notes and the status menu.
struct AppNavigationCommands: View {
    var body: some View {
        Button("Open Canvas") { CanvasWindowController.shared.show() }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        LocalTrashCommands()
        Button("Settings…") { CloudSyncController.shared.show() }
            .keyboardShortcut(",")
        Button("Sync Folder…") { CloudSyncController.shared.show() }
    }
}
