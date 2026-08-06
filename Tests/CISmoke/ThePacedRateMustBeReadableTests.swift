// ThePacedRateMustBeReadableTests.swift
// Echoel — #435. The guard over a guide that paces a rate its own measurement cannot read.
//
// THE DEFECT. `BreathPattern.curated` paces four rates: resonance 6.0/min, coherent 6.0,
// box (4-4-4-4) 3.75, 4-7-8 3.1579. `RespirationEstimator.reportableRange` is
// `[minRate / bandTolerance, maxRate * bandTolerance]` = `[3.7736, 31.8]`. Two of the four sit
// BELOW its lower bound — so while the user follows Echoel's own breathing guide, Echoel's own
// breath measurement cannot read back the rate it is asking for. `BreathGuideView` offers a
// "drive the ball from your MEASURED breath" mode that can never light up there, and
// `bioNormalized` drops the breath term entirely, so the music stops following the breath at
// exactly the moment the user is deliberately breathing.
//
// ⭐ THE TWO FAIL DIFFERENTLY, and that is the finding worth more than the boolean. Modelling
// only the mechanism in question — the breath period is read between zero-crossings of the
// heartbeat series, so a cycle quantises to a whole number of beats, and a crossing survives
// only if the rate it implies lands in the band — swept over pulses 45…110:
//   · resonance / coherent  6.0/min, +59% inside   121/121 branches, mean 6.0140 (+0.23%)
//   · box                   3.75/min, 0.62% BELOW   54/127 branches, mean 3.8590 (**+2.91%**),
//                                                   and 12 of 66 pulses accept NOTHING — pulse
//                                                   60 exactly, where a 16 s cycle is exactly
//                                                   16 beats and both quantisations give 3.75
//   · 4-7-8                 3.1579/min, 16.3% below   **0/131** branches, silent at all 66
// So box does not go quiet: it reads HIGH by ~3%. That is #426's one-sided filter in a second
// place, and it is the reason the fix is neither "widen the band" nor "change the technique".
//
// ⛔ THOSE SWEEP NUMBERS ARE NOT ASSERTED HERE, deliberately. They come from a MODEL of the
// acceptance band and beat quantisation, not from `RespirationEstimator` itself; pinning them
// would pin my model rather than the product, which is the more expensive kind of green. What
// this file asserts is decidable from the shipped types alone.
//
// ⚠️ AND WHAT IS NOT TESTED BECAUSE IT IS TRUE BY CONSTRUCTION: `measurementNote` is DERIVED
// from `pacedRateIsReportable`, so "the note appears iff the rate is out of band" is a
// tautology and asserting it would be a guard that cannot fail (#367). What can fail — and is
// asserted — is WHICH concrete patterns land on which side, which goes red if a segment
// duration changes or the estimator's band is retuned.
//
// ⚠️ AND THE HONEST LIMIT ON THE DOORS: both surfaces that present this picker are unreachable
// today. `BreathGuideView` is constructed only inside `BioSourceView` (doorless, #276) and
// `MeditationView` only under `showMeditation`, one of the three presentation flags with no
// setter at all. So the copy this slice adds cannot be seen by a user right now. It is written
// anyway for the same reason #433 and #434 repaired a dormant path: the arithmetic is wrong
// whether or not a door exists, and a door that arrives later must not arrive on top of a
// silent contradiction.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePacedRateMustBeReadableTests: XCTestCase {

    /// Same shape as the other source-scanning guards in this bundle: locate the tree from
    /// `#filePath`, never from the working directory (which is not the repo root under
    /// `xcodebuild`), and SKIP rather than report a green it did not earn if the tree is absent.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — the two scans below inspect source \
                text, so they SKIP rather than passing on nothing
                """)
        }
        return root
    }

    /// Comment lines are stripped before any scan. The doc comments in this repo quote the very
    /// numbers and forms they warn against, so a scan over raw source cannot tell a claim from
    /// a ⛔ correction of that claim.
    private func codeOnly(_ relative: String) throws -> String {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(relative),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func pattern(_ id: String) throws -> BreathPattern {
        try XCTUnwrap(BreathPattern.curated.first { $0.id == id },
                      "No curated pattern with id \(id) — the curated set was renamed or trimmed.")
    }

    // MARK: - The paced rates themselves

    /// Pins the four paced rates. Everything below is a statement about these numbers, so if a
    /// segment duration changes this test names the change before the others fail confusingly.
    func testTheCuratedPatternsPaceTheseRates() throws {
        let expected: [(String, Double)] = [
            ("resonance", 6.0),          // 4 + 6
            ("coherent", 6.0),           // 5 + 5
            ("box", 3.75),               // 4 + 4 + 4 + 4 = 16 s
            ("relaxing478", 60.0 / 19.0) // 4 + 7 + 8 = 19 s
        ]
        XCTAssertEqual(BreathPattern.curated.count, expected.count, """
            The curated set has \(BreathPattern.curated.count) patterns, not \(expected.count). \
            A pattern was added or removed without deciding whether Echoel can read its pace \
            back — which is the whole point of this file.
            """)
        for (id, rate) in expected {
            let p = try pattern(id)
            XCTAssertEqual(p.ratePerMinute, rate, accuracy: 1e-9, """
                \(id) paces \(p.ratePerMinute)/min, not \(rate). Its segments changed; \
                re-derive which side of RespirationEstimator.reportableRange it now falls on \
                before adjusting this number.
                """)
        }
    }

    // MARK: - Which side of the band each one lands on

    /// The load-bearing assertion. Red if a segment changes OR if the estimator's band is
    /// retuned — which is exactly when somebody needs to look at this again.
    func testTwoOfTheFourPacedRatesAreOutsideWhatTheEstimatorCanReport() throws {
        let band = RespirationEstimator.reportableRange

        for id in ["resonance", "coherent"] {
            let p = try pattern(id)
            XCTAssertTrue(p.pacedRateIsReportable, """
                \(id) paces \(p.ratePerMinute)/min, which is now OUTSIDE the reportable band \
                \(band). These two are the no-hold HRV patterns — the ones the product is \
                actually about. If the estimator can no longer read back the rate its own \
                guide paces for resonance breathing, that is a ship-blocker, not a caption.
                """)
            XCTAssertNil(p.measurementNote, """
                \(id) is readable but carries the "can't read your breath rate" caption. Either \
                the band moved or the pattern did; the copy must move with it in the same commit.
                """)
        }

        for id in ["box", "relaxing478"] {
            let p = try pattern(id)
            XCTAssertFalse(p.pacedRateIsReportable, """
                \(id) paces \(p.ratePerMinute)/min and now reads as INSIDE the reportable band \
                \(band). If that is because the band was widened, check what else the wider \
                acceptance lets in before celebrating — #424 widened it once and had to justify \
                the constant against a whole pulse axis. If it is because the pattern changed, \
                it is no longer 4-4-4-4 / 4-7-8 and should not carry that name.
                """)
            XCTAssertNotNil(p.measurementNote, """
                \(id) is outside the band and says nothing about it. A guide that paces a rate \
                its own readout cannot follow, silently, is the lying-control class.
                """)
        }
    }

    /// The DEFAULT must be readable. `curated` is documented as resonance-first and the UI is
    /// required to keep it preselected, so this is the one a first-time user meets.
    func testTheDefaultPatternIsOneEchoelCanRead() throws {
        let first = try XCTUnwrap(BreathPattern.curated.first, "The curated set is empty.")
        XCTAssertEqual(first.id, "resonance", """
            The first curated pattern is \(first.id), not resonance. The file's own doc says \
            resonance leads and the UI must keep it preselected.
            """)
        XCTAssertTrue(first.pacedRateIsReportable, """
            The default pattern paces \(first.ratePerMinute)/min, outside \
            \(RespirationEstimator.reportableRange). A first-time user would follow the guide \
            and watch the breath readout stay blank.
            """)
    }

    // MARK: - The chain, not a copy

    /// `pacedRateIsReportable` must ASK the estimator rather than restate its bound. A second
    /// copy of 3.7736 here is the #416 defect, and it would go stale silently the next time
    /// `bandTolerance` is retuned — which has already happened three times (#424).
    func testTheBoundIsChainedToTheEstimatorAndNotCopied() throws {
        let code = try codeOnly("Sources/Echoelmusic/Bio/BreathPattern.swift")
        XCTAssertTrue(code.contains("RespirationEstimator.reportableRange"), """
            BreathPattern no longer reads RespirationEstimator.reportableRange. If the bound was \
            inlined, it is now a second definition of a number that has moved three times.
            """)
        // The doc comments above quote the band on purpose, which is why the scan is on code
        // only — the same reason the other guards in this bundle strip comments first.
        for literal in ["3.77", "31.8"] {
            XCTAssertFalse(code.contains(literal), """
                BreathPattern's CODE contains the literal \(literal) — the estimator's band \
                written out by hand. Ask reportableRange instead.
                """)
        }
    }

    // MARK: - The doors

    /// A correct property no surface reads is the same defect with more steps (#418). Both
    /// picker surfaces are doorless today (see the file header) — this asserts the copy is
    /// wired for when they are not.
    func testBothPatternPickersRenderTheNote() throws {
        for path in ["Sources/Echoelmusic/Studio/BreathGuideView.swift",
                     "Sources/Echoelmusic/Studio/MeditationView.swift"] {
            let code = try codeOnly(path)
            XCTAssertTrue(code.contains("measurementNote"), """
                \(path) presents the curated pattern picker but never renders \
                `measurementNote`, so a user picking Box or 4-7-8 there gets a dead breath \
                readout with no explanation.
                """)
        }
    }
}
