// NoteRoleTests.swift
// Echoel — multitimbral Step 1: notes carry an arrangement ROLE (bass/harmony/lead)
// so the (upcoming) per-layer voices can route by role. Guards the tagging in
// BioComposer and the Codable/legacy behaviour of Note.role.

import XCTest
@testable import Echoelmusic

final class NoteRoleTests: XCTestCase {

    private func input(_ style: MusicStyle, hr: Float = 90) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, coherence: 0.4,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 110, seed: 7)
    }

    func testHarmonicTakeCarriesBassAndHarmony() {
        // Was "...AllThreeRoles" (asserting .lead too) until founder 2026-07-21
        // ("Melodien sollen die Leute selbst machen") set every genre's
        // leadDensity to 0 — BioComposer.compose no longer emits a .lead-role
        // note for any style, so that assertion is retired here too (see
        // MusicStyleTests.testNoGenreAutoGeneratesLeadNotes for the canonical
        // invariant). Bass + harmony are still generated for every harmonic take.
        let roles = Set(BioComposer.compose(input(.synthwave)).notes.map { $0.role })
        XCTAssertFalse(roles.contains(.lead),   "no genre auto-generates a lead line anymore")
        XCTAssertTrue(roles.contains(.harmony), "a harmonic take needs pad/chord/pulse harmony")
        XCTAssertTrue(roles.contains(.bass),    "a harmonic take needs a bass line")
    }

    func testTrapIsALeadFreeFläche() {
        // Founder 2026-07-09: the trap dark-bell lead — the exposed pure-wave line
        // ("zu laut, unangenehm") — is retired. Trap now voices a sustained pad +
        // held bass root through composeHarmonic; only its signature beat remains.
        let roles = Set(BioComposer.compose(input(.trap)).notes.map { $0.role })
        XCTAssertFalse(roles.contains(.lead), "no lead melody in the trap Fläche")
        XCTAssertTrue(roles.contains(.bass), "trap keeps its grounding bass root")
        XCTAssertTrue(roles.contains(.harmony), "trap keeps its dark pad")
    }

    func testSelfObservationIsADroneNotALead() {
        // Founder 2026-07-07 ("laute quakige Töne … soll sich in den Trance-Pad-Ambient
        // einfügen"): selfObservation is now a pure sustained Fläche — a drone pad + one
        // grounding bass root, NO lead line (it used to route to `ambientMelody`, a bare
        // exposed .lead tune). See BioComposer.compose.
        let roles = Set(BioComposer.compose(input(.selfObservation)).notes.map { $0.role })
        XCTAssertFalse(roles.contains(.lead), "the meditative drone carries no lead line")
        XCTAssertTrue(roles.contains(.bass), "the drone keeps a grounding bass root")
    }

    func testDefaultRoleIsHarmony() {
        XCTAssertEqual(Note(pitch: 60, startStep: 0).role, .harmony)
    }

    func testRoleCodableRoundTrip() throws {
        let n = Note(pitch: 64, startStep: 2, lengthSteps: 3, velocity: 0.7, role: .lead)
        let data = try JSONEncoder().encode(n)
        let back = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(back.role, .lead)
        XCTAssertEqual(back.pitch, 64)
    }

    func testLegacyNoteWithoutRoleDecodesAsHarmony() throws {
        // A pre-multitimbral clip has no "role" key → must decode as .harmony.
        let legacy = #"{"id":"\#(UUID().uuidString)","pitch":60,"startTick":0,"lengthTicks":120,"velocity":0.8}"#
        let back = try JSONDecoder().decode(Note.self, from: Data(legacy.utf8))
        XCTAssertEqual(back.role, .harmony)
    }
}
