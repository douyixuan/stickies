import AppKit
import SwiftUI
import CloudKit

@MainActor final class CloudSyncController: ObservableObject {
    static let shared = CloudSyncController()
    @Published private(set) var coordinator: SyncCoordinator
    @Published var setupError: String?
    @Published private(set) var settingUp = false
    private struct FolderChoice: Codable { var bookmark: Data; var id: UUID }
    private var choiceURL: URL { NoteStore.shared.localDataDirectory.appendingPathComponent("sync-folder.json") }
    private var window: NSWindow?
    private var worker: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var driveObserver: NSObjectProtocol?
    private init() {
        let local = NoteStore.shared
        coordinator = SyncCoordinator(local: local, transport: CloudKitTransport(), file: local.localDataDirectory.appendingPathComponent("sync-state.json"))
        if FileManager.default.fileExists(atPath: choiceURL.path) {
            do {
                let choice = try JSONDecoder().decode(FolderChoice.self, from: Data(contentsOf: choiceURL))
                var stale = false
                let url = try URL(resolvingBookmarkData: choice.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale else { throw SyncCoordinator.Failure.blocked("Choose the sync folder again to renew access.") }
                coordinator = makeFolderCoordinator(url, id: choice.id)
            } catch { setupError = "Reconnect your selected sync folder. Existing data and history are preserved." }
        }
    }
    private func makeFolderCoordinator(_ url: URL, id: UUID) -> SyncCoordinator {
        SyncCoordinator(local: NoteStore.shared, transport: FolderSyncTransport(folder: url, id: id),
                        file: NoteStore.shared.localDataDirectory.appendingPathComponent("sync-folder-" + id.uuidString + ".json"))
    }
    func chooseFolder(create: Bool) {
        guard !settingUp, !coordinator.busy, !coordinator.ledger.enabled, NoteStore.shared.syncWritable else { return }
        settingUp = true
        let previous = coordinator
        let picker = NSOpenPanel()
        picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = false
        picker.message = create ? "Choose a parent folder in your cloud drive. iStickies2 will create its own sync folder there. No notes upload until you select them and enable sync." : "Choose the iStickies2 sync folder created on your first Mac. Only that folder is accessed."
        picker.prompt = create ? "Create Sync Folder" : "Connect Sync Folder"
        guard picker.runModal() == .OK, let selected = picker.url else { settingUp = false; return }
        Task {
            defer { settingUp = false }
            let access = selected.startAccessingSecurityScopedResource()
            defer { if access { selected.stopAccessingSecurityScopedResource() } }
            do {
                let folder = try await Task.detached { () throws -> URL in
                    return create ? try SyncFolder.create(in: selected) : selected
                }.value
                let manifest = try await Task.detached { try SyncFolder.coordinated(folder, writing: false) { try SyncFolder.manifest($0) } }.value
                guard coordinator === previous, !previous.ledger.enabled, !previous.busy, NoteStore.shared.syncWritable else { throw SyncCoordinator.Failure.blocked("Sync settings changed during folder selection. Try again.") }
                previous.disable()
                guard !previous.pendingDisable else { throw SyncCoordinator.Failure.blocked("Could not pause the previous sync folder.") }
                let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let next = makeFolderCoordinator(folder, id: manifest.id)
                // Setup never uploads. Reconnecting an existing selection requires explicit enable.
                next.disable()
                guard !next.pendingDisable else { throw SyncCoordinator.Failure.blocked("Could not save the disabled sync setting.") }
                try JSONEncoder().encode(FolderChoice(bookmark: bookmark, id: manifest.id)).write(to: choiceURL, options: .atomic)
                coordinator = next; setupError = nil; start()
            } catch { setupError = error.localizedDescription }
        }
    }
    func start() {
        guard worker == nil, coordinator.availability == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.coordinator.accountChanged() }
        }
        driveObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.coordinator.accountChanged() }
        }
        worker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.coordinator.cycle()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
    func show() {
        if window == nil {
            let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            result.title = "Sync Folder — iStickies2"
            result.contentView = NSHostingView(rootView: SyncSettingsHost(controller: self))
            result.isReleasedWhenClosed = false; result.center(); window = result
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SyncSettingsHost: View {
    @ObservedObject var controller: CloudSyncController
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Create Sync Folder…") { controller.chooseFolder(create: true) }
                Button("Open Existing Sync Folder…") { controller.chooseFolder(create: false) }
            }.disabled(controller.settingUp || controller.coordinator.ledger.enabled || controller.coordinator.busy)
            Text("First Mac: create a folder in your cloud drive. Other Mac: connect the same folder after it appears in Finder. Enable folder sync each time the app starts. No Apple developer account is required. A local folder works too, but transfer requires a cloud drive.").font(.caption)
            if let error = controller.setupError { Text(error).foregroundStyle(.orange) }
            SyncSettingsView(sync: controller.coordinator, notes: .shared)
                .id(controller.coordinator.scope)
                .disabled(controller.settingUp)
        }.padding(12)
    }
}

struct SyncSettingsView: View {
    @ObservedObject var sync: SyncCoordinator
    @ObservedObject var notes: NoteStore
    @State private var selection = Set<UUID>()
    @State private var deleting: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Folder").font(.title2.bold())
            Text("Sync note text and colors between your Macs. Window positions, hidden state and layouts stay on each Mac.")
                .foregroundStyle(.secondary)
            if sync.availability != nil {
                Text("Create a sync folder on your first Mac, or open the same folder on your other Mac.").font(.caption)
            }
            Text(sync.status).font(.callout).textSelection(.enabled)
            HStack {
                if sync.pendingDisable { Button("Retry Saving Off") { sync.disable() } }
                if sync.ledger.enabled {
                    Button("Turn Off Sync") { sync.disable() }
                    Button("Sync Now") { Task { await sync.cycle() } }.disabled(sync.busy || sync.blocked)
                } else {
                    Button("Enable Sync for Selected Notes (\(selection.count))") {
                        sync.enable(selected: selection)
                        Task { await sync.cycle() }
                    }.disabled(sync.availability != nil || sync.blocked || sync.busy)
                }
                if sync.busy { ProgressView().controlSize(.small) }
            }
            if !sync.ledger.enabled {
                Text("Nothing is selected automatically. Enabling downloads your cloud notes and uploads only selected local notes. Future new notes also sync. Turning sync off keeps this Mac’s copies and does not delete cloud notes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(notes.notes) { note in
                    HStack {
                        if !sync.ledger.enabled && sync.ledger.entries[note.id] == nil {
                            Toggle(isOn: Binding(get: { selection.contains(note.id) }, set: { if $0 { selection.insert(note.id) } else { selection.remove(note.id) } })) {
                                Text(note.text.split(separator: "\n").first.map(String.init) ?? "Empty note").lineLimit(1)
                            }
                        } else {
                            Text(note.text.split(separator: "\n").first.map(String.init) ?? "Empty note").lineLimit(1)
                            Spacer()
                            Text(sync.ledger.entries[note.id] == nil ? "Local only" : "Sync selected").font(.caption).foregroundStyle(.secondary)
                        }
                        if sync.ledger.entries[note.id] != nil {
                            Button("Delete Everywhere…") { deleting = note.id }.disabled(sync.busy || sync.blocked)
                        }
                    }
                }
                ForEach(sync.recoverableIDs, id: \.self) { id in
                    HStack {
                        Text("Deleted: " + (sync.ledger.entries[id]?.recovery?.content.text ?? "")).lineLimit(2)
                        Spacer()
                        Button("Restore Deleted Note") { sync.restoreDeleted(id) }.disabled(sync.busy || sync.blocked)
                    }
                }
                ForEach(sync.conflicts, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conflicting versions").font(.headline)
                        Text("This Mac (color \(notes.note(id)?.color ?? 0)): " + (notes.note(id)?.text ?? "Deleted on this Mac")).textSelection(.enabled)
                        if let remote = sync.ledger.entries[id]?.conflict?.value {
                            Text("Cloud (color \(remote.content.color)): " + (remote.deleted ? "Deleted in cloud folder" : remote.content.text)).textSelection(.enabled)
                        }
                        if let versions = sync.ledger.entries[id]?.conflict?.alternatives {
                            ForEach(Array(versions.enumerated()), id: \.offset) { index, value in
                                VStack(alignment: .leading) {
                                    Text("Cloud version \(index + 1), color \(value.content.color): " + (value.deleted ? "Deleted" : value.content.text)).textSelection(.enabled)
                                    Button("Use Cloud Version \(index + 1)") { sync.resolve(id, useCloud: true, variant: value) }.disabled(sync.busy)
                                }
                            }
                        }
                        HStack {
                            Button("Keep This Mac’s Version") { sync.resolve(id, useCloud: false) }
                            Button("Use Cloud Version") { sync.resolve(id, useCloud: true) }
                        }.disabled(sync.busy)
                    }.padding(.vertical, 8)
                }
            }
            Text("Closing a note only hides it. Delete Everywhere queues a deletion for the next successful sync.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        .alert("Delete this note from synced Macs?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete Everywhere", role: .destructive) { if let id = deleting { sync.deleteEverywhere(id) }; deleting = nil }
        } message: { Text("This removes the local note and queues a cloud deletion. Offline Macs receive the deletion after they reconnect. Folder sync retains historical revisions containing previous note text. This is not secure erasure.") }
    }
}
