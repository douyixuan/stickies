import Foundation
import AppKit

@main
struct CanvasTests {
    // Legacy input fixture; intentionally independent of the UI projection's Codable conformance.
    struct Fixture: Codable {
        var id: UUID
        var text: String
        var color: Int
        var frame: CGRect
        var visible: Bool
    }
    @MainActor
    static func main() throws {
        // Names and selection must describe the same color even for legacy out-of-range indices.
        let expected: [(String, [CGFloat])] = [
            ("Pale Yellow", [1.0, 0.95, 0.67]), ("Light Blue", [0.79, 0.91, 1.0]),
            ("Lavender", [0.88, 0.83, 1.0]), ("Pale Green", [0.83, 0.94, 0.78])
        ]
        precondition(NotePalette.names.count == NotePalette.colors.count)
        for index in [Int.min, -5, -1, 0, 1, 2, 3, 4, 5, Int.max] {
            let selected = NotePalette.normalizedIndex(index)
            precondition((0..<4).contains(selected))
            precondition(NotePalette.name(index) == expected[selected].0)
            let color = NotePalette.color(index).usingColorSpace(.sRGB)!
            let components = [color.redComponent, color.greenComponent, color.blueComponent]
            precondition(zip(components, expected[selected].1).allSatisfy { abs($0 - $1) < 0.00001 })
        }
        precondition(NotePalette.normalizedIndex(-1) == 3 && NotePalette.normalizedIndex(4) == 0)
        // No NSApplication, NSWindow or user data: fixture must live in an explicit temp directory.
        guard let path = ProcessInfo.processInfo.environment["STICKIES_DATA_DIR"] else {
            fatalError("An isolated data directory is required")
        }
        let url = URL(fileURLWithPath: path).appendingPathComponent("notes.json")
        let fixture: [Fixture] = (0..<50).map { index -> Fixture in
            let frame = CGRect(x: CGFloat(index * 12), y: CGFloat(index * 7), width: 260, height: 220)
            return Fixture(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, text: "Note \(index)\nCafé 工作", color: index % 5,
                       frame: frame,
                       visible: index % 2 == 0)
        }
        if CommandLine.arguments.contains("--restore") {
            let saved = NoteStore.shared.notes
            precondition(saved.count == 51)
            for (before, after) in zip(fixture, saved) {
                precondition(before.id == after.id && before.text == after.text && before.color == after.color)
                precondition(before.frame == after.frame && before.visible == after.visible)
            }
            let created = saved.last!
            precondition(created.text == "Canvas edited\nSecond line")
            precondition(created.color == 2 && !created.visible)
            precondition(NoteStore.shared.persistenceError == nil)
            print("PASS: fresh-process restoration preserves all 50 original notes and hidden Canvas edit")
            return
        }
        try JSONEncoder().encode(fixture).write(to: url)
        let store = NoteStore.shared
        // Model migration, if present, may write during load; Canvas queries must not.
        let original = try Data(contentsOf: url)
        precondition(store.notes.count == 50)
        precondition(CanvasQuery.matches("Café 工作", query: "CAFE 工作"))
        precondition(CanvasQuery.matches("hello\nworld", query: "  world  hello\n"))
        precondition(!CanvasQuery.matches("hello", query: "hello missing"))
        precondition(CanvasQuery.matches("", query: "  \n"))
        precondition(CanvasQuery.title("\n\nTitle\nBody") == "Title")
        precondition(CanvasQuery.title("   ") == "New Note")
        precondition(CanvasQuery.title(String(repeating: "a", count: 120)).count == 80)
        let results = store.notes.filter { CanvasQuery.matches($0.text, query: "工作") }
        precondition(results.count == 50 && results.filter { !$0.visible }.count == 25)
        let afterBrowsing = try Data(contentsOf: url)
        precondition(afterBrowsing == original, "Browsing must not write notes")

        let id = store.createNote(showWindow: false)
        precondition(store.note(id)?.visible == false)
        precondition(store.note(id)?.text == "")
        store.updateText(id, "Canvas edited\nSecond line")
        store.setColor(id, 2)
        let saved = store.notes
        precondition(saved.count == 51)
        for (before, after) in zip(fixture, saved) {
            precondition(before.id == after.id && before.text == after.text && before.color == after.color)
            precondition(before.frame == after.frame && before.visible == after.visible)
        }
        let created = saved.last!
        precondition(created.id == id && created.text == "Canvas edited\nSecond line")
        precondition(created.color == 2 && !created.visible)
        precondition(store.persistenceError == nil)
        print("PASS: Canvas search, 50-note/hidden discovery, read-only browsing, isolated creation/edit/color persistence and unchanged existing frames/content")
    }
}
