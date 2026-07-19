// PerTrackAutomationResolverTests.swift
// L2/L4 S2b-prep: pins the pure composition (parse keyPath + resolve laneID→slot
// at dispatch time + denormalize) that turns the device wiring into a thin shell.
// Every no-op case (global keyPath, foreign/deleted/overflow lane, unknown param)
// is asserted here so the device layer can trust a non-nil result.

import XCTest
@testable import Echoelmusic

final class PerTrackAutomationResolverTests: XCTestCase {

    // Bio + roll(primary) + two secondary MIDI lanes → sec[0] at slot 0, sec[1] at slot 1.
    private func makeDoc() -> (TimelineDocument, roll: UUID, sec: [UUID]) {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let s1 = TimelineLane(name: "MIDI 2", kind: .midi)
        let s2 = TimelineLane(name: "MIDI 3", kind: .midi)
        let doc = TimelineDocument(lanes: [bio, roll, s1, s2], regions: [])
        return (doc, roll.id, [s1.id, s2.id])
    }

    private func lookup(_ base: String) -> ParameterDescriptor? {
        DDSPParameterCatalog.descriptors.first { $0.keyPath == base }
    }

    private func resolve(_ keyPath: String, _ n: Float, _ doc: TimelineDocument,
                         roll: UUID, capacity: Int = 4) -> PerTrackAutomationResolver.Resolved? {
        PerTrackAutomationResolver.resolve(keyPath: keyPath, normalized: n, document: doc,
                                           rollLane: roll, capacity: capacity,
                                           descriptor: lookup)
    }

    // MARK: - Happy path: resolves slot + base + denormalized value

    func testResolve_perTrackCutoff_resolvesSlotAndDenormalizedValue() {
        let (doc, roll, sec) = makeDoc()
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff")
        let r = resolve(kp, 0.5, doc, roll: roll)
        XCTAssertEqual(r?.slot, 0)
        XCTAssertEqual(r?.base, "ddsp.filter.cutoff")
        // cutoff range [20, 18000], 0.5 → 9010.
        XCTAssertEqual(r?.value ?? -1, 9010, accuracy: 1e-3)
    }

    func testResolve_secondLane_resolvesSlotOne() {
        let (doc, roll, sec) = makeDoc()
        let kp = PerTrackParameterKeyPath.make(laneID: sec[1], base: "ddsp.amp.level")
        let r = resolve(kp, 1.0, doc, roll: roll)
        XCTAssertEqual(r?.slot, 1)
        XCTAssertEqual(r?.base, "ddsp.amp.level")
        XCTAssertEqual(r?.value ?? -1, 1.0, accuracy: 1e-6)   // amp range [0,1]
    }

    func testResolve_denormalizationBounds() {
        let (doc, roll, sec) = makeDoc()
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff")
        XCTAssertEqual(resolve(kp, 0, doc, roll: roll)?.value ?? -1, 20, accuracy: 1e-3)
        XCTAssertEqual(resolve(kp, 1, doc, roll: roll)?.value ?? -1, 18_000, accuracy: 1e-3)
    }

    // MARK: - No-op cases (all return nil)

    func testResolve_globalKeyPath_returnsNil() {
        let (doc, roll, _) = makeDoc()
        XCTAssertNil(resolve("ddsp.filter.cutoff", 0.5, doc, roll: roll))
    }

    func testResolve_foreignOrDeletedLane_returnsNil() {
        let (doc, roll, _) = makeDoc()
        // roll lane owns no rack slot; an unknown UUID is a deleted/foreign lane.
        XCTAssertNil(resolve(PerTrackParameterKeyPath.make(laneID: roll, base: "ddsp.filter.cutoff"),
                             0.5, doc, roll: roll))
        XCTAssertNil(resolve(PerTrackParameterKeyPath.make(laneID: UUID(), base: "ddsp.filter.cutoff"),
                             0.5, doc, roll: roll))
    }

    func testResolve_overflowBeyondCapacity_returnsNil() {
        let (doc, roll, sec) = makeDoc()
        // sec[1] is rank 1; capacity 1 → no physical voice → no-op.
        let kp = PerTrackParameterKeyPath.make(laneID: sec[1], base: "ddsp.filter.cutoff")
        XCTAssertNil(resolve(kp, 0.5, doc, roll: roll, capacity: 1))
        // sec[0] still resolves at capacity 1.
        XCTAssertEqual(resolve(PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.filter.cutoff"),
                               0.5, doc, roll: roll, capacity: 1)?.slot, 0)
    }

    func testResolve_unknownBaseParameter_returnsNil() {
        let (doc, roll, sec) = makeDoc()
        let kp = PerTrackParameterKeyPath.make(laneID: sec[0], base: "ddsp.does.notexist")
        XCTAssertNil(resolve(kp, 0.5, doc, roll: roll))
    }

    /// Pins the isBio exclusion directly: a bio lane owns no secondary rack slot,
    /// so a per-track write addressed to it is a no-op. Guards against a future
    /// change that stopped filtering bio lanes out of the secondary set.
    func testResolve_bioLane_returnsNil() throws {
        let (doc, roll, _) = makeDoc()
        let bioID = try XCTUnwrap(doc.lanes.first(where: { $0.isBio })?.id)
        let kp = PerTrackParameterKeyPath.make(laneID: bioID, base: "ddsp.filter.cutoff")
        XCTAssertNil(resolve(kp, 0.5, doc, roll: roll))
    }
}
