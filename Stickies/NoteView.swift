import SwiftUI

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NoteStore.shared

    private let colors: [Color] = [
        Color(red: 1.0, green: 0.95, blue: 0.67),
        Color(red: 0.79, green: 0.91, blue: 1.0),
        Color(red: 0.88, green: 0.83, blue: 1.0),
        Color(red: 0.83, green: 0.94, blue: 0.78)
    ]

    var body: some View {
        if let note = store.note(noteID) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "note.text")
                    Spacer()
                    Menu {
                        ForEach(0..<colors.count, id: \.self) { index in
                            Button("Color \(index + 1)") {
                                store.setColor(noteID, index)
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                    }
                    .menuStyle(.borderlessButton)
                }
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.top, 10)

                TextEditor(text: Binding(
                    get: { store.note(noteID)?.text ?? "" },
                    set: { store.updateText(noteID, $0) }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(8)
            }
            .background(colors[((note.color % colors.count) + colors.count) % colors.count])
            .overlay(alignment: .bottom) {
                if let error = store.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding(8).background(.regularMaterial)
                }
            }
        }
    }
}
