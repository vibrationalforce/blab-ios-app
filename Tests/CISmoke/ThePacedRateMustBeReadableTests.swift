// ThePacedRateMustBeReadableTests.swift
// Echoel — #435. The guard over a guide that paces a rate its own measurement cannot read.
//
// THE DEFECT. `BreathPattern.curated` paces four rates: resonance 6.0/min, coherent 6.0,
// box (4-4-4-4) 3.75, 4-7-8 3.1579. `RespirationEstimator.reportableRange` is
// `[minRate / bandTolerance, maxRate * bandTolerance]` = `[3.7736, 31.8]`. Two of the four sit
// BELOW its lower bound — so while the user follows Echoel's own breathing guide, Echoel's own
// breath readout cannot show the rate it is asking for. `BreathGuideView` offers a "drive the
// ball from your MEASURED breath" mode that gates on `breathRate > 0`, and `BioStripView` shows
// a breath number; both are wrong or blank for those two patterns, with nothing on screen
// saying why.
//
// ⭐ THE TWO FAIL DIFFERENTLY, and that is the finding worth more than the boolean. Modelling
// only the mechanism in question — the breath period is read between zero-crossings of the
// heartbeat series, so a cycle quantises to a whole number of beats, and a crossing survives
// only if the rate it implies lands in the band — swept over pulses 45…110:
//   · resonance / coherent  6.0/min, +59% inside   121/121 branches, mean 6.0140 (+0.23%)
//   · box                   3.75/min, 0.62% BELOW   54/127 branches, mean 3.8590 (**+2.91%**),
//                                                   and 12 of 66 integer pulses accept NOTHING
//   · 4-7-8                 3.1579/min, 16.3% below   **0/131** branches, silent at all 66
// So box does NOT go quiet: it reads HIGH by ~3%, at roughly five of every six resting pulses.
// That is #426's one-sided filter in a second place, and it is the reason the fix is neither
// "widen the band" nor "change the technique".
//
// ⛔ AND IT IS THE REASON THE FIRST SHIPPED CAPTION WAS FALSE. It promised silence — "the live
// breath readout won't follow it" — twenty-odd lines below a doc comment in the same commit
// saying "it does not go silent, it reads high". The caption is what the user reads. It now
// claims only what is decidable with no model in it at all: the paced rate is below the band,
// the estimator only publishes inside the band, therefore the readout can never show this pace
// — it stays blank or it reads high. `testTheNoteDoesNotPromiseSilence` is the regression.
//
// ⛔ THOSE SWEEP NUMBERS ARE NOT ASSERTED HERE, deliberately. They come from a MODEL of the
// acceptance band and beat quantisation, not from `RespirationEstimator` itself; pinning them
// would pin my model rather than the product, which is the more expensive kind of green. What
// this file asserts is decidable from the shipped types alone.
//
// ⛔ AND THE FIRST VERSION OF THIS HEADER DESCRIBED A DIFFERENT FILE. It said the
// note-appears-iff-out-of-band assertion "is NOT tested because it is true by construction" —
// while the file asserted exactly that, twice, at both ends of the band. Two reviewers found it
// independently. The assertions are KEPT, and the reason they earn their place is not that they
// can fail today: it is that `measurementNote` is one edit away from being a stored per-pattern
// string, and on that edit they are the only thing that notices the copy and the arithmetic have
// parted company. What is NOT claimed for them is that they can fail against today's derivation.
//
// ⛔ AND THE BOOLEAN ALONE PINS NOTHING DISTINGUISHING, which the first version also missed. On
// the shipped curated set `measurementNote != nil` coincides exactly with `hasHolds`, so
// replacing the derivation with `hasHolds ? "…" : nil` passed every assertion in this file.
// `testTheNoteFollowsTheBandAndNotTheHolds` breaks that coincidence with two synthesised
// patterns on which the two properties disagree.
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
                source tree not present under \(root.path) — the three scans below inspect source \
                text, so they SKIP rather than passing on nothing
                """)
        }
        return root
    }

    /// Comment lines are stripped before any scan. This is load-bearing for the POSITIVE half of
    /// the chain scan: `BreathPattern.swift` names `RespirationEstimator.reportableRange` in a
    /// doc comment as well as in code, so an unstripped scan would be satisfied by prose alone.
    /// (It is NOT what makes the negative half work — the literals `3.77` and `31.8` appear
    /// nowhere in that file, comments included. The first version of this comment claimed the
    /// opposite, which is the "a comment with a false justification is worse than none" defect
    /// this repo names in CLAUDE.md.)
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
    ///
    /// The `measurementNote` halves are entailed by the `pacedRateIsReportable` halves for as
    /// long as the note stays derived; they are kept for the day it stops being derived (see the
    /// file header). They are not claimed as independently failing checks today.
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
                \(id) is readable but carries the out-of-band caption. Either the band moved or \
                the pattern did; the copy must move with it in the same commit.
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
                its own readout cannot show, silently, is the lying-control class.
                """)
        }
    }

    /// `curated` is documented as resonance-first and the UI is required to keep it preselected,
    /// so this is the pattern a first-time user meets. Only the ORDERING is asserted here — that
    /// resonance itself is readable is pinned by the test above, and repeating it would be a
    /// second check that can only fail together with the first.
    func testTheDefaultPatternIsResonance() throws {
        let first = try XCTUnwrap(BreathPattern.curated.first, "The curated set is empty.")
        XCTAssertEqual(first.id, "resonance", """
            The first curated pattern is \(first.id), not resonance. The file's own doc says \
            resonance leads and the UI must keep it preselected — and resonance is the only \
            curated pattern whose pace Echoel can read back.
            """)
    }

    // MARK: - The note follows the BAND, not the holds

    /// On the shipped curated set the two properties coincide exactly, so every other assertion
    /// in this file survives replacing the derivation with `hasHolds ? "…" : nil`. These two
    /// synthesised patterns break the coincidence in both directions.
    func testTheNoteFollowsTheBandAndNotTheHolds() throws {
        // 10 s in, 10 s out — 3.0/min: NO holds, and below the band.
        let slowNoHolds = BreathPattern(
            id: "test.slowNoHolds", name: "slow", evidence: "test fixture",
            segments: [.init(kind: .inhale, seconds: 10), .init(kind: .exhale, seconds: 10)])
        XCTAssertEqual(slowNoHolds.ratePerMinute, 3.0, accuracy: 1e-9,
                       "Fixture clamped: BreathPattern.init capped a segment this test relies on.")
        XCTAssertFalse(slowNoHolds.hasHolds, "Fixture is meant to have no holds.")
        XCTAssertNotNil(slowNoHolds.measurementNote, """
            A no-hold pattern paced at 3.0/min — below RespirationEstimator.reportableRange — \
            carries no note. The note is keyed to the holds, not to the band. Those two \
            coincide on the shipped curated set, so nothing else in this file would catch it.
            """)

        // 4 in, 2 hold, 4 out — 6.0/min: HAS a hold, and inside the band.
        let fastWithHold = BreathPattern(
            id: "test.fastWithHold", name: "fast", evidence: "test fixture",
            segments: [.init(kind: .inhale, seconds: 4), .init(kind: .holdFull, seconds: 2),
                       .init(kind: .exhale, seconds: 4)])
        XCTAssertEqual(fastWithHold.ratePerMinute, 6.0, accuracy: 1e-9,
                       "Fixture clamped: BreathPattern.init capped a segment this test relies on.")
        XCTAssertTrue(fastWithHold.hasHolds, "Fixture is meant to contain a hold.")
        XCTAssertNil(fastWithHold.measurementNote, """
            A pattern paced at 6.0/min — squarely inside the band — carries the out-of-band note \
            because it happens to contain a hold. The note must follow the band.
            """)
    }

    // MARK: - What the note may and may not claim

    /// The first shipped caption promised SILENCE, which is false for box at roughly five of
    /// every six resting pulses (see the header). The note must state both branches, because
    /// "below the band" is all the boolean knows — it does not know "silent".
    func testTheNoteDoesNotPromiseSilence() throws {
        let note = try XCTUnwrap(pattern("box").measurementNote,
                                 "Box is out of band and must carry a note.")
        let lower = note.lowercased()
        XCTAssertTrue(lower.contains("blank"), """
            The out-of-band caption does not mention the blank case: "\(note)"
            """)
        XCTAssertTrue(lower.contains("high"), """
            The out-of-band caption does not mention the reads-high case: "\(note)". Box does \
            NOT go silent — it publishes a rate at most resting pulses and reads about 3% high. \
            A caption claiming only silence is the lying-control class inverted: it tells the \
            user a live number is dead.
            """)
        XCTAssertFalse(lower.contains("heal") || lower.contains("therap"), """
            The out-of-band caption drifted into health/therapy language: "\(note)". This copy \
            is a measurement caveat, never a claim about the body.
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
                `measurementNote`, so a user picking Box or 4-7-8 there gets a breath readout \
                that cannot show their pace, with no explanation.
                """)
        }
    }

    /// The second contradiction the caption alone does not close: "Follow my breath" gates on
    /// `breathRate > 0`, so for 4-7-8 the "Start the camera to measure your breath." line is the
    /// PERMANENT state with the camera already running. That instruction must branch.
    func testTheFollowModeHintKnowsAboutTheBand() throws {
        let code = try codeOnly("Sources/Echoelmusic/Studio/BreathGuideView.swift")
        XCTAssertTrue(code.contains("pacedRateIsReportable"), """
            BreathGuideView renders the caption but its "Follow my breath" hint still says \
            "Start the camera" unconditionally. For a pattern paced below the band that is a \
            standing falsehood — the camera IS running and will never publish a rate.
            """)
    }
}
