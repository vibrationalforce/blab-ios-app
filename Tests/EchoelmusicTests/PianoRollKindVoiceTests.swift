// PianoRollKindVoiceTests.swift
// Echoel — S2-W2-6 ("Spur = Instrument"): the PRIMARY roll routes through its
// lane's KIND voice when that lane is a sub-bass. Pins the pure, host-free parts:
// PianoRollModel.setKindVoice swap-release + idempotency, and the SubBassVoice
// NoteVoice conformance + velocity handling.
// The live trigger()/outputVoice routing itself is integration-level (private,
// needs a full transport) exactly like the sibling slot sinks — its correctness
// rides these pins + the two mandatory reviewers.
// Guarded like the types it touches (PianoRollModel = SwiftUI; sub = Accelerate).
//
// ⛔ `testLaneDrumKitVoice_isANoteVoice_mapsFloatVelocityToTheKit` was DELETED with
//    #167 (founder 2026-07-27, "erstmal gar nicht mehr rein"): it constructed
//    `LaneDrumKitVoice` and asserted against `DrumNoteMap`, and both types are gone
//    together with `DrumSynthVoice`. `LaneVoiceKind.drums` survives as a case that always
//    allocates to `.poly` — there is no kit voice left for a NoteVoice conformance to reach.
//    (⛔ "survives ONLY as a persisted rawValue" stood here and is FALSE: that enum is not
//     `Codable`. See its own case comment for what actually keeps it.)

#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class PianoRollKindVoiceTests: XCTestCase {

    /// A recording NoteVoice to observe the roll's routing decisions off-engine.
    final class RecordingNoteVoice: NoteVoice {
        var ons: [(pitch: Int, velocity: Float)] = []
        var offs: [Int] = []
        var allOffCount = 0
        func noteOn(pitch: Int, velocity: Float) { ons.append((pitch, velocity)) }
        func noteOff(pitch: Int) { offs.append(pitch) }
        func allNotesOff() { allOffCount += 1 }
    }

    func testSetKindVoice_swapReleasesOldVoice_andIsIdempotent() {
        let roll = PianoRollModel()
        let a = RecordingNoteVoice()
        let b = RecordingNoteVoice()
        roll.setKindVoice(a)          // nil → a: nothing to release yet
        XCTAssertEqual(a.allOffCount, 0)
        roll.setKindVoice(b)          // a → b: releasing swap hits the OLD voice
        XCTAssertEqual(a.allOffCount, 1, "swapping away from a releases a's notes")
        roll.setKindVoice(b)          // b → b: unchanged ⇒ no work
        XCTAssertEqual(b.allOffCount, 0, "an unchanged binding must not re-release")
        roll.setKindVoice(nil)        // b → nil: clearing releases b
        XCTAssertEqual(b.allOffCount, 1, "clearing the kind voice releases it")
    }

    func testSubBassVoice_isANoteVoice_ignoresVelocityRoutesThePitch() {
        let sub = SubBassVoice()
        let nv: any NoteVoice = sub
        nv.noteOn(pitch: 40, velocity: 0.5)          // mono sub: velocity ignored, pitch enqueued
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "on")
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 40)
        nv.noteOff(pitch: 40)
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "off")
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 40)
    }
}
#endif
