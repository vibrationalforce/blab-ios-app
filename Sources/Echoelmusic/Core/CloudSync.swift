// CloudSync.swift
// Echoel — Phase 0 of CloudKit sync: the pure, backend-agnostic foundation.
//
// Projects, patches and sessions are already plain Codable JSON behind
// AppGroupStore. This layer lets those stores sync to a cloud backend WITHOUT
// binding to CloudKit yet: a small protocol the real CKContainer adapter will
// implement in Phase 1 (after the owner registers the iCloud container and
// enables the entitlement). Everything here is Foundation-only, local-first, and
// fully unit-tested against an in-memory mock — no iCloud account required.
//
// Design rules (from scratchpads/PLAN_CLOUDKIT_SYNC.md):
//   • Local store stays the source of truth; cloud is an additive mirror.
//   • Last-writer-wins per record by `modifiedAt` (ties keep local — no data loss
//     surprise from a clock skew that favours the server).
//   • If iCloud is unavailable / signed-out, the engine NO-OPS. It never blocks
//     the app and never throws into the UI.

import Foundation

/// One syncable item: a stable id, its store type, a modification time (for
/// conflict resolution) and the encoded model payload.
public struct SyncRecord: Sendable, Equatable, Identifiable {
    public var id: String
    public var type: String
    public var modifiedAt: Date
    public var payload: Data

    public init(id: String, type: String, modifiedAt: Date, payload: Data) {
        self.id = id
        self.type = type
        self.modifiedAt = modifiedAt
        self.payload = payload
    }
}

/// Last-writer-wins conflict resolution.
public enum SyncConflict {
    /// Returns whichever record was modified more recently; on a tie, local wins
    /// (deterministic, avoids server-clock-skew data loss).
    public static func resolve(local: SyncRecord, remote: SyncRecord) -> SyncRecord {
        remote.modifiedAt > local.modifiedAt ? remote : local
    }

    /// Merge two record sets by id using `resolve`. Records present on only one
    /// side are kept. Output is sorted by id for determinism.
    public static func merge(local: [SyncRecord], remote: [SyncRecord]) -> [SyncRecord] {
        var byID: [String: SyncRecord] = [:]
        for r in local { byID[r.id] = r }
        for r in remote {
            if let existing = byID[r.id] {
                byID[r.id] = resolve(local: existing, remote: r)
            } else {
                byID[r.id] = r
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }
}

/// iCloud availability. The engine only syncs when `.available`.
public enum CloudAccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, unknown
}

/// The cloud backend the engine talks to. The real CloudKit private-DB adapter
/// (Phase 1) conforms to this; tests use an in-memory mock. Sendable + async so
/// it never blocks the main actor.
public protocol CloudBackend: Sendable {
    func accountStatus() async -> CloudAccountStatus
    func fetch(type: String) async throws -> [SyncRecord]
    func save(_ records: [SyncRecord]) async throws
}

/// A local store that can be synced: it exposes its records and accepts a merged
/// set back. The existing @MainActor stores (PatchStore, ClipStore, …) will
/// conform in Phase 1.
@MainActor
public protocol SyncableStore: AnyObject {
    var recordType: String { get }
    func exportRecords() -> [SyncRecord]
    func importMerged(_ records: [SyncRecord])
}

/// Orchestrates a local-first sync: pull remote, merge (LWW), push the merged set,
/// hand the merge back to the local store. No-ops when iCloud is unavailable.
@MainActor
public final class CloudSyncEngine {

    private let backend: CloudBackend
    public private(set) var lastStatus: CloudAccountStatus = .unknown
    public private(set) var lastSyncedAt: Date?

    public init(backend: CloudBackend) {
        self.backend = backend
    }

    /// Sync one store. Returns true if a sync actually ran (iCloud available),
    /// false if it no-oped. Never throws into the caller — failures are swallowed
    /// so the app keeps working offline.
    @discardableResult
    public func sync(_ store: SyncableStore) async -> Bool {
        let status = await backend.accountStatus()
        lastStatus = status
        guard status == .available else { return false }

        do {
            let local = store.exportRecords()
            let remote = try await backend.fetch(type: store.recordType)
            let merged = SyncConflict.merge(local: local, remote: remote)
            // Only push what changed relative to remote (cheap delta).
            let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
            let toPush = merged.filter { remoteByID[$0.id] != $0 }
            if !toPush.isEmpty { try await backend.save(toPush) }
            store.importMerged(merged)
            lastSyncedAt = Date()
            return true
        } catch {
            // Offline / transient CloudKit error → keep local, try again later.
            return false
        }
    }
}
