// TimelineStoreDebounceTests.swift
// Echoel — task #56 C6 (scratchpads/AUDIT_CLIP_JITTER_2026-07-16.md): the disk
// write behind TimelineStore.persist() is now debounced (trailing-edge — only the
// LAST scheduled write of a rapid burst hits the file system), while the in-memory
// document + onDocumentChanged callback stay fully synchronous, unchanged timing.
//
// Isolation (established idiom — see TimelineStoreAutomationEditTests.swift):
// AppGroupStore falls back to Application Support in CI/SwiftPM, and every
// TimelineStore shares the SAME on-disk "timeline" file — so assertions here
// never touch absolute document counts, only a specifically-created, uniquely
// named lane looked up by its own ID.

import XCTest
@testable import Echoelmusic

final class TimelineStoreDebounceTests: XCTestCase {

    @MainActor
    func testRapidMutations_debounce_onlyFinalValueEventuallyPersists() async throws {
        let store = TimelineStore()
        store.saveDebounceInterval = .milliseconds(20)
        let laneName = "debounce-test-\(UUID().uuidString)"
        store.addLane(kind: .midi, name: laneName)
        guard let laneID = store.document.lanes.last(where: { $0.name == laneName })?.id else {
            return XCTFail("addLane did not append the lane")
        }

        // A rapid burst — the kind of thing a clip drag fires many times a second.
        store.setLaneLevel(id: laneID, 0.2)
        store.setLaneLevel(id: laneID, 0.5)
        store.setLaneLevel(id: laneID, 0.9)

        // onDocumentChanged/document mutation are synchronous — no wait needed to
        // observe the FINAL in-memory value immediately.
        XCTAssertEqual(store.document.lanes.first { $0.id == laneID }?.level, 0.9,
                       accuracy: 1e-6, "in-memory document must update synchronously")

        // The debounced disk write needs time to land.
        try? await Task.sleep(for: .milliseconds(120))

        let onDisk = AppGroupStore(subdirectory: "Timeline").load(TimelineDocument.self, name: "timeline")
        let persistedLane = onDisk?.lanes.first { $0.id == laneID }
        XCTAssertEqual(persistedLane?.level, 0.9, accuracy: 1e-6,
                       "only the LAST value of the burst should ever reach disk")
    }

    @MainActor
    func testFlushPendingSave_writesImmediately_withoutWaitingForDebounce() {
        let store = TimelineStore()
        store.saveDebounceInterval = .seconds(30)   // would never fire within the test
        let laneName = "flush-test-\(UUID().uuidString)"
        store.addLane(kind: .audio, name: laneName)
        guard let laneID = store.document.lanes.last(where: { $0.name == laneName })?.id else {
            return XCTFail("addLane did not append the lane")
        }
        store.setLaneLevel(id: laneID, 1.4)

        store.flushPendingSave()

        let onDisk = AppGroupStore(subdirectory: "Timeline").load(TimelineDocument.self, name: "timeline")
        let persistedLane = onDisk?.lanes.first { $0.id == laneID }
        XCTAssertEqual(persistedLane?.level, 1.4, accuracy: 1e-6,
                       "flushPendingSave must write the current document immediately")
    }

    @MainActor
    func testFlushPendingSave_invalidatesAnAlreadyScheduledDebouncedWrite() async throws {
        // A debounced write that was scheduled BEFORE flushPendingSave() must not
        // clobber a later, different document state once it eventually wakes.
        let store = TimelineStore()
        store.saveDebounceInterval = .milliseconds(30)
        let laneName = "invalidate-test-\(UUID().uuidString)"
        store.addLane(kind: .midi, name: laneName)
        guard let laneID = store.document.lanes.last(where: { $0.name == laneName })?.id else {
            return XCTFail("addLane did not append the lane")
        }

        store.setLaneLevel(id: laneID, 0.3)   // schedules a debounced write of 0.3
        store.setLaneLevel(id: laneID, 1.1)   // mutate again, then flush immediately
        store.flushPendingSave()

        // Wait past the FIRST debounce's original deadline — if it were not
        // invalidated, it would now try to write its stale generation.
        try? await Task.sleep(for: .milliseconds(80))

        let onDisk = AppGroupStore(subdirectory: "Timeline").load(TimelineDocument.self, name: "timeline")
        let persistedLane = onDisk?.lanes.first { $0.id == laneID }
        XCTAssertEqual(persistedLane?.level, 1.1, accuracy: 1e-6,
                       "a stale, superseded debounced write must never land after a flush")
    }
}
