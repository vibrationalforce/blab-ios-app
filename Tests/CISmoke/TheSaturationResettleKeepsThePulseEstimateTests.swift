// TheSaturationResettleKeepsThePulseEstimateTests — pins #834.
//
// THE MEASURED LOSS (founder device log v10.79.420, 13:44:05): confidence had just reached
// 0.89 at a stable 52–53 bpm when `bright=0.99` fired the saturation re-settle — and the
// flush discarded the ESTIMATE along with the window, restarting the trust climb from zero.
// The window, filters, peaks and acf are OPTICAL state and are genuinely invalid after an
// exposure step; `estimatedBPM`/`recentBPMs` are PHYSIOLOGICAL state — the heart does not
// change because the exposure re-locked, and the finger stays on the lens through the whole
// event. #834 splits the two: the saturation site keeps the estimate (confidence halved),
// the other four flush sites state `keepEstimate: false` — their estimates are unsettled,
// or the finger/person may have changed.
//
// WHY THE GATE STAYS SOUND: `lastAutoStrength` is optical and ALWAYS clears, so
// `pulseTrustworthy` refuses until a fresh window rebuilds real periodicity — the retained
// estimate reaches the display's hold and the agreement term, never the bus, until then.
// The publisher's fresh-read discipline (all three evidence values read AFTER
// `manageExposure()`) is now the ONLY defense against a stale-acf/live-bpm mismatch —
// claim 4 pins that ordering, because the old `bpm > 0` short-circuit belt is gone at the
// saturation site by design.
//
// KINDS (§1): tests 1–3 are END-TO-END BEHAVIOUR on the shipped `CameraAnalyzer`; tests
// 4–5 are SOURCE-TEXT SCANS (comment-stripped). Whether the faster re-lock is AUDIBLE as
// continuity (music keeps following the body through a re-settle) is a DEVICE PROBE —
// open, answered by the next log's `estimate kept — #834` breadcrumb beside the trust line.
//
// GRADING (§3): this file names `resetForRecovery(keepEstimate:)`, which the same commit
// creates — it does not compile against the parent, so NO assertion has a verdict there
// (forward by construction, one absence reported once, #486). The scans and the halving
// arithmetic were driven in Python against the worktree before push (#442: 0.5 × 0.5 =
// 0.25 is exact in binary floating point).
//
// #364: extending `keepEstimate: true` to ANOTHER site later (e.g. the stall recovery,
// whose own doc records a conf-0.90 pre-stall lock) is legitimate — bring its device
// evidence and update claim 3's count in the same commit; the message says so.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheSaturationResettleKeepsThePulseEstimateTests: XCTestCase {

    #if canImport(AVFoundation)
    // MARK: - 1. END-TO-END: the keep-path retains the heart and clears the light

    @MainActor
    func testKeepingTheEstimateRetainsBPMAndHalvesConfidence() {
        let analyzer = CameraAnalyzer()
        analyzer.startPulseDetection()
        analyzer.estimatedBPM = 52
        analyzer.bpmConfidence = 0.5
        analyzer.resetForRecovery(keepEstimate: true)
        XCTAssertEqual(analyzer.estimatedBPM, 52, """
            The keep-path discarded the physiological estimate — that is the v10.79.420 \
            13:44:05 loss unfixed: a converging pulse thrown away by an exposure step that \
            says nothing about the heart.
            """)
        XCTAssertEqual(analyzer.bpmConfidence, 0.25, """
            The keep-path no longer HALVES the confidence (0.5 → 0.25 is exact, #442). \
            Keeping it whole would present a flushed take as fully trusted; zeroing it \
            re-creates the slow climb the keep exists to avoid.
            """)
        XCTAssertEqual(analyzer.signalQuality, 0, """
            The keep-path stopped clearing the OPTICAL state. Quality describes the light \
            of a window that no longer exists; a retained value would be a fabricated \
            measurement (#654's class).
            """)
    }

    // MARK: - 2. END-TO-END: the flush-path contract is unchanged

    @MainActor
    func testTheFlushPathStillZeroesEverything() {
        let analyzer = CameraAnalyzer()
        analyzer.startPulseDetection()
        analyzer.estimatedBPM = 52
        analyzer.bpmConfidence = 0.5
        analyzer.resetForRecovery(keepEstimate: false)
        XCTAssertEqual(analyzer.estimatedBPM, 0,
                       "the false-path retained the estimate — the pre-#834 contract broke")
        XCTAssertEqual(analyzer.bpmConfidence, 0,
                       "the false-path retained confidence — the pre-#834 contract broke")
    }

    /// The `isPulseDetecting` guard survives (COUNTERWEIGHT — #651 added exposure-path
    /// callers; without the guard they would clear state on a take that measures nothing).
    @MainActor
    func testRecoveryIsANoOpWhileNotDetecting() {
        let analyzer = CameraAnalyzer()
        analyzer.estimatedBPM = 52
        analyzer.resetForRecovery(keepEstimate: false)
        XCTAssertEqual(analyzer.estimatedBPM, 52,
                       "resetForRecovery lost its isPulseDetecting guard")
    }

    #endif

    // MARK: - source helpers

    /// Delegates to the ONE stripper (§2, #453/#477) — this file carries two strict
    /// EQUALITY counts, and a private line-filter would count a future trailing comment
    /// like `… // unlike the keepEstimate: true site` as a phantom call site.
    private func code(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    /// Brace-matched body after a UNIQUE key (#408): returns nil when the key is absent
    /// or ambiguous, so the caller fails loudly instead of scanning the wrong region.
    private static func body(of key: String, in text: String) -> String? {
        guard text.components(separatedBy: key).count - 1 == 1,
              let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return nil
    }

    // MARK: - 3. Exactly ONE site believes in continuity, and it is the saturation branch

    func testOnlyTheSaturationSiteKeepsTheEstimate() {
        let publisher = code("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift")
        guard !publisher.isEmpty else { return }
        XCTAssertEqual(publisher.components(separatedBy: "keepEstimate: true").count - 1, 1, """
            The number of `keepEstimate: true` sites changed. ONE is the #834 decision — the \
            saturation re-settle, where the finger provably stays on the lens. Adding another \
            (the stall recovery is the documented candidate) is legitimate WITH its own device \
            evidence: update this count and the file header in the same commit (#456/#364). \
            Removing the one reverts the founder-measured 13:44:05 fix — say why.
            """)
        // Brace-matched, NOT a char window (#408): this branch carries 40+ lines of blanked
        // comment whitespace, and a `prefix(1_200)` failed on the very commit that wrote it
        // when the review added five comment lines. The branch body is the honest scope.
        guard let branch = Self.body(of: "if saturatedTicks >= Self.resettleAfterTicks",
                                     in: publisher) else {
            return XCTFail("the saturation branch anchor is gone or ambiguous — re-anchor (#454)")
        }
        XCTAssertTrue(branch.contains("keepEstimate: true"), """
            The one `keepEstimate: true` no longer sits in the saturation branch — the site \
            that keeps continuity moved without this guard moving with it (#456).
            """)
        // A FLOOR, not an equality (#364) — `EveryDeliberateResettleFlushesTheWindowTests`
        // keeps the TOTAL flush count a floor because adding a flush site is expected and
        // legitimate; an equality here would encode the opposite policy about the same
        // event. The #834 DECISION is carried by the `true`-count equality above.
        XCTAssertGreaterThanOrEqual(publisher.components(separatedBy: "keepEstimate: false").count - 1, 4, """
            Fewer than FOUR flush sites state `keepEstimate: false` (dead-window · \
            weak-periodicity · finger-loss · stall recovery existed at #834) — the parameter \
            has no default (#431) precisely so every site says which continuity it believes \
            in; a vanished site is a real decision, not a tidy-up.
            """)
    }

    // MARK: - 4. The fresh-read discipline is now load-bearing — pin the ordering

    /// The old belt (`bpm > 0` short-circuiting after a flush) is gone at the saturation
    /// site: after its flush `bpm` stays > 0 while fresh acf is 0. The gate stays sound
    /// ONLY because all three evidence values are read AFTER `manageExposure()` — the
    /// publisher's own comment now names this test as the pin.
    func testTheEvidenceReadsFollowTheExposureManagement() {
        let publisher = code("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift")
        guard !publisher.isEmpty else { return }
        let anchors = ["self.manageExposure()",
                       "let bpm = self.analyzer.estimatedBPM",
                       "let confNow = self.analyzer.bpmConfidence",
                       "let acfNow = self.analyzer.lastAutoStrength"]
        var positions: [String.Index] = []
        for needle in anchors {
            let hits = publisher.components(separatedBy: needle).count - 1
            guard hits == 1, let range = publisher.range(of: needle) else {
                return XCTFail("""
                    `\(needle)` occurs \(publisher.components(separatedBy: needle).count - 1)× \
                    — the ordering below needs each exactly once (#408); re-anchor.
                    """)
            }
            positions.append(range.lowerBound)
        }
        XCTAssertTrue(positions[0] < positions[1] && positions[1] < positions[2]
                      && positions[2] < positions[3], """
            The evidence reads no longer all follow `manageExposure()` in the publish tick. \
            A read BEFORE it can pair a stale-high acf with a post-flush bpm that #834 keeps \
            nonzero — `pulseTrustworthy`'s strong-acf clause would then publish a reading \
            the analyzer just flushed. This ordering is the ONLY remaining defense.
            """)
    }
}
