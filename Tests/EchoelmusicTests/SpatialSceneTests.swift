// SpatialSceneTests.swift
// Echoel — S1 of the spatial expansion: the scene document must clamp bad
// coordinates, round-trip through its wire format (Codable), and diff/apply
// deterministically — peers converge on identical state or the protocol lies.

import XCTest
@testable import Echoelmusic

final class SpatialSceneTests: XCTestCase {

    // MARK: - Position clamping (bounds are the protocol contract)

    func testPositionClampsToProtocolBounds() {
        let p = SpatialPosition(azimuth: 200, elevation: -120, distance: 2)
        XCTAssertEqual(p.azimuth, 180)
        XCTAssertEqual(p.elevation, -90)
        XCTAssertEqual(p.distance, 1)

        let q = SpatialPosition(azimuth: -181, elevation: 95, distance: -0.5)
        XCTAssertEqual(q.azimuth, -180)
        XCTAssertEqual(q.elevation, 90)
        XCTAssertEqual(q.distance, 0)
    }

    func testPositionNonFiniteCollapsesToSafeDefault() {
        let p = SpatialPosition(azimuth: .nan, elevation: .infinity, distance: .nan)
        XCTAssertEqual(p.azimuth, 0)
        XCTAssertEqual(p.elevation, 0)
        XCTAssertEqual(p.distance, 0)
    }

    func testObjectClampsUnitFields() {
        let o = SpatialObject(id: "x", extent: 2, gain: -1, roomSend: .nan)
        XCTAssertEqual(o.extent, 1)
        XCTAssertEqual(o.gain, 0)
        XCTAssertEqual(o.roomSend, 0)
    }

    // MARK: - Cartesian derivation (ADM: x right, y front, z up; +az = left)

    func testCartesianFrontUnit() {
        let c = SpatialPosition.front.cartesian
        XCTAssertEqual(c.x, 0, accuracy: 1e-5)
        XCTAssertEqual(c.y, 1, accuracy: 1e-5)
        XCTAssertEqual(c.z, 0, accuracy: 1e-5)
    }

    func testCartesianLeftIsNegativeX() {
        // ADM: +90° azimuth = hard LEFT = -x (x axis points right).
        let c = SpatialPosition(azimuth: 90, elevation: 0, distance: 1).cartesian
        XCTAssertEqual(c.x, -1, accuracy: 1e-5)
        XCTAssertEqual(c.y, 0, accuracy: 1e-5)
        XCTAssertEqual(c.z, 0, accuracy: 1e-5)
    }

    func testCartesianZenith() {
        let c = SpatialPosition(azimuth: 0, elevation: 90, distance: 1).cartesian
        XCTAssertEqual(c.x, 0, accuracy: 1e-5)
        XCTAssertEqual(c.y, 0, accuracy: 1e-5)
        XCTAssertEqual(c.z, 1, accuracy: 1e-5)
    }

    // MARK: - Codable round-trip (wire format)

    func testSceneCodableRoundTrip() throws {
        var scene = SpatialScene(room: RoomModel(width: 12, depth: 15, height: 6,
                                                 decayTime: 2.0, diffusion: 0.5))
        scene.upsert(SpatialObject(id: "voice-1",
                                   position: SpatialPosition(azimuth: -30, elevation: 10, distance: 0.8),
                                   extent: 0.1, gain: 0.9, roomSend: 0.3,
                                   motionRef: "orbit-a", visualRef: nil,
                                   ownerPeer: "peer-abc"))
        scene.upsert(SpatialObject(id: "sub-1"))

        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(SpatialScene.self, from: data)
        XCTAssertEqual(decoded, scene)
        XCTAssertEqual(decoded.version, SpatialScene.schemaVersion)
        XCTAssertEqual(decoded.revision, scene.revision)
    }

    func testDiffCodableRoundTrip() throws {
        let old = SpatialScene()
        var new = old
        new.upsert(SpatialObject(id: "a"))
        let diff = new.diff(from: old)

        let data = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(SpatialScene.Diff.self, from: data)
        XCTAssertEqual(decoded, diff)
    }

    // MARK: - Revision (peers order by revision, not wall-clock)

    func testRevisionBumpsOnMutationOnly() {
        var scene = SpatialScene()
        XCTAssertEqual(scene.revision, 0)

        scene.upsert(SpatialObject(id: "a"))
        XCTAssertEqual(scene.revision, 1)

        // Upserting the identical object is a no-op — no bump.
        scene.upsert(SpatialObject(id: "a"))
        XCTAssertEqual(scene.revision, 1)

        var changed = SpatialObject(id: "a")
        changed.gain = 0.5
        scene.upsert(changed)
        XCTAssertEqual(scene.revision, 2)

        scene.removeObject(id: "missing")
        XCTAssertEqual(scene.revision, 2)

        scene.removeObject(id: "a")
        XCTAssertEqual(scene.revision, 3)

        scene.room.decayTime = 3
        XCTAssertEqual(scene.revision, 4)
    }

    // MARK: - Diff / apply convergence

    func testDiffDetectsAddRemoveChangeAndRoom() {
        var old = SpatialScene()
        old.upsert(SpatialObject(id: "keep"))
        old.upsert(SpatialObject(id: "drop"))
        old.upsert(SpatialObject(id: "edit"))

        var new = old
        new.removeObject(id: "drop")
        var edited = SpatialObject(id: "edit")
        edited.position = SpatialPosition(azimuth: 45, elevation: 0, distance: 0.5)
        new.upsert(edited)
        new.upsert(SpatialObject(id: "fresh"))
        new.room.diffusion = 0.9

        let diff = new.diff(from: old)
        XCTAssertEqual(diff.added.map(\.id), ["fresh"])
        XCTAssertEqual(diff.removed, ["drop"])
        XCTAssertEqual(diff.changed.map(\.id), ["edit"])
        XCTAssertNotNil(diff.room)
        XCTAssertEqual(diff.toRevision, new.revision)
        XCTAssertFalse(diff.isEmpty)
    }

    func testIdenticalScenesDiffIsEmpty() {
        var scene = SpatialScene()
        scene.upsert(SpatialObject(id: "a"))
        let diff = scene.diff(from: scene)
        XCTAssertTrue(diff.isEmpty)
        XCTAssertNil(diff.order, "identical order → no order payload")
    }

    // Array position IS the ADM/IEM object index, so order must converge too.
    // A pure reorder produces an empty STRUCTURAL diff; without the order payload
    // the peers would silently disagree on which object is /adm/obj/1.
    func testPureReorder_convergesAndIsNotEmpty() {
        var old = SpatialScene()
        old.upsert(SpatialObject(id: "A"))
        old.upsert(SpatialObject(id: "B"))       // [A, B]
        var new = SpatialScene()
        new.upsert(SpatialObject(id: "B"))
        new.upsert(SpatialObject(id: "A"))       // [B, A]

        let diff = new.diff(from: old)
        XCTAssertFalse(diff.isEmpty, "a reorder is a real change to send")
        XCTAssertEqual(diff.added, [])
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.changed, [])
        XCTAssertEqual(diff.order, ["B", "A"])

        let converged = old.applying(diff)
        XCTAssertEqual(converged.objects.map(\.id), ["B", "A"], "peer converges on the new order")
        XCTAssertEqual(converged.revision, new.revision)
    }

    // Add/remove that also shifts positions: order still converges exactly.
    func testAddRemove_reordersToTarget() {
        var old = SpatialScene()
        old.upsert(SpatialObject(id: "A"))
        old.upsert(SpatialObject(id: "B"))
        old.upsert(SpatialObject(id: "C"))       // [A, B, C]

        var new = SpatialScene()                 // built in a different order
        new.upsert(SpatialObject(id: "C"))
        new.upsert(SpatialObject(id: "A"))
        new.upsert(SpatialObject(id: "D"))       // [C, A, D]  (B removed, D added)

        let converged = old.applying(new.diff(from: old))
        XCTAssertEqual(converged.objects.map(\.id), ["C", "A", "D"])
        XCTAssertEqual(converged, new)
    }

    func testApplyingDiffReproducesNewScene() {
        var old = SpatialScene()
        old.upsert(SpatialObject(id: "keep"))
        old.upsert(SpatialObject(id: "drop"))

        var new = old
        new.removeObject(id: "drop")
        new.upsert(SpatialObject(id: "fresh",
                                 position: SpatialPosition(azimuth: -90, elevation: 30, distance: 1)))
        new.room.decayTime = 4

        let converged = old.applying(new.diff(from: old))
        XCTAssertEqual(converged, new)
        XCTAssertEqual(converged.revision, new.revision)
    }

    // MARK: - Roles (P2 capability matrix — the protocol's permission table)

    func testRoleCapabilityMatrix() {
        XCTAssertTrue(SpatialRole.author.canEditScene)
        XCTAssertTrue(SpatialRole.author.canAdjustMix)
        XCTAssertTrue(SpatialRole.author.canPerform)

        XCTAssertFalse(SpatialRole.performer.canEditScene)
        XCTAssertFalse(SpatialRole.performer.canAdjustMix)
        XCTAssertTrue(SpatialRole.performer.canPerform)

        XCTAssertFalse(SpatialRole.mixControl.canEditScene)
        XCTAssertTrue(SpatialRole.mixControl.canAdjustMix)
        XCTAssertFalse(SpatialRole.mixControl.canPerform)

        XCTAssertTrue(SpatialRole.renderer.rendersOutput)
        for role in SpatialRole.allCases where role != .renderer {
            XCTAssertFalse(role.rendersOutput, "\(role) must not render")
        }

        let obs = SpatialRole.observer
        XCTAssertFalse(obs.canEditScene)
        XCTAssertFalse(obs.canAdjustMix)
        XCTAssertFalse(obs.canPerform)
        XCTAssertFalse(obs.rendersOutput)
    }

    func testRoleRawValuesAreWireStable() {
        // These strings are the protocol contract (ECHOEL_SESSION_PROTOCOL.md).
        XCTAssertEqual(SpatialRole.author.rawValue, "author")
        XCTAssertEqual(SpatialRole.performer.rawValue, "performer")
        XCTAssertEqual(SpatialRole.renderer.rawValue, "renderer")
        XCTAssertEqual(SpatialRole.mixControl.rawValue, "mixControl")
        XCTAssertEqual(SpatialRole.observer.rawValue, "observer")
    }
}
