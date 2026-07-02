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

    func testHarmonicTakeCarriesAllThreeRoles() {
        let roles = Set(BioComposer.compose(input(.synthwave)).notes.map { $0.role })
        XCTAssertTrue(roles.contains(.lead),    "a harmonic take needs a lead line")
        XCTAssertTrue(roles.contains(.harmony), "a harmonic take needs pad/chord/pulse harmony")
        XCTAssertTrue(roles.contains(.bass),    "a harmonic take needs a bass line")
    }

    func testTrapCarriesLeadAndBass() {
        let roles = Set(BioComposer.compose(input(.trap)).notes.map { $0.role })
        XCTAssertTrue(roles.contains(.lead), "trap bell is the lead")
        XCTAssertTrue(roles.contains(.bass), "trap 808 is the bass")
    }

    func testAmbientLineIsLead() {
        let roles = Set(BioComposer.compose(input(.selfObservation)).notes.map { $0.role })
        XCTAssertTrue(roles.contains(.lead), "the ambient breath line is the lead")
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
