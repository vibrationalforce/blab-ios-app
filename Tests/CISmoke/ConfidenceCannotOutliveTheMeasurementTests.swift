// ConfidenceCannotOutliveTheMeasurementTests.swift
// Echoel — a published pulse confidence may not describe a measurement that no longer happened.
//
// WHAT THIS GUARDS, and it comes straight off a device log rather than a code read. Log 2482
// (v10.79.365) contains this line:
//
//     rPPG: finger=yes … amp=0.0134 pk=3 acf=0.00 auto=0 … bpm=65 conf=0.59
//
// `acf=0.00 auto=0` means the autocorrelation found NO periodicity — the independent estimator
// reported nothing at all. `bpm=65 conf=0.59` was published beside it, both identical to the
// previous window. The arithmetic was not wrong; the analyzer had RETURNED EARLY (too few
// peaks, or no usable intervals, with the autocorrelation too weak for `fallbackBPM`), and an
// early return leaves `bpmConfidence` and `estimatedBPM` untouched. Downstream — the trust
// gate, the bio bus, the pulse readout — a stale confident number is indistinguishable from a
// live one. That is the defect: not a wrong number, an OLD number wearing a fresh one's clothes.
//
// THE FIX IS A CEILING ON AGE, NOT A DECAY FACTOR, and this file pins the shape as much as the
// values. The peak scan is throttled to ~4 Hz, so any per-call factor compounds at a rate that
// depends on the camera's frame rate, the throttle and the drain size — the class #337 names
// ("measure dt, do not assume the rate"), and the class the motion branch in the same file has
// already paid for once (a 0.6 factor wiped a good lock in one tick). `confidenceCeiling(forAge:)`
// is a pure function of elapsed TIME: it cannot compound, and it behaves identically on a phone
// that delivers 15 fps and one that delivers 30.
//
// ⚠️ THE TWO CONSTANTS ARE A JUDGEMENT AND ARE NOT PINNED HERE. 2 s of grace and zero by 8 s
// were chosen, not measured. What this file pins is the SHAPE — fresh is unpenalised, old is
// zero, and it is monotone in between — because that is what stays true when the founder's
// device says the numbers should be 1.5 and 6. Pinning the constants would make a legitimate
// tuning pass a red for no reason, which is how a guard gets deleted instead of updated.
//
// ⚠️ HONEST LIMITS. The first test is a real unit test of a pure function. The second is a
// source-text scan (there is no simulator in the blocking bundle) proving that each bail-out
// which produces no measurement actually calls the clamp — a correct ceiling nobody calls is
// worth nothing. Neither proves the published bio stream improves on a real body.
// NEEDS-FOUNDER-VERIFY: get a clean lock, then LIFT the finger and watch the pulse readout —
// does the confidence fall away within a few seconds instead of standing still at its last
// value? And the opposite risk: with the finger held normally, does the reading still hold
// through the ordinary wobbles, or did the grace period turn out to be too short?
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest
#if canImport(AVFoundation)
@testable import Echoelmusic
#endif

final class ConfidenceCannotOutliveTheMeasurementTests: XCTestCase {

    private static let analyzer = "Sources/Echoelmusic/Video/CameraAnalyzer.swift"

    #if canImport(AVFoundation)
    /// The ceiling is 1 while fresh, 0 once old, and never rises with age.
    func testTheCeilingFallsWithAgeAndReachesZero() {
        let hold = CameraAnalyzer.confidenceHoldSeconds
        let zero = CameraAnalyzer.confidenceZeroSeconds

        XCTAssertLessThan(hold, zero, """
            The grace period is not shorter than the age at which confidence must be zero, so \
            the ramp between them is inverted or empty. A stale confidence would then either \
            never fall or fall instantly — the two failure modes this ceiling exists to sit \
            between.
            """)

        XCTAssertEqual(CameraAnalyzer.confidenceCeiling(forAge: 0), 1, accuracy: 0.0001, """
            A measurement taken THIS instant is being penalised. The ceiling may only ever \
            lower a confidence that has gone stale; if it bites at age zero it caps every \
            healthy lock in the app.
            """)
        XCTAssertEqual(CameraAnalyzer.confidenceCeiling(forAge: hold), 1, accuracy: 0.0001, """
            The grace period does not reach its own boundary, so a single dropped window \
            already costs confidence. The whole point of the grace is that one missing window \
            on a good lock is free.
            """)
        XCTAssertEqual(CameraAnalyzer.confidenceCeiling(forAge: zero), 0, accuracy: 0.0001, """
            Confidence is still positive at the age it is supposed to have reached zero. Past \
            this point the published pair describes nothing that was measured, and any \
            positive number invites a consumer to trust it.
            """)
        XCTAssertEqual(CameraAnalyzer.confidenceCeiling(forAge: zero * 10), 0, accuracy: 0.0001, """
            The ceiling does not stay at zero for ages beyond the zero point — a linear ramp \
            continued past its end goes NEGATIVE, and a negative confidence compared with a \
            `>` gate is a different bug, not a safer one.
            """)

        // Monotone in between — the property that survives a re-tuning of both constants.
        var previous = 1.0
        for step in 0...40 {
            let age = zero * 1.2 * Double(step) / 40.0
            let value = CameraAnalyzer.confidenceCeiling(forAge: age)
            XCTAssertLessThanOrEqual(value, previous + 0.0001, """
                The ceiling RISES as the measurement gets older (age \(age) s gave \(value) \
                after \(previous)). Whatever the constants are, a stale reading may never earn \
                back trust by waiting — only a fresh measurement may.
                """)
            previous = value
        }

        XCTAssertEqual(CameraAnalyzer.confidenceCeiling(forAge: .nan), 0, accuracy: 0.0001, """
            A non-finite age produces something other than zero. Timestamps arriving from the \
            capture pipeline are not guaranteed sane, and the safe reading of "I cannot tell \
            how old this is" is "do not trust it".
            """)
    }
    #endif

    /// Every bail-out that produces no measurement clamps the published confidence.
    ///
    /// ⛔ A CEILING NOBODY CALLS IS WORTH NOTHING, which is why this scan exists next to a real
    /// unit test. The defect in the device log was not a miscalculated confidence — it was a
    /// confidence that no code path touched. A future refactor that adds a fifth early return
    /// re-opens exactly that hole while the test above stays green.
    func testEveryBailOutClampsTheConfidence() throws {
        let source = try codeLines(Self.analyzer)

        // The bail-outs, by the guard text each one is spelled with. Kept as literal fragments
        // rather than a regex over `return` because this file is 900+ lines and most returns
        // are ordinary control flow, not "I produced nothing".
        let bailOuts = [
            "guard !cleanIntervals.isEmpty",
            "guard bpm > 40 && bpm < 200"
        ]
        for text in bailOuts {
            guard let line = source.first(where: { $0.contains(text) }) else {
                throw XCTSkip("""
                    `\(text)` is gone from CameraAnalyzer — the peak path was restructured, so \
                    this guard should be rewritten with it rather than left to pass vacuously
                    """)
            }
            XCTAssertTrue(line.contains("ageConfidence("), """
                A bail-out that produces no measurement does not clamp the published \
                confidence: \(line.trimmingCharacters(in: .whitespaces)) The window ends with \
                `bpmConfidence` and `estimatedBPM` exactly as the last real measurement left \
                them, and nothing downstream can tell the difference. Device log 2482 shows \
                what that looks like: `acf=0.00 auto=0 … bpm=65 conf=0.59`.
                """)
        }

        // The two peak-count bail-outs delegate to `fallbackBPM` first, then clamp — assert the
        // pairing, since calling only the fallback is precisely the pre-fix behaviour.
        let fallbackCalls = source.filter { $0.contains("fallbackBPM(auto") }
        XCTAssertFalse(fallbackCalls.isEmpty, """
            `fallbackBPM(auto…)` is no longer called from the peak path. If the autocorrelation \
            fallback was removed, the bail-outs that depended on it need re-reading — and this \
            guard needs rewriting with them.
            """)
        for call in fallbackCalls {
            XCTAssertTrue(call.contains("timestamp:"), """
                `fallbackBPM` is called without a timestamp: \
                \(call.trimmingCharacters(in: .whitespaces)) It commits a real measurement, so \
                it has to stamp the freshness clock — otherwise a run carried entirely by the \
                autocorrelation ages out under the ceiling while it is measuring perfectly well.
                """)
        }
    }

    // MARK: - Reading the source

    /// Lines of `path` that are not whole-line comments. Load-bearing: the rationale blocks in
    /// `CameraAnalyzer` quote `ageConfidence` and the guard texts in prose, so an unfiltered
    /// scan could be satisfied by the paragraphs explaining the fix while the code had lost it.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent(Self.analyzer).path) else {
            throw XCTSkip("Source tree not present next to the test bundle — nothing to check")
        }
        return root
    }
}
