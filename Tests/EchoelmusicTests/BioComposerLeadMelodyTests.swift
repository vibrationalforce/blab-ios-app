// BioComposerLeadMelodyTests.swift
// Echoel — guards the pure chord-tone-snap helper used by the (formerly
// auto-generated) lead line. Founder 2026-07-20 "sicherstellen dass keine
// Melodien Melodien sind" drove a stepwise/in-key emergent-property pair here;
// founder 2026-07-21 ("Melodien sollen die Leute selbst machen" — Psytrance bis
// Rocksteady, extended to every remaining melodic genre) then set every genre's
// leadDensity to 0 (MusicStyle.swift / MusicStyleTests.swift), so BioComposer no
// longer emits any .lead-role notes to measure — those two emergent tests were
// REMOVED (their premise no longer exists) rather than left vacuously green.
// nearestChordDegree itself is unrelated to whether it's currently invoked; it
// stays exercised directly as a pure function.

import XCTest
@testable import Echoelmusic

final class BioComposerLeadMelodyTests: XCTestCase {

    // MARK: - Pure helper: nearest chord tone in scale-degree space

    func testNearestChordDegreeSnapsToTheClosestTone() {
        let triad = [0, 2, 4]          // root, third, fifth (7-degree scale)
        let n = 7
        // Already a chord tone → unchanged.
        XCTAssertEqual(BioComposer.nearestChordDegree(0, tones: triad, degreesPerOctave: n), 0)
        XCTAssertEqual(BioComposer.nearestChordDegree(4, tones: triad, degreesPerOctave: n), 4)
        // A passing tone snaps to the nearest chord tone.
        XCTAssertEqual(BioComposer.nearestChordDegree(1, tones: triad, degreesPerOctave: n), 0) // between 0 and 2 → down to 0
        XCTAssertEqual(BioComposer.nearestChordDegree(3, tones: triad, degreesPerOctave: n), 2) // between 2 and 4 → down to 2
        XCTAssertEqual(BioComposer.nearestChordDegree(5, tones: triad, degreesPerOctave: n), 4) // between 4 and next-octave root(7) → down to 4
    }

    func testNearestChordDegreeCrossesOctaves() {
        let triad = [0, 2, 4]
        let n = 7
        // Degree 6 is closest to the octave root (7), not to 4.
        XCTAssertEqual(BioComposer.nearestChordDegree(6, tones: triad, degreesPerOctave: n), 7)
        // Negative degrees image down an octave.
        XCTAssertEqual(BioComposer.nearestChordDegree(-1, tones: triad, degreesPerOctave: n), 0)  // 0 is nearer than -3
        XCTAssertEqual(BioComposer.nearestChordDegree(-2, tones: triad, degreesPerOctave: n), -3) // octave-down fifth (4-7)
    }

    func testNearestChordDegreeGuardsEmptyTones() {
        XCTAssertEqual(BioComposer.nearestChordDegree(5, tones: [], degreesPerOctave: 7), 5)
        XCTAssertEqual(BioComposer.nearestChordDegree(5, tones: [0, 2, 4], degreesPerOctave: 0), 5)
    }
}
