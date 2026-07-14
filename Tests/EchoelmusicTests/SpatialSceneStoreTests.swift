// SpatialSceneStoreTests.swift
// The live immersive scene store: one SpatialObject per real (non-bio) track,
// placed by ImmersiveObjectDefaults, with user/automation moves preserved across
// a rebuild. @MainActor because the store is @MainActor @Observable.

import XCTest
@testable import Echoelmusic

@MainActor
final class SpatialSceneStoreTests: XCTestCase {

    private func lane(_ name: String,
                      instrument: TrackInstrument? = .polySynth,
                      isBio: Bool = false) -> TimelineLane {
        TimelineLane(name: name, kind: .midi, isBio: isBio, builtinInstrument: instrument)
    }

    // MARK: Rebuild → one object per real lane

    func testRebuildMakesOneObjectPerNonBioLane() {
        let store = SpatialSceneStore()
        let lanes = [lane("Pad"), lane("Bass", instrument: .subBass), lane("Drums", instrument: .drums)]
        store.rebuild(from: lanes)
        XCTAssertEqual(store.scene.objects.count, 3)
        for l in lanes {
            XCTAssertNotNil(store.object(forLane: l.id), "lane \(l.name) should have an object")
        }
    }

    func testBioLanesAreNeverObjects() {
        let store = SpatialSceneStore()
        let real = lane("Pad")
        let bio = lane("Herz", instrument: .bioVoice, isBio: true)
        store.rebuild(from: [real, bio])
        XCTAssertEqual(store.scene.objects.count, 1)
        XCTAssertNotNil(store.object(forLane: real.id))
        XCTAssertNil(store.object(forLane: bio.id))
    }

    // MARK: Default placement comes from ImmersiveObjectDefaults

    func testDefaultPlacementMatchesImmersiveDefaults() {
        let store = SpatialSceneStore()
        let lanes = [lane("A", instrument: .subBass), lane("B", instrument: .polySynth)]
        store.rebuild(from: lanes)
        let expectedSub = ImmersiveObjectDefaults.defaultObject(
            for: .subBass, laneID: lanes[0].id, laneIndex: 0, laneCount: 2)
        XCTAssertEqual(store.object(forLane: lanes[0].id), expectedSub)
    }

    // MARK: Moves survive a rebuild

    func testRebuildPreservesMovedPosition() {
        let store = SpatialSceneStore()
        let a = lane("A")
        let b = lane("B")
        store.rebuild(from: [a, b])
        let moved = SpatialPosition(azimuth: 123, elevation: 20, distance: 0.3)
        store.setPosition(laneID: a.id, moved)
        // Rebuild with the same lanes (e.g. after a mute toggle) must NOT reset A.
        store.rebuild(from: [a, b])
        XCTAssertEqual(store.object(forLane: a.id)?.position, moved)
    }

    func testRebuildPreservesMovedExtent() {
        let store = SpatialSceneStore()
        let a = lane("A")
        store.rebuild(from: [a])
        store.setExtent(laneID: a.id, 0.9)
        store.rebuild(from: [a])
        XCTAssertEqual(store.object(forLane: a.id)?.extent, 0.9, accuracy: 0.0001)
    }

    // MARK: Add / remove lanes

    func testAddedLaneGetsDefaultRemovedLaneDrops() {
        let store = SpatialSceneStore()
        let a = lane("A")
        let b = lane("B")
        store.rebuild(from: [a])
        XCTAssertEqual(store.scene.objects.count, 1)
        // Add b.
        store.rebuild(from: [a, b])
        XCTAssertEqual(store.scene.objects.count, 2)
        XCTAssertNotNil(store.object(forLane: b.id))
        // Remove a.
        store.rebuild(from: [b])
        XCTAssertEqual(store.scene.objects.count, 1)
        XCTAssertNil(store.object(forLane: a.id))
        XCTAssertNotNil(store.object(forLane: b.id))
    }

    // MARK: setPosition / setExtent

    func testSetPositionUpdatesObject() {
        let store = SpatialSceneStore()
        let a = lane("A")
        store.rebuild(from: [a])
        let p = SpatialPosition(azimuth: -45, elevation: -10, distance: 0.6)
        store.setPosition(laneID: a.id, p)
        XCTAssertEqual(store.object(forLane: a.id)?.position, p)
    }

    func testSetExtentUpdatesObject() {
        let store = SpatialSceneStore()
        let a = lane("A")
        store.rebuild(from: [a])
        store.setExtent(laneID: a.id, 0.42)
        XCTAssertEqual(store.object(forLane: a.id)?.extent, 0.42, accuracy: 0.0001)
    }

    func testSetPositionOnUnknownLaneIsNoOp() {
        let store = SpatialSceneStore()
        store.rebuild(from: [lane("A")])
        let before = store.scene.objects
        store.setPosition(laneID: UUID(), SpatialPosition(azimuth: 10, elevation: 0, distance: 1))
        XCTAssertEqual(store.scene.objects, before)
    }

    // MARK: nil builtinInstrument falls back to polySynth

    func testNilInstrumentFallsBackToPolySynth() {
        let store = SpatialSceneStore()
        let a = lane("A", instrument: nil)
        store.rebuild(from: [a])
        let expected = ImmersiveObjectDefaults.defaultObject(
            for: .polySynth, laneID: a.id, laneIndex: 0, laneCount: 1)
        XCTAssertEqual(store.object(forLane: a.id), expected)
    }
}
