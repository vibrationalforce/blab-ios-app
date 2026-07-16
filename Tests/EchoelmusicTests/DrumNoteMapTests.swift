// DrumNoteMapTests.swift
// Echoel — S2-W2-2 (dissolution, "Spur = Instrument"): pins the PURE
// MIDI-pitch → drum-pad mapping the LaneDrumKitVoice plays. Laws (plan §3
// S2-W2-2): TOTAL (every pitch maps — no dead keys), deterministic,
// GM-informed pad zones (kick 35/36 · snare family 37–40 · hats 42/44/46
// with 44 the tightest), tom/perc fallback pitched from the note, and
// velocity→gain with a floor (a played note is never inaudible).
// Guarded like DrumSynthVoice (DrumSynthParams lives behind it); the
// macOS SwiftPM CI runs these (the repo has no Linux gate).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class DrumNoteMapTests: XCTestCase {

    // MARK: - Pad zones (GM-informed)

    func testPadZones_matchTheGMLayout() {
        XCTAssertEqual(DrumNoteMap.pad(forPitch: 35), .kick)
        XCTAssertEqual(DrumNoteMap.pad(forPitch: 36), .kick)
        for p in 37...40 {
            XCTAssertEqual(DrumNoteMap.pad(forPitch: p), .snare, "pitch \(p) is snare family")
        }
        for p in [42, 44, 46] {
            XCTAssertEqual(DrumNoteMap.pad(forPitch: p), .hat, "pitch \(p) is a hat")
        }
        XCTAssertEqual(DrumNoteMap.pad(forPitch: 45), .perc, "tom pitch falls to perc")
        XCTAssertEqual(DrumNoteMap.pad(forPitch: 60), .perc)
    }

    func testMapping_isTotal_everyPitchProducesAFiniteHit() {
        for pitch in -12...140 {   // beyond MIDI range on both sides
            let hit = DrumNoteMap.hit(pitch: pitch, velocity: 100)
            XCTAssertTrue(hit.params.frequency.isFinite, "pitch \(pitch)")
            XCTAssertGreaterThan(hit.params.frequency, 0, "pitch \(pitch)")
            XCTAssertTrue((0.05...1.0).contains(hit.gain), "pitch \(pitch)")
        }
    }

    func testMapping_isDeterministic() {
        let a = DrumNoteMap.hit(pitch: 38, velocity: 96)
        let b = DrumNoteMap.hit(pitch: 38, velocity: 96)
        XCTAssertEqual(a, b)
    }

    // MARK: - Musical character

    func testHats_dampingOrder_pedalTightestOpenLoosest() {
        // Plan: 44 (pedal) = tighter than 42 (closed); 46 (open) rings longest.
        let closed = DrumNoteMap.params(forPitch: 42).damping
        let pedal = DrumNoteMap.params(forPitch: 44).damping
        let open = DrumNoteMap.params(forPitch: 46).damping
        XCTAssertGreaterThan(pedal, closed, "pedal hat chokes hardest")
        XCTAssertGreaterThan(closed, open, "open hat rings loosest")
    }

    func testKick_sitsBelowTheSnare() {
        XCTAssertLessThan(DrumNoteMap.params(forPitch: 36).frequency,
                          DrumNoteMap.params(forPitch: 38).frequency)
    }

    func testPercFallback_pitchesWithTheNote_andClamps() {
        // The tom/perc pad follows the played pitch (higher note = higher drum) —
        // deterministic and clamped to a musical band at the extremes.
        let low = DrumNoteMap.params(forPitch: 41).frequency
        let mid = DrumNoteMap.params(forPitch: 48).frequency
        let high = DrumNoteMap.params(forPitch: 60).frequency
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
        XCTAssertGreaterThanOrEqual(DrumNoteMap.params(forPitch: -12).frequency, 40)
        XCTAssertLessThanOrEqual(DrumNoteMap.params(forPitch: 140).frequency, 600)
    }

    // MARK: - Velocity → gain

    func testVelocityGain_linearWithFloorAndClamp() {
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: 127), 1.0, accuracy: 1e-6)
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: 64), 64.0 / 127.0, accuracy: 1e-6)
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: 1), 0.05, accuracy: 1e-6,
                       "quiet notes floor at audible, never vanish")
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: 0), 0.05, accuracy: 1e-6)
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: -9), 0.05, accuracy: 1e-6)
        XCTAssertEqual(DrumNoteMap.gain(forVelocity: 300), 1.0, accuracy: 1e-6)
    }

    // MARK: - LaneDrumKitVoice container (no engine — nothing may touch a node)

    @MainActor
    func testKitVoice_padCountAndPreAttachSafety() {
        let kit = LaneDrumKitVoice()
        XCTAssertFalse(kit.isActive, "fresh kit is unattached")
        // Pre-attach control calls must be safe no-ops / node-free:
        kit.noteOn(pitch: 36, velocity: 100)   // configure+fire enqueue only
        kit.noteOff(pitch: 36)
        kit.allNotesOff()
        kit.setGain(0.5)                       // guarded: must NOT force a source node
        kit.setPan(-0.3)
        kit.setInsert(TrackFX(filter: .lowPass, cutoffHz: 900, resonance: 1.0, drive: 0.2))
        XCTAssertFalse(kit.isActive)
    }

    @MainActor
    func testKitVoice_cachesParamsPerPad_reconfiguresOnlyOnChange() {
        let kit = LaneDrumKitVoice()
        kit.noteOn(pitch: 36, velocity: 100)   // kick
        let kickParams = kit.appliedParamsForTests[DrumNoteMap.Pad.kick.rawValue]
        XCTAssertEqual(kickParams, DrumNoteMap.params(forPitch: 36))
        XCTAssertEqual(kit.configureCountForTests, 1, "first hit configures once")
        kit.noteOn(pitch: 36, velocity: 60)    // same pad, same params → cache holds
        kit.noteOn(pitch: 36, velocity: 127)   // steady groove — still no reconfigure
        XCTAssertEqual(kit.appliedParamsForTests[DrumNoteMap.Pad.kick.rawValue], kickParams)
        XCTAssertEqual(kit.configureCountForTests, 1,
                       "repeat hits with the same preset must NOT reconfigure (the cache law)")
        kit.noteOn(pitch: 35, velocity: 100)   // kick pad, DIFFERENT preset → recache
        XCTAssertEqual(kit.appliedParamsForTests[DrumNoteMap.Pad.kick.rawValue],
                       DrumNoteMap.params(forPitch: 35))
        XCTAssertEqual(kit.configureCountForTests, 2, "a preset CHANGE reconfigures exactly once")
        XCTAssertNil(kit.appliedParamsForTests[DrumNoteMap.Pad.hat.rawValue],
                     "untouched pads stay unconfigured")
    }
}
#endif
