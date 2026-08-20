// TheGuideSheetTitleSaysWhoseBodyTests.swift
// Echoel — #646: the guide sheet had one MARKED heading and one UNMARKED, 54 lines apart.
//
// WHAT THIS GUARDS. `BioMetricsGuideView` is the sheet `BioStripView` opens from any metric
// cell. Its section header `"How your body shapes the sound"` has carried a conditional origin
// note since #627b — `"demo values, not your body"` under the demo source, `"read your pulse to
// see it move"` with no reading. Its TOP heading, `"What your body is showing"`, carried none,
// and that is the first line a reader sees after tapping through.
//
// ⭐ HALF-MARKED IS WORSE THAN UNMARKED, and this file is the second time this repo has paid for
// it (#636 wrote the law; #637 paid it inside this same sheet, where a marked SECTION sat above
// unmarked ROWS). The marked sibling does not merely fail to help the title — it actively makes
// the title more convincing, because a reader who sees one heading qualify itself concludes that
// an unqualified one is the measured, real thing.
//
// ⚠️ THE TITLE KEEPS ITS WORDS. Only the marking is added. A heading that rewrites itself as the
// source changes is disorienting where a suffix beside a stable heading is not, and the sibling
// already established the suffix shape in this very sheet. Same decision #645 made when it moved
// a sentence's subject and left the founder's wording untouched.
//
// ⭐ AND THE FIX REMOVED AN EVALUATION RATHER THAN ADDING ONE, which is the opposite of what I
// wrote first. The section header used to call `liveBio` TWICE on its own (`== nil`, then
// `?.source`); one frame through `originNote(for:)` makes it ONE, closing an internal straddle
// that had a real failure mode — a frame expiring between the two calls made the second return
// nil and NEITHER branch render, hiding the demo marker outright. Non-row evaluations above the
// rows go from "at most 2" to "exactly 2" — one, not two, when there was no reading at all,
// because the parent's `else if` was skipped in that case. Claim 5 pins that the sheet never
// grows back a second `liveBio` read inside one heading.
//
// KIND (§1): **MIXED.** Claims 1–3 DRIVE `BioMetric.originNote(for:)` — a pure static on a
// `public enum` in the Foundation-only half of the file, above `#if canImport(SwiftUI)`. That is
// END-TO-END, the strong kind, and it is available here precisely because the string decision was
// hoisted out of the `View`. Claims 4–6 are SOURCE-TEXT SCANS: `BioMetricsGuideView.body` is a
// `@MainActor` `View` this bundle cannot mount.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (6e89b65):
//   · **1 TRUE REGRESSION — 5b.** `liveBio == nil` genuinely exists on the parent, and the
//     named reason is exactly the parent's defect: a heading that tests nil and then reads
//     `liveBio` again can render NEITHER branch if the frame expires between the two calls.
//     Transcribed, it misses there for the reason its message gives — the #367 bar.
//   · **1 ABSENCE, REPORTED TWICE — 4 and 6b.** `BioMetric.originNote(for:)` does not exist
//     on the parent, so both needles miss. That is ONE finding, not two (#486). ⚠️ AND THE
//     PARENT-VERDICT WORDING HAS TO BE ONE THING, not two: this bundle names `originNote`, so
//     it DOES NOT COMPILE against the parent and **no assertion has a verdict there** — the
//     three bullets here are hand-transcriptions of what each needle would find, not run
//     results. The first draft said both ("would be red there" AND "no verdict there"), and
//     §3 names that exact ambiguity as what let #488 ship a red gate for a cycle.
//   · **3 FORWARD, BEHAVIOURAL (claims 1, 2, 3)** — they drive `originNote`. ⛔ The first
//     draft wrote "7 … (1, 2, and 3 × 4 sources)", counting claim 3's loop iterations as
//     separate assertions while counting another loop as one — two conventions in one header,
//     inflated in the generous direction. The sibling written one slice earlier states the
//     rule: counting executions is #486's flattering direction wearing arithmetic.
//   · **1 COUNTERWEIGHT, green on both trees — 6a**, and it is the point of the file: the title
//     keeps its words, so a "sweep the file for the word body" cleanup reds here rather than
//     passing quietly. (6b is not a counterweight — see the absence bullet.)
//   · **Stripper: PROPHYLAKTISCH — 0 of the 3 remaining scan verdicts flip.** ⛔ The first draft
//     claimed TRAGEND and gave a reason that was half false: it said BOTH marker literals are
//     prose-quoted, and driven, only "demo values, not your body" is (raw 3, stripped 1) while
//     "read your pulse to see it move" occurs exactly once, in code. Both reviewers measured
//     it. The flip lived entirely in the duplicated claim that this pass removed, so the label
//     is now the weaker, true one. The stripper stays because §2's rule is one stripper, not
//     one load-bearing stripper.
//
// ⚠️ #364: a different honest shape is not forbidden. Marking at the sheet's presenter, dropping
// the possessive from the title entirely, or folding both headings into one marked container
// would all satisfy the law and turn claims 4/5 red — that is the moment to rewrite this file.
// What is forbidden silently is a sheet that qualifies one body claim and leaves its title bare.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGuideSheetTitleSaysWhoseBodyTests: XCTestCase {

    private static let sheet = "Sources/Echoelmusic/Studio/BioMetricInfo.swift"

    // MARK: - 1–3  the one definition, driven

    /// 1 — FORWARD, END-TO-END. No frame at all names no body and tells the reader what to do.
    func testNoReadingAsksForOneRatherThanNamingABody() {
        XCTAssertEqual(BioMetric.originNote(for: nil), "read your pulse to see it move", """
            The no-reading note changed. With no frame the sheet has measured nothing, so the \
            only honest heading suffix is an instruction — naming any body invents a reading.
            """)
    }

    /// 2 — FORWARD, END-TO-END. The demo source is named as the demo source.
    func testTheDemoSourceIsNamed() {
        let note = BioMetric.originNote(for: Self.frame(source: .fallback))
        XCTAssertEqual(note, "demo values, not your body", """
            The demo note changed or vanished. Under Simulation every number in this sheet comes \
            from the demo generator; a heading that says "your body is showing" over them is the \
            defect #646 removed, and the phrase must match the sibling section header verbatim.
            """)
    }

    /// 3 — FORWARD, END-TO-END. A real body gets NO suffix — the marking must not become noise.
    func testARealBodyIsNotMarked() {
        // ⛔ `.bleHeartRate` STOOD HERE AND IS NOT A CASE — the enum spells it `.ble`. A
        // compile error in the blocking bundle, caught by opening `BioSource` rather than
        // trusting a plausible name; the same class of mistake that took #643 red.
        // `.faceCam` is deliberately out: it carries no pulse, so whether the sheet's
        // title is true for it is a separate question this slice does not answer.
        // ⛔ AND `.oura` WAS SILENTLY ABSENT — five of seven cases named, one excluded with a
        // reason, one just missing, which reads as "everything else is covered". Same shape as
        // the DDSP-mapping retraction: an enumeration checked against its own tidiness instead
        // of against the enum. Six of seven are now named, `.faceCam` by exception.
        for source in [BioSource.cameraPPG, .healthKit, .ble, .watch, .oura] {
            XCTAssertNil(BioMetric.originNote(for: Self.frame(source: source)), """
                \(source) is being marked as if it were not a body. Marking a measured body is \
                over-correction: the suffix stops meaning anything if it is always there, and \
                this family's remaining risk is over-correction, not under-correction.
                """)
        }
    }

    // MARK: - 4–6  the wiring, and what must not regress

    /// 4 — REGRESSION. Both headings ask the one definition; neither carries a literal.
    func testBothHeadingsAskTheOneDefinition() throws {
        let code = try codeText(Self.sheet)
        let calls = squeezed(code).components(separatedBy: "BioMetric.originNote(for:liveBio)")
            .count - 1
        XCTAssertEqual(calls, 2, """
            `BioMetric.originNote(for: liveBio)` is called \(calls) times, not twice — the title \
            and the section header. If the title stopped calling it, the sheet is half-marked \
            again; if a third caller appeared, say so here rather than letting the count rot.
            """)
    }

    /// 5 — REGRESSION. No heading reads `liveBio` twice on its own again.
    ///
    /// ⛔ THIS METHOD ALSO PINNED EACH MARKER LITERAL AT ONE OCCURRENCE AND THAT WAS A VERBATIM
    /// DUPLICATE. `TheMetricSheetRowsSayWhoseBodyTests` already pins both literals at exactly
    /// one occurrence, in exactly this file, through an equivalent stripper. Two guards going
    /// red together for one cause is what #486 books as one finding, and §6 forbids "a second
    /// copy of a threshold that a shipped type already owns" — this was the same defect one
    /// level up. Removing it also removed the file's only stripper-flipping needle, so the
    /// grading label moved from TRAGEND to PROPHYLAKTISCH; the honest version is the weaker one.
    func testNoHeadingReadsTheFrameTwice() throws {
        let code = try codeText(Self.sheet)
        // The straddle this slice closed: `liveBio == nil` followed by `liveBio?.source` inside
        // one heading could render NEITHER branch if the frame expired between the two calls,
        // hiding the demo marker. Banning the nil-test is how that shape cannot come back.
        XCTAssertFalse(squeezed(code).contains("liveBio==nil"), """
            A heading tests `liveBio == nil` and then reads it again. `usableBio()` re-reads the \
            wall clock on every call, so a frame expiring between the two makes the second \
            return nil and neither branch render — the demo marker disappears entirely. Pass \
            ONE frame to `originNote(for:)` instead.
            """)
    }

    /// 6 — COUNTERWEIGHT. The title keeps its words and the definition asks the one predicate.
    func testTheTitleKeepsItsWordsAndTheOneSyntheticPredicate() throws {
        let code = try codeText(Self.sheet)
        XCTAssertTrue(code.contains("Text(\"What your body is showing\")"), """
            The sheet title was reworded. #646 adds a MARKING beside it; rewriting the heading \
            per source is a different, more disorienting shape and was considered and rejected. \
            If it is rewritten deliberately, retire this claim rather than weakening it.
            """)
        XCTAssertTrue(squeezed(code).contains("frame.source.isSynthetic"), """
            `originNote(for:)` no longer asks `BioSource.isSynthetic`. That comparison has ONE \
            definition (#639) and this file had already spelled `== .fallback` out twice; \
            re-inlining it is how the third spelling grows.
            """)
    }

    // MARK: - helpers

    private struct SheetAnchorMissing: Error { let reason: String }

    private static func frame(source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 12, breathPhase: 0.25,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    private func squeezed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SheetAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
