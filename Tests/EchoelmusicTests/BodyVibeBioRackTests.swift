// BodyVibeBioRackTests.swift
// BodyVibe B1 (PLAN_BODYVIBE_TRACK_PANEL_2026-07-17 §B) — the last v1 deferral
// falls: a .bioVoice lane binds a REAL lane BioReactiveSynthVoice rack unit.
// Pins, at the logic level (no audio render, no engine):
//   1. KindVoiceAllocator vends .bio refs (capacity, exhaustion fallback,
//      and the pre-B1 default shape bioUnits == 0 ⇒ poly).
//   2. LaneVoiceRack facade: setKind(.bioVoice) binds .bio(0); the sequencer
//      GATE (noteOn → envelope open, matching noteOff / rebind → released);
//      mono last-note-wins (a stale off never cuts the newer note).
//   3. Mixer stage clamps: lane gain 0…2 (non-finite ⇒ 0), pan −1…1.
// Units are installed via the Debug test seams (attachAll needs a live
// AudioEngine, which unit tests must not construct); BioReactiveSynthVoice
// construction alone adds no audio-graph node.

#if canImport(AVFoundation) && canImport(Accelerate)
import AVFoundation
import XCTest
@testable import Echoelmusic

@MainActor
final class BodyVibeBioRackTests: XCTestCase {

    // MARK: - Allocator (pure)

    func testAllocator_bioVoice_bindsBioUnit() {
        let out = KindVoiceAllocator.allocate(
            ordered: [(slot: 0, kind: .bioVoice), (slot: 1, kind: .poly)],
            subUnits: 0, samplerUnits: 0, bioUnits: 1)
        XCTAssertEqual(out[0], .bio(0), "a bio lane must bind the bio unit")
        XCTAssertEqual(out[1], .poly(1))
    }

    func testAllocator_bioCapacity_firstRankWins_secondFallsBackPoly() {
        // Input order deliberately reversed — contention resolves by RANK.
        let out = KindVoiceAllocator.allocate(
            ordered: [(slot: 2, kind: .bioVoice), (slot: 0, kind: .bioVoice)],
            subUnits: 0, samplerUnits: 0, bioUnits: 1)
        XCTAssertEqual(out[0], .bio(0), "lowest rank takes the one bio unit")
        XCTAssertEqual(out[2], .poly(2), "exhausted kind falls back to poly — never silence")
    }

    func testAllocator_defaultBioUnitsZero_keepsTheFormerDeferralShape() {
        // bioUnits defaults to 0, so every pre-B1 call site is bit-identical:
        // a bio lane resolves to poly exactly as during the v1 deferral.
        let out = KindVoiceAllocator.allocate(
            ordered: [(slot: 0, kind: .bioVoice)],
            subUnits: 1, samplerUnits: 1)
        XCTAssertEqual(out[0], .poly(0))
    }

    // MARK: - Rack binding + sequencer gate

    private func makeBioRack(capacity: Int = 2) -> (LaneVoiceRack, BioReactiveSynthVoice) {
        let rack = LaneVoiceRack(capacity: capacity)
        rack.installVoicesForTests((0..<capacity).map { _ in PolySynthVoice(maxVoices: 2) })
        let bio = BioReactiveSynthVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [], bios: [bio])
        return (rack, bio)
    }

    func testSetKind_bioVoice_bindsBioRef() {
        let (rack, _) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        XCTAssertEqual(rack.bindingsForTests[0], .bio(0))
    }

    func testSetKind_bioVoice_withoutBioUnit_fallsBackPoly_andNoteOnIsSafe() {
        let rack = LaneVoiceRack(capacity: 1)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2)])
        rack.installKindUnitsForTests(subs: [])   // zero bio units
        rack.setKind(slot: 0, kind: .bioVoice)
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0),
                       "no bio unit ⇒ poly fallback (the flag-OFF / pre-B1 sound)")
        rack.noteOn(slot: 0, pitch: 60, velocity: 0.8)   // must not crash
        rack.noteOff(slot: 0, pitch: 60)
    }

    func testGate_noteOnOpens_matchingNoteOffCloses() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        XCTAssertFalse(bio.isPlayingNote, "silent until the sequencer gate opens")
        rack.noteOn(slot: 0, pitch: 60, velocity: 1)
        XCTAssertTrue(bio.isPlayingNote, "sequencer noteOn must open the envelope")
        rack.noteOff(slot: 0, pitch: 60)
        XCTAssertFalse(bio.isPlayingNote, "matching noteOff must close the envelope")
    }

    func testGate_staleOff_neverCutsTheNewerNote() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        rack.noteOn(slot: 0, pitch: 60, velocity: 1)
        rack.noteOn(slot: 0, pitch: 64, velocity: 1)   // legato retrigger (mono, last wins)
        rack.noteOff(slot: 0, pitch: 60)               // stale off of the OLD note
        XCTAssertTrue(bio.isPlayingNote, "a stale off must not cut the newer note")
        rack.noteOff(slot: 0, pitch: 64)
        XCTAssertFalse(bio.isPlayingNote, "the current note's off closes the gate")
    }

    func testRebindAway_releasesHeldNote() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        rack.noteOn(slot: 0, pitch: 60, velocity: 1)
        XCTAssertTrue(bio.isPlayingNote)
        rack.setKind(slot: 0, kind: .poly)   // rebind must never strand a gate-held note
        XCTAssertFalse(bio.isPlayingNote, "rebind away from bio must release the held note")
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0))
    }

    func testTransposeChangeMidNote_offStillMatches_rawPitch() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        rack.noteOn(slot: 0, pitch: 60, velocity: 1)
        rack.setTranspose(slot: 0, semitones: 7)       // mid-note lane transpose edit
        rack.noteOff(slot: 0, pitch: 60)               // off arrives RAW, must still match
        XCTAssertFalse(bio.isPlayingNote, "raw-pitch gate: transpose change may not strand the note")
    }

    // MARK: - Mixer-stage clamps

    func testLaneGain_clampsToFaderContract_andNonFiniteFailsSilent() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        rack.setGain(slot: 0, 5)
        XCTAssertEqual(bio.sourceNode.volume, 2, accuracy: 0.0001, "lane fader contract is 0…2")
        rack.setGain(slot: 0, Float.nan)
        XCTAssertEqual(bio.sourceNode.volume, 0, accuracy: 0.0001, "non-finite gain fails SILENT")
        rack.setGain(slot: 0, 0.5)
        XCTAssertEqual(bio.sourceNode.volume, 0.5, accuracy: 0.0001)
    }

    func testLanePan_clamps() {
        let (rack, bio) = makeBioRack()
        rack.setKind(slot: 0, kind: .bioVoice)
        rack.setPan(slot: 0, 3)
        XCTAssertEqual(bio.sourceNode.pan, 1, accuracy: 0.0001)
        rack.setPan(slot: 0, -3)
        XCTAssertEqual(bio.sourceNode.pan, -1, accuracy: 0.0001)
        rack.setPan(slot: 0, Float.nan)
        XCTAssertEqual(bio.sourceNode.pan, 0, accuracy: 0.0001, "non-finite pan is center")
    }
}
#endif
