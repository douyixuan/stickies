import AppKit

extension NoteWindowMode {
    var level: NSWindow.Level {
        switch self {
        case .standard: return .normal
        case .desktop: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating: return .floating
        }
    }

    var collectionBehavior: NSWindow.CollectionBehavior {
        self == .desktop ? [.canJoinAllSpaces, .stationary, .ignoresCycle] : []
    }

    var menuTitle: String {
        switch self {
        case .standard: return "Ordinary Windows"
        case .desktop: return "Desktop — Behind Apps"
        case .floating: return "Floating — Keep on Top"
        }
    }
}

extension NotePalette {
    static func color(_ index: Int) -> NSColor {
        let swatch = NotePalette.swatch(index)
        return NSColor(srgbRed: swatch.red, green: swatch.green, blue: swatch.blue, alpha: 1)
    }
}

/// Double-clicking the title folds a note. Text and controls keep their usual events.
final class NoteWindow: NSWindow {
    var onTitleDoubleClick: (() -> Void)?
    var onGestureBegan: (() -> Void)?
    var onGestureEnded: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onGestureBegan?() }
        // Native title dragging and performDrag may consume mouse-up inside their tracking loop.
        defer { if event.type == .leftMouseDown { onGestureEnded?() } }
        if event.type == .leftMouseUp { onGestureEnded?() }
        if event.type == .leftMouseDown, event.clickCount == 2,
           event.locationInWindow.y >= contentLayoutRect.maxY,
           let root = contentView?.superview {
            var hit: NSView? = root.hitTest(root.convert(event.locationInWindow, from: nil))
            var onControl = false
            while let view = hit {
                if view is NSControl || NSStringFromClass(type(of: view)).contains("Hosting") {
                    onControl = true
                    break
                }
                hit = view.superview
            }
            if !onControl {
                onTitleDoubleClick?()
                return
            }
        }
        super.sendEvent(event)
    }
}

/// A small grip inside the native drag region, never over editable text.
final class NoteDragHint: NSView {
    var onDoubleClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { window?.performDrag(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(window?.isKeyWindow == true ? 0.22 : 0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: bounds.midY - 1, width: 16, height: 2),
                     xRadius: 1, yRadius: 1).fill()
    }
}
