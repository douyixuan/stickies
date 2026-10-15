import AppKit

/// A small hint inside the native drag region, never over editable text.
final class NoteDragHint: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(window?.isKeyWindow == true ? 0.22 : 0.12).setFill()
        let grip = NSBezierPath(roundedRect: NSRect(x: 4, y: bounds.midY - 1, width: 16, height: 2), xRadius: 1, yRadius: 1)
        grip.fill()
    }
}
