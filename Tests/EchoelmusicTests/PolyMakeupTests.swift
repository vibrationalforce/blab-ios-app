// PolyMakeupTests.swift
// Echoel — the smoothed poly makeup gain (EchoelPolyDDSP.polyMakeupTarget /
// .smoothedMakeup). Guards Ralph-Zyklus 2 "Polyphonie-Headroom" (founder
// 2026-07-11: "EchoelSynth rudimentär bei den Levels · Einzelnote voll, Akkord
// zerrt nicht"): a single note must play near-FULL while a dense chord is backed
// off along a 1/√N law — and the change from note to note must EASE, never jump
// (the old raw per-block 1/√N pumped, which is why smoothing is mandatory).
// Pure functions → fully unit-testable, no AVAudio / Accelerate render needed.
//
// ⛔ WHY THE EXPONENT IS PINNED HERE AND NOT LEFT AS "roughly 1/√N" (#195, 2026-07-28).
// #195 was filed to RAISE it — "1/√N applies to incoherent sums; a chord sums coherently".
// That reasoning is exactly inverted for the quantity this gain controls. Measured on
// additive 8-harmonic voices at real intervals, 40 random phase sets each: RMS grows as
// N^0.50 (to three decimals) for every chord with distinct pitches and every phase set —
// it is the PEAK that grows coherently, at N^~1.0, and the peak is the safety tanh's and
// the limiter's problem, not this function's. Acting on #195 would have made every chord
// quieter than a single note, i.e. the "too thin" direction the founder keeps reporting.
// The full table is on `polyMakeupTarget` in EchoelDDSP.swift. So the law is measured,
// not assumed, and `testFollowsInverseSqrtLaw` checks the exponent at three points rather
// than one ratio — a single 1:4 ratio also passes for a plain "halve every doubling"
// lookup that is not a power law at all.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class PolyMakeupTests: XCTestCase {

    private typealias Poly = EchoelPolyDDSP

    func testSingleNoteIsNearFull() {
        // One voice must play at the full single-voice gain — NOT the old thin 0.40.
        let g = Poly.polyMakeupTarget(voiceCount: 1)
        XCTAssertGreaterThan(g, 0.8, "a single note must sound full, well above the old 0.40")
    }

    func testZeroOrNegativeVoicesClampToFull() {
        // Silence / a bad count must not divide-by-zero or blow up — treated as 1 voice.
        XCTAssertEqual(Poly.polyMakeupTarget(voiceCount: 0), Poly.polyMakeupTarget(voiceCount: 1))
        XCTAssertEqual(Poly.polyMakeupTarget(voiceCount: -5), Poly.polyMakeupTarget(voiceCount: 1))
    }

    func testDenseChordIsBackedOff() {
        // More voices → lower makeup, so the summed LOUDNESS stays put as notes stack.
        // NOT "so the coherent sum is tamed before the tanh" (what this comment used to
        // say): the peak still grows N^0.5 after this gain — see the file header.
        let one = Poly.polyMakeupTarget(voiceCount: 1)
        let four = Poly.polyMakeupTarget(voiceCount: 4)
        let twelve = Poly.polyMakeupTarget(voiceCount: 12)
        XCTAssertGreaterThan(one, four, "a chord is quieter per-voice than a single note")
        XCTAssertGreaterThan(four, twelve, "a denser chord is backed off further")
    }

    func testFollowsInverseSqrtLaw() {
        // THE EXPONENT, at three points, because one ratio does not identify a power law:
        // 1, 4 and 9 all sit above the 0.22 floor, so each must satisfy g(N) = g(1)·N^−0.5
        // exactly. Solving for p in g(N)/g(1) = N^−p pins it to 0.500, which is the number
        // #195 proposed to raise and the measurement says to keep (see the file header).
        let one = Poly.polyMakeupTarget(voiceCount: 1)
        for n in [4, 9] {
            let g = Poly.polyMakeupTarget(voiceCount: n)
            XCTAssertEqual(g, one / Float(n).squareRoot(), accuracy: 1e-5,
                           "\(n) voices must land on the 1/√N law, not near it")
            // `logf`, not `log` — the global `log` in this project is the EchoelLogger.
            let p = -logf(g / one) / logf(Float(n))
            XCTAssertEqual(p, 0.5, accuracy: 1e-4,
                           "\(n) voices: exponent is 0.500 by measurement — raising it toward "
                           + "1 makes a chord quieter than a single note")
        }
        XCTAssertEqual(Poly.polyMakeupTarget(voiceCount: 4), one / 2, accuracy: 0.01,
                       "1/√N: 4 voices ≈ half the single-note gain")
    }

    func testNeverBelowTheFloor() {
        // Even a pathological voice count stays at/above the safety floor (no silence,
        // no negative gain).
        let g = Poly.polyMakeupTarget(voiceCount: 64)
        XCTAssertGreaterThanOrEqual(g, 0.22, "makeup never collapses below the floor")
    }

    func testSmoothingEasesGraduallyNotInOneJump() {
        // Going from a full single note (0.85) to a dense-chord target must move only a
        // FRACTION of the way in one block — this is the anti-pump property.
        let target = Poly.polyMakeupTarget(voiceCount: 12)   // ~0.245, well below 0.85
        let step = Poly.smoothedMakeup(current: 0.85, target: target, coeff: 0.04)
        XCTAssertLessThan(step, 0.85, "it moves toward the chord target")
        XCTAssertGreaterThan(step, target + 0.4, "but only a small fraction in one block (no jump)")
    }

    func testSmoothingConvergesToTarget() {
        // Held at a constant voice count, the smoothed gain converges to the target.
        let target = Poly.polyMakeupTarget(voiceCount: 3)
        var g: Float = 0.85
        for _ in 0..<2000 { g = Poly.smoothedMakeup(current: g, target: target, coeff: 0.04) }
        XCTAssertEqual(g, target, accuracy: 0.001, "settles exactly on the voice-count target")
    }

    func testSmoothingCoeffIsClamped() {
        // A coeff ≥ 1 snaps to target (never overshoots); ≤ 0 holds — both bounded.
        XCTAssertEqual(Poly.smoothedMakeup(current: 0.2, target: 0.85, coeff: 5), 0.85, accuracy: 1e-6)
        XCTAssertEqual(Poly.smoothedMakeup(current: 0.2, target: 0.85, coeff: -1), 0.2, accuracy: 1e-6)
    }
}
#endif
