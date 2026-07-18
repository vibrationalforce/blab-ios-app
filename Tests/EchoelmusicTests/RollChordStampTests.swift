import XCTest
@testable import Echoelmusic

/// Tests for the pure `RollChordStamp` — the coherence-chosen, voice-led chord a
/// roll-cell tap drops. Pins determinism, register/timing invariants, and that
/// coherence + seed actually steer the pick.
final class RollChordStampTests: XCTestCase {

    private let key = MusicalKey(root: 0, scale: .major)   // C major

    // MARK: - Determinism (seed + UUID fold)

    func testStamp_isDeterministicForSameInputs() {
        let a = RollChordStamp.stamp(anchorPitch: 60, startTick: 240, lengthTicks: 480,
                                     velocity: 0.8, key: key, coherence: 0.7, seed: 42)
        let b = RollChordStamp.stamp(anchorPitch: 60, startTick: 240, lengthTicks: 480,
                                     velocity: 0.8, key: key, coherence: 0.7, seed: 42)
        XCTAssertEqual(a, b, "same inputs must produce identical notes, ids included")
        XCTAssertFalse(a.isEmpty)
    }

    // MARK: - Timing / velocity invariants

    func testStamp_allNotesShareStartLengthVelocity() {
        let notes = RollChordStamp.stamp(anchorPitch: 64, startTick: 360, lengthTicks: 200,
                                         velocity: 0.6, key: key, coherence: 0.5, seed: 7)
        XCTAssertFalse(notes.isEmpty)
        for n in notes {
            XCTAssertEqual(n.startTick, 360)
            XCTAssertEqual(n.lengthTicks, 200)
            XCTAssertEqual(n.velocity, 0.6, accuracy: 1e-6)
        }
    }

    func testStamp_floorsLengthAndVelocity() {
        let notes = RollChordStamp.stamp(anchorPitch: 60, startTick: 0, lengthTicks: 0,
                                         velocity: 0.0, key: key, coherence: 1, seed: 1)
        for n in notes {
            XCTAssertGreaterThanOrEqual(n.lengthTicks, 1, "length floored at 1 tick")
            XCTAssertGreaterThanOrEqual(n.velocity, 0.05, "velocity floored so the chord is audible")
        }
    }

    // MARK: - Register invariants

    func testStamp_notesStayWithinRegisterAboveAnchor() {
        let anchor = 55
        let span = 12
        let notes = RollChordStamp.stamp(anchorPitch: anchor, startTick: 0, lengthTicks: 120,
                                         key: key, coherence: 0.3, seed: 99, registerSpan: span)
        XCTAssertFalse(notes.isEmpty)
        for n in notes {
            XCTAssertGreaterThanOrEqual(n.pitch, anchor, "voicing sits on/above the tapped row")
            XCTAssertLessThanOrEqual(n.pitch, anchor + span, "voicing stays inside the register span")
            XCTAssertGreaterThanOrEqual(n.pitch, 0)
            XCTAssertLessThanOrEqual(n.pitch, 127)
        }
    }

    func testStamp_clampsAnchorToMidiRange() {
        let hi = RollChordStamp.stamp(anchorPitch: 999, startTick: 0, lengthTicks: 120,
                                      key: key, coherence: 0.5, seed: 3)
        for n in hi { XCTAssertLessThanOrEqual(n.pitch, 127) }
        let lo = RollChordStamp.stamp(anchorPitch: -999, startTick: 0, lengthTicks: 120,
                                      key: key, coherence: 0.5, seed: 3)
        for n in lo { XCTAssertGreaterThanOrEqual(n.pitch, 0) }
    }

    // MARK: - Chord shape

    func testStamp_producesAChordNotJustOneNote() {
        // A well-formed major key yields a real triad (≥ 2 distinct pitches).
        let notes = RollChordStamp.stamp(anchorPitch: 60, startTick: 0, lengthTicks: 480,
                                         key: key, coherence: 0.9, seed: 5)
        let distinct = Set(notes.map(\.pitch))
        XCTAssertGreaterThanOrEqual(distinct.count, 2, "a stamp drops a chord, not a single note")
    }

    // MARK: - Coherence + seed steer the pick

    func testStamp_variesAcrossSeeds() {
        // Across many seeds the stamp is not a constant — the harmonic selector
        // actually explores. (Robust: 12 seeds, expect ≥ 2 distinct chord roots.)
        var roots = Set<Int>()
        for seed in UInt64(0)..<12 {
            let notes = RollChordStamp.stamp(anchorPitch: 60, startTick: 0, lengthTicks: 120,
                                             key: key, coherence: 0.2, seed: seed)
            if let low = notes.map(\.pitch).min() { roots.insert(low % 12) }
        }
        XCTAssertGreaterThanOrEqual(roots.count, 2, "seed must steer the chord choice")
    }

    func testStamp_lowCoherenceExploresAtLeastAsWideAsHigh() {
        // High coherence collapses to the plain function (narrow set of outcomes);
        // low coherence opens the window. Over a seed sweep, low-coherence outcomes
        // are at least as varied as high-coherence ones.
        func rootSpread(coherence: Float) -> Int {
            var roots = Set<Int>()
            for seed in UInt64(0)..<16 {
                let notes = RollChordStamp.stamp(anchorPitch: 60, startTick: 0, lengthTicks: 120,
                                                 key: key, coherence: coherence, seed: seed)
                if let low = notes.map(\.pitch).min() { roots.insert(low % 12) }
            }
            return roots.count
        }
        XCTAssertGreaterThanOrEqual(rootSpread(coherence: 0.0), rootSpread(coherence: 1.0))
    }
}
