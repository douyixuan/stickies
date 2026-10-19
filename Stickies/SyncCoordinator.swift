import Foundation
import Combine

@MainActor final class SyncCoordinator: ObservableObject {
    struct ApplyIntent: Codable {
        var before: SyncValue?
        var after: SyncValue
        var ancestor: CloudNote?
    }
    struct Entry: Codable {
        var base: CloudNote?
        var pending: ApplyIntent?
        var outbound: SyncValue?
        var conflict: CloudNote?
        var deleted: SyncValue?
        var recovery: SyncValue?
        var resolutionRequested = false
    }
    struct Ledger: Codable {
        var version = 1
        var enabled = false
        var zoneEstablished = false
        var scope: String
        var account: String?
        var known = Set<UUID>()
        var entries: [UUID: Entry] = [:]
    }
    enum Failure: LocalizedError {
        case blocked(String)
        var errorDescription: String? { if case let .blocked(s) = self { return s }; return nil }
    }
    @Published private(set) var ledger: Ledger
    @Published private(set) var status = "Sync is off. Notes stay on this Mac."
    @Published private(set) var busy = false
    @Published private(set) var blocked = false
    private let local: SyncLocalStore
    private let transport: SyncTransport
    private let file: URL
    private var generation = 0
    private var storageInvalid = false
    @Published private(set) var pendingDisable = false
    private var offMarker: URL { file.appendingPathExtension("off") }
    // Injectable durable-write boundary for crash/failure tests.
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    var scope: String { transport.scope }
    var availability: String? { transport.availability }
    var recoverableIDs: [UUID] { ledger.entries.filter { $0.value.deleted != nil && $0.value.recovery != nil && $0.value.pending == nil && current($0.key) == nil }.map(\.key).sorted { $0.uuidString < $1.uuidString } }
    var conflicts: [UUID] { ledger.entries.filter { $0.value.conflict != nil }.map(\.key).sorted { $0.uuidString < $1.uuidString } }

    init(local: SyncLocalStore, transport: SyncTransport, file: URL) {
        self.local = local; self.transport = transport; self.file = file
        ledger = Ledger(scope: transport.scope)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let state = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
                guard state.version == 1, state.scope == transport.scope,
                      state.entries.allSatisfy({ id, e in
                          [e.base?.value.id, e.pending?.after.id, e.pending?.before?.id, e.outbound?.id, e.conflict?.value.id, e.deleted?.id, e.recovery?.id].compactMap { $0 }.allSatisfy { $0 == id }
                      }) else { throw Failure.blocked("Sync history is incompatible. Original files are preserved.") }
                ledger = state
            } catch { storageInvalid = true; blocked = true; status = "Sync history could not be read. Original files are preserved; sync is blocked." }
        }
        if FileManager.default.fileExists(atPath: offMarker.path) { ledger.enabled = false }
        if transport.requiresLaunchConsent && ledger.enabled {
            ledger.enabled = false
            status = "Confirm the selected sync folder, then enable sync for this session. Folder access does not verify your cloud account."
        }
        if !local.syncWritable { blocked = true; status = "This notes folder is read-only or already open elsewhere." }
    }
    private func persist(_ next: Ledger) throws {
        guard !blocked, local.syncWritable else { throw Failure.blocked("Sync storage is not writable.") }
        try write(JSONEncoder().encode(next), file)
        ledger = next
    }
    private func change(_ edit: (inout Ledger) -> Void) throws {
        var next = ledger; edit(&next); try persist(next)
    }
    func enable(selected: Set<UUID>) {
        guard !busy else { return }
        do {
            if let availability { throw Failure.blocked(availability) }
            try change { next in
                next.enabled = true
                next.known.formUnion(local.syncValues.map(\.id))
                for id in selected where local.syncValues.contains(where: { $0.id == id }) && next.entries[id] == nil { next.entries[id] = Entry() }
            }
            if FileManager.default.fileExists(atPath: offMarker.path) { try FileManager.default.removeItem(at: offMarker) }
            generation += 1; status = "Enabled. Selected notes and future new notes will sync."
        } catch { ledger.enabled = false; status = error.localizedDescription }
    }
    func disable() {
        generation += 1
        guard local.syncStorageOwned else {
            ledger.enabled = false; blocked = true
            status = "This instance does not own the notes storage lock. Sync settings were not written."
            return
        }
        do {
            // Independent durable stop marker wins over an older enabled ledger after restart.
            try Data("off".utf8).write(to: offMarker, options: .atomic)
            pendingDisable = false; blocked = storageInvalid
            do { try change { $0.enabled = false } } catch { ledger.enabled = false }
            status = "Sync is off. Local notes and history remain. A request already sent may finish."
        } catch {
            pendingDisable = true; blocked = true
            status = "Could not save the off setting. No more requests run in this session. Retry Saving Off before quitting."
        }
    }
    func accountChanged() { disable(); status = "iCloud account changed. Sync is paused; return to the original account before enabling." }
    private func current(_ id: UUID) -> SyncValue? { local.syncValues.first { $0.id == id } }
    private func matches(_ value: SyncValue?, _ wanted: SyncValue) -> Bool { wanted.deleted ? value == nil : value == wanted }
    private func recover(_ id: UUID) throws {
        guard let pending = ledger.entries[id]?.pending else { return }
        let now = current(id)
        if pending.after.deleted, let before = pending.before, !before.deleted {
            try change { $0.entries[id]?.recovery = before }
        }
        if !matches(now, pending.after) {
            guard now == pending.before else {
                if let ancestor = pending.ancestor {
                    try change { $0.entries[id]?.conflict = ancestor; $0.entries[id]?.pending = nil; $0.entries[id]?.deleted = nil }
                    return
                }
                throw Failure.blocked("A local note changed during recovery. No version was overwritten.")
            }
            try local.applySync(pending.after)
        }
        try change {
            $0.entries[id]?.base = pending.ancestor
            $0.entries[id]?.pending = nil
            $0.entries[id]?.deleted = pending.after.deleted ? pending.after : nil
        }
    }
    private func apply(_ desired: SyncValue, ancestor: CloudNote?) throws {
        let id = desired.id
        try change { $0.entries[id]?.pending = ApplyIntent(before: current(id), after: desired, ancestor: ancestor) }
        try recover(id)
    }
    func deleteEverywhere(_ id: UUID) {
        guard !busy, var value = current(id), ledger.entries[id] != nil else { return }
        value = SyncValue(content: NoteContent(id: id), deleted: true)
        do {
            try change { next in
                let ancestor = next.entries[id]?.base
                next.entries[id]?.deleted = value
                next.entries[id]?.pending = ApplyIntent(before: current(id), after: value, ancestor: ancestor)
            }
            try recover(id)
            status = "Deletion queued. It will sync when connected; closing a note still only hides it."
        } catch { status = error.localizedDescription }
    }
    func restoreDeleted(_ id: UUID) {
        guard !busy, current(id) == nil, ledger.entries[id]?.pending == nil, ledger.entries[id]?.deleted != nil, let value = ledger.entries[id]?.recovery else { return }
        do {
            try apply(value, ancestor: ledger.entries[id]?.base)
            status = "Restored on this Mac. Enable sync to send the restored note."
        } catch { status = error.localizedDescription }
    }
    func resolve(_ id: UUID, useCloud: Bool, variant: SyncValue? = nil) {
        guard !busy, let remote = ledger.entries[id]?.conflict else { return }
        do {
            if useCloud { try apply(variant ?? remote.value, ancestor: remote) }
            else {
                // Use the displayed cloud version as CAS ancestor; a newer server change conflicts again.
                guard current(id) != nil || ledger.entries[id]?.deleted != nil else { throw Failure.blocked("Local version is unavailable.") }
                try change { $0.entries[id]?.base = remote; if current(id) != nil { $0.entries[id]?.deleted = nil } }
            }
            try change { $0.entries[id]?.conflict = nil; $0.entries[id]?.resolutionRequested = true }
        } catch { status = error.localizedDescription }
    }
    func cycle() async {
        guard ledger.enabled, !blocked, !busy else { return }
        busy = true; defer { busy = false }
        let ticket = generation
        func active() -> Bool { ticket == generation && ledger.enabled && !blocked }
        do {
            if let availability { throw Failure.blocked(availability) }
            let account = try await transport.account()
            guard active() else { return }
            guard ledger.account == nil || ledger.account == account else { throw Failure.blocked("A different iCloud account is signed in. Return to the original account; no notes were transferred.") }
            if ledger.account == nil { try change { $0.account = account } }
            for id in Array(ledger.entries.keys) { try recover(id) }
            let newIDs = Set(local.syncValues.map(\.id)).subtracting(ledger.known)
            try change { next in
                next.known.formUnion(newIDs)
                for id in newIDs { next.entries[id] = Entry() }
            }
            let records = try await transport.fetch(createZoneIfMissing: !ledger.zoneEstablished)
            guard active(), try await transport.account() == account, active() else { return }
            guard Set(records.map { $0.value.id }).count == records.count else { throw Failure.blocked("Cloud returned duplicate note identities.") }
            try change { $0.zoneEstablished = true }
            let remotes = Dictionary(uniqueKeysWithValues: records.map { ($0.value.id, $0) })
            for remote in records where ledger.entries[remote.value.id] == nil {
                let id = remote.value.id
                guard current(id) == nil else { throw Failure.blocked("A cloud note matches a local-only note. Select that local note explicitly before syncing it.") }
                try change { $0.entries[id] = Entry(pending: ApplyIntent(before: nil, after: remote.value, ancestor: remote)); $0.known.insert(id) }
                try recover(id)
            }
            for id in Array(ledger.entries.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
                guard active() else { return }
                guard let entry = ledger.entries[id], entry.conflict == nil else { continue }
                let localValue = entry.deleted ?? current(id)
                guard let localValue else { throw Failure.blocked("A synced local note is missing. No cloud record was deleted.") }
                let remote = remotes[id]
                if remote == nil && entry.base != nil { throw Failure.blocked("A cloud record disappeared without a deletion marker. Sync paused to protect local notes.") }
                if let remote, remote.alternatives != nil, !(entry.resolutionRequested && entry.base?.systemFields == remote.systemFields) {
                    try change { $0.entries[id]?.conflict = remote }; continue
                }
                let desired: SyncValue
                do { desired = entry.resolutionRequested && entry.base?.systemFields == remote?.systemFields ? localValue : try remote.map { try SyncValue.merge(base: entry.base?.value, local: localValue, remote: $0.value) } ?? localValue }
                catch {
                    try change { $0.entries[id]?.conflict = remote }
                    continue
                }
                if desired != localValue { try apply(desired, ancestor: remote) }
                if desired == remote?.value && !entry.resolutionRequested {
                    try change { $0.entries[id]?.base = remote; $0.entries[id]?.outbound = nil }
                    continue
                }
                try change { $0.entries[id]?.outbound = desired }
                guard try await transport.account() == account, active() else { return }
                let saved = try await transport.save(desired, replacing: remote)
                guard active(), try await transport.account() == account, active() else { return }
                // Never apply an upload response to local notes: they may have changed during await.
                try change { $0.entries[id]?.base = saved; $0.entries[id]?.outbound = nil; $0.entries[id]?.resolutionRequested = false }
            }
            let pending = ledger.entries.contains { id, entry in
                entry.pending != nil || entry.outbound != nil || entry.resolutionRequested || (entry.deleted ?? current(id)) != entry.base?.value
            }
            status = !conflicts.isEmpty ? "Conflicts need your choice. All versions are preserved." : pending ? "Local changes are queued for the next sync." : transport.completionMessage
        } catch { if active() { status = "Sync paused: \(error.localizedDescription) Local changes remain on this Mac." } }
    }
}
