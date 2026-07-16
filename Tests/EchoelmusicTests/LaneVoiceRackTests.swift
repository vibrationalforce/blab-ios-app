// LaneVoiceRackTests.swift
// Echoel — pins the S2-W1 melodic-insert fan-out: LaneVoiceRack.setInsert must
// reach EVERY slot voice (review LOW from e73122c: the fan-out had no test).
// Voices are installed via the test seam (attachAll needs a live AudioEngine,
// which unit tests must not construct); PolySynthVoice construction alone adds
// no audio-graph node, so this runs on the Xcode gate without an engine.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class LaneVoiceRackTests: XCTestCase {

    func testSetInsert_unattached_isSafeNoOp() {
        let rack = LaneVoiceRack(capacity: 4)
        rack.setInsert(TrackFX(filter: .lowPass, cutoffHz: 900, resonance: 1.1, drive: 0.2))
        XCTAssertFalse(rack.isActive, "setInsert must not fake an attach")
        XCTAssertTrue(rack.voices.isEmpty, "no voice may be created outside attachAll")
    }

    func testSetInsert_fansOutToEveryVoice() {
        let rack = LaneVoiceRack(capacity: 3, maxVoicesPerSlot: 2)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        let fx = TrackFX(filter: .lowPass, cutoffHz: 750, resonance: 1.4, drive: 0.35)
        rack.setInsert(fx)
        XCTAssertEqual(rack.voices.count, 3)
        for (i, v) in rack.voices.enumerated() {
            XCTAssertEqual(v.appliedInsert, fx, "slot \(i) missed the melodic insert")
        }
    }

    func testVoiceSlot_boundsAndAttachGate() {
        let rack = LaneVoiceRack(capacity: 2)
        XCTAssertNil(rack.voice(slot: 0), "unattached rack must not vend voices")
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        XCTAssertNotNil(rack.voice(slot: 0))
        XCTAssertNotNil(rack.voice(slot: 1))
        XCTAssertNil(rack.voice(slot: 2), "out-of-range slot must be nil, not a crash")
        XCTAssertNil(rack.voice(slot: -1))
    }

    func testPolySynthVoice_setInsert_recordsAppliedInsert() {
        let v = PolySynthVoice(maxVoices: 2)
        XCTAssertNil(v.appliedInsert, "fresh voice has no insert memory")
        let fx = TrackFX(filter: .highPass, cutoffHz: 240, resonance: 0.9, drive: 0.1)
        v.setInsert(fx)
        XCTAssertEqual(v.appliedInsert, fx)
        v.setInsert(.off)
        XCTAssertEqual(v.appliedInsert, .off, "later writes win — memory mirrors the last call")
    }
}
#endif
