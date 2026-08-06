// ResonanceBreathingNeedsMoreThanOneWindowTests.swift
// Echoel — #343. The camera could not measure the one breathing rate the product is about.
//
// ⭐ THE DEFECT, and it is not a settling-time nuisance. `CameraRPPGBioPublisher` built a
// FRESH `RespirationEstimator` on every publish and fed it only the newest analysis window.
// That window is 10 s (`CameraAnalyzer`: `min(n, Int(effectiveSampleRate * 10))`). Respiration
// rate is read from the time between two UPWARD zero-crossings of the band-passed RSA signal,
// so a window that spans ONE breath cycle can hold at most one crossing — and one crossing is
// not a period. At 6 breaths/min the cycle IS 10 s.
//
// 6/min is not an arbitrary corner. It is the HRV-resonance rate this app cites in
// `BioScienceInfo` (Lehrer/Vaschillo) and paces toward in `BreathPacer`. So the camera was
// structurally blind exactly where the product aims, and it said so in the least useful way:
// `confidence` still landed at 0.46–0.50 — ABOVE the 0.4 gate the publisher uses — while
// `ratePerMinute` stayed 0. "Breath measured: yes. Rate: zero."
//
// It went unnoticed because it is RATE-DEPENDENT, which `testFasterBreathingAlwaysWorked`
// pins: at 15 breaths/min a 10 s window holds two or three crossings and the old code was
// right at every phase. Anyone testing by breathing normally saw a working feature.
//
// THE FIX is not a longer window (that costs latency everywhere — see #340, which calls the
// 10 s window the single largest item in the bio→audio budget). It is to stop throwing the
// estimator away: ONE estimator per take, each beat ingested exactly once, via the absolute
// `CameraAnalyzer.beatTimes` this slice adds. Windows overlap ~90 % and interval VALUES carry
// no identity, so "newer than the last beat I consumed" is the only exact de-duplication.
//
// ⚠️ HONEST LIMITS.
//   · The behavioural half drives the PURE estimator with a synthetic RSA series. It proves
//     the arithmetic and the blind spot. It does NOT prove the camera path works on a real
//     finger — that needs a device run, and the acquisition itself is a separate open
//     problem (#304/#410).
//   · The wiring half is a source scan, so it can confirm that the estimator is long-lived
//     and reset on stop, not that the values reach the ear.
//   · Real RSA is noisier and shallower than a clean sine. The thresholds here are floors
//     against the STRUCTURAL failure (rate identically 0), not quality judgements.

import Foundation
import XCTest
@testable import Echoelmusic

final class ResonanceBreathingNeedsMoreThanOneWindowTests: XCTestCase {

    /// The rate `BioScienceInfo` cites and `BreathPacer` paces toward.
    private static let resonanceBreathsPerMinute = 6.0
    /// `CameraAnalyzer` analyses `effectiveSampleRate * 10` samples.
    private static let analysisWindowSeconds = 10.0
    /// The publisher's own gate: `resp.confidence >= 0.4` means "breath measured".
    private static let measuredBreathGate = 0.4

    // MARK: - The blind spot

    /// ⭐ THE REGRESSION, stated as the defect rather than as the repair: ONE analysis window
    /// cannot yield a resonance breathing rate, at ANY starting phase. Four phases, because a
    /// single one would leave open the reading "unlucky alignment" — it is not luck, it is
    /// that one cycle contains one crossing.
    func testOneWindowCannotMeasureResonanceBreathing() {
        for phase in Self.phases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: Self.analysisWindowSeconds,
                                      breathsPerMinute: Self.resonanceBreathsPerMinute,
                                      phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            XCTAssertEqual(estimator.ratePerMinute, 0,
                           """
                           A single \(Self.analysisWindowSeconds) s window reported \
                           \(estimator.ratePerMinute) breaths/min at phase \(phase). If this \
                           now passes because the estimator changed, re-derive the guard — but \
                           do NOT delete it: it is the reason the estimator is long-lived.
                           """)
            // The half that makes it harmful rather than merely incomplete: the publisher's
            // gate is OPEN here, so the frame is published as a measured breath of rate zero.
            XCTAssertGreaterThanOrEqual(
                estimator.confidence, Self.measuredBreathGate,
                """
                Phase \(phase): confidence \(estimator.confidence) fell below the publisher's \
                \(Self.measuredBreathGate) gate. That would make the old behaviour honest \
                (no claim at all) and this test's premise wrong — recheck before trusting it.
                """)
        }
    }

    /// The same signal, accumulated the way the publisher now does it, is measured correctly.
    /// 60 s is roughly six resonance cycles — the estimator needs four crossings for full
    /// count-confidence, so this is the first duration at which the answer is not marginal.
    func testAccumulatingAcrossWindowsMeasuresResonanceBreathing() {
        for phase in Self.phases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: 60,
                                      breathsPerMinute: Self.resonanceBreathsPerMinute,
                                      phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            XCTAssertEqual(estimator.ratePerMinute, Self.resonanceBreathsPerMinute, accuracy: 1.0,
                           "phase \(phase): 60 s of 6/min RSA read as \(estimator.ratePerMinute)")
            XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                        "phase \(phase): confidence \(estimator.confidence)")
        }
    }

    /// Why nobody caught it: at an ordinary resting rate the old code was right at every
    /// phase. This is the control that keeps the finding narrow and truthful — the window was
    /// never "too short" in general, it was too short for slow breathing.
    func testFasterBreathingAlwaysWorked() {
        for phase in Self.phases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: Self.analysisWindowSeconds,
                                      breathsPerMinute: 15, phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            XCTAssertGreaterThan(estimator.ratePerMinute, 0,
                                 """
                                 15 breaths/min in one window read as 0 at phase \(phase). \
                                 If that becomes true, the defect is no longer rate-specific \
                                 and this file's whole framing needs rewriting.
                                 """)
        }
    }

    // MARK: - The wiring

    /// A correct estimator that is thrown away every second is the same defect with more
    /// steps, so the fix is only real if the publisher HOLDS one. Anchored on the property
    /// existing first — a scan that only forbids the old shape passes on a file that lost
    /// both (the #367 trap: a guard whose pass carries no information).
    func testThePublisherHoldsOneEstimatorForTheWholeTake() throws {
        let text = Self.codeOnly(try Self.source("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"))
        XCTAssertTrue(text.contains("private var respiration = RespirationEstimator()"),
                      """
                      The publisher no longer holds a long-lived RespirationEstimator. Without \
                      it, resonance breathing is unmeasurable again — see this file's header.
                      """)
        XCTAssertFalse(text.contains("var resp = RespirationEstimator()"),
                       """
                       A per-publish RespirationEstimator is back. That is the #343 defect \
                       verbatim: it can only ever see one 10 s window.
                       """)
        XCTAssertTrue(text.contains("respiration.reset()"),
                      """
                      `stop()` must reset the estimator. A new take gets a new one: the last \
                      take's baseline, envelope and cycle count say nothing about this body \
                      now. (The first version of this message blamed a stale cursor across a \
                      camera teardown — false: the clock is `systemUptime`, monotonic since \
                      boot. Right conclusion, wrong reason.)
                      """)
    }

    /// ⭐ THE REGRESSION #343 ITSELF INTRODUCED, and the reason this file grew a fourth
    /// behavioural test. `crossingCount` is monotonic and `ratePerMinute` keeps its last
    /// value, so once four cycles are seen `countConf` pins at 1.0 and `confidence` has a
    /// hard floor of 0.5 — permanently above the publisher's 0.4 "measured" gate.
    ///
    /// While the estimator was rebuilt every publish that floor could not outlive one 10 s
    /// window. Making it live for a whole take turned a bounded staleness into a LATCH: on a
    /// 60 s resonance series followed by a perfectly flat heart rate, confidence sat at
    /// exactly 0.500 forever and the publisher went on reporting "6.0 breaths/min, measured"
    /// with no breathing at all — a frozen value stamped with a fresh timestamp, the very
    /// thing the pulse path already has a truth gate for.
    ///
    /// So the fix for #343 is only honest WITH the freshness term, and this test is what
    /// keeps the two together.
    func testAMeasuredRateExpiresWhenTheBreathingStops() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 60,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                    "premise: 60 s of clean RSA must read as measured first")

        // Breathing stops; the heart keeps beating at a flat rate. Nothing new to see.
        var t = 60.0
        for _ in 0..<30 {
            t += 1
            estimator.ingest(heartRate: 60, at: t)
        }
        XCTAssertLessThan(estimator.confidence, Self.measuredBreathGate,
                          """
                          30 s after the last breath cycle the estimator still reports \
                          confidence \(estimator.confidence) — at or above the publisher's \
                          \(Self.measuredBreathGate) gate — so `breathRate` \
                          \(estimator.ratePerMinute) keeps being published as MEASURED. That \
                          is the latch the freshness term exists to prevent; do not remove it \
                          without replacing it.
                          """)
    }

    /// The other half of the same rule: the expiry must not fire while breathing continues.
    /// Without this, "make confidence decay" could be satisfied by a term that also kills a
    /// perfectly good resonance measurement — the slowest supported rate has 15 s between
    /// cycles, which is longer than most naive timeouts.
    func testAContinuingSlowBreathNeverExpires() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 120,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                    """
                                    Two minutes of uninterrupted 6/min breathing expired to \
                                    \(estimator.confidence). The freshness grace is too tight \
                                    for the rate this product is built around.
                                    """)
        XCTAssertEqual(estimator.ratePerMinute, Self.resonanceBreathsPerMinute, accuracy: 1.0)
    }

    /// `beatTimes` only works as a de-duplication key while it stays 1:1 with `rrIntervals`.
    /// The two are produced together today; this holds the pairing so a later edit to one
    /// side cannot silently desynchronise them into an off-by-one respiration signal.
    func testEveryRRAssignmentCarriesItsBeatTimes() throws {
        let text = Self.codeOnly(try Self.source("Sources/Echoelmusic/Video/CameraAnalyzer.swift"))
        let assigns = Self.count(of: "rrIntervals = cleanIntervals", in: text)
        let paired = Self.count(of: "beatTimes = cleanEndTimes", in: text)
        XCTAssertGreaterThan(assigns, 0, "Could not find the RR publication at all — re-derive")
        XCTAssertEqual(assigns, paired,
                       """
                       \(assigns) site(s) publish `rrIntervals` but only \(paired) publish \
                       `beatTimes`. A consumer that indexes one by the other would read the \
                       wrong beat's interval.
                       """)
        let clears = Self.count(of: "rrIntervals.removeAll()", in: text)
        let clearsPaired = Self.count(of: "beatTimes.removeAll()", in: text)
        XCTAssertEqual(clears, clearsPaired,
                       """
                       \(clears) site(s) clear `rrIntervals` but only \(clearsPaired) clear \
                       `beatTimes`. A surviving times array outlives the intervals it indexes.
                       """)
    }

    // MARK: - Helpers

    private static let phases: [Double] = [0, .pi / 2, .pi, 3 * .pi / 2]

    private struct Beat { let time: Double; let heartRate: Double }

    /// Beat series of a heart whose rate is sinusoidally modulated by breathing (RSA) —
    /// the signal `RespirationEstimator` is built to read. Each beat lands one interval after
    /// the last, so the sample spacing is irregular exactly as it is on a real pulse.
    /// The ±3 bpm swing is a deliberately generous but not absurd resting RSA amplitude.
    private static func rsaBeats(seconds: Double,
                                 breathsPerMinute: Double,
                                 phase: Double,
                                 meanBPM: Double = 60,
                                 swingBPM: Double = 3) -> [Beat] {
        var out: [Beat] = []
        var t = 0.0
        while t < seconds {
            let hr = meanBPM + swingBPM * sin(2 * .pi * (breathsPerMinute / 60) * t + phase)
            out.append(Beat(time: t, heartRate: hr))
            t += 60 / hr
        }
        return out
    }

    /// Everything before a `//` on each line. This file's scans look for shapes that the
    /// SOURCE also describes in prose (the fixed code documents the broken form by name), and
    /// a raw-text scan cannot tell code from a comment — a trap this repo has now paid for
    /// from both directions (#404, #420).
    private static func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func count(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var total = 0
        var cursor = text.startIndex
        while let found = text.range(of: needle, range: cursor..<text.endIndex) {
            total += 1
            cursor = found.upperBound
        }
        return total
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relativePath) not present — this scan cannot report a green")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
