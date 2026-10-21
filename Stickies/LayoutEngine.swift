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

    /// Snap translations only, within the current display's usable area. Never resize or teleport.
    static func snapToScreenEdges(_ frame: CGRect, screens: [CGRect], threshold: CGFloat = 12) -> CGRect {
        func valid(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
                && rect.width > 0 && rect.height > 0
        }
        guard valid(frame), threshold.isFinite, threshold >= 0 else { return frame }
        let candidates = screens.filter { valid($0) && area(frame.intersection($0)) > 0 }.sorted {
            let a = area(frame.intersection($0)), b = area(frame.intersection($1))
            if a != b { return a > b }
            if $0.minX != $1.minX { return $0.minX < $1.minX }
            return $0.minY < $1.minY
        }
        guard let bounds = candidates.first, frame.width <= bounds.width, frame.height <= bounds.height else { return frame }
        func snapped(_ value: CGFloat, to edges: [CGFloat]) -> CGFloat {
            guard let edge = edges.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(edge - value) <= threshold else { return value }
            return edge
        }
        var result = frame
        result.origin.x = snapped(frame.minX, to: [bounds.minX, bounds.maxX - frame.width])
        result.origin.y = snapped(frame.minY, to: [bounds.minY, bounds.maxY - frame.height])
        return bounds.contains(result) ? result : frame
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
