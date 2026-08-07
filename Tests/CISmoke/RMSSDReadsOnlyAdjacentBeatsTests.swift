// RMSSDReadsOnlyAdjacentBeatsTests.swift
// Echoel — #425. `CameraAnalyzer.calculateRMSSD()` walked `rrIntervals` FLAT, and the publisher
// computed `hrvPNN50` from the same array flat. That array is COMPACTED TWICE — a `continue`
// past every peak difference outside 0.3…1.5 s, then an IQR rejection, both writing into fresh
// arrays — so two entries that are neighbours in the array can be seconds apart in the body.
// RMSSD and pNN50 read CONSECUTIVE pairs, so a difference taken across a removed beat is an
// artifact of the removal, not a beat-to-beat change.
//
// ⭐ THE SLICE CHANGES NO ACCEPTANCE DECISION, and that is the design, not a caveat.
// `RRIntervalHygiene` (the strap's route to `HRVMetrics`'s `segments:` overloads) DECIDES which
// beats to accept and returns the runs as a by-product. The camera has already made that
// decision, twice, with its own rules — running hygiene over the survivors would apply a THIRD
// acceptance policy to a series whose adjacency is already destroyed, and Malik's 20 % step is
// tuned for a chest strap. `RRAdjacency` instead derives the runs from evidence the analyzer
// already keeps for #343: `beatTimes`, the absolute time of each interval's SECOND beat. Nothing
// is accepted or rejected; availability cannot drop.
//
// ⚠️ WHICH CLAIMS HERE CAN ACTUALLY FAIL, said first, because most of them cannot fail TODAY.
//
//   • Claims 1 and 2 (the two source scans) are the regressions. Before this slice
//     `calculateRMSSD` held a hand-written flat loop and the publisher held
//     `pnn50(rrMs: rrMs)`; both assertions were false. That is established by reading the old
//     code, not by a run — `RRAdjacency` does not exist on the old tree, so this FILE could not
//     compile there. Same honesty as every other scan guard in this bundle.
//   • Claim 3 (SDNN stays flat) and claim 6 (the 1:1 invariant) are COUNTERWEIGHTS: green on
//     both sides, present so that the tidy-looking next edit goes red instead of silent.
//   • Claims 4 and 5 exercise a type this commit introduces, so they were never red. They pin
//     behaviour a later simplification would take away, which is the only thing a test over new
//     code can honestly claim.
//
// ⭐ CLAIM 3 IS THE EXPENSIVE ONE AND IT IS WORTH ITS SPACE. The symmetric-looking follow-up is
// "make SDNN segment-aware too". `HRVMetrics.sdnn(segments:)` deliberately EXCLUDES length-1
// runs (the compensatory-pause exclusion, documented at that overload), and on a badly-gapped
// camera take almost every run is length 1. Measured on the isolated fixture below — three
// accepted intervals, each with a dropped beat on either side — `sdnn(rrMs:)` reads **50.0 ms**
// and `sdnn(segments:)` reads **0.0**. Publishing 0 for a take that has real intervals is worse
// than the artifact it would be trying to remove, and whether the strap's exclusion suits the
// camera's gap structure is UNMEASURED. So the camera keeps the flat form on purpose, and the
// scan makes that a decision rather than an accident.
//
// ⚠️ THE FIXTURE NUMBERS BELOW ARE A FIXTURE, NOT A DEVICE MEASUREMENT. The gapped series in
// claim 5 is deliberately harsh (one ~85 ms step across the hole among nine pairs) and inflates
// flat RMSSD by +159 %. The honest device-scale figures — 0 % on a clean take, up to ~+9.6 %
// RMSSD and +2…4 pp pNN50 on poor contact — are in `RRAdjacency`'s header, together with the
// note that the artifact RATES driving them are assumptions rather than recorded measurements.

import Foundation
import XCTest
@testable import Echoelmusic

/// Thrown when a scan anchor is gone. An uncaught error in a `throws` test method is a FAILURE,
/// which is the point — `XCTSkip` would have been green, and a rename is exactly the edit that
/// must not silently disarm a scan.
private struct AnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class RMSSDReadsOnlyAdjacentBeatsTests: XCTestCase {

    // MARK: - 1. the analyzer pools within runs

    /// RED before #425: the body was a hand-written `for i in 1..<rrIntervals.count` loop.
    ///
    /// Pins the ARGUMENT as well as the call. A scan that only required the string
    /// `RRAdjacency.segments` would stay green on `segments(intervalsMs: rrIntervals,
    /// endTimesSeconds: [])` — which returns `[]`, makes RMSSD 0 forever, and looks correct in
    /// a diff. #431's lesson: a guard over a call must pin what makes the call meaningful.
    func testTheAnalyzerPoolsWithinRuns() throws {
        let body = try calculateRMSSDBody()
        XCTAssertTrue(body.contains("RRAdjacency.segments"), """
            `CameraAnalyzer.calculateRMSSD()` no longer goes through `RRAdjacency`.
            `rrIntervals` is compacted twice, so a flat successive-difference walk counts \
            differences across dropped beats. Body scanned (comments blanked):
            \(body)
            """)
        XCTAssertTrue(body.contains("endTimesSeconds: beatTimes"), """
            `calculateRMSSD()` calls `RRAdjacency.segments` but not with `beatTimes`.
            The timestamps ARE the evidence — with anything else the segmentation is either \
            wrong or vacuous. Body scanned:
            \(body)
            """)
        XCTAssertTrue(body.contains("HRVMetrics.rmssd(segments:"), """
            `calculateRMSSD()` computes the runs and then does not use the segment-aware \
            metric. `rmssd(rrMs:)` over a flattened run list is the original defect with an \
            extra step. Body scanned:
            \(body)
            """)
    }

    // MARK: - 2. the publisher pools pNN50 within runs

    /// RED before #425: `hrvPNN50: Float(HRVMetrics.pnn50(rrMs: rrMs))`.
    ///
    /// pNN50 is the one that moves MOST in relative terms, because a cross-gap difference is
    /// exactly the kind that clears the 50 ms threshold — on the fixture in claim 5 it is the
    /// difference between 11.1 % and 0 %.
    func testThePublisherPoolsPNN50WithinRuns() throws {
        let window = try liveFrameWindow(from: "hrvPNN50:", to: nil)
        XCTAssertTrue(window.contains("RRAdjacency.segments"), """
            The camera publisher computes `hrvPNN50` from the compacted array flat.
            Window scanned (comments blanked):
            \(window)
            """)
        XCTAssertTrue(window.contains("endTimesSeconds: beatTimes"), """
            `hrvPNN50` segments on something other than `beatTimes` — see the note on \
            claim 1 about pinning the argument, not just the call. Window scanned:
            \(window)
            """)
    }

    // MARK: - 3. COUNTERWEIGHT — SDNN deliberately stays flat

    /// Green before AND after. Present so the symmetric-looking follow-up is a red test rather
    /// than a silent behaviour change: see the ⭐ block at the top for the measured cost
    /// (50.0 ms → 0.0 on a fully isolated take).
    func testSDNNDeliberatelyStaysFlat() throws {
        let window = try liveFrameWindow(from: "hrvSDNNms:", to: "hrvPNN50:")
        XCTAssertTrue(window.contains("HRVMetrics.sdnn(rrMs:"), """
            `hrvSDNNms` no longer uses the flat form. SDNN is a SPREAD and has no adjacency \
            requirement, so segmenting it buys nothing — what it would import is \
            `sdnn(segments:)`'s isolated-beat exclusion, a separate judgment that is \
            unmeasured for the camera's gap structure. Window scanned:
            \(window)
            """)
        XCTAssertFalse(window.contains("segments"), """
            `hrvSDNNms` mentions segments. If this is a deliberate reversal, change the ⭐ \
            block at the top of this file in the same commit and say what measurement \
            justified it — do not just delete this assertion. Window scanned:
            \(window)
            """)
    }

    // MARK: - 4. RRAdjacency: the arithmetic

    /// A clean take has no holes, so the segmentation returns ONE run and the result is
    /// bit-identical to the old flat walk. This is the claim that makes the slice safe to land
    /// blind: it cannot change a well-placed finger's numbers at all.
    ///
    /// Bit-identity is exact rather than approximate for a real reason, not luck:
    /// `rmssd(rrMs:)` divides by `count - 1` and `rmssd(segments:)` divides by the pair count,
    /// and for a single run of n intervals those are the same integer — so the two functions
    /// perform the identical sequence of floating-point operations.
    /// ⚠️ The fixture carries two differences past 50 ms on purpose. With a flat, low-variance
    /// series both pNN50 forms return 0 and the bit-identity assertion would be `0 == 0` — true
    /// of doing nothing at all. Here they must agree on **40 %**.
    func testACleanTakeIsOneRunAndBitIdentical() {
        let (intervals, endTimes) = take(intervalsMs: [800, 812, 869, 806, 799, 815], gapsBefore: [])
        let runs = RRAdjacency.segments(intervalsMs: intervals, endTimesSeconds: endTimes)
        XCTAssertEqual(runs.count, 1, "a series with no dropped beats must be one run")
        XCTAssertEqual(runs.first ?? [], intervals, "the one run must be the whole series")
        XCTAssertEqual(HRVMetrics.rmssd(segments: runs), HRVMetrics.rmssd(rrMs: intervals),
                       "on a clean take the segmented form must be bit-identical to the flat one")
        XCTAssertEqual(HRVMetrics.pnn50(segments: runs), HRVMetrics.pnn50(rrMs: intervals),
                       "same for pNN50 — a clean take must not move at all")
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: intervals), 40.0, accuracy: 1e-9,
                       "the fixture must actually exercise the 50 ms threshold")
        XCTAssertEqual(RRAdjacency.gapCount(intervalsMs: intervals, endTimesSeconds: endTimes), 0)
    }

    /// The tolerance is load-bearing in BOTH directions, so both are pinned.
    ///
    /// Below it, the only error in play is floating point: the times are `systemUptime` seconds
    /// and the interval makes a ×1000/÷1000 round trip through milliseconds, so the residue is
    /// a few ulps. Above it, the smallest hole a real dropped beat can leave is one peak
    /// spacing, and `CameraAnalyzer`'s refractory refuses peaks closer than ~0.2 s. The 2e-4
    /// case below is therefore NOT a physical scenario — it is the mechanism, checked just past
    /// the line, three orders of magnitude below the smallest real hole.
    func testTheToleranceSeparatesFloatResidueFromARealHole() {
        let residue = RRAdjacency.toleranceSeconds / 2
        let (i1, e1) = take(intervalsMs: [800, 800], gapsBefore: [], extraGapSeconds: [1: residue])
        XCTAssertEqual(RRAdjacency.segments(intervalsMs: i1, endTimesSeconds: e1).count, 1,
                       "a sub-tolerance residue is float noise, not a dropped beat")

        let hole = RRAdjacency.toleranceSeconds * 2
        let (i2, e2) = take(intervalsMs: [800, 800], gapsBefore: [], extraGapSeconds: [1: hole])
        XCTAssertEqual(RRAdjacency.segments(intervalsMs: i2, endTimesSeconds: e2).count, 2,
                       "anything past the tolerance is a hole — otherwise the constant is a rubber stamp")
    }

    /// Length-1 runs are KEPT. Dropping them here would pre-empt a decision that belongs to the
    /// metric: `rmssd(segments:)` and `pnn50(segments:)` skip them anyway, while
    /// `sdnn(segments:)` excludes them ON PURPOSE and would then be silently fed a different
    /// series than it asked for.
    func testIsolatedIntervalsSurviveAsLengthOneRuns() {
        let (intervals, endTimes) = take(intervalsMs: [800, 900, 850], gapsBefore: [1, 2])
        let runs = RRAdjacency.segments(intervalsMs: intervals, endTimesSeconds: endTimes)
        XCTAssertEqual(runs.map(\.count), [1, 1, 1], "every interval is isolated here")
        XCTAssertEqual(RRAdjacency.gapCount(intervalsMs: intervals, endTimesSeconds: endTimes), 2)
        XCTAssertEqual(HRVMetrics.rmssd(segments: runs), 0,
                       "no run holds a pair, so RMSSD is unknown — and `calculateRMSSD` keeps its previous value")
        // The measured cost quoted in the ⭐ block, pinned so the number cannot rot.
        XCTAssertEqual(HRVMetrics.sdnn(rrMs: intervals), 50.0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.sdnn(segments: runs), 0,
                       "this is what segmenting SDNN would publish for this take")
    }

    /// A length mismatch returns `[]` rather than indexing on a broken invariant. Not defensive
    /// noise: the two arrays are produced together and are 1:1 by construction, so a mismatch
    /// means an edit broke one side, and pairing each interval with someone else's timestamp
    /// would yield an HRV number computed from mismatched beats — worse than no number. The
    /// respiration ingest in the same publisher refuses on exactly this check.
    func testMismatchedLengthsRefuseRatherThanGuess() {
        XCTAssertEqual(RRAdjacency.segments(intervalsMs: [800, 810], endTimesSeconds: [1.0]).count, 0)
        XCTAssertEqual(RRAdjacency.gapCount(intervalsMs: [800, 810], endTimesSeconds: [1.0]), 0)
        XCTAssertEqual(RRAdjacency.segments(intervalsMs: [], endTimesSeconds: []).count, 0)
        XCTAssertEqual(RRAdjacency.gapCount(intervalsMs: [], endTimesSeconds: []), 0,
                       "gapCount must not go negative on an empty series")
    }

    // MARK: - 5. the change is not cosmetic

    /// The counterpart to claim 4: a clean take must not move, and a gapped one must.
    /// Without this, "bit-identical on a clean take" is also satisfied by doing nothing at all.
    ///
    /// Fixture, not a device measurement — see the ⚠️ block at the top. Six intervals near
    /// 800 ms, a dropped beat, then four near 900 ms: the single ~85 ms step across the hole is
    /// the entire difference, and it is the only pair that clears the pNN50 threshold.
    func testAGappedSeriesDisagreesWithTheFlatWalk() {
        let (intervals, endTimes) = take(
            intervalsMs: [800, 810, 795, 805, 800, 815, 900, 890, 905, 895],
            gapsBefore: [6])
        let runs = RRAdjacency.segments(intervalsMs: intervals, endTimesSeconds: endTimes)
        XCTAssertEqual(runs.map(\.count), [6, 4], "the hole sits between the sixth and seventh interval")

        XCTAssertEqual(HRVMetrics.rmssd(rrMs: intervals), 30.4138, accuracy: 1e-3)
        XCTAssertEqual(HRVMetrics.rmssd(segments: runs), 11.7260, accuracy: 1e-3)
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: intervals), 100.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.pnn50(segments: runs), 0, accuracy: 1e-9)

        // SDNN is untouched HERE because this fixture has no length-1 run — the flat and
        // segment-aware forms coincide. Claim 4's isolated fixture is where they part.
        XCTAssertEqual(HRVMetrics.sdnn(rrMs: intervals),
                       HRVMetrics.sdnn(segments: runs), accuracy: 1e-9)
    }

    // MARK: - 6. COUNTERWEIGHT — the 1:1 invariant the whole thing rests on

    /// Green before AND after. `RRAdjacency` is only as good as the promise that `beatTimes` and
    /// `rrIntervals` describe the same beats, and that promise lives in `CameraAnalyzer`: they
    /// are assigned together at both build sites and cleared together at both teardown sites.
    /// A future edit that clears one without the other would leave the segmentation reading
    /// last take's timestamps — and the mismatch guard in claim 4 only catches it when the
    /// LENGTHS happen to differ.
    func testTheTwoArraysAreWrittenAndClearedTogether() throws {
        // Hoisted rather than interpolated inline: #287 made the blocking gate RED because a
        // failure message built too much expression for the type-checker to price.
        let code = try analyzerSource()
        let intervalAssigns = count(of: "rrIntervals = cleanIntervals", in: code)
        let timeAssigns = count(of: "beatTimes = cleanEndTimes", in: code)
        let assignMessage = "assigned \(intervalAssigns) vs \(timeAssigns) times — "
            + "they must be written together or the segmentation reads mismatched beats"
        XCTAssertEqual(timeAssigns, intervalAssigns, assignMessage)
        XCTAssertGreaterThanOrEqual(intervalAssigns, 2, "both build sites must still be present")

        let intervalClears = count(of: "rrIntervals.removeAll()", in: code)
        let timeClears = count(of: "beatTimes.removeAll()", in: code)
        let clearMessage = "cleared \(intervalClears) vs \(timeClears) times — a take that "
            + "clears one and not the other carries the previous take's timestamps"
        XCTAssertEqual(timeClears, intervalClears, clearMessage)
        XCTAssertGreaterThanOrEqual(intervalClears, 2, "both teardown sites must still be present")
    }

    // MARK: - fixtures

    /// Build a series plus the absolute time of each interval's second beat.
    ///
    /// - Parameters:
    ///   - gapsBefore: indices at which a beat was dropped immediately before that interval —
    ///     0.85 s of unaccounted time, comfortably past `toleranceSeconds` and past the
    ///     analyzer's ~0.2 s refractory.
    ///   - extraGapSeconds: an explicit hole width per index, for the tolerance test.
    private func take(intervalsMs: [Double],
                      gapsBefore: Set<Int>,
                      extraGapSeconds: [Int: Double] = [:]) -> ([Double], [Double]) {
        var t = 10_000.0     // a plausible `systemUptime`, so the float residue is realistic
        var endTimes: [Double] = []
        for (i, ms) in intervalsMs.enumerated() {
            if gapsBefore.contains(i) { t += 0.85 }
            if let extra = extraGapSeconds[i] { t += extra }
            t += ms / 1000.0
            endTimes.append(t)
        }
        return (intervalsMs, endTimes)
    }

    // MARK: - source access

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Comment-stripped analyzer source.
    ///
    /// `SourceText.codeOnly` (#453) is load-bearing rather than hygienic here: the ⛔ block this
    /// slice added above `calculateRMSSD` quotes the OLD flat-walk description, and the doc on
    /// `hrvSDNNms` names `sdnn(segments:)` in prose. Under a scanner that kept comments, claim 3's
    /// negative assertion would go red on the very comment that explains why it is negative.
    private func analyzerSource() throws -> String {
        try source(at: "Sources/Echoelmusic/Video/CameraAnalyzer.swift")
    }

    private func publisherSource() throws -> String {
        try source(at: "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift")
    }

    private func source(at relative: String) throws -> String {
        let path = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(repoRoot().path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body of `calculateRMSSD()`.
    ///
    /// Brace-matched rather than "the next N lines": the method sits mid-file with neighbours
    /// on both sides, and a fixed window would either miss a reflowed body or widen into the
    /// next method — the file-ORDER trap this repo has paid for elsewhere. The matcher does not
    /// understand braces inside string literals; this body contains none, and a future one that
    /// does would need the matcher taught, not the guard deleted.
    private func calculateRMSSDBody() throws -> String {
        let code = try analyzerSource()
        guard let anchor = code.range(of: "func calculateRMSSD()") else {
            // FAIL, do not skip: a skip PASSES CI, so a rename would silently disarm claim 1.
            throw AnchorMissing(reason: "`func calculateRMSSD()` is gone from CameraAnalyzer.swift")
        }
        guard let open = code.range(of: "{", range: anchor.upperBound..<code.endIndex) else {
            throw AnchorMissing(reason: "no body found after `func calculateRMSSD()`")
        }
        var depth = 0
        var i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.upperBound..<i]) }
            }
            i = code.index(after: i)
        }
        throw AnchorMissing(reason: "unbalanced braces after `func calculateRMSSD()`")
    }

    /// The LIVE `BioSampleFrame` construction — the one built from a real measurement.
    ///
    /// ⛔ SCOPING TO IT IS NOT TIDINESS, IT IS THE DIFFERENCE BETWEEN A GUARD AND A FALSE
    /// FAILURE. The first version of this file windowed the whole publisher from the first
    /// `hrvSDNNms:` — and the first one is the DROPOUT-HOLD republish ~90 lines earlier, which
    /// forwards `held.hrvSDNNms` and never mentions `HRVMetrics` at all. Claim 3 would have gone
    /// red on correct code, and the obvious "fix" — relaxing the assertion — would have
    /// disarmed the only thing standing between SDNN and a silent symmetrisation. #408's lesson
    /// stated once more: a scan must anchor on a token that exists ONLY at the intended site,
    /// and checking that uniqueness is part of writing the scan, not part of reviewing it.
    private func liveFrameConstruction() throws -> String {
        let code = try publisherSource()
        guard let start = code.range(of: "let frame = BioSampleFrame(") else {
            // FAIL, do not skip.
            throw AnchorMissing(
                reason: "`let frame = BioSampleFrame(` is gone from CameraRPPGBioPublisher.swift")
        }
        guard let end = code.range(of: "bus.publish(bio: frame)",
                                   range: start.upperBound..<code.endIndex) else {
            throw AnchorMissing(reason: "no `bus.publish(bio: frame)` after the live construction")
        }
        return String(code[start.upperBound..<end.lowerBound])
    }

    /// A slice of the live construction between two of its arguments, so a negative assertion
    /// cannot be satisfied — or defeated — by a neighbouring argument on the same call.
    /// `to: nil` runs to the end of the construction.
    private func liveFrameWindow(from: String, to: String?) throws -> String {
        let code = try liveFrameConstruction()
        guard let start = code.range(of: from) else {
            throw AnchorMissing(reason: "`\(from)` is gone from the live BioSampleFrame construction")
        }
        guard let to else { return String(code[start.lowerBound...]) }
        guard let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            throw AnchorMissing(reason: "`\(to)` not found after `\(from)` in the live construction")
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    private func count(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
