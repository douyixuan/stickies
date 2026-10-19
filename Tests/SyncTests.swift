import Foundation

@main struct SyncTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stickies-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); count += 1
        }
        func note(_ text: String) -> SyncValue { SyncValue(content: NoteContent(text: text)) }
        func engine(_ local: TestLocal, _ cloud: TestCloud, _ name: String) -> SyncCoordinator {
            SyncCoordinator(local: local, transport: cloud, file: root.appendingPathComponent(name))
        }
        let a = note("selected"), privateNote = note("private")
        let local = TestLocal([a, privateNote]), cloud = TestCloud()
        var sync = engine(local, cloud, "one")
        await sync.cycle(); check(cloud.calls == 0, "Off means no cloud calls")
        sync.enable(selected: [a.id]); await sync.cycle()
        check(cloud.records[a.id]?.value == a && cloud.records[privateNote.id] == nil, "Only selected initial notes uploaded")
        check(sync.ledger.entries[a.id]?.base != nil, "Ancestor persisted")
        // Offline modifications survive restart and resume from a known ancestor.
        local.syncValues[0].content.text = "offline edit"; cloud.failFetch = true
        await sync.cycle(); check(cloud.records[a.id]?.value == a, "Offline writes cannot alter cloud")
        sync = engine(local, cloud, "one"); cloud.failFetch = false; await sync.cycle()
        check(cloud.records[a.id]?.value.content.text == "offline edit", "Restart retries durable local edits")
        // Disjoint field merge and same-field conflict preserve both versions.
        var remote = cloud.records[a.id]!.value; remote.content.color = 3; _ = cloud.put(remote)
        local.syncValues.firstIndex(where: { $0.id == a.id }).map { local.syncValues[$0].content.text = "local second" }
        await sync.cycle()
        check(cloud.records[a.id]?.value.content.text == "local second" && cloud.records[a.id]?.value.content.color == 3, "Disjoint changes merged")
        remote = cloud.records[a.id]!.value; remote.content.text = "cloud conflicting"; _ = cloud.put(remote)
        local.syncValues.firstIndex(where: { $0.id == a.id }).map { local.syncValues[$0].content.text = "local conflicting" }
        await sync.cycle(); check(sync.conflicts.contains(a.id), "Same-field conflict retained")
        check(local.syncValues.first { $0.id == a.id }?.content.text == "local conflicting", "Conflict never overwrites local")
        sync.resolve(a.id, useCloud: false); await sync.cycle()
        check(cloud.records[a.id]?.value.content.text == "local conflicting", "Explicit keep-local resolution uses CAS")
        // An edit made while save is in flight is never replaced by its old response.
        local.syncValues.firstIndex(where: { $0.id == a.id }).map { local.syncValues[$0].content.text = "sent" }
        cloud.saving = { local.syncValues.firstIndex(where: { $0.id == a.id }).map { local.syncValues[$0].content.text = "newer while saving" } }
        await sync.cycle(); check(local.syncValues.first { $0.id == a.id }?.content.text == "newer while saving", "In-flight edit preserved")
        await sync.cycle(); check(cloud.records[a.id]?.value.content.text == "newer while saving", "Later edit eventually uploads")
        cloud.loseSaveResponse = true
        local.syncValues.firstIndex(where: { $0.id == a.id }).map { local.syncValues[$0].content.text = "uncertain commit" }
        await sync.cycle(); sync = engine(local, cloud, "one"); await sync.cycle()
        check(sync.ledger.entries[a.id]?.base?.value.content.text == "uncertain commit", "Lost response recovers by read/compare")
        // Complete-page failure must not apply any remote records.
        let imported = note("remote import"); _ = cloud.put(imported); cloud.failFetch = true
        await sync.cycle(); check(!local.syncValues.contains { $0.id == imported.id }, "Partial fetch applied nothing")
        cloud.failFetch = false; local.failApply = true; await sync.cycle()
        check(sync.ledger.entries[imported.id]?.pending != nil, "Full remote intent survives local write failure")
        local.failApply = false; sync = engine(local, cloud, "one"); await sync.cycle()
        check(local.syncValues.contains(imported), "Pending remote import restored after restart")
        // Crash after notes apply, before acknowledgement; a later user edit must survive.
        var remote2 = imported; remote2.content.text = "remote newer"; _ = cloud.put(remote2)
        var injected = false
        sync.write = { data, url in
            let state = try JSONDecoder().decode(SyncCoordinator.Ledger.self, from: data)
            if !injected && state.entries[imported.id]?.base?.value == remote2 && state.entries[imported.id]?.pending == nil {
                injected = true; throw SyncCoordinator.Failure.blocked("injected ack failure")
            }
            try data.write(to: url, options: .atomic)
        }
        await sync.cycle(); check(injected && local.syncValues.contains(remote2), "Notes committed before failed ancestor ack")
        local.syncValues.firstIndex(where: { $0.id == imported.id }).map { local.syncValues[$0].content.text = "edited after crash" }
        sync = engine(local, cloud, "one"); await sync.cycle()
        check(local.syncValues.first { $0.id == imported.id }?.content.text == "edited after crash" && sync.conflicts.contains(imported.id), "Recovery preserves post-crash edit")
        // Deletion is a durable tombstone and edit-delete conflicts preserve the edit.
        sync.resolve(imported.id, useCloud: false); await sync.cycle()
        sync.deleteEverywhere(imported.id); await sync.cycle()
        check(cloud.records[imported.id]?.value.deleted == true && cloud.records[imported.id]?.value.content.text == "", "Deletion clears cloud body and retains tombstone")
        check(!local.syncValues.contains { $0.id == imported.id }, "Local deleted projection removed")
        // Account changes and shutdown invalidate async callbacks.
        let untouched = local.syncValues
        cloud.fetched = { sync.disable() }; await sync.cycle()
        check(!sync.ledger.enabled && local.syncValues == untouched, "Disabled fetch response ignored")
        let calls = cloud.calls; await sync.cycle(); check(cloud.calls == calls, "Off performs no calls")
        sync.enable(selected: []); cloud.user = "account-B"; await sync.cycle()
        check(cloud.calls == calls, "Account switch makes no data request")
        // Local-only UUID collisions are never silently enrolled.
        let collisionCloud = TestCloud(); _ = collisionCloud.put(privateNote)
        let collision = engine(TestLocal([privateNote]), collisionCloud, "collision")
        collision.enable(selected: []); await collision.cycle()
        check(collision.ledger.entries[privateNote.id] == nil, "Unselected identity collision stays local-only")
        // Invalid state blocks; no reset or automatic upload.
        try Data("{broken".utf8).write(to: root.appendingPathComponent("broken"))
        let broken = engine(local, cloud, "broken"); broken.enable(selected: [a.id]); await broken.cycle()
        check(broken.blocked && !broken.ledger.enabled, "Corrupt ledger fails closed")
        let unavailable = TestCloud(); unavailable.availability = "missing signature"
        let gate = engine(local, unavailable, "gate"); gate.enable(selected: [a.id]); await gate.cycle()
        check(!gate.ledger.enabled && unavailable.calls == 0, "Unsigned build cannot enable transport")
        // A failed local deletion followed by a new edit must respect Keep This Mac.
        let deleteCloud = TestCloud(), deleteLocal = TestLocal([a])
        var deletion = engine(deleteLocal, deleteCloud, "delete-recovery")
        deletion.enable(selected: [a.id]); await deletion.cycle()
        deleteLocal.failApply = true; deletion.deleteEverywhere(a.id)
        deleteLocal.syncValues[0].content.text = "edited after failed delete"
        deleteLocal.failApply = false; deletion = engine(deleteLocal, deleteCloud, "delete-recovery")
        await deletion.cycle(); check(deletion.conflicts.contains(a.id), "Delete recovery retains newer local edit as conflict")
        deletion.resolve(a.id, useCloud: false); await deletion.cycle()
        check(deleteCloud.records[a.id]?.value.deleted == false && deleteCloud.records[a.id]?.value.content.text == "edited after failed delete", "Keep local must clear old tombstone")
        deletion.write = { _, _ in throw SyncCoordinator.Failure.blocked("ledger write failed") }
        deletion.disable()
        deletion = engine(deleteLocal, deleteCloud, "delete-recovery")
        let oldCalls = deleteCloud.calls; await deletion.cycle()
        check(!deletion.ledger.enabled && deleteCloud.calls == oldCalls, "Off marker survives ledger write failure and restart")
        let lockedLocal = TestLocal([a]); lockedLocal.syncStorageOwned = false; lockedLocal.syncWritable = false
        let locked = engine(lockedLocal, TestCloud(), "locked")
        locked.disable()
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("locked.off").path), "Unowned storage cannot write off marker")
        let consentCloud = TestCloud(); consentCloud.requiresLaunchConsent = true
        let consentLocal = TestLocal([a])
        var consent = engine(consentLocal, consentCloud, "launch-consent")
        consent.enable(selected: [a.id]); await consent.cycle()
        consent = engine(consentLocal, consentCloud, "launch-consent")
        let consentCalls = consentCloud.calls; await consent.cycle()
        check(!consent.ledger.enabled && consentCloud.calls == consentCalls, "Folder model requires explicit consent after restart")
        consent.enable(selected: []); await consent.cycle()
        check(consent.ledger.enabled && consentCloud.calls > consentCalls, "Explicit resume retains selected membership")
        print("PASS: \(count) isolated sync assertions; simulated transport only, no iCloud requests")
    }
}
