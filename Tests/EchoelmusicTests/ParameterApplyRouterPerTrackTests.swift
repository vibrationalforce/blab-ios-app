// ParameterApplyRouterPerTrackTests.swift
// Automation-in-Spur L2/L4 S2b: the router's per-track dispatch branch. The pure
// resolver (PerTrackAutomationResolver) is pinned elsewhere; here we pin the WIRE —
// that applyNormalized routes a "track.<laneID>.<base>" keyPath to the injected
// per-track setter with the resolved slot/base/real value, leaves the global path
// untouched, and stays a byte-identical no-op until bindPerTrack is called.

import XCTest
@testable import Echoelmusic

@MainActor
final class ParameterApplyRouterPerTrackTests: XCTestCase {

    /// Records per-track setter calls; `applied` decides the return value.
    private final class Recorder {
        var calls: [(slot: Int, base: String, real: Float)] = []
        var applied = true
        func take(_ slot: Int, _ base: String, _ real: Float) -> Bool {
            calls.append((slot, base, real)); return applied
        }
    }

    private func makeRegistry() -> EchoelParameterRegistry {
        let r = EchoelParameterRegistry()
        r.register(DDSPParameterCatalog.descriptors)
        return r
    }

    // Bio + roll(primary) + two secondary MIDI lanes → sec[0] at slot 0, sec[1] at slot 1.
    private func makeDoc() -> (TimelineDocument, roll: UUID, sec: [UUID]) {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let s1 = TimelineLane(name: "MIDI 2", kind: .midi)
        let s2 = TimelineLane(name: "MIDI 3", kind: .midi)
        return (TimelineDocument(lanes: [bio, roll, s1, s2], regions: []), roll.id, [s1.id, s2.id])
    }

    private func wiredRouter(_ rec: Recorder, doc: TimelineDocument, roll: UUID, capacity: Int = 4)
        -> ParameterApplyRouter {
        let router = ParameterApplyRouter(registry: makeRegistry())
        router.bindPerTrack(
            context: { ParameterApplyRouter.PerTrackContext(document: doc, rollLane: roll, capacity: capacity) },
            setter: { rec.take($0, $1, $2) })
        return router
    }

    // MARK: - Happy path

    func testPerTrackKeyPath_dispatchesResolvedSlotBaseValue() {
        let (doc, roll, sec) = makeDoc()
        let rec = Recorder()
        let router = wiredRouter(rec, doc: doc, roll: roll)
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff")

        let applied = router.applyNormalized(kp, 0.5)

        XCTAssertEqual(rec.calls.count, 1)
        XCTAssertEqual(rec.calls.first?.slot, 0)
        XCTAssertEqual(rec.calls.first?.base, "ddsp.filter.cutoff")
        XCTAssertEqual(rec.calls.first?.real ?? -1, 9010, accuracy: 1e-3)   // [20,18000] @ 0.5
        XCTAssertEqual(applied ?? -1, 9010, accuracy: 1e-3)
    }

    func testSecondLane_dispatchesSlotOne() {
        let (doc, roll, sec) = makeDoc()
        let rec = Recorder()
        let router = wiredRouter(rec, doc: doc, roll: roll)
        let kp = PerTrackParameterKeyPath.make(laneID: sec[1], base: "ddsp.amp.level")

        _ = router.applyNormalized(kp, 1.0)

        XCTAssertEqual(rec.calls.first?.slot, 1)
        XCTAssertEqual(rec.calls.first?.real ?? -1, 1.0, accuracy: 1e-6)   // amp [0,1]
    }

    // MARK: - Golden gate: per-track is a no-op until wired

    func testPerTrackKeyPath_unwired_isNoOp() {
        let (_, _, sec) = makeDoc()
        let router = ParameterApplyRouter(registry: makeRegistry())   // no bindPerTrack
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff")
        XCTAssertNil(router.applyNormalized(kp, 0.5))
    }

    // MARK: - Global path is untouched by the branch

    func testGlobalKeyPath_stillUsesGlobalSetter() {
        let (doc, roll, _) = makeDoc()
        let rec = Recorder()
        let router = wiredRouter(rec, doc: doc, roll: roll)
        var globalReal: Float?
        router.bind("ddsp.filter.cutoff") { globalReal = $0 }

        let applied = router.applyNormalized("ddsp.filter.cutoff", 0.5)

        XCTAssertEqual(applied ?? -1, 9010, accuracy: 1e-3)
        XCTAssertEqual(globalReal ?? -1, 9010, accuracy: 1e-3)
        XCTAssertTrue(rec.calls.isEmpty, "a global keyPath must not touch the per-track setter")
    }

    // MARK: - No-op cases still return nil (never a foreign write)

    func testForeignLane_returnsNil_andDoesNotCallSetter() {
        let (doc, roll, _) = makeDoc()
        let rec = Recorder()
        let router = wiredRouter(rec, doc: doc, roll: roll)
        // roll lane owns no rack slot; unknown UUID is deleted/foreign.
        XCTAssertNil(router.applyNormalized(
            PerTrackParameterKeyPath.make(laneID: roll, base: "ddsp.filter.cutoff"), 0.5))
        XCTAssertNil(router.applyNormalized(
            PerTrackParameterKeyPath.make(laneID: UUID(), base: "ddsp.filter.cutoff"), 0.5))
        XCTAssertTrue(rec.calls.isEmpty)
    }

    func testSetterReportsNoLiveVoice_returnsNil() {
        let (doc, roll, sec) = makeDoc()
        let rec = Recorder()
        rec.applied = false   // resolved a slot, but no live voice took the write
        let router = wiredRouter(rec, doc: doc, roll: roll)
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff")

        XCTAssertNil(router.applyNormalized(kp, 0.5))
        XCTAssertEqual(rec.calls.count, 1, "the setter was still consulted")
    }
}
