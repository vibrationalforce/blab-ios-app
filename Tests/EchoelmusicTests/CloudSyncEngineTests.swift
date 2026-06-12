// CloudSyncEngineTests.swift
// Echoel — Phase 0 CloudKit sync: pure, backend-agnostic engine.
// Verified against an in-memory mock, no iCloud account / entitlement required.
//
// Invariants under test:
//   • Engine NO-OPS (returns false, never mutates the store) when iCloud is not
//     available — signed-out / restricted / unknown.
//   • Last-writer-wins conflict resolution by `modifiedAt`; ties keep local.
//   • merge() converges two record sets (union by id, newest payload wins).
//   • A real sync pushes only the delta and hands the merged set back to the store.
//   • The engine NEVER throws into the caller, even when the backend errors.

import XCTest
@testable import Echoelmusic

// MARK: - In-memory test doubles

/// A backend whose account status and stored records are fully controllable, and
/// which can be told to throw on fetch/save to exercise the never-throw contract.
private actor MockCloudBackend: CloudBackend {
    private var status: CloudAccountStatus
    private var store: [String: SyncRecord] = [:]
    private var failFetch = false
    private var failSave = false
    private(set) var saveCount = 0
    private(set) var lastSaved: [SyncRecord] = []

    init(status: CloudAccountStatus, seed: [SyncRecord] = []) {
        self.status = status
        for r in seed { store[r.id] = r }
    }

    func setStatus(_ s: CloudAccountStatus) { status = s }
    func setFailFetch(_ v: Bool) { failFetch = v }
    func setFailSave(_ v: Bool) { failSave = v }

    func accountStatus() async -> CloudAccountStatus { status }

    func fetch(type: String) async throws -> [SyncRecord] {
        if failFetch { throw CocoaError(.fileReadUnknown) }
        return store.values.filter { $0.type == type }
    }

    func save(_ records: [SyncRecord]) async throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        saveCount += 1
        lastSaved = records
        for r in records { store[r.id] = r }
    }
}

/// A trivial @MainActor store backed by an array, recording how many times its
/// merged set was handed back.
@MainActor
private final class MockSyncableStore: SyncableStore {
    let recordType: String
    var records: [SyncRecord]
    private(set) var importCount = 0

    init(recordType: String = "Patch", records: [SyncRecord] = []) {
        self.recordType = recordType
        self.records = records
    }

    func exportRecords() -> [SyncRecord] { records }

    func importMerged(_ records: [SyncRecord]) {
        self.records = records
        importCount += 1
    }
}

// MARK: - Helpers

private func rec(_ id: String, _ secondsAgo: TimeInterval, _ body: String, type: String = "Patch") -> SyncRecord {
    SyncRecord(
        id: id,
        type: type,
        modifiedAt: Date(timeIntervalSince1970: 1_000_000 + secondsAgo),
        payload: Data(body.utf8)
    )
}

// MARK: - Conflict resolution (pure, synchronous)

final class SyncConflictTests: XCTestCase {

    func testResolvePrefersNewerRemote() {
        let local = rec("a", 0, "old")
        let remote = rec("a", 10, "new")
        XCTAssertEqual(SyncConflict.resolve(local: local, remote: remote), remote)
    }

    func testResolvePrefersNewerLocal() {
        let local = rec("a", 10, "new")
        let remote = rec("a", 0, "old")
        XCTAssertEqual(SyncConflict.resolve(local: local, remote: remote), local)
    }

    func testResolveTieKeepsLocal() {
        let local = rec("a", 5, "local")
        let remote = rec("a", 5, "remote")
        XCTAssertEqual(SyncConflict.resolve(local: local, remote: remote), local,
                       "equal timestamps must deterministically keep local")
    }

    func testMergeUnionsBothSides() {
        let local = [rec("a", 0, "la"), rec("b", 0, "lb")]
        let remote = [rec("b", 10, "rb"), rec("c", 0, "rc")]
        let merged = SyncConflict.merge(local: local, remote: remote)

        XCTAssertEqual(merged.map { $0.id }, ["a", "b", "c"], "union, sorted by id")
        // "b" conflict: remote is newer → remote payload wins.
        let b = merged.first { $0.id == "b" }
        XCTAssertEqual(b?.payload, Data("rb".utf8))
        // a and c are one-sided → preserved as-is.
        XCTAssertEqual(merged.first { $0.id == "a" }?.payload, Data("la".utf8))
        XCTAssertEqual(merged.first { $0.id == "c" }?.payload, Data("rc".utf8))
    }

    func testMergeIsDeterministicRegardlessOfOrder() {
        let local = [rec("z", 0, "1"), rec("m", 0, "2"), rec("a", 0, "3")]
        let remote = [rec("a", 5, "4"), rec("q", 0, "5")]
        let m1 = SyncConflict.merge(local: local, remote: remote)
        let m2 = SyncConflict.merge(local: remote, remote: local)
        // Same id set, sorted; the only conflict ("a") resolves to the newer side
        // (timeAgo 5) in both directions, so the union is identical.
        XCTAssertEqual(m1.map { $0.id }, m2.map { $0.id })
        XCTAssertEqual(m1.first { $0.id == "a" }?.payload, Data("4".utf8))
        XCTAssertEqual(m2.first { $0.id == "a" }?.payload, Data("4".utf8))
    }
}

// MARK: - Engine behaviour

@MainActor
final class CloudSyncEngineTests: XCTestCase {

    func testNoOpsWhenSignedOut() async {
        let backend = MockCloudBackend(status: .noAccount, seed: [rec("a", 10, "remote")])
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [rec("a", 0, "local")])

        let ran = await engine.sync(store)

        XCTAssertFalse(ran, "must no-op when iCloud is signed out")
        XCTAssertEqual(store.importCount, 0, "store must be untouched")
        XCTAssertEqual(engine.lastStatus, .noAccount)
        XCTAssertNil(engine.lastSyncedAt)
        let saves = await backend.saveCount
        XCTAssertEqual(saves, 0, "nothing pushed when unavailable")
    }

    func testNoOpsWhenRestrictedOrUnknown() async {
        for status in [CloudAccountStatus.restricted, .unknown] {
            let backend = MockCloudBackend(status: status)
            let engine = CloudSyncEngine(backend: backend)
            let store = MockSyncableStore(records: [rec("a", 0, "local")])
            let ran = await engine.sync(store)
            XCTAssertFalse(ran, "no-op for \(status)")
            XCTAssertEqual(store.importCount, 0)
        }
    }

    func testRunsWhenAvailableAndMergesBothWays() async {
        // Local has a newer "a" and a unique "local-only"; remote has a unique
        // "remote-only" and an older "a".
        let backend = MockCloudBackend(status: .available, seed: [
            rec("a", 0, "old-a"),
            rec("remote-only", 0, "R"),
        ])
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [
            rec("a", 10, "new-a"),
            rec("local-only", 0, "L"),
        ])

        let ran = await engine.sync(store)

        XCTAssertTrue(ran)
        XCTAssertEqual(store.importCount, 1, "merged set handed back exactly once")
        XCTAssertNotNil(engine.lastSyncedAt)
        XCTAssertEqual(engine.lastStatus, .available)

        let ids = store.records.map { $0.id }.sorted()
        XCTAssertEqual(ids, ["a", "local-only", "remote-only"], "store now holds the union")
        // Conflict on "a": local is newer → local payload survives.
        XCTAssertEqual(store.records.first { $0.id == "a" }?.payload, Data("new-a".utf8))
    }

    func testPushesOnlyTheDelta() async {
        // Remote already has an up-to-date "shared"; only "a" (newer locally) and
        // "local-only" should be pushed.
        let backend = MockCloudBackend(status: .available, seed: [
            rec("shared", 0, "S"),
            rec("a", 0, "old-a"),
        ])
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [
            rec("shared", 0, "S"),       // identical → not pushed
            rec("a", 10, "new-a"),       // newer → pushed
            rec("local-only", 0, "L"),   // new → pushed
        ])

        _ = await engine.sync(store)

        let saved = await backend.lastSaved
        let savedIDs = Set(saved.map { $0.id })
        XCTAssertEqual(savedIDs, ["a", "local-only"], "only changed records are pushed")
        XCTAssertFalse(savedIDs.contains("shared"), "unchanged record is not re-pushed")
    }

    func testDoesNotPushWhenNothingChanged() async {
        let shared = rec("x", 0, "X")
        let backend = MockCloudBackend(status: .available, seed: [shared])
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [shared])

        let ran = await engine.sync(store)

        XCTAssertTrue(ran)
        let saves = await backend.saveCount
        XCTAssertEqual(saves, 0, "no delta → no save call")
        XCTAssertEqual(store.importCount, 1, "merged set still handed back")
    }

    func testNeverThrowsOnFetchFailure() async {
        let backend = MockCloudBackend(status: .available)
        await backend.setFailFetch(true)
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [rec("a", 0, "L")])

        let ran = await engine.sync(store)

        XCTAssertFalse(ran, "transient fetch error → graceful false, not a throw")
        XCTAssertEqual(store.importCount, 0, "store untouched on failure")
        XCTAssertNil(engine.lastSyncedAt)
    }

    func testNeverThrowsOnSaveFailure() async {
        let backend = MockCloudBackend(status: .available, seed: [rec("a", 0, "old")])
        await backend.setFailSave(true)
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [rec("a", 10, "new")]) // forces a delta push

        let ran = await engine.sync(store)

        XCTAssertFalse(ran, "save error → graceful false")
        XCTAssertEqual(store.importCount, 0, "no partial import when push fails")
    }

    func testStatusRecoversAfterSignIn() async {
        let backend = MockCloudBackend(status: .noAccount, seed: [rec("a", 0, "R")])
        let engine = CloudSyncEngine(backend: backend)
        let store = MockSyncableStore(records: [rec("b", 0, "L")])

        var ran = await engine.sync(store)
        XCTAssertFalse(ran)

        await backend.setStatus(.available)
        ran = await engine.sync(store)
        XCTAssertTrue(ran, "engine recovers once iCloud becomes available")
        XCTAssertEqual(store.records.map { $0.id }.sorted(), ["a", "b"])
    }
}
