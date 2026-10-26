import SwiftUI

/// The editable body of one note.
struct NoteBodyView: View {
    let noteID: UUID
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        if let note = store.note(noteID) {
            TextEditor(text: Binding(
                get: { store.note(noteID)?.text ?? "" },
                set: {
                    store.setText(noteID, $0)
                    AppServices.shared.windows.refreshTitle(noteID)
                }
            ))
            .disabled(!store.isWritable)
            .font(.system(size: 15))
            .foregroundStyle(.black)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(nsColor: NotePalette.color(note.color)))
            .contextMenu { SingleNoteMenu(noteID: noteID) }
            .overlay(alignment: .bottom) {
                if let message = store.readOnlyReason ?? store.lastError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.regularMaterial)
                }
            }
        }
    }
}

/// Note actions live in the native title bar; no extra toolbar covers the text.
struct NoteHeaderView: View {
    let noteID: UUID
    @EnvironmentObject private var store: NoteStore
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("New Note") { AppServices.shared.windows.createNote() }
            Button("Hide This Note") { AppServices.shared.windows.hide(noteID) }
            Button(store.isCollapsed(noteID) ? "Expand Note" : "Collapse Note") {
                AppServices.shared.windows.toggleCollapse(noteID)
            }
            Divider()
            SingleNoteMenu(noteID: noteID)
            Divider()
            ArrangementMenu()
            WindowModeMenu()
        } label: {
            Image(systemName: "note.text")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Note actions")
        .help("Note actions")
        .font(.system(size: 11))
        .foregroundStyle(.black.opacity(hovering ? 0.8 : 0.42))
        .frame(width: 28, height: 22)
        .onHover { hovering = $0 }
    }
}

/// Shared by the editor context menu and the title-bar actions menu.
struct SingleNoteMenu: View {
    let noteID: UUID
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        Menu("Note Color") { NoteColorPicker(noteID: noteID) }
            .disabled(!store.isWritable)
        Toggle("Keep This Note on Top", isOn: Binding(
            get: { store.windowMode(for: noteID) == .floating },
            set: {
                store.setNoteFloating(noteID, $0)
                AppServices.shared.windows.applyAllPresentations()
            }
        ))
        .disabled(!store.isWritable)
        if store.preferences.hasOverride(noteID) {
            Button("Use Global Window Default") {
                store.setNoteFloating(noteID, nil)
                AppServices.shared.windows.applyAllPresentations()
            }
            .disabled(!store.isWritable)
        }
        Divider()
        Button("Move to Trash on This Mac", role: .destructive) {
            AppServices.shared.windows.moveToTrash(noteID)
        }
        .disabled(!store.isWritable || store.isTrashed(noteID))
    }
}

struct NoteColorPicker: View {
    let noteID: UUID
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        Picker("Note color", selection: Binding(
            get: { NotePalette.normalizedIndex(store.note(noteID)?.color ?? 0) },
            set: {
                store.setColor(noteID, $0)
                AppServices.shared.windows.applyPresentation(noteID)
            }
        )) {
            ForEach(Array(NotePalette.swatches.indices), id: \.self) { index in
                Text(NotePalette.name(index)).tag(index)
            }
        }
        .pickerStyle(.inline)
        .accessibilityLabel("Note color")
    }
}

struct ArrangementMenu: View {
    @EnvironmentObject private var store: NoteStore
    private var windows: NoteWindowManager { AppServices.shared.windows }

    var body: some View {
        Button("Free Layout") { windows.arrange(.free) }
            .keyboardShortcut("0", modifiers: [.command, .option])
        Button("Arrange Grid") { windows.arrange(.grid) }
            .keyboardShortcut("1", modifiers: [.command, .option])
        Button("Arrange List") { windows.arrange(.list) }
            .keyboardShortcut("2", modifiers: [.command, .option])
        Button("Arrange Compact") { windows.arrange(.compact) }
            .keyboardShortcut("3", modifiers: [.command, .option])
        Button("Restore Previous Layout") { windows.restorePreviousLayout() }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!store.canRestorePreviousLayout)
        Button("Undo Last Layout") { windows.undoLayout() }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(!store.canUndoLayout)
        Toggle("Snap to Screen Edges", isOn: Binding(
            get: { store.preferences.snapToScreenEdges },
            set: { store.setSnapToScreenEdges($0) }
        ))
        .disabled(!store.isWritable)
        .help("On drag release, snap within 12 points of the display's usable edges. Resizing stays free.")
    }
}

struct WindowModeMenu: View {
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        Picker("Note Window Layer", selection: Binding(
            get: { store.preferences.windowMode },
            set: {
                store.setWindowMode($0)
                AppServices.shared.windows.applyAllPresentations()
            }
        )) {
            ForEach(NoteWindowMode.allCases, id: \.self) { mode in
                Text(mode.menuTitle).tag(mode)
            }
        }
        .disabled(!store.isWritable)
    }
}

struct TrashMenu: View {
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        Menu("Restore from Trash on This Mac") {
            if store.trashedNotes.isEmpty {
                Text("Trash is Empty")
            }
            ForEach(store.trashedNotes) { note in
                Button(note.title) { AppServices.shared.windows.restoreFromTrash(note.id) }
                    .disabled(!store.isWritable)
            }
        }
    }
}
