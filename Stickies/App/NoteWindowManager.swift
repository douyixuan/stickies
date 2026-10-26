import AppKit
import SwiftUI

/// Owns the note windows and every decision that needs to know about displays.
/// The store holds the data; this layer turns it into windows and back.
final class NoteWindowManager: NSObject, NSWindowDelegate {
    let store: NoteStore
    private var windows: [UUID: NoteWindow] = [:]
    /// Note ids whose windows this manager is moving itself, so its own
    /// `setFrame` calls are not mistaken for the user dragging.
    private var applyingFrames: Set<UUID> = []
    /// Undo points already taken during the in-flight mouse gesture.
    private var gestureCaptured: Set<UUID> = []
    /// Notes resized during the in-flight gesture. Edge snapping is for moves only.
    private var gestureResized: Set<UUID> = []

    init(store: NoteStore) {
        self.store = store
        super.init()
    }

    private var screens: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    private func onScreen(_ frame: CGRect, collapsed: Bool) -> CGRect {
        LayoutEngine.restore(frame, screens: screens,
                             minimumHeight: collapsed ? LayoutState.collapsedHeight : StickyNote.minimumHeight)
    }

    // MARK: Launch

    func restoreWindows() {
        if store.notes.isEmpty, store.isWritable {
            if let id = store.createNote() {
                store.setText(id, Self.welcomeText)
            }
        }
        for note in store.visibleNotes { show(note.id) }

        if let reason = store.readOnlyReason {
            let alert = NSAlert()
            alert.messageText = "iStickies2 is not saving changes"
            alert.informativeText = reason
            alert.runModal()
        }
    }

    private static let welcomeText = """
        Welcome to iStickies2

        Write here. Drag the title bar to move this note, drag a corner to resize it.
        Double-click the title bar to fold the note.

        The menu bar note icon has New Note, colors, Grid/List arrangement and window layering.
        Closing a note hides it; Show All Notes brings it back.
        """

    // MARK: Windows

    @discardableResult
    func createNote() -> UUID? {
        guard let id = store.createNote() else { return nil }
        show(id)
        return id
    }

    /// Also used on a read-only run: the windows open, the store simply refuses writes.
    func show(_ id: UUID) {
        guard !store.isTrashed(id), let note = store.note(id) else { return }
        store.setVisible(id, true)

        if let window = windows[id] {
            applyPresentation(id)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }

        // A note saved on a display that is gone comes back onto an available one.
        store.setFrame(id, expanded: onScreen(note.frame, collapsed: store.isCollapsed(id)))

        let window = NoteWindow(contentRect: store.note(id)?.frame ?? note.frame,
                                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                backing: .buffered, defer: false)
        window.onTitleDoubleClick = { [weak self] in self?.toggleCollapse(id) }
        window.onGestureBegan = { [weak self] in self?.beginGesture(id) }
        window.onGestureEnded = { [weak self] in self?.endGesture(id) }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: StickyNote.minimumWidth, height: StickyNote.minimumHeight)
        window.contentView = NSHostingView(rootView: NoteBodyView(noteID: id).environmentObject(store))
        window.delegate = self

        let actions = NSTitlebarAccessoryViewController()
        actions.layoutAttribute = .right
        let header = NSHostingView(rootView: NoteHeaderView(noteID: id).environmentObject(store))
        header.frame = NSRect(x: 0, y: 0, width: 60, height: 22)
        header.toolTip = "Note actions and colors. Drag the empty title bar to move this note."
        actions.view = header
        window.addTitlebarAccessoryViewController(actions)

        let grip = NSTitlebarAccessoryViewController()
        grip.layoutAttribute = .left
        let hint = NoteDragHint(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        hint.onDoubleClick = { [weak self] in self?.toggleCollapse(id) }
        hint.toolTip = "Drag this title bar to move the note. Double-click to fold it."
        grip.view = hint
        window.addTitlebarAccessoryViewController(grip)

        windows[id] = window
        applyPresentation(id)
        window.makeKeyAndOrderFront(nil)
    }

    func hide(_ id: UUID) {
        store.setVisible(id, false)
        windows[id]?.orderOut(nil)
    }

    func showAll() {
        store.showAll()
        for note in store.activeNotes { show(note.id) }
    }

    func hideAll() {
        store.hideAll()
        for window in windows.values { window.orderOut(nil) }
    }

    func moveToTrash(_ id: UUID) {
        guard store.moveToTrash(id) else { return }
        windows[id]?.orderOut(nil)
        windows[id]?.delegate = nil
        windows.removeValue(forKey: id)
    }

    func restoreFromTrash(_ id: UUID) {
        guard store.restoreFromTrash(id) else { return }
        show(id)
    }

    /// Pushes the store's state onto one live window: frame, fold, title, color and layer.
    func applyPresentation(_ id: UUID) {
        guard let note = store.note(id), let window = windows[id] else { return }
        let collapsed = store.isCollapsed(id)
        let mode = store.windowMode(for: id)
        window.title = note.title
        window.backgroundColor = NotePalette.color(note.color)
        window.level = mode.presentationLevel(applicationActive: NSApplication.shared.isActive)
        window.collectionBehavior = mode.collectionBehavior
        window.minSize = NSSize(width: StickyNote.minimumWidth,
                                height: collapsed ? LayoutState.collapsedHeight : StickyNote.minimumHeight)
        if collapsed { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
        window.titleVisibility = collapsed ? .visible : .hidden
        window.contentView?.isHidden = collapsed

        let target = store.layout.renderedFrame(id: id, expanded: note.frame)
        if window.frame != target {
            applyingFrames.insert(id)
            window.setFrame(target, display: true, animate: false)
            applyingFrames.remove(id)
        }
    }

    /// The native title follows the first line as you type, without touching geometry.
    func refreshTitle(_ id: UUID) {
        guard let note = store.note(id) else { return }
        windows[id]?.title = note.title
    }

    func applyAllPresentations() {
        for id in windows.keys { applyPresentation(id) }
    }

    /// Window levels only, on activation and deactivation. Nothing is shown, hidden,
    /// reordered or saved: a note you hid stays hidden when you come back to the app.
    func refreshActivation(_ active: Bool) {
        for (id, window) in windows {
            window.level = store.windowMode(for: id).presentationLevel(applicationActive: active)
        }
    }

    // MARK: Folding

    func toggleCollapse(_ id: UUID) {
        guard let note = store.note(id) else { return }
        let collapsing = !store.isCollapsed(id)
        var collapsed = store.layout.collapsed
        if collapsing { collapsed.insert(id) } else { collapsed.remove(id) }
        // Unfolding may need to pull a note back onto a display it was folded away from.
        let frame = collapsing ? note.frame : onScreen(note.frame, collapsed: false)
        store.apply(NoteStore.LayoutChange(frames: [id: frame], collapsed: collapsed))
        applyPresentation(id)
    }

    // MARK: Arranging

    func arrange(_ strategy: Arrangement) {
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        guard store.arrange(strategy, in: area) else { return }
        applyAllPresentations()
    }

    func undoLayout() {
        guard store.undoLayout(clamping: { [weak self] in self?.onScreen($0, collapsed: false) ?? $0 }) else { return }
        applyAllPresentations()
    }

    func restorePreviousLayout() {
        guard store.restorePreviousLayout(clamping: { [weak self] in self?.onScreen($0, collapsed: false) ?? $0 }) else { return }
        applyAllPresentations()
    }

    /// Recovers visible notes when displays or their usable areas change mid-session.
    func recoverDisplayLayout() {
        let available = screens
        guard !available.isEmpty else { return }
        var frames: [UUID: CGRect] = [:]
        for note in store.visibleNotes {
            let restored = onScreen(note.frame, collapsed: store.isCollapsed(note.id))
            if restored != note.frame { frames[note.id] = restored }
        }
        guard !frames.isEmpty else { return }
        store.apply(NoteStore.LayoutChange(frames: frames, recordUndo: false))
        applyAllPresentations()
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = id(of: sender) { hide(id) }
        return false
    }

    func windowDidMove(_ notification: Notification) { recordFrame(notification) }
    func windowDidResize(_ notification: Notification) { recordFrame(notification) }

    private func recordFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = id(of: window),
              !applyingFrames.contains(id), let note = store.note(id) else { return }
        let expanded = store.layout.expandedFrame(id: id, rendered: window.frame, previous: note.frame)
        guard expanded != note.frame else { return }
        if !gestureCaptured.contains(id) {
            store.markUndoPoint(ids: [id])
            gestureCaptured.insert(id)
        }
        if expanded.size != note.frame.size { gestureResized.insert(id) }
        store.setFrame(id, expanded: expanded)
    }

    private func beginGesture(_ id: UUID) {
        gestureCaptured.remove(id)
        gestureResized.remove(id)
    }

    /// On mouse-up, a moved note may snap to the display's usable edges. A resized one never
    /// does: snapping it would drag the opposite edge along and undo the resize.
    private func endGesture(_ id: UUID) {
        defer { beginGesture(id) }
        guard gestureCaptured.contains(id), !gestureResized.contains(id), store.preferences.snapToScreenEdges,
              let window = windows[id], let note = store.note(id) else { return }
        let snapped = LayoutEngine.snapToScreenEdges(window.frame, screens: screens)
        guard snapped != window.frame else { return }
        store.setFrame(id, expanded: store.layout.expandedFrame(id: id, rendered: snapped, previous: note.frame))
        applyPresentation(id)
    }

    private func id(of window: NSWindow) -> UUID? {
        windows.first { $0.value === window }?.key
    }
}
