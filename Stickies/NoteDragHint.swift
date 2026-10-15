import AppKit

/// A small hint inside the native drag region, never over editable text.
final class NoteDragHint: NSView {
    var onDoubleClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { window?.performDrag(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(window?.isKeyWindow == true ? 0.22 : 0.12).setFill()
        let grip = NSBezierPath(roundedRect: NSRect(x: 4, y: bounds.midY - 1, width: 16, height: 2), xRadius: 1, yRadius: 1)
        grip.fill()
    }
}


/// Title double-click folds a note; text and native/SwiftUI controls keep their usual events.
final class NoteWindow: NSWindow {
    var onTitleDoubleClick: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2,
           event.locationInWindow.y >= contentLayoutRect.maxY,
           let root = contentView?.superview {
            var hit: NSView? = root.hitTest(root.convert(event.locationInWindow, from: nil))
            var control = false
            while let view = hit {
                if view is NSControl || NSStringFromClass(type(of: view)).contains("Hosting") { control = true; break }
                hit = view.superview
            }
            if !control { onTitleDoubleClick?(); return }
        }
        super.sendEvent(event)
    }
}

enum NoteWindowMode: String, Codable, CaseIterable {
    case standard, desktop, floating

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
}

