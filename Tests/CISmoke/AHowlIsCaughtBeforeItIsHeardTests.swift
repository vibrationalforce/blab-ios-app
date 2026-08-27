// AHowlIsCaughtBeforeItIsHeardTests.swift
// Echoel — #847 (founder 2026-08-27: "Feedback guard soll auf die betroffenen
// Frequenzbändern reagieren … es soll erst gar kein Piepsen entstehen").
//
// END-TO-END BEHAVIOUR (Tests/CISmoke/CLAUDE.md §1): `FeedbackGuard.HowlDetector` is a
// pure Foundation value type driven directly — the strong kind of guard. What no test here
// can prove: that the detector catches a REAL howl on a REAL speaker before a human hears
// it. That is a device probe and stays open (NEEDS-FOUNDER-VERIFY lives on the wiring
// slice, not here).
//
// WHY THIS TYPE EXISTS. The guard it replaced WAS REACTIVE (until #848): the broadband
// duck fires only when RMS is already over 0.85 and rising, and the single notch engaged
// only AFTER the duck (the `ducking && ringingBin` join — retired by the wiring slice,
// #848b review F3 past-tensed this paragraph). By then the beep was audible. A howl's
// actual signature appears EARLIER and
// is narrowband: ONE stationary spectral peak, dominating its neighbourhood, growing
// across ticks (3-bin energy, so FFT scalloping cannot fake growth), with NO harmonic
// partner at 2f and NO subharmonic parent at f/2 — a sung note has one or the other, a
// howl has neither. The detector encodes exactly those signatures, so the wiring slice
// can notch at low level, before audibility.
//
// ⭐ WIRED since #848: `AudioEngine.updateFeedbackGuard()` consults the detector on
// every guard tick with fresh audio (#850: a frozen window is skipped) and
// `applyNotchDefence` maps candidates onto four dynamic notch bands (shape pinned
// by `TheNotchIsSlewedAndMonitorOnlyTests` test 7).
// `AudioInputDoorTests`' two-way header guard watches `HowlDetector` as its wiring
// proxy since the same commit. (#847 shipped the type deliberately caller-less for
// one commit; that boundary note is retired with the wiring, #425.)
//
// ⭐ GRADING (§3). Two commits share this file. Against #847's parent (0a7eb88) it named
// a symbol that did not exist — no verdict there, hand-transcribed in Python instead
// (every expectation derived by algebra, #442/#686 — a CI round trip is a lottery
// ticket, not a check). Against the FOLLOW-UP's parent (cb0acc0, the first cut of the
// detector): `testAHarmonicRichCrescendoIsVetoedOnBothPartials` is ONE genuine
// REGRESSION-witness — red there at tick 5, where the octave bin's clean track fired
// (the #847 review's finding 1, reproduced in transcription before the fix). The poison
// test's witness additions and every other vector are green on both trees; test 8's
// duck/slew assertions are COUNTERWEIGHTS — no slice here may disturb the level half or
// the slew law.

import Foundation
import XCTest
@testable import Echoelmusic

final class AHowlIsCaughtBeforeItIsHeardTests: XCTestCase {

    /// 64 bins of quiet broadband floor with named peaks written on top.
    /// Floor 0.01 everywhere ⇒ every neighbourhood mean is 0.01 exactly, so the
    /// dominance threshold (×6) is crossed at magnitude 0.06 — all vectors use ≥ 0.1.
    private func spectrum(_ peaks: [Int: Float]) -> [Float] {
        var m = [Float](repeating: 0.01, count: 64)
        for (bin, mag) in peaks { m[bin] = mag }
        return m
    }

    private func config(persistence: Int = 4, maxCandidates: Int = 4)
    -> FeedbackGuard.HowlDetector.Config {
        var c = FeedbackGuard.HowlDetector.Config()
        c.persistenceTicks = persistence
        c.maxCandidates = maxCandidates
        return c
    }

    // MARK: 1. The core promise — a growing lone peak is caught, and not before its time

    /// A single peak at bin 20 growing 0.1 → 0.2 over four ticks: silent for the first
    /// three (persistence), a candidate on the fourth (growth 2.0 ≥ 1.25), at bin 20.
    func testAGrowingLonePeakBecomesACandidateAfterPersistence() {
        var d = FeedbackGuard.HowlDetector(config: config())
        let mags: [Float] = [0.1, 0.12, 0.15, 0.2]
        var results: [[FeedbackGuard.HowlDetector.Candidate]] = []
        for m in mags { results.append(d.observe(magnitudes: spectrum([20: m]))) }
        XCTAssertTrue(results[0].isEmpty && results[1].isEmpty && results[2].isEmpty,
                      "a candidate before `persistenceTicks` observations would notch " +
                      "transients — persistence is the anti-false-positive half of prevention")
        XCTAssertEqual(results[3].map(\.bin), [20],
                       "four persistent, growing, dominant, harmonic-free observations " +
                       "ARE the howl signature — this is the moment to notch, still quiet")
    }

    /// The absolute level is deliberately NOT the trigger: over a proportionally quiet
    /// floor (0.001) the same shape fires at peak 0.04 — far under the duck's 0.85
    /// broadband ceiling. Catching it quiet is the founder's "gar kein Piepsen".
    /// (The dominance test is RELATIVE — over the louder 0.01 floor of `spectrum(_:)`
    /// a 0.04 peak is rightly ignored; that pairing is asserted here too, because it is
    /// what keeps a quiet mix's ordinary content un-notched.)
    func testTheDetectorFiresAtLowAbsoluteLevel() {
        func quiet(_ peak: Float) -> [Float] {
            var m = [Float](repeating: 0.001, count: 64)
            m[20] = peak
            return m
        }
        var d = FeedbackGuard.HowlDetector(config: config())
        var last: [FeedbackGuard.HowlDetector.Candidate] = []
        for m in [0.02, 0.024, 0.03, 0.04] as [Float] {
            last = d.observe(magnitudes: quiet(m))
        }
        XCTAssertEqual(last.map(\.bin), [20],
                       "0.04 over a 0.001 floor is a quiet but unmistakable loop — the " +
                       "whole point is acting before anything is loud")
        var d2 = FeedbackGuard.HowlDetector(config: config())
        var lastLoudFloor: [FeedbackGuard.HowlDetector.Candidate] = []
        for m in [0.02, 0.024, 0.03, 0.04] as [Float] {
            lastLoudFloor = d2.observe(magnitudes: spectrum([20: m]))
        }
        XCTAssertTrue(lastLoudFloor.isEmpty,
                      "the SAME peak over a 10× louder floor is not dominant — absolute " +
                      "level alone must neither trigger nor exempt")
    }

    // MARK: 2. What must NEVER fire — the musical signals

    /// A loud but STATIC peak (a held clean note, a sine pad) never becomes a candidate:
    /// growth is a required signature, feedback always builds.
    func testAStaticPeakIsNeverACandidate() {
        var d = FeedbackGuard.HowlDetector(config: config())
        for _ in 0..<8 {
            XCTAssertTrue(d.observe(magnitudes: spectrum([20: 0.3])).isEmpty,
                          "a stationary magnitude is a NOTE, not a howl — notching it " +
                          "is the false positive that makes players disable guards")
        }
    }

    /// A growing peak WITH a strong second harmonic is a crescendoing sung note, not
    /// feedback — and BOTH halves of the pair stay silent: the fundamental falls to the
    /// harmonic veto, and the harmonic itself falls to the SUBharmonic veto. Six ticks,
    /// not four, on purpose: the #847 review proved the first version's octave bin built
    /// a clean track and fired at tick 5 — one tick past where the test stopped looking
    /// (#367: green for a reason other than its message).
    func testAHarmonicRichCrescendoIsVetoedOnBothPartials() {
        var d = FeedbackGuard.HowlDetector(config: config())
        for m in [0.1, 0.13, 0.16, 0.2, 0.24, 0.29] as [Float] {
            // 2 × bin 20 = bin 40 carries half the peak's energy — a voice, not a howl.
            XCTAssertTrue(d.observe(magnitudes: spectrum([20: m, 40: m * 0.5])).isEmpty,
                          "a crescendo must notch NEITHER its fundamental (harmonic " +
                          "veto) NOR its octave (subharmonic veto) — notching the 2nd " +
                          "harmonic audibly thins the voice, the exact false positive " +
                          "this ask is priced against")
        }
    }

    /// Below the absolute floor nothing fires, however dominant: on near-silence the
    /// neighbourhood mean is ~0 and ratios alone would notch the noise floor.
    func testTheNoiseFloorCannotBeNotched() {
        var d = FeedbackGuard.HowlDetector(config: config())
        for _ in 0..<8 {
            var m = [Float](repeating: 0.000001, count: 64)
            m[20] = 0.0005   // hugely dominant relatively, far under minMagnitude
            XCTAssertTrue(d.observe(magnitudes: m).isEmpty,
                          "relative dominance over silence is not a howl")
        }
    }

    // MARK: 3. Per-band, plural — the founder's "betroffene Frequenzbänder"

    /// Two simultaneous growing howls are BOTH reported, strongest growth first, and
    /// `maxCandidates` caps the list.
    func testTwoSimultaneousHowlsAreBothCaughtAndRanked() {
        var d = FeedbackGuard.HowlDetector(config: config())
        var last: [FeedbackGuard.HowlDetector.Candidate] = []
        let a: [Float] = [0.1, 0.15, 0.22, 0.3]   // growth 3.0 at bin 20
        let b: [Float] = [0.1, 0.12, 0.15, 0.2]   // growth 2.0 at bin 33
        for i in 0..<4 { last = d.observe(magnitudes: spectrum([20: a[i], 33: b[i]])) }
        XCTAssertEqual(last.map(\.bin), [20, 33],
                       "both bands, ranked by severity — one notch per affected band is " +
                       "the ask, and ranking decides who gets a filter when bands run out")
        var capped = FeedbackGuard.HowlDetector(config: config(maxCandidates: 1))
        var lastCapped: [FeedbackGuard.HowlDetector.Candidate] = []
        for i in 0..<4 {
            lastCapped = capped.observe(magnitudes: spectrum([20: a[i], 33: b[i]]))
        }
        XCTAssertEqual(lastCapped.map(\.bin), [20],
                       "the cap keeps the strongest — the wiring slice has finitely many " +
                       "EQ bands and must never be promised more candidates than that")
    }

    /// A howl that jitters ±1 bin between ticks (FFT leakage breathing) is still ONE
    /// persistent track — without the tolerance every real howl would reset its own count.
    func testOneBinOfJitterDoesNotResetPersistence() {
        var d = FeedbackGuard.HowlDetector(config: config())
        let bins = [20, 21, 20, 21]
        let mags: [Float] = [0.1, 0.13, 0.16, 0.2]
        var last: [FeedbackGuard.HowlDetector.Candidate] = []
        for i in 0..<4 { last = d.observe(magnitudes: spectrum([bins[i]: mags[i]])) }
        XCTAssertEqual(last.count, 1, "±1 bin of jitter is the same howl")
        XCTAssertTrue(last.first.map { [20, 21].contains($0.bin) } ?? false,
                      "the reported bin follows the track's latest position")
    }

    /// A vanished peak resets its track: one missed tick means the loop was broken
    /// (someone moved, the note ended) — a howl at ~15 Hz observation never misses.
    func testAMissedTickResetsTheTrack() {
        var d = FeedbackGuard.HowlDetector(config: config())
        for m in [0.1, 0.12, 0.15] as [Float] { _ = d.observe(magnitudes: spectrum([20: m])) }
        _ = d.observe(magnitudes: spectrum([:]))   // gone for one tick
        let after = d.observe(magnitudes: spectrum([20: 0.2]))
        XCTAssertTrue(after.isEmpty,
                      "after a miss the count restarts — stale persistence would notch " +
                      "the NEXT unrelated sound at that frequency")
    }

    // MARK: 4. Poison + the untouched neighbours

    /// Non-finite magnitudes are skipped, never propagated, never a candidate — while a
    /// clean howl elsewhere in the SAME spectrum is still caught. The witness peak is
    /// what keeps this from being vacuously green over an inert detector (#847 review
    /// finding 7a: without it, an empty result satisfied every `allSatisfy`).
    func testNonFiniteMagnitudesCannotPoisonTheDetector() {
        var d = FeedbackGuard.HowlDetector(config: config())
        let witness: [Float] = [0.1, 0.12, 0.15, 0.2, 0.25, 0.3]
        for tick in 0..<6 {
            var m = spectrum([50: witness[tick]])
            m[20] = .nan
            m[30] = .infinity
            let out = d.observe(magnitudes: m)
            XCTAssertTrue(out.allSatisfy { $0.bin != 20 && $0.bin != 30 },
                          "a poisoned bin must be invisible, not a candidate")
            XCTAssertTrue(out.allSatisfy { $0.severity.isFinite },
                          "severity reaches UI/log surfaces — non-finite must not escape")
            if tick >= 3 {
                XCTAssertEqual(out.map(\.bin), [50],
                               "the clean growing peak must still be caught amid the " +
                               "poison — a detector that goes inert under NaN would " +
                               "pass the two checks above for the wrong reason")
            } else {
                XCTAssertTrue(out.isEmpty, "persistence still applies to the witness")
            }
        }
    }

    /// COUNTERWEIGHTS (§3, green on both trees): this slice adds a brain and must not
    /// disturb the level half or the slew law the wiring will reuse.
    func testTheDuckAndTheSlewAreUndisturbed() {
        XCTAssertEqual(FeedbackGuard.gainReductionDB(rmsHistory: [0.5, 0.6, 0.65]), 0,
                       "under the ceiling the duck stays silent — level half untouched")
        XCTAssertGreaterThan(
            FeedbackGuard.gainReductionDB(rmsHistory: [0.5, 0.8, 0.99]), 0,
            "over the ceiling and rising it still ducks — the last-resort defence stands")
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: 0, target: -24), -4,
                       "the slew law is unchanged; the wiring slice ramps every band " +
                       "through exactly this function")
    }
}
