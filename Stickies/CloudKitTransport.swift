import Foundation
import CloudKit
import Security

struct CloudConfiguration {
    var container: String?
    var environment: String?
    var problem: String?
    static func installed() -> Self {
        var code: SecCode?
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              (entitlements["com.apple.developer.icloud-services"] as? [String])?.contains("CloudKit") == true,
              let container = Bundle.main.object(forInfoDictionaryKey: "StickiesCloudContainer") as? String,
              (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains(container) == true,
              let environment = entitlements["com.apple.developer.icloud-container-environment"] as? String,
              ["Development", "Production"].contains(environment) else {
            return Self(problem: "This build is not signed for iCloud. A CloudKit container and signed build are required; local notes still work.")
        }
        return Self(container: container, environment: environment)
    }
}

@MainActor final class CloudKitTransport: SyncTransport {
    let configuration: CloudConfiguration
    var scope: String { "\(configuration.container ?? "unconfigured")/\(configuration.environment ?? "none")/iStickiesNotes-v1" }
    var availability: String? { configuration.problem }
    private var container: CKContainer?
    private let zone = CKRecordZone.ID(zoneName: "iStickiesNotes-v1", ownerName: CKCurrentUserDefaultName)
    init(configuration: CloudConfiguration = .installed()) { self.configuration = configuration }
    private func client() throws -> CKContainer {
        guard configuration.problem == nil, let identifier = configuration.container else {
            throw SyncCoordinator.Failure.blocked(configuration.problem ?? "Missing iCloud configuration.")
        }
        if let container { return container }
        let result = CKContainer(identifier: identifier); container = result; return result
    }
    func account() async throws -> String {
        let client = try client()
        guard try await client.accountStatus() == .available else {
            throw SyncCoordinator.Failure.blocked("Sign in to iCloud on this Mac, then try again.")
        }
        return try await client.userRecordID().recordName
    }
    nonisolated private static func decode(_ record: CKRecord) throws -> CloudNote {
        guard record.recordType == "StickyNote", let id = UUID(uuidString: record.recordID.recordName),
              let schema = record["schema"] as? Int, schema == 1,
              let text = record["text"] as? String, let color = record["color"] as? Int,
              let deleted = record["deleted"] as? Int, [0,1].contains(deleted) else {
            throw SyncCoordinator.Failure.blocked("The cloud contains an unsupported note format. No local notes were replaced.")
        }
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archive); archive.finishEncoding()
        return CloudNote(value: SyncValue(content: NoteContent(id: id, text: text, color: color), deleted: deleted == 1), systemFields: archive.encodedData)
    }
    private final class FetchResult: @unchecked Sendable {
        let lock = NSLock()
        var records: [CloudNote] = []
        var error: Error?
        func accept(_ result: Result<CKRecord, Error>) {
            lock.lock(); defer { lock.unlock() }
            do { records.append(try CloudKitTransport.decode(result.get())) } catch { self.error = error }
        }
        func fail(_ error: Error) { lock.lock(); defer { lock.unlock() }; self.error = error }
        func finish(_ result: Result<Void, Error>) -> Result<[CloudNote], Error> {
            lock.lock(); defer { lock.unlock() }
            do { try result.get(); if let error { throw error }; return .success(records) }
            catch { return .failure(error) }
        }
    }
    func fetch(createZoneIfMissing: Bool) async throws -> [CloudNote] {
        let database = try client().privateCloudDatabase
        do {
            let results = try await database.recordZones(for: [zone])
            guard let result = results[zone] else { throw SyncCoordinator.Failure.blocked("Cloud zone response is incomplete.") }
            _ = try result.get()
        } catch {
            guard createZoneIfMissing, (error as? CKError)?.code == .zoneNotFound else { throw error }
            let created = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
            guard let result = created.saveResults[zone] else { throw SyncCoordinator.Failure.blocked("Cloud zone creation was not confirmed.") }
            _ = try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone], configurationsByRecordZoneID: nil)
            // Fetch every page before applying any result. Tombstones remain records.
            operation.fetchAllChanges = true
            let result = FetchResult()
            operation.recordWasChangedBlock = { _, value in result.accept(value) }
            operation.recordWithIDWasDeletedBlock = { _, _ in result.fail(SyncCoordinator.Failure.blocked("A cloud record was removed outside iStickies2. Sync paused to protect local notes.")) }
            operation.recordZoneFetchResultBlock = { _, value in if case let .failure(error) = value { result.fail(error) } }
            operation.fetchRecordZoneChangesResultBlock = { value in continuation.resume(with: result.finish(value)) }
            database.add(operation)
        }
    }
    func save(_ value: SyncValue, replacing base: CloudNote?) async throws -> CloudNote {
        let database = try client().privateCloudDatabase
        let record: CKRecord
        if let base {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: base.systemFields)
            decoder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: decoder), restored.recordID.recordName == value.id.uuidString,
                  restored.recordID.zoneID == zone else { throw SyncCoordinator.Failure.blocked("Cloud revision is invalid; sync stopped.") }
            decoder.finishDecoding(); record = restored
        } else { record = CKRecord(recordType: "StickyNote", recordID: CKRecord.ID(recordName: value.id.uuidString, zoneID: zone)) }
        record["schema"] = 1 as CKRecordValue
        record["text"] = value.content.text as CKRecordValue
        record["color"] = value.content.color as CKRecordValue
        record["deleted"] = (value.deleted ? 1 : 0) as CKRecordValue
        let response = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let result = response.saveResults[record.recordID] else { throw SyncCoordinator.Failure.blocked("Cloud save was not confirmed. Local changes remain queued.") }
        return try Self.decode(result.get())
    }
}
