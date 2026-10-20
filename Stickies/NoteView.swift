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
                Menu("Note Color") { NoteColorOptions(noteID: noteID) }
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 11))
        .foregroundStyle(.black.opacity(hovering ? 0.8 : 0.42))
        .frame(width: 52, height: 22)
        .onHover { hovering = $0 }
    }
}


struct ArrangementCommands: View {
    @ObservedObject private var store = NoteStore.shared
    var body: some View {
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
        Picker("All Note Windows", selection: Binding(get: { store.windowMode }, set: { store.setWindowMode($0) })) {
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
        Button("Settings…") { CloudSyncController.shared.show() }
            .keyboardShortcut(",")
        Button("Sync Folder…") { CloudSyncController.shared.show() }
    }
}
