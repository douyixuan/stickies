import CoreGraphics
import Foundation

enum Arrangement: String, Codable {
    case free, grid, list, compact
}

/// Pure geometry. No windows, no screens API, no persistence: callers pass the usable areas in.
enum LayoutEngine {
    /// Keep the whole window reachable, including after a display is disconnected.
    static func constrain(_ frame: CGRect, to bounds: CGRect, minimumHeight: CGFloat = StickyNote.minimumHeight) -> CGRect {
        let width = min(max(frame.width, StickyNote.minimumWidth), bounds.width)
        let height = min(max(frame.height, minimumHeight), bounds.height)
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    /// Pull a frame back onto the display it overlaps most. An unknown layout is left alone.
    static func restore(_ frame: CGRect, screens: [CGRect], minimumHeight: CGFloat = StickyNote.minimumHeight) -> CGRect {
        guard let bounds = screens.max(by: { area(frame.intersection($0)) < area(frame.intersection($1)) }) else {
            return frame
        }
        return constrain(frame, to: bounds, minimumHeight: minimumHeight)
    }

    /// Snap translations only, within the current display's usable area. Never resize or teleport.
    static func snapToScreenEdges(_ frame: CGRect, screens: [CGRect], threshold: CGFloat = 12) -> CGRect {
        guard isUsable(frame), threshold.isFinite, threshold >= 0 else { return frame }
        let candidates = screens.filter { isUsable($0) && area(frame.intersection($0)) > 0 }.sorted {
            let a = area(frame.intersection($0)), b = area(frame.intersection($1))
            if a != b { return a > b }
            if $0.minX != $1.minX { return $0.minX < $1.minX }
            return $0.minY < $1.minY
        }
        guard let bounds = candidates.first, frame.width <= bounds.width, frame.height <= bounds.height else {
            return frame
        }
        var result = frame
        result.origin.x = snap(frame.minX, to: [bounds.minX, bounds.maxX - frame.width], threshold: threshold)
        result.origin.y = snap(frame.minY, to: [bounds.minY, bounds.maxY - frame.height], threshold: threshold)
        return bounds.contains(result) ? result : frame
    }

    /// Frames for `count` notes, in reading order, inside `bounds`.
    static func arrange(count: Int, in bounds: CGRect, strategy: Arrangement) -> [CGRect] {
        guard strategy != .free, count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let gap: CGFloat = 16
        let collapsed = strategy == .compact
        let minimumHeight = collapsed ? LayoutState.collapsedHeight : StickyNote.minimumHeight
        let width = min(StickyNote.defaultSize.width, bounds.width)
        let height = min(collapsed ? LayoutState.collapsedHeight : StickyNote.defaultSize.height, bounds.height)
        let columns = strategy == .list ? 1 : max(1, Int((bounds.width - gap) / (width + gap)))
        let rows = max(1, Int((bounds.height - gap) / (height + gap)))
        let capacity = columns * rows
        return (0..<count).map { index in
            // Overflow starts a new overlapping page instead of leaving the display.
            let slot = index % capacity
            let offset = CGFloat((index / capacity) % 6) * 12
            let frame = CGRect(x: bounds.minX + gap + CGFloat(slot % columns) * (width + gap) + offset,
                               y: bounds.maxY - gap - height - CGFloat(slot / columns) * (height + gap) - offset,
                               width: width, height: height)
            return constrain(frame, to: bounds, minimumHeight: minimumHeight)
        }
    }

    private static func snap(_ value: CGFloat, to edges: [CGFloat], threshold: CGFloat) -> CGFloat {
        guard let edge = edges.min(by: { abs($0 - value) < abs($1 - value) }), abs(edge - value) <= threshold else {
            return value
        }
        return edge
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
