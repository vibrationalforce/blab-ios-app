// BioComposerLeadMelodyTests.swift
// Echoel — guards that the harmonic-genre LEAD sings like a melody instead of
// arpeggiating the chord (founder 2026-07-20: "sicherstellen dass keine Melodien
// Melodien sind"). The lead now walks the scale STEPWISE and re-anchors to a chord
// tone on strong beats — so consecutive notes are mostly small steps (a melody),
// not the third-or-more leaps a chord-tone-only walk produced (an arpeggio).
// Both the pure snap helper and the emergent melodic property are asserted.

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

    // MARK: - Emergent property: the lead sings (mostly stepwise), not arpeggiates

    /// Lead-bearing harmonic genres (audible melody, not a sustained Fläche).
    private var leadBearing: [MusicStyle] {
        MusicStyle.allCases.filter {
            !$0.harmonicProfile.sustained
            && $0.harmonicProfile.leadDensity > 0
            && $0.beatArchetype != .signature   // trap/dub use their own bespoke lead paths
        }
    }

    // A calm, higher-density body: many lead notes (so plenty of off-beat passing
    // tones to measure) and low tension (so the occasional dissonance bend doesn't
    // pollute the interval statistic). Deterministic per seed.
    private func input(style: MusicStyle, seed: UInt64) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 84, hrvNormalized: 0.7, coherence: 0.7,
                          breathPhase: 0.2, breathDepth: 0.6,
                          key: MusicalKey(root: 0, scale: style.scale),
                          style: style, mode: style.defaultMode,
                          lockedTempo: style.defaultTempo, seed: seed)
    }

    func testLeadLineIsMostlyStepwiseNotArpeggiated() {
        // Pool the interval between consecutive lead notes across many seeds. A
        // stepwise (singing) line produces many small steps (≤ 2 semitones); a pure
        // chord-tone arpeggio produces essentially NONE (its smallest interval is a
        // 3rd, ≥ 3 semitones). The threshold is deliberately conservative — well below
        // what a stepwise line yields, yet impossible for an arpeggio to reach — so it
        // guards the "melody, not arpeggio" property without being brittle.
        for style in leadBearing {
            var stepwise = 0
            var total = 0
            for seed in UInt64(1)...UInt64(60) {
                let comp = BioComposer.compose(input(style: style, seed: seed))
                let lead = comp.notes.filter { $0.role == .lead }
                    .sorted { $0.startStep < $1.startStep }
                guard lead.count >= 2 else { continue }
                for i in 1..<lead.count {
                    let interval = abs(lead[i].pitch - lead[i - 1].pitch)
                    if interval > 0 { total += 1 }        // ignore repeated notes
                    if interval >= 1 && interval <= 2 { stepwise += 1 }
                }
            }
            guard total > 0 else {
                XCTFail("\(style): expected an audible lead line to measure")
                continue
            }
            let fraction = Double(stepwise) / Double(total)
            XCTAssertGreaterThan(fraction, 0.20,
                "\(style): lead should sing (stepwise) — only \(Int(fraction * 100))% of intervals were steps (arpeggio would be ~0%)")
        }
    }

    func testLeadStaysInKey() {
        // Passing tones must remain diatonic — the stepwise walk is over scale
        // degrees, so every lead note is still in the scale. Uses an aroused body
        // (more notes, higher tension) to exercise the passing-tone path hard.
        for style in leadBearing {
            let key = MusicalKey(root: 5, scale: style.scale)
            let take = BioComposer.Input(heartRateBPM: 96, hrvNormalized: 0.3, coherence: 0.3,
                                         breathPhase: 0.6, breathDepth: 0.5, key: key,
                                         style: style, mode: style.defaultMode,
                                         lockedTempo: style.defaultTempo, seed: 7)
            let comp = BioComposer.compose(take)
            for note in comp.notes where note.role == .lead {
                XCTAssertTrue(key.contains(note.pitch),
                              "\(style): lead pitch \(note.pitch) fell outside \(key.name)")
            }
        }
    }
}
