import CoreGraphics
import Foundation

func testLayoutEngine() {
    let screen = CGRect(x: -1440, y: 80, width: 1440, height: 820)

    for strategy in [Arrangement.grid, .list, .compact] {
        for count in [0, 1, 4, 50] {
            let frames = LayoutEngine.arrange(count: count, in: screen, strategy: strategy)
            Check.equal(frames.count, count, "\(strategy) produces one frame per note")
            Check.that(frames.allSatisfy { screen.contains($0) }, "\(strategy) keeps every note on screen")
            Check.that(frames == LayoutEngine.arrange(count: count, in: screen, strategy: strategy),
                       "\(strategy) is deterministic")
        }
    }
    Check.that(LayoutEngine.arrange(count: 50, in: screen, strategy: .free).isEmpty,
               "free layout moves nothing")
    Check.that(LayoutEngine.arrange(count: 50, in: screen, strategy: .compact)
        .allSatisfy { $0.height == LayoutState.collapsedHeight }, "compact folds every note")
    // Three notes fit one column of this display, so no overflow page offsets them.
    let column = LayoutEngine.arrange(count: 3, in: screen, strategy: .list)
    Check.that(column.allSatisfy { $0.minX == column[0].minX }, "list uses a single column")

    let tiny = CGRect(x: 0, y: 0, width: 150, height: 100)
    Check.that(LayoutEngine.arrange(count: 10, in: tiny, strategy: .grid).allSatisfy { tiny.contains($0) },
               "a display smaller than one note still contains every frame")

    // Display recovery.
    let gone = CGRect(x: 5000, y: -2000, width: 900, height: 1200)
    Check.that(screen.contains(LayoutEngine.restore(gone, screens: [screen])),
               "a note from a disconnected display comes back on screen")
    let second = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let onSecond = CGRect(x: -1000, y: 100, width: 260, height: 220)
    Check.equal(LayoutEngine.restore(onSecond, screens: [second, screen]), onSecond,
                "a note already on a display is left alone")
    Check.equal(LayoutEngine.restore(onSecond, screens: []), onSecond,
                "with no known displays nothing is moved")

    // Edge snapping.
    let near = CGRect(x: screen.minX + 5, y: screen.minY + 4, width: 260, height: 220)
    let snapped = LayoutEngine.snapToScreenEdges(near, screens: [screen])
    Check.equal(snapped.origin, CGPoint(x: screen.minX, y: screen.minY), "a near edge snaps")
    Check.equal(snapped.size, near.size, "snapping never resizes")
    let far = CGRect(x: screen.minX + 400, y: screen.minY + 400, width: 260, height: 220)
    Check.equal(LayoutEngine.snapToScreenEdges(far, screens: [screen]), far, "a distant note does not snap")
    let offscreen = CGRect(x: 9000, y: 9000, width: 260, height: 220)
    Check.equal(LayoutEngine.snapToScreenEdges(offscreen, screens: [screen]), offscreen,
                "a note on no known display does not teleport")
    let huge = CGRect(x: 0, y: 0, width: 4000, height: 4000)
    Check.equal(LayoutEngine.snapToScreenEdges(huge, screens: [screen]), huge,
                "a note larger than the display is left alone")

    // Folded geometry keeps the expanded height.
    var layout = LayoutState()
    let id = UUID()
    let expanded = CGRect(x: 10, y: 10, width: 260, height: 220)
    Check.equal(layout.renderedFrame(id: id, expanded: expanded), expanded, "an unfolded note renders as-is")
    layout.collapsed.insert(id)
    let folded = layout.renderedFrame(id: id, expanded: expanded)
    Check.equal(folded.height, LayoutState.collapsedHeight, "a folded note is one title bar high")
    Check.equal(folded.maxY, expanded.maxY, "folding keeps the top edge in place")
    Check.equal(layout.expandedFrame(id: id, rendered: folded, previous: expanded), expanded,
                "unfolding restores the expanded height")
}
