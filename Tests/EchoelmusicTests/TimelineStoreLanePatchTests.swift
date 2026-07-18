// #23 Slice S1 — per-lane SynthPatch authoring (persist-first, pure/Linux-CI).
// The store setter that lets each MIDI track carry its own optional timbre.
// The editor door (S2), the primary-lane sink (S2b) and the device-gated
// live-apply (S3) build on top of this — all this slice does is set/clear/persist
// `lane.patch` exactly like the other structural lane fields (sample/instrument),
// staying out of the region undo history.

import XCTest
@testable import Echoelmusic

final class TimelineStoreLanePatchTests: XCTestCase {

    @MainActor
    func testSetLanePatch_setsAndClears() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "Lead")
        guard let id = store.document.lanes.last?.id else { return XCTFail("no lane") }
        XCTAssertNil(store.document.lanes.last?.patch, "a fresh lane follows the global voice")

        let bright = SynthPatch(name: "Bright", brightness: 0.9)
        store.setLanePatch(id, patch: bright)
        XCTAssertEqual(store.document.lanes.last?.patch, bright)

        // Clearing = nil (back to the shared voice), not a decode failure.
        store.setLanePatch(id, patch: nil)
        XCTAssertNil(store.document.lanes.last?.patch)
    }

    @MainActor
    func testSetLanePatch_unknownID_noChange() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "Lead")
        guard let id = store.document.lanes.last?.id else { return XCTFail("no lane") }
        let dark = SynthPatch(name: "Dark", brightness: 0.1)
        store.setLanePatch(id, patch: dark)

        // A stale/unknown id must not crash and must not touch the real lane.
        store.setLanePatch(UUID(), patch: SynthPatch(name: "Other", brightness: 0.5))
        XCTAssertEqual(store.document.lanes.last?.patch, dark)
    }

    @MainActor
    func testSetLanePatch_leavesOtherLaneFieldsUntouched() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "Lead")
        guard let id = store.document.lanes.last?.id else { return XCTFail("no lane") }
        store.setLaneTranspose(id: id, 5)
        store.setLaneDetune(id: id, 12)
        store.setLaneLevel(id: id, 0.7)

        store.setLanePatch(id, patch: SynthPatch(name: "Warm", brightness: 0.4))

        XCTAssertEqual(store.document.lanes.last?.transposeSemitones, 5)
        XCTAssertEqual(store.document.lanes.last?.detuneCents, 12)
        XCTAssertEqual(store.document.lanes.last?.level, 0.7)
        XCTAssertEqual(store.document.lanes.last?.patch?.name, "Warm")
    }

    /// Lane fields are deliberately NOT in the region undo stack — a timbre choice
    /// must not be reverted by a region-level undo (matches setLaneGenreOverride /
    /// setLaneSample). Setting a patch must leave `canUndo` where it was.
    @MainActor
    func testSetLanePatch_doesNotEnterRegionUndoHistory() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "Lead")
        guard let id = store.document.lanes.last?.id else { return XCTFail("no lane") }
        let before = store.canUndo
        store.setLanePatch(id, patch: SynthPatch(name: "X", brightness: 0.6))
        XCTAssertEqual(store.canUndo, before, "a lane patch change is not a region-undo step")
    }
}
