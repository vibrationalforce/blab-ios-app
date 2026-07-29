// MixerBakeSmokeTests.swift
// Echoel — the mixing law (#174), in the BLOCKING bundle.
//
// WHY THIS ONE EARNS A GATE. `MixerStore.mixedVelocity` is the single point where a
// user's fader becomes a note's velocity, and the velocity IS the level all the way
// downstream — the roll's audibility floor, the felt sub, the MusicalFrame publish and
// the MIDI export all read it. Two properties below are not style preferences; they are
// the reasons the calling code is shaped the way it is, and if either silently changed
// the app would regress into a bug that already shipped once:
//
//  1. NON-COMPOUNDING is FALSE — applying the law twice really does square the user
//     term. That is exactly why `EchoelStudioView` keeps `lastRawBars` and re-derives
//     from the composer's own notes on every fader move, instead of trimming the take
//     it already has. A future session that "simplifies" that away needs to fail here.
//  2. The result must ALWAYS land in [0, 1] and never be NaN — for any input at all.
//     That is the property that keeps a poisoned value off the audio thread. My first
//     draft of this file asserted something stronger and FALSE (that a NaN genre or
//     fader silences the note); it does not, because `combined` uses the other
//     `min`/`max` argument order and `Swift.min(1, .nan)` returns 1, i.e. unity. The
//     assertions below pin what the code actually does, checked against it rather than
//     against what the doc comment made it sound like.
//
// (`Tests/EchoelmusicTests/MixerStoreTests.swift` covers `combined` in depth — but that
// suite is non-blocking today, #208. These four run where red actually stops a ship.)

import XCTest
@testable import Echoelmusic

final class MixerBakeSmokeTests: XCTestCase {

    /// A fader at zero silences; a fader at unity leaves the genre balance alone.
    func testTheFaderEndpointsMeanSilenceAndUntouched() {
        XCTAssertEqual(MixerStore.mixedVelocity(0.8, genre: 1.0, user: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(MixerStore.mixedVelocity(0.8, genre: 1.0, user: 1), 0.8, accuracy: 1e-6)
        // Genre glue below unity still applies at a unity fader — the user trims, the
        // genre balances, and unity means "the genre's own balance", not "no glue".
        XCTAssertEqual(MixerStore.mixedVelocity(0.8, genre: 0.5, user: 1), 0.4, accuracy: 1e-6)
    }

    /// The product is capped at 1, so a genre level above unity (dubTechno/trap bass is
    /// 1.18) can never push a velocity past the top of the range.
    func testTheResultIsCappedAtFullVelocity() {
        XCTAssertEqual(MixerStore.mixedVelocity(0.95, genre: 1.18, user: 1), 0.95, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(MixerStore.mixedVelocity(1.0, genre: 1.18, user: 1), 1)
    }

    /// THE #174 PROPERTY. Baking the law onto an already-baked velocity compounds — so
    /// re-balancing a take MUST start from the composer's raw notes. If this ever stops
    /// failing to match, the re-derive-from-raw design has lost its reason to exist and
    /// somebody has quietly changed the law.
    func testApplyingTheLawTwiceCompounds_whichIsWhyTheRawTakeIsKept() {
        let raw: Float = 0.8
        let once = MixerStore.mixedVelocity(raw, genre: 1.0, user: 0.5)
        let twice = MixerStore.mixedVelocity(once, genre: 1.0, user: 0.5)
        XCTAssertEqual(once, 0.4, accuracy: 1e-6)
        XCTAssertEqual(twice, 0.2, accuracy: 1e-6)
        XCTAssertNotEqual(once, twice, accuracy: 1e-3)
        // …and from the RAW velocity, a second fader position is reached exactly, with
        // no memory of the first. This is what `rebalanceTake()` relies on.
        XCTAssertEqual(MixerStore.mixedVelocity(raw, genre: 1.0, user: 0.25),
                       0.2, accuracy: 1e-6)
    }

    /// A non-finite VELOCITY (a poisoned bio-derived dynamic) comes out silent, not NaN —
    /// a NaN velocity propagates into the voice and has caused shipped permanent silence
    /// before. Negative input is clamped for the same reason.
    func testANonFiniteOrNegativeVelocityLeavesASilentNote() {
        XCTAssertEqual(MixerStore.mixedVelocity(.nan, genre: 1.0, user: 1), 0, accuracy: 1e-6)
        XCTAssertEqual(MixerStore.mixedVelocity(-0.5, genre: 1.0, user: 1), 0, accuracy: 1e-6)
        XCTAssertEqual(MixerStore.mixedVelocity(.infinity, genre: 1.0, user: 1), 1, accuracy: 1e-6)
    }

    /// THE INVARIANT THAT PROTECTS THE AUDIO THREAD, over every awkward input including
    /// the two that behave as unity rather than as silence. Deliberately written as
    /// "finite and inside the range" rather than as a per-case expectation: it is the
    /// property the render path actually depends on, and it holds no matter which way
    /// round a future edit writes the clamps.
    func testTheResultIsAlwaysFiniteAndInRangeForEveryInput() {
        let awkward: [Float] = [0, 0.5, 1, 1.18, -1, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        for v in awkward {
            for g in awkward {
                for u in awkward {
                    let out = MixerStore.mixedVelocity(v, genre: g, user: u)
                    XCTAssertFalse(out.isNaN, "NaN out of velocity \(v), genre \(g), user \(u)")
                    XCTAssertGreaterThanOrEqual(out, 0, "below range: \(v)/\(g)/\(u)")
                    XCTAssertLessThanOrEqual(out, 1, "above range: \(v)/\(g)/\(u)")
                }
            }
        }
    }

    /// The surprising half, pinned so nobody "discovers" it again as a bug: a non-finite
    /// GENRE or FADER reads as unity, not as silence. Harmless (neither is reachable, and
    /// the value stays in range) but worth a named test, because the doc comment claiming
    /// otherwise is exactly the sort of thing that gets believed instead of checked.
    func testANonFiniteGenreOrFaderReadsAsUnityNotAsSilence() {
        XCTAssertEqual(MixerStore.mixedVelocity(0.8, genre: .nan, user: 1), 0.8, accuracy: 1e-6)
        XCTAssertEqual(MixerStore.mixedVelocity(0.8, genre: 1.0, user: .nan), 0.8, accuracy: 1e-6)
    }
}
