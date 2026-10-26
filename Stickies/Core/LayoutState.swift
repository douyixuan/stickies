import CoreGraphics
import Foundation

/// Device-only presentation, deliberately separate from note content.
/// On disk in `layout.json`; the schema is unchanged from version 0.3.
struct LayoutState: Codable, Equatable {
    static let collapsedHeight: CGFloat = 32

    var schemaVersion = 1
    var collapsed: Set<UUID> = []
    var arrangement: Arrangement = .free
    /// The frames an arrangement replaced, so "Restore Previous Layout" survives a relaunch.
    var snapshot: Snapshot?

    struct Entry: Codable, Equatable {
        var id: UUID
        var frame: CGRect
        var collapsed: Bool
    }

    struct Snapshot: Codable, Equatable {
        var entries: [Entry]
        var arrangement: Arrangement
    }

    /// A folded note shows only its title bar; its expanded height is remembered in the note.
    func renderedFrame(id: UUID, expanded: CGRect) -> CGRect {
        guard collapsed.contains(id) else { return expanded }
        return CGRect(x: expanded.minX, y: expanded.maxY - Self.collapsedHeight,
                      width: expanded.width, height: Self.collapsedHeight)
    }

    func expandedFrame(id: UUID, rendered: CGRect, previous: CGRect) -> CGRect {
        guard collapsed.contains(id) else { return rendered }
        return CGRect(x: rendered.minX, y: rendered.maxY - previous.height,
                      width: rendered.width, height: previous.height)
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw NoteFile.Failure.unsupportedVersion }
        guard let entries = snapshot?.entries else { return }
        guard Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ isUsable($0.frame) }) else { throw NoteFile.Failure.corrupt }
    }

    private func isUsable(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    }
}
