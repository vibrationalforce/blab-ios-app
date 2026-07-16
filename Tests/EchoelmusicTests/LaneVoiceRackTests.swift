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

    // MARK: - S2-W2-3 kind-routing facade (pure allocation + routing laws)

    func testSetKind_zeroUnits_isTheFlagOffShape_allPoly() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        rack.setKind(slot: 0, kind: .drums)      // no kit units installed
        rack.setKind(slot: 1, kind: .subBass)    // no sub units installed
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0), "no units ⇒ poly fallback (today's sound)")
        XCTAssertEqual(rack.bindingsForTests[1], .poly(1))
    }

    func testSetKind_bindsKitAndSub_andNoteOnRoutesToTheKit() {
        let rack = LaneVoiceRack(capacity: 3)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        let kit = LaneDrumKitVoice()
        rack.installKindUnitsForTests(kits: [kit], subs: [SubBassVoice()])
        rack.setKind(slot: 0, kind: .drums)
        rack.setKind(slot: 1, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .drums(0))
        XCTAssertEqual(rack.bindingsForTests[1], .subBass(0))
        // Routing proof: a note-ON on the drums slot configures the kit's pad
        // (the kit's per-pad preset cache is the observable), not the poly slot.
        rack.noteOn(slot: 0, pitch: 36, velocity: 1.0)
        XCTAssertEqual(kit.appliedParamsForTests[DrumNoteMap.Pad.kick.rawValue],
                       DrumNoteMap.params(forPitch: 36))
        // Sub slot + poly slot note paths must be safe no-crash enqueues too.
        rack.noteOn(slot: 1, pitch: 33, velocity: 0.8)
        rack.noteOn(slot: 2, pitch: 60, velocity: 0.8)
        // Note-OFF fan (H5b): offs go to ALL bindable voices, harmlessly.
        rack.noteOff(slot: 0, pitch: 36)
        rack.noteOff(slot: 1, pitch: 33)
    }

    func testSetKind_lowerRankWinsContention_andRebindRestoresPoly() {
        let rack = LaneVoiceRack(capacity: 3)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(kits: [LaneDrumKitVoice()], subs: [])
        rack.setKind(slot: 2, kind: .drums)
        XCTAssertEqual(rack.bindingsForTests[2], .drums(0), "sole drums lane takes the kit")
        rack.setKind(slot: 0, kind: .drums)
        XCTAssertEqual(rack.bindingsForTests[0], .drums(0), "lower rank claims the kit on rebind")
        XCTAssertEqual(rack.bindingsForTests[2], .poly(2), "outbid lane falls back to poly, never silence")
        rack.setKind(slot: 0, kind: .poly)
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0))
        XCTAssertEqual(rack.bindingsForTests[2], .drums(0), "freed kit returns to the remaining drums lane")
    }

    func testFacade_unattached_isSafeNoOp() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.setKind(slot: 0, kind: .drums)
        XCTAssertTrue(rack.bindingsForTests.isEmpty, "setKind must gate on attach")
        rack.noteOn(slot: 0, pitch: 36, velocity: 1.0)   // routes nowhere, no crash
        rack.noteOff(slot: 0, pitch: 36)
        rack.setGain(slot: 0, 1.0)
        rack.setPan(slot: 0, 0.5)
        rack.setTranspose(slot: 0, semitones: 12)
        rack.setDetune(slot: 0, cents: 10)
    }

    func testTranspose_pitchesSubAtEnqueue_andChangeReleasesHeldSub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(kits: [], subs: [SubBassVoice()])
        rack.setKind(slot: 0, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .subBass(0))
        rack.setTranspose(slot: 0, semitones: -12)
        rack.noteOn(slot: 0, pitch: 45, velocity: 0.9)   // enqueues 33 (45−12)
        rack.setTranspose(slot: 0, semitones: 0)          // change ⇒ allNotesOff (no strand)
        rack.noteOff(slot: 0, pitch: 45)                  // off at NEW shift — harmless
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
