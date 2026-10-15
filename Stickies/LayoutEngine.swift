import CoreGraphics
import Foundation

enum Arrangement: String, Codable {
    case free, grid, list, compact
}

enum LayoutEngine {
    /// Keep the whole window accessible, including after a display is disconnected.
    static func constrain(_ frame: CGRect, to bounds: CGRect, minimumHeight: CGFloat = 120) -> CGRect {
        let width = min(max(frame.width, 180), bounds.width)
        let height = min(max(frame.height, minimumHeight), bounds.height)
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    static func restore(_ frame: CGRect, screens: [CGRect], minimumHeight: CGFloat = 120) -> CGRect {
        guard let bounds = screens.max(by: { area(frame.intersection($0)) < area(frame.intersection($1)) }) else {
            return frame
        }
        return constrain(frame, to: bounds, minimumHeight: minimumHeight)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    static func arrange(count: Int, in bounds: CGRect, strategy: Arrangement) -> [CGRect] {
        guard strategy != .free, count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let gap: CGFloat = 16
        let width = min(260, bounds.width)
        let height = min(strategy == .compact ? NoteLayoutState.collapsedHeight : 220, bounds.height)
        let columns = strategy != .list ? max(1, Int((bounds.width - gap) / (width + gap))) : 1
        let rows = max(1, Int((bounds.height - gap) / (height + gap)))
        let capacity = columns * rows
        return (0..<count).map { index in
            // Overflow starts a new overlapping page instead of leaving the display.
            let slot = index % capacity
            let offset = CGFloat((index / capacity) % 6) * 12
            let frame = CGRect(x: bounds.minX + gap + CGFloat(slot % columns) * (width + gap) + offset,
                               y: bounds.maxY - gap - height - CGFloat(slot / columns) * (height + gap) - offset,
                               width: width, height: height)
            return constrain(frame, to: bounds, minimumHeight: strategy == .compact ? NoteLayoutState.collapsedHeight : 120)
        }
    }
}


/// Device-only presentation, deliberately outside note content and its persistence schema.
struct NoteLayoutState: Codable {
    static let collapsedHeight: CGFloat = 32
    var schemaVersion = 1
    var collapsed: Set<UUID> = []
    var arrangement: Arrangement = .free
    var snapshot: Snapshot?

    struct Entry: Codable {
        var id: UUID
        var frame: CGRect
        var collapsed: Bool
    }
    struct Snapshot: Codable {
        var entries: [Entry]
        var arrangement: Arrangement
    }

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
        guard schemaVersion == 1 else { throw ValidationError.invalid }
        if let entries = snapshot?.entries {
            guard Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ entry in
                      let f = entry.frame
                      return [f.origin.x, f.origin.y, f.width, f.height].allSatisfy { $0.isFinite }
                          && f.width > 0 && f.height > 0
                  }) else { throw ValidationError.invalid }
        }
    }
    enum ValidationError: Error { case invalid }
}
