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
        // Sub routing proof via the sub's command seam; poly path no-crash.
        rack.noteOn(slot: 1, pitch: 33, velocity: 0.8)
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.kind, "on")
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.pitch, 33)
        rack.noteOn(slot: 2, pitch: 60, velocity: 0.8)
        // Note-OFF routes to the CURRENT binding only (audio review MEDIUM on
        // 89814a2: a fan to all subs could cut a foreign lane's held note).
        rack.noteOff(slot: 0, pitch: 36)   // drums-bound → kit no-op
        XCTAssertEqual(rack.subs[0].noteCommandCountForTests, 1,
                       "a drums slot's off must NOT reach the sub")
        rack.noteOff(slot: 1, pitch: 33)   // sub-bound → matching off
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.kind, "off")
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.pitch, 33)
    }

    func testMidiVelocityMapping_edges() {
        XCTAssertEqual(LaneVoiceRack.midiVelocity(1.0), 127)
        XCTAssertEqual(LaneVoiceRack.midiVelocity(0.0), 0)
        XCTAssertEqual(LaneVoiceRack.midiVelocity(0.5), 64, "0.5 × 127 = 63.5 rounds to 64")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(1.5), 127, "over-range clamps")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(-1.0), 0, "under-range clamps")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(.nan), 0, "non-finite fails silent")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(.infinity), 0)
    }

    func testRebind_releasesThePreviouslyBoundSub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(kits: [], subs: [sub])
        rack.setKind(slot: 0, kind: .subBass)
        rack.noteOn(slot: 0, pitch: 40, velocity: 0.9)
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "on")
        rack.setKind(slot: 0, kind: .poly)   // rebind ⇒ old voice released
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "allOff",
                       "carry (b): rebind must allNotesOff the previously bound voice")
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0))
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
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(kits: [], subs: [sub])
        rack.setKind(slot: 0, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .subBass(0))
        rack.setTranspose(slot: 0, semitones: -12)
        rack.noteOn(slot: 0, pitch: 45, velocity: 0.9)
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 33, "sub is pitched at enqueue (45−12)")
        rack.setTranspose(slot: 0, semitones: 0)
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "allOff",
                       "shift change while sub-bound must release (off-matching law)")
        rack.noteOff(slot: 0, pitch: 45)                  // off at NEW shift — harmless
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 45, "off carries the current shift")
    }

    // MARK: - S2-W2-5 bus-insert + tuning fans

    func testBusFans_emptyRack_areSafeNoOps() {
        // flag-OFF shape: no kits/subs ⇒ the .drums/.bass/tuning fans touch nothing.
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        rack.setDrumsInsert(TrackFX(filter: .lowPass, cutoffHz: 800, resonance: 1.0, drive: 0.2))
        rack.setBassInsert(TrackFX(filter: .lowPass, cutoffHz: 120, resonance: 0.8, drive: 0.1))
        rack.setTuning(a4Hz: 432)
        XCTAssertTrue(rack.kits.isEmpty)
        XCTAssertTrue(rack.subs.isEmpty)
    }

    func testSetDrumsInsert_fansToEveryKit() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2)])
        let kit = LaneDrumKitVoice()
        rack.installKindUnitsForTests(kits: [kit], subs: [])
        let fx = TrackFX(filter: .highPass, cutoffHz: 300, resonance: 1.2, drive: 0.4)
        rack.setDrumsInsert(fx)
        XCTAssertEqual(kit.lastInsertForTests, fx, "drums bus insert must reach the kit")
    }

    func testSetBassInsert_andTuning_fanToEverySub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2)])
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(kits: [], subs: [sub])
        let fx = TrackFX(filter: .lowPass, cutoffHz: 90, resonance: 0.7, drive: 0.15)
        rack.setBassInsert(fx)
        XCTAssertEqual(sub.lastInsertForTests, fx, "bass bus insert must reach the sub")
        rack.setTuning(a4Hz: 432)
        XCTAssertEqual(sub.lastTuningForTests ?? -1, 432, accuracy: 1e-6,
                       "concert pitch must reach the lane sub (in tune at A=432)")
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
