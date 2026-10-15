import Foundation

/// Search is read-only: opening Canvas never changes note visibility or geometry.
enum CanvasQuery {
    static func matches(_ text: String, query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        return terms.allSatisfy { text.localizedStandardContains(String($0)) }
    }

    static func title(_ text: String) -> String {
        let line = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? "New Note" : String(line.prefix(80))
    }
}
