import CoreGraphics
import Foundation

/// A note's content and its position on this Mac. One value, one file, no schema fan-out.
struct StickyNote: Codable, Identifiable, Equatable {
    static let defaultSize = CGSize(width: 260, height: 220)
    static let minimumWidth: CGFloat = 180
    static let minimumHeight: CGFloat = 120

    var id = UUID()
    var text = ""
    var color = 0
    var frame = CGRect(x: 120, y: 180, width: defaultSize.width, height: defaultSize.height)
    var visible = true

    /// First non-empty line; used as the window title and in menus.
    var title: String {
        let first = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "New Note" : String(trimmed.prefix(80))
    }

    /// All whitespace-separated terms must appear, ignoring case and accents.
    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        return terms.allSatisfy { text.localizedStandardContains(String($0)) }
    }
}
