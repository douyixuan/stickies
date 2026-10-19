import Foundation

@MainActor final class TestLocal: SyncLocalStore {
    var syncValues: [SyncValue]
    var syncWritable = true
    var syncStorageOwned = true
    var failApply = false
    init(_ values: [SyncValue]) { syncValues = values }
    func applySync(_ value: SyncValue) throws {
        if failApply { throw SyncCoordinator.Failure.blocked("injected local write failure") }
        syncValues.removeAll { $0.id == value.id }
        if !value.deleted { syncValues.append(value) }
    }
}
@MainActor final class TestCloud: SyncTransport {
    let scope = "test-container/Development/test-zone"
    var requiresLaunchConsent = false
    var availability: String?
    var user = "account-A"
    var records: [UUID: CloudNote] = [:]
    var revision = 0
    var calls = 0
    var failFetch = false
    var loseSaveResponse = false
    var fetched: (() -> Void)?
    var saving: (() -> Void)?
    func account() async throws -> String { user }
    func fetch(createZoneIfMissing: Bool) async throws -> [CloudNote] {
        calls += 1
        if failFetch { throw SyncCoordinator.Failure.blocked("injected partial page error") }
        let snapshot = Array(records.values); fetched?(); fetched = nil; return snapshot
    }
    func put(_ value: SyncValue) -> CloudNote {
        revision += 1
        let record = CloudNote(value: value, systemFields: Data(String(revision).utf8))
        records[value.id] = record; return record
    }
    func save(_ value: SyncValue, replacing base: CloudNote?) async throws -> CloudNote {
        calls += 1; saving?(); saving = nil
        guard records[value.id]?.systemFields == base?.systemFields else { throw SyncCoordinator.Failure.blocked("CAS conflict") }
        let result = put(value)
        if loseSaveResponse { loseSaveResponse = false; throw SyncCoordinator.Failure.blocked("lost server response") }
        return result
    }
}
