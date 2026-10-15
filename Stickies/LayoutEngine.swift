import CoreGraphics

enum LayoutEngine {
    static func arrange(count: Int, in bounds: CGRect, strategy: Arrangement) -> [CGRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 16
        let width: CGFloat = 260
        let height: CGFloat = 220
        let columns: Int
        switch strategy {
        case .grid:
            columns = max(1, Int((bounds.width + gap) / (width + gap)))
        case .list:
            columns = 1
        }
        return (0..<count).map { index in
            let col = index % columns
            let row = index / columns
            return CGRect(
                x: bounds.minX + gap + CGFloat(col) * (width + gap),
                y: bounds.maxY - gap - height - CGFloat(row) * (height + gap),
                width: width,
                height: height
            )
        }
    }
}
