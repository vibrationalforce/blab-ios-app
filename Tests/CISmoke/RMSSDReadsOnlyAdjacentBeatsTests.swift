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
// is accepted or rejected.
//
// ⛔ AND THE SENTENCE THAT FOLLOWED THAT ONE — "availability cannot drop" — WAS FALSE, in three
// places at once (here, the commit body, and the CLAUDE.md entry). It is true of ACCEPTANCE
// decisions and false of the published NUMBERS, which is the half a reader cares about:
// `pnn50(segments:)` returns 0 where the flat walk returned a percentage, and `rmssd` now goes to
// 0 on a window whose intervals are all isolated, where the flat walk always produced something.
// That drop is the CORRECTION — the old number was manufactured by the removal — but calling it
// "cannot drop" made the slice claim a free lunch while the `calculateRMSSD` doc, in the same
// commit, described the drop at length. A slice must not contain both a claim and its refutation.
//
// ⚠️ WHICH CLAIMS HERE CAN ACTUALLY FAIL, said first, because most of them cannot fail TODAY.
//
//   • Claims 1 and 2 (the two source scans) are the regressions. Before this slice
//     `calculateRMSSD` held a hand-written flat loop and the publisher held
//     `pnn50(rrMs: rrMs)`; both assertions were false. That is established by reading the old
//     code, not by a run — `RRAdjacency` does not exist on the old tree, so this FILE could not
//     compile there. Same honesty as every other scan guard in this bundle.
//   • Claim 2b is the regression for the FIRST version of this slice, which added a
//     `guard value > 0 else { return }` and left two count gates at the call sites. All three
//     were holds; see the ⛔ on that test.
//   • Claim 3 (SDNN stays flat) is a COUNTERWEIGHT: green on both sides, present so that the
//     tidy-looking next edit goes red instead of silent.
//   • Claims 4 and 5 exercise a type this commit introduces, so they were never red. They pin
//     behaviour a later simplification would take away, which is the only thing a test over new
//     code can honestly claim.
//
// ⛔ THERE IS NO CLAIM 6, AND ITS ABSENCE IS DELIBERATE. The first version carried a
// "the two arrays are written and cleared together" test that counted `rrIntervals = …` against
// `beatTimes = …` and compared totals. `ResonanceBreathingNeedsMoreThanOneWindowTests`
// (`testEveryRRAssignmentCarriesItsBeatTimes`) already holds that invariant and holds it
// STRICTLY BETTER — it walks the lines, requires the partner to be the next non-empty statement,
// and pins the site count at 4 — and its own ⛔ block retracts the head-count form by name:
// "two unrelated edits … would leave perfectly balanced. It counted, it did not pair." Adding a
// weaker second copy of a live guard is the #416 defect committed by a file whose header invokes
// #416. The invariant IS load-bearing for `RRAdjacency`; it is simply already guarded.
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
// flat RMSSD by +159 %. The honest device-scale figures — exactly 0 on a GAP-FREE series (which
// claim 4 pins bit-for-bit, and which is arithmetic, not a model run), up to ~+9.6 % RMSSD and
// +2…4 pp pNN50 on poor contact — are in `RRAdjacency`'s header, together with the note that the
// artifact RATES driving them are assumptions rather than recorded measurements. ⛔ This line
// said "0 % on a clean take" and cited the model's zero-injection row for it; that row still has
// band/IQR holes and reads −0.03 %. The exact zero comes from the one-run identity, not the
// model — see the ⛔ block beside that table.

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
        // #459: the runs are PUBLISHED here, not kept local, because the publisher's pNN50
        // reads them. A `let runs = …` again would put the adjacency decision back at two
        // call sites — which is the state this whole file exists to prevent between the two
        // metrics, one level up.
        XCTAssertTrue(body.contains("rrSegments = RRAdjacency.segments"), """
            `calculateRMSSD()` no longer assigns `rrSegments`. The publisher reads that \
            property for `hrvPNN50`; if this stops writing it, pNN50 pools over whatever the \
            last window left behind — or over nothing at all. Body scanned:
            \(body)
            """)
    }

    // MARK: - 2. the publisher pools pNN50 within runs

    /// RED before #425: `hrvPNN50: Float(HRVMetrics.pnn50(rrMs: rrMs))`.
    ///
    /// pNN50 is the one that moves MOST in relative terms, because a cross-gap difference is
    /// exactly the kind that clears the 50 ms threshold — on the fixture in claim 5 it is the
    /// difference between 11.1 % and 0 %.
    ///
    /// ⚠️ REWRITTEN BY #459, AND THE PROPERTY IT GUARDS IS UNCHANGED. Until then this scanned
    /// for the publisher making its OWN `RRAdjacency.segments(intervalsMs:endTimesSeconds:)`
    /// call — correct behaviour, guarded at the wrong level: the analyzer made the identical
    /// call for RMSSD, so the adjacency decision existed twice, from the same two arrays, with
    /// the argument pair hand-copied at both sites (#416). It now reads `analyzer.rrSegments`.
    /// The assertions moved with the code rather than being deleted (#456): the first pins that
    /// it reads the shared runs, the second that it does NOT re-derive them, and claim 1 above
    /// pins that the analyzer still derives them from `beatTimes`. The three together are what
    /// used to be two.
    func testThePublisherPoolsPNN50WithinRuns() throws {
        let window = try liveFrameWindow(from: "hrvPNN50:", to: nil)
        XCTAssertTrue(window.contains("HRVMetrics.pnn50(segments: self.analyzer.rrSegments)"), """
            The camera publisher no longer takes `hrvPNN50` from the analyzer's shared runs. \
            Either it is pooling the compacted array flat again (the #425 defect) or it has \
            gone back to deriving the runs itself (the #459 defect). Window scanned \
            (comments blanked):
            \(window)
            """)
        XCTAssertFalse(window.contains("RRAdjacency"), """
            The publisher derives the adjacency runs a second time. That is the #459 shape: \
            two copies of one decision, either of which a later edit can change alone, leaving \
            RMSSD and pNN50 disagreeing about which beats are adjacent in the SAME frame. \
            If this is deliberate, say what made one call site insufficient. Window scanned:
            \(window)
            """)
    }

    // MARK: - 2c. COUNTERWEIGHT — the shared runs cannot outlive their inputs

    /// ⛔ HONEST GRADING — THE FIRST VERSION GOT ITS OWN CATEGORY WRONG, in three artifacts at
    /// once (here, the `60af6fd` commit body, and the `decisions.csv` row). It said "GREEN before
    /// and after". It is **RED** on the parent tree: `rrSegments.removeAll()` does not exist
    /// there, so the loop below fails at BOTH clear sites. And it is not saved by the #461 escape
    /// hatch either — this is a pure TEXT scan that never references the symbol, so it compiles
    /// and runs on the old tree and genuinely fails.
    ///
    /// But it is not a REGRESSION test, and calling it one would be the other half of the same
    /// error. Its redness there is VACUOUS: it fails because the property did not exist, not
    /// because a defect did. That is the signature-shaped red CLAUDE.md's #427 entry already
    /// retracts once ("eine signaturbedingte Rotfärbung als Regression zu verbuchen wäre dieselbe
    /// Selbst-Fehleinordnung"), and #433's lesson is that mis-grading your own tests is HARDER to
    /// see than a guard that cannot fail, because either way everything is green.
    /// The accurate label: **a forward guard, green from #459 onward, present because #459
    /// CREATES the failure mode it guards.**
    ///
    /// Deriving the runs at publish time had one property worth naming: they could not be
    /// stale, because they did not exist between publishes. Caching them on the analyzer trades
    /// that for a single definition — and buys an obligation. `rrIntervals`/`beatTimes` are
    /// emptied at two places (the lock-loss branch and `resetPulseState`); a run list left
    /// standing beside empty arrays would publish a pNN50 for beats that no longer exist, with
    /// a fresh `CFAbsoluteTimeGetCurrent()` stamp on the frame — the shape no downstream
    /// freshness policy can detect, and the exact class the ⛔ block on `calculateRMSSD`
    /// already documents for `rmssd`.
    ///
    /// The scan is textual because the property is `private(set)` on a type behind
    /// `#if canImport(AVFoundation)` and both clear sites are `private`. It asserts the pairing
    /// rather than a count: every line that empties `rrIntervals` must be within a few lines of
    /// one that empties `rrSegments`.
    ///
    /// ⚠️ THE ±3 IS A REAL CONSTRAINT ON THE SOURCE, not a free constant, and it is written on
    /// `rrSegments` too so the coupling is visible from the other end. `SourceText.codeOnly`
    /// blanks a comment but KEEPS its line (#453), so a three-line explanatory block above either
    /// clear would push it out of range and turn a CORRECT file red. That is why both site notes
    /// are trailing comments. Widening the window is the wrong repair: it is what keeps the three
    /// statements one block instead of three scattered ones.
    ///
    /// ⚠️ AND IT ONLY RECOGNISES `.removeAll()`. A future clear written `rrIntervals = []` is
    /// invisible to the DETECTOR — so it is matched here as well, purely forward-looking (there
    /// are zero such lines today, so this changes nothing on the current tree). Note the
    /// companion guard in `ResonanceBreathingNeedsMoreThanOneWindowTests` has the same blind
    /// spot and is NOT widened here; naming it is cheaper than editing a guard this slice does
    /// not otherwise touch.
    func testTheSharedRunsAreClearedWithTheArraysTheyCameFrom() throws {
        let lines = try analyzerSource().split(separator: "\n", omittingEmptySubsequences: false)
        let clearIndices = lines.indices.filter {
            lines[$0].contains("rrIntervals.removeAll()") || lines[$0].contains("rrIntervals = []")
        }
        XCTAssertGreaterThanOrEqual(clearIndices.count, 2, """
            expected both places that empty `rrIntervals` (lock loss + `resetPulseState`), \
            found \(clearIndices.count). If a clear site was removed, the arrays now survive a \
            state this file assumed they did not.
            """)
        for i in clearIndices {
            let near = lines[max(0, i - 3)...min(lines.count - 1, i + 3)]
            XCTAssertTrue(near.contains {
                $0.contains("rrSegments.removeAll()") || $0.contains("rrSegments = []")
            }, """
                `rrIntervals` is emptied at line \(i + 1) without emptying `rrSegments`. The \
                cached runs would then outlive the beats they describe and the next publish \
                would carry a pNN50 for a window that no longer exists. Neighbourhood:
                \(near.joined(separator: "\n"))
                """)
        }
    }

    // MARK: - 2b. the two layers share ONE unavailability policy

    /// RED on the first version of #425, which added `guard value > 0 else { return }`.
    ///
    /// ⛔ THAT HOLD BROKE THE ONE SENTINEL RULE THE BUS WRITES DOWN, and it is the reason this
    /// assertion exists rather than the tidier-looking hold. `BioSampleFrame.hrvPNN50` says
    /// "`0` may mean 'not available' or a genuine 0 %; pair with `hrvRMSSDms > 0`", and
    /// `OSCSender` gates `/bio/heart/pnn50` on RMSSD, not on pNN50's own value. The publisher's
    /// pNN50 goes through `pnn50(segments:)`, which returns 0 when no run holds a pair. So on
    /// an all-isolated window a held RMSSD published `hrvRMSSDms > 0` beside `hrvPNN50 == 0`,
    /// the gate opened, and an external integrator received a confident **genuine 0 %**.
    ///
    /// Two layers must not answer "not available" two different ways. Assigning
    /// unconditionally is the cheap half of that: both go to 0 together, all three heart
    /// addresses close together, and no new state is needed. The scan is deliberately a
    /// NEGATIVE one on the assignment site rather than a behavioural test, because
    /// `calculateRMSSD` is `private` on a type behind `#if canImport(AVFoundation)`.
    ///
    /// ⛔ AND SCANNING ONLY THE BODY WAS NOT ENOUGH — a reviewer found the same hold surviving
    /// TWICE at the CALL SITES (`if rrIntervals.count >= 3 { calculateRMSSD() }`) plus once more
    /// as this body's own `guard rrIntervals.count >= 2 else { return }`. A minimum-sample gate
    /// whose failure branch is `return` IS a hold: the arrays refresh, `rmssd` does not, and the
    /// next publish carries a stale `hrvRMSSDms > 0` beside a fresh `hrvPNN50 == 0`. Both counts
    /// are reachable — `guard intervals.count >= 2` runs before the IQR pass and IQR can leave
    /// one survivor. `calculateRMSSDBody()` is brace-matched to the method, so it could not see
    /// any of it. **A guard over a policy must cover every site that can enforce the policy, not
    /// just the one the fix happened to touch** — hence the second half below, which is why this
    /// test names the call sites explicitly.
    func testTheAnalyzerDoesNotHoldAStaleRMSSD() throws {
        let body = try calculateRMSSDBody()
        XCTAssertTrue(body.contains("rmssd = HRVMetrics.rmssd(segments:"), """
            `calculateRMSSD()` no longer assigns unconditionally. If a hold was reintroduced, \
            the publisher's `hrvPNN50` must gain the SAME policy in the same commit — \
            otherwise `hrvRMSSDms > 0` beside `hrvPNN50 == 0` opens the OSC gate on a number \
            no body produced. Body scanned:
            \(body)
            """)
        let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false)
        let bodyGuards = bodyLines.filter { $0.contains("guard") || $0.contains("return") }
        XCTAssertTrue(bodyGuards.isEmpty, """
            `calculateRMSSD()` grew an early return again: \(bodyGuards).
            See the ⛔ block on this test — any conditional return here leaves `rmssd` stale \
            while `hrvPNN50` is recomputed, which is what publishes a fabricated 0 %.
            """)

        // The call sites. `HRVMetrics` owns the minimum-sample decision (`pairs > 0`); a second
        // one here is the #416 defect and, because its failure branch skips the call entirely,
        // it is the identical hold one frame up.
        let code = try analyzerSource()
        let callLines = code.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("calculateRMSSD()") && !$0.contains("func ") }
        XCTAssertGreaterThanOrEqual(callLines.count, 2, """
            expected both publication sites to still call `calculateRMSSD()`, found \
            \(callLines.count). A site that stops calling it leaves `rmssd` stale for that path.
            """)
        let gatedCalls = callLines.filter { $0.contains("if ") || $0.contains("count") }
        XCTAssertTrue(gatedCalls.isEmpty, """
            `calculateRMSSD()` is called behind a condition again: \(gatedCalls).
            The minimum-sample decision belongs to `HRVMetrics` (`pairs > 0`), which \
            `pnn50(segments:)` already uses — a second threshold here makes the two metrics \
            become unavailable at different moments, which is exactly the split this file exists \
            to close.
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
    /// spacing, and `CameraAnalyzer`'s refractory refuses peaks closer than **0.3 s**
    /// (`refractorySeconds` clamps with `max(0.3, …)` and falls back to 0.3). The 2e-4
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
                       "no run holds a pair, so RMSSD is unknown — 0 is the documented sentinel")
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

    // MARK: - fixtures

    /// Build a series plus the absolute time of each interval's second beat.
    ///
    /// - Parameters:
    ///   - gapsBefore: indices at which a beat was dropped immediately before that interval —
    ///     0.85 s of unaccounted time, comfortably past `toleranceSeconds` and past the
    ///     analyzer's **0.3 s** refractory floor (`refractorySeconds` clamps with `max(0.3, …)`
    ///     and falls back to 0.3). ⛔ This line read "~0.2 s" in the first version — the same
    ///     wrong number `RRAdjacency`'s tolerance doc carried, copied across, and wrong in the
    ///     SAFE direction on both sides so nothing could have caught it.
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

}
