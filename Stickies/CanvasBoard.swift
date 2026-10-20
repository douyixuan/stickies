import Foundation
import SwiftUI

struct CanvasBoardState: Codable {
    var schemaVersion = 1
    var frames: [UUID: CGRect] = [:]
    var arrangement: Arrangement = .free
    var snapshot: Snapshot?
    struct Snapshot: Codable {
        var frames: [UUID: CGRect]
        var arrangement: Arrangement
    }
    static func frames(for ids: [UUID], strategy: Arrangement, columns: Int) -> [UUID: CGRect] {
        var seen = Set<UUID>()
        let ids = ids.filter { seen.insert($0).inserted }
        let columns = strategy == .list ? 1 : max(1, columns)
        let size = CGSize(width: strategy == .list ? 360 : 240,
                          height: strategy == .compact ? 54 : (strategy == .list ? 90 : 170))
        return Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: 12 + CGFloat(index % columns) * (size.width + 16),
                        y: 12 + CGFloat(index / columns) * (size.height + 16),
                        width: size.width, height: size.height))
        })
    }
    func validate() throws {
        guard schemaVersion == 1 else { throw InvalidState.invalid }
        for frame in Array(frames.values) + Array(snapshot?.frames.values ?? [:].values) {
            guard [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy({ $0.isFinite }),
                  frame.minX >= 0, frame.minY >= 0, frame.maxX <= 100_000, frame.maxY <= 100_000,
                  (180...600).contains(frame.width), (54...400).contains(frame.height) else {
                throw InvalidState.invalid
            }
        }
    }
    enum InvalidState: Error { case invalid }
}

@MainActor
final class CanvasBoardStore: ObservableObject {
    @Published private(set) var state = CanvasBoardState()
    @Published private(set) var error: String?
    private let notes: NoteStore
    private let url: URL
    private var validFile = true
    var writable: Bool { notes.localStateWritable && validFile }

    init(notes: NoteStore) {
        self.notes = notes
        url = notes.localDataDirectory.appendingPathComponent("canvas-layout.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(CanvasBoardState.self, from: Data(contentsOf: url))
            try loaded.validate()
            state = loaded
        } catch {
            validFile = false
            self.error = "Could not read Canvas layout. Original file preserved; arrangement is disabled."
        }
    }
    @discardableResult
    private func commit(_ next: CanvasBoardState) -> Bool {
        guard writable else { return false }
        do {
            try next.validate()
            // Before-image and resulting positions commit together in one local atomic file.
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            state = next
            error = nil
            return true
        } catch {
            self.error = "Canvas layout could not be saved. Previous positions are unchanged."
            return false
        }
    }
    func ensureEntries(_ ids: [UUID]) {
        var next = state
        for id in ids where next.frames[id] == nil {
            var slot = 0
            var frame: CGRect
            repeat {
                frame = CGRect(x: 12 + (slot % 3) * 256, y: 12 + (slot / 3) * 186, width: 240, height: 170)
                slot += 1
            } while next.frames.values.contains(where: { $0.intersects(frame) })
            next.frames[id] = frame
        }
        if next.frames != state.frames { commit(next) }
    }
    func arrange(_ strategy: Arrangement, ids: [UUID], columns: Int) {
        guard !ids.isEmpty else { return }
        var next = state
        if strategy != .free {
            let defaults = CanvasBoardState.frames(for: ids, strategy: .grid, columns: columns)
            next.frames.merge(defaults) { existing, _ in existing }
            next.snapshot = CanvasBoardState.Snapshot(frames: next.frames, arrangement: state.arrangement)
            let frames = CanvasBoardState.frames(for: ids, strategy: strategy, columns: columns)
            next.frames.merge(frames) { _, new in new }
        }
        next.arrangement = strategy
        commit(next)
    }
    func move(_ id: UUID, to origin: CGPoint) {
        guard var frame = state.frames[id], origin.x.isFinite, origin.y.isFinite else { return }
        frame.origin = CGPoint(x: min(99_000, max(0, origin.x)), y: min(99_000, max(0, origin.y)))
        var next = state
        next.frames[id] = frame
        next.arrangement = .free
        commit(next)
    }
    func restore() {
        guard let snapshot = state.snapshot else { return }
        var next = state
        next.frames.merge(snapshot.frames) { _, old in old }
        next.arrangement = snapshot.arrangement
        commit(next)
    }
}

struct CanvasBoardView: View {
    @Binding var selection: UUID?
    let query: String
    @ObservedObject private var notes = NoteStore.shared
    @StateObject private var board = CanvasBoardStore(notes: .shared)
    private var filtered: [StickyNote] { notes.activeNotes.filter { CanvasQuery.matches($0.text, query: query) } }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - 24) / 256))
            let fallback = CanvasBoardState.frames(for: filtered.map(\.id), strategy: .grid, columns: columns)
            let frames = searching ? fallback : board.state.frames.merging(fallback) { old, _ in old }
            VStack(spacing: 8) {
                HStack {
                    Menu("Arrange Board") {
                        Button("Free") { board.arrange(.free, ids: notes.activeNotes.map(\.id), columns: columns) }
                        Button("Grid") { board.arrange(.grid, ids: notes.activeNotes.map(\.id), columns: columns) }
                        Button("List") { board.arrange(.list, ids: notes.activeNotes.map(\.id), columns: columns) }
                        Button("Compact") { board.arrange(.compact, ids: notes.activeNotes.map(\.id), columns: columns) }
                        Button("Restore Board") { board.restore() }.disabled(board.state.snapshot == nil)
                    }
                    .disabled(searching || !board.writable)
                    Spacer()
                }.padding(.horizontal, 12)
                if searching {
                    Text("Search results — clear search to drag or arrange the board.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
                if let error = board.error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 12) }
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        ForEach(filtered) { note in
                            if let frame = frames[note.id] {
                                CanvasCard(note: note, selected: selection == note.id,
                                           movable: !searching && board.writable, frame: frame,
                                           select: { selection = note.id },
                                           move: { board.move(note.id, to: $0) })
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(width: max(geometry.size.width - 2, (frames.values.map(\.maxX).max() ?? 0) + 12),
                           height: max(200, (frames.values.map(\.maxY).max() ?? 0) + 12), alignment: .topLeading)
                }
            }
        }
        .onAppear { if !searching { board.ensureEntries(notes.activeNotes.map(\.id)) } }
        .onChange(of: notes.activeNotes.map(\.id)) { _, ids in if !searching { board.ensureEntries(ids) } }
        .onChange(of: searching) { _, active in
            if !active { board.ensureEntries(notes.activeNotes.map(\.id)) }
        }
    }
}

private struct CanvasCard: View {
    let note: StickyNote
    let selected: Bool
    let movable: Bool
    let frame: CGRect
    let select: () -> Void
    let move: (CGPoint) -> Void
    @GestureState private var translation: CGSize = .zero
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(CanvasQuery.title(note.text)).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if !note.visible { Image(systemName: "eye.slash").font(.caption) }
            }
            if frame.height > 60 {
                Text(note.text.isEmpty ? "Empty note" : note.text)
                    .font(.system(size: 13)).lineLimit(frame.height > 100 ? 6 : 2)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(Color(nsColor: NotePalette.color(note.color)), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .black.opacity(0.12), lineWidth: selected ? 3 : 1))
        .contentShape(Rectangle())
        .offset(movable ? translation : .zero)
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { select() }
        .gesture(DragGesture(minimumDistance: 5)
            .updating($translation) { value, state, _ in if movable { state = value.translation } }
            .onEnded { value in
                guard movable else { return }
                select()
                move(CGPoint(x: frame.minX + value.translation.width, y: frame.minY + value.translation.height))
            })
    }
}
