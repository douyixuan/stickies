import CoreGraphics

enum Arrangement {
    case grid, list
}

enum LayoutEngine {
    /// Keep the whole window accessible, including after a display is disconnected.
    static func constrain(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(max(frame.width, 180), bounds.width)
        let height = min(max(frame.height, 120), bounds.height)
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    static func restore(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let bounds = screens.max(by: { area(frame.intersection($0)) < area(frame.intersection($1)) }) else {
            return frame
        }
        return constrain(frame, to: bounds)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    static func arrange(count: Int, in bounds: CGRect, strategy: Arrangement) -> [CGRect] {
        guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let gap: CGFloat = 16
        let width = min(260, bounds.width)
        let height = min(220, bounds.height)
        let columns = strategy == .grid ? max(1, Int((bounds.width - gap) / (width + gap))) : 1
        let rows = max(1, Int((bounds.height - gap) / (height + gap)))
        let capacity = columns * rows
        return (0..<count).map { index in
            // Overflow starts a new overlapping page instead of leaving the display.
            let slot = index % capacity
            let offset = CGFloat((index / capacity) % 6) * 12
            let frame = CGRect(x: bounds.minX + gap + CGFloat(slot % columns) * (width + gap) + offset,
                               y: bounds.maxY - gap - height - CGFloat(slot / columns) * (height + gap) - offset,
                               width: width, height: height)
            return constrain(frame, to: bounds)
        }
    }
}
