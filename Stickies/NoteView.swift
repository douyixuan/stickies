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
            .font(.system(size: 15))
            .foregroundStyle(.black)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(nsColor: NotePalette.color(note.color)))
            .overlay(alignment: .bottom) {
                if let error = store.persistenceError ?? store.layoutError ?? store.preferenceError {
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
            Menu {
                ForEach(0..<NotePalette.colors.count, id: \.self) { index in
                    Button("Color \(index + 1)") { store.setColor(noteID, index) }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .accessibilityLabel("Note colors")
            .help("Note colors")
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
