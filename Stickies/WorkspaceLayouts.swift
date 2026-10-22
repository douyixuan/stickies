import SwiftUI
import AppKit

/// Named device-local geometry only. No content, visibility, sync or active-selection state.
struct WorkspaceLayouts: Codable {
    var schemaVersion = 1
    var items: [Item] = []
    struct Item: Codable, Identifiable {
        var id: UUID
        var name: String
        var placements: [Placement]
    }
    struct Placement: Codable {
        var id: UUID
        var frame: CGRect
    }
    func validate() throws {
        guard schemaVersion == 1, Set(items.map(\.id)).count == items.count,
              Set(items.map { $0.name.lowercased() }).count == items.count else { throw Invalid.catalog }
        for item in items {
            guard !item.name.isEmpty, item.name.count <= 80,
                  item.name == item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  Set(item.placements.map(\.id)).count == item.placements.count,
                  item.placements.allSatisfy({ p in
                      [p.frame.minX, p.frame.minY, p.frame.width, p.frame.height].allSatisfy(\.isFinite)
                          && p.frame.width > 0 && p.frame.height > 0
                  }) else { throw Invalid.catalog }
        }
    }
    enum Invalid: Error { case catalog }
}

@MainActor
final class WorkspaceWindowController: NSObject, NSWindowDelegate {
    static let shared = WorkspaceWindowController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 430),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Layout Workspaces"
            panel.minSize = NSSize(width: 500, height: 400)
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: WorkspaceLayoutsView())
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WorkspaceLayoutsView: View {
    @ObservedObject private var store = NoteStore.shared
    @State private var selection: UUID?
    @State private var name = ""
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save and switch note positions and sizes on this Mac. Text, colors, visibility and folded state stay unchanged.")
                .font(.callout)
            List(selection: $selection) {
                ForEach(store.workspaceLayouts.items) { item in
                    HStack { Text(item.name); Spacer(); Text("\(item.placements.count) placements").foregroundStyle(.secondary) }
                        .tag(item.id)
                }
            }
            TextField("Workspace name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button("Create from Current Layout") {
                    if let id = store.createWorkspace(name: name) { selection = id; status = "Workspace created." }
                }
                Button("Rename") {
                    if let selection, store.renameWorkspace(selection, name: name) { status = "Workspace renamed." }
                }.disabled(selection == nil)
            }
            HStack {
                Button("Save Current Layout") {
                    if let selection, store.saveWorkspace(selection) { status = "Selected workspace updated." }
                }
                .help("Replace the selected workspace's saved positions and sizes with the current layout.")
                Button("Switch to Saved Layout") {
                    if let selection, store.switchWorkspace(selection) { status = "Saved layout applied. Undo Last Layout reverses positions and sizes." }
                }
            }.disabled(selection == nil)
            if let error = store.workspaceError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            else { Text(status.isEmpty ? "Moving notes does not update saved layouts. Choose Save Current Layout to replace the selected layout." : status).foregroundStyle(.secondary) }
        }
        .padding(16)
        .disabled(!store.canUseWorkspaces)
        .onChange(of: selection) { _, id in
            name = store.workspaceLayouts.items.first(where: { $0.id == id })?.name ?? ""
            status = ""
        }
    }
}
