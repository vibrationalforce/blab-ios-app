// RefractoryIsAskedInTimeTests.swift
// Echoel — the beat-refractory is a TIME and must be asked as one. In the BLOCKING bundle.
//
// ⛔ THIS FILE REPLACES `RefractoryFollowsTheMeasuredRateTests.swift` FROM THE SAME DAY, and
// the rename is the point rather than tidiness: that file guarded a sample-count conversion,
// and the conversion itself was the defect. A guard whose NAME describes an approach the code
// no longer takes is the stale-name trap this repo keeps paying for, so it went with it.
//
// THE TWO-STEP HISTORY, because each step is instructive (#373 → #374):
//
// 1. `detectPeaks` spaced accepted peaks by a count derived from `effectiveSampleRate` — the
//    ASSUMED 15 Hz, re-tuned at most once per acquisition. On the 7.5–15 Hz captures the
//    device logs record, the count came from the wrong rate.
// 2. #373 substituted the MEASURED window rate and deliberately preserved truncation, to keep
//    the change a no-op where the rates already agree. A review found what those two do
//    TOGETHER, which neither does alone: the local-maximum test compares against `i±1` and
//    `i±2`, so two accepted peaks can never be closer than THREE indices — a pair at distance
//    1 or 2 would need `w[a] > w[b]` and `w[b] > w[a]`. A minimum distance of 1, 2 or 3
//    therefore rejects NOTHING, and measured-rate-plus-truncation lands 7.5–13.3 Hz devices
//    exactly there. The refractory became a provable no-op on precisely the hardware the fix
//    was aimed at.
//
// So the fix is not a better conversion — it is not converting. `isWithinRefractory` compares
// two sample TIMESTAMPS, which `detectPeaks` already uses three statements later to compute
// the intervals themselves. That also removes a second problem the same review found: the
// window is NOT uniformly sampled (the saturation hold drops samples while wall time
// advances), so any window-wide rate under-reports exactly when the signal is worst.
//
// ⚠️ WHAT A GREEN HERE DOES NOT MEAN. This is one pure predicate. It cannot say a pulse was
// read correctly on a device. And note a scope limit the review raised: on a stale-15 device
// the BANDPASS is also designed for 15 Hz, so at a real 7.5 Hz its 0.7–4 Hz passband sits at
// 0.35–2 Hz. A poor device result would therefore not falsify this change.

#if canImport(AVFoundation)
import Foundation
import XCTest
@testable import Echoelmusic

final class RefractoryIsAskedInTimeTests: XCTestCase {

    typealias A = CameraAnalyzer

    // MARK: - The invariant the sample-count version could not hold

    /// ⛔ THE OBVIOUS VERSION OF THIS TEST IS WRONG, and I wrote it before catching it — it is
    /// recorded here because the mistake looks like a passing test. "Take one gap, express it
    /// on each rate's sample grid, assert the verdicts agree" REQUANTISES the gap: 0.29 s is
    /// 2 samples at 7.5 Hz (0.267 s) but 9 at 30 Hz (0.300 s), which genuinely straddle a
    /// 0.3 s refractory. That test goes red on correct code, because the grid it introduced —
    /// not the predicate — moved the gap.
    ///
    /// So the comparison is against the exact time rule instead, over the grids that actually
    /// occur. The first assertion is a restatement of the contract (it catches a rounding step
    /// smuggled back into the predicate, nothing more). The second carries the real content:
    /// the OLD sample-count rule disagrees on real (rate, spacing) pairs, and every single
    /// disagreement is in the same direction — the count was too permissive.
    func testTheVerdictIsTheExactTimeComparisonAndTheCountRuleWasNot() {
        var disagreements: [String] = []
        for rate in [7.5, 10.0, 12.0, 13.0, 15.0, 20.0, 30.0] {
            for bpm in [0.0, 72.0] {
                let seconds = A.refractorySeconds(autoBPM: bpm)
                let countRuleDistance = Swift.max(1, Int(rate * seconds))
                // Timestamps from zero: at a realistic CFAbsoluteTime (~8e8) the boundary is
                // fuzzy by ~1e-7 s, which is physically irrelevant but would make an exact
                // comparison here depend on rounding rather than on the rule.
                for samples in 3...12 {
                    let gap = Double(samples) / rate
                    let verdict = A.isWithinRefractory(previous: 0, candidate: gap, autoBPM: bpm)
                    XCTAssertEqual(verdict, gap < seconds, """
                        At \(rate) Hz / autoBPM \(bpm), a \(samples)-sample gap of \(gap) s was \
                        judged \(verdict) but the refractory is \(seconds) s. The predicate has \
                        stopped being a plain time comparison.
                        """)
                    // Distances 1 and 2 are unreachable (the local-maximum test forbids them),
                    // so only 3 and up can reveal a difference.
                    if (samples < countRuleDistance) != (gap < seconds) {
                        disagreements.append("\(rate)Hz/bpm\(bpm)/\(samples)")
                        XCTAssertTrue(gap < seconds, """
                            At \(rate) Hz / autoBPM \(bpm) the count rule was STRICTER than the \
                            time rule for a \(samples)-sample gap. Every known disagreement runs \
                            the other way (the count under-rejects); a reversal means the \
                            refractory now discards real beats.
                            """)
                    }
                }
            }
        }
        XCTAssertFalse(disagreements.isEmpty, """
            The sample-count rule now agrees with the time rule everywhere tested. That would \
            mean this change is a no-op — but it is not, and the commit says so: it rejects \
            gaps the count admitted. If the rates or the refractory table changed, re-derive \
            this rather than deleting it.
            """)
    }

    /// The concrete case the review found, stated as its own test so a regression names itself.
    /// At 7.5 Hz a three-sample gap is 0.4 s. With autoBPM 72 the refractory is ~0.4167 s, so
    /// 0.4 s is INSIDE it and the candidate must be refused. The sample-count version computed
    /// a distance of 3, which rejects nothing at all.
    func testTheSevenAndAHalfHertzGapThatTheCountVersionLetThrough() {
        let t0 = 500.0
        let threeSamplesAtSevenAndAHalf = 3.0 / 7.5     // 0.4 s
        XCTAssertTrue(A.isWithinRefractory(previous: t0,
                                           candidate: t0 + threeSamplesAtSevenAndAHalf,
                                           autoBPM: 72), """
            A 0.4 s gap is no longer inside the ~0.4167 s refractory for a 72 bpm fundamental. \
            On a 7.5 Hz capture that is the dicrotic notch being admitted, which doubles the \
            peak count — the octave error this refractory exists to prevent.
            """)
    }

    // MARK: - The boundary itself

    /// Strictly inside is refused; exactly at the boundary and beyond is accepted. Stated
    /// because "minimum distance" is ambiguous in prose and unambiguous here.
    func testTheBoundaryIsExclusiveAtTheRefractoryItself() {
        let seconds = A.refractorySeconds(autoBPM: 0)     // 0.3 s, the acquisition fallback
        // From zero on purpose: `10.0 + 0.3 - 10.0` is 0.3000000000000007, so a boundary test
        // anchored at a non-zero origin measures floating-point rounding, not the rule.
        let t0 = 0.0
        XCTAssertTrue(A.isWithinRefractory(previous: t0, candidate: t0 + seconds - 0.001,
                                           autoBPM: 0), """
            A gap just UNDER the refractory was not treated as inside it — that peak would be \
            accepted, which is the notch getting through.
            """)
        XCTAssertFalse(A.isWithinRefractory(previous: t0, candidate: t0 + seconds,
                                            autoBPM: 0), """
            A gap exactly equal to the refractory was refused. The refractory is a MINIMUM \
            spacing; refusing the boundary makes it fractionally stricter than every comment \
            and test that describes it.
            """)
        XCTAssertFalse(A.isWithinRefractory(previous: t0, candidate: t0 + 1.0,
                                            autoBPM: 0), "A one-second gap was refused.")
    }

    /// The adaptive half still adapts: a faster fundamental means a shorter refractory, so a
    /// gap that is refused at 60 bpm can be accepted at 150.
    func testAFasterFundamentalShortensTheRefractory() {
        let t0 = 0.0
        let gap = 0.35
        XCTAssertTrue(A.isWithinRefractory(previous: t0, candidate: t0 + gap, autoBPM: 60), """
            At a 60 bpm fundamental the refractory is 0.5 s, so a 0.35 s gap must be refused.
            """)
        XCTAssertFalse(A.isWithinRefractory(previous: t0, candidate: t0 + gap, autoBPM: 150), """
            At a 150 bpm fundamental the refractory clamps to 0.3 s, so a 0.35 s gap is a \
            plausible beat and must be accepted. If this fails the adaptive half is gone and \
            fast pulses will be decimated.
            """)
    }

    // MARK: - Hostile timestamps

    /// Fails OPEN, and the direction is a deliberate choice rather than an oversight: refusing
    /// on a bad timestamp would zero the peak count, and a bpm=0 run is indistinguishable in
    /// the device logs from "no finger on the lens" — the diagnosis this repo has already lost
    /// time to twice.
    func testANonFiniteTimestampAcceptsRatherThanSilencingTheScan() {
        for bad in [Double.nan, .infinity, -Double.infinity] {
            XCTAssertFalse(A.isWithinRefractory(previous: bad, candidate: 5, autoBPM: 72),
                           "A previous timestamp of \(bad) refused the candidate.")
            XCTAssertFalse(A.isWithinRefractory(previous: 5, candidate: bad, autoBPM: 72),
                           "A candidate timestamp of \(bad) was refused.")
        }
    }

    /// Out-of-order timestamps mean the window is corrupt. Unlike a non-finite value there is
    /// no safe reading, so the candidate is refused rather than trusted — a negative gap would
    /// otherwise sail past any "gap < refractory" test as a large negative number.
    func testAnOutOfOrderTimestampIsRefused() {
        XCTAssertTrue(A.isWithinRefractory(previous: 100, candidate: 99, autoBPM: 72), """
            A candidate BEFORE the previous peak was accepted. A negative gap is always less \
            than the refractory, so this must refuse — otherwise corrupt ordering silently \
            admits peaks at any spacing.
            """)
    }

    // MARK: - The structural half: no going back to a sample count

    /// The arithmetic above stays green even if someone reintroduces a count, because the
    /// predicate would still be correct in isolation — it would simply stop being called. This
    /// is the check that fails in that case.
    func testThePeakScanComparesTimestampsAndNotASampleDistance() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Video/CameraAnalyzer.swift")
        guard let src = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("CameraAnalyzer.swift not readable at \(path.path) — source scan skipped")
        }
        XCTAssertTrue(src.contains("isWithinRefractory(previous:"), """
            The peak scan no longer calls `isWithinRefractory`. If the refractory moved, it \
            needs its own guard; if it was converted back to a sample count, read this file's \
            header — that form is provably inert below ~13.3 Hz.
            """)
        XCTAssertFalse(src.contains("minPeakDistance"), """
            `minPeakDistance` is back in `CameraAnalyzer.swift`. A refractory expressed as a \
            sample count cannot reject anything when it truncates to 3 or less, which is what \
            it does on every capture below ~13.3 Hz.
            """)
        XCTAssertFalse(src.contains("refractorySamples"), """
            `refractorySamples` is back. It was deleted with #374, not deprecated — see the \
            header for why converting a refractory into samples is the defect rather than the \
            fix.
            """)
    }
}
#endif
