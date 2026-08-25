// TheTrustGateSaysWhichClauseRefusedTests.swift
// Echoel — #573. Guards the publish-gate instrument that the next trust-rule decision rests on.
//
// WHY THIS FILE EXISTS AND WHY IT IS MOSTLY BEHAVIOUR. The founder's two v10.79.387 logs show
// `body=0` on every `generate` line across ~11 minutes. #572 removed one cause (a three-second
// engage latch). The remaining suspicion — that `pulseTrustworthy`'s SECOND witness, `acf`, is
// the binding clause — is currently a HAND COUNT over 2 s snapshots, and acting on a hand count
// is precisely what #566 cost. So this cycle ships an instrument, and the instrument itself has
// to be right: a miscounted breadcrumb would be worse than none, because the next threshold
// decision would be made ON it.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1):
//   · claims 1–4 are END-TO-END BEHAVIOUR over `PulseTrustVerdict`, `TrustWindowTally` and the
//     shipped `CameraRPPGBioPublisher.trustVerdict`/`shouldPublish` statics. They drive real
//     code, not a sample of it: claim 1 sweeps a grid and compares two shipped predicates.
//   · claims 5–6 are SOURCE-TEXT SCANS. They exist because `shouldPublish`'s own doc block
//     records the gap they close: *"no test asserts that the publish loop actually CALLS this"*.
//     A tally that is never fed is silent, not red — the ONE failure mode behaviour cannot see.
//   · claim 7 (#833) is END-TO-END BEHAVIOUR over the per-class `acfOnly(…)` block — the
//     coincidence statistics the v10.79.420 log could not deliver from window-wide maxima.
//   · DEVICE PROBE, open and NOT covered: whether the `trust:` line is legible in the diag file
//     and whether one line per ~30 s is the right cadence. That is the founder's read, and the
//     window size is pinned as a floor (#364) so it stays retunable without a red gate.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`9fff9aa`) and this
// tree — there is no local toolchain (§0), and this file names three symbols the same commit
// creates, so it does not COMPILE against the parent and NO assertion has a verdict there:
//   · claims 1–3 + 5–6 are therefore FORWARD guards by construction, reported as such rather
//     than as regressions (#433 — the flattering direction is the same defect as the harsh one).
//     One absence, reported once (#486): `PulseTrustVerdict`, `TrustWindowTally` and
//     `trustVerdict` are absent on the parent together.
//   · claim 4 is a COUNTERWEIGHT whose LOGIC is green on both trees, and that is its job: it
//     pins the ORDERING of two shipped floors that the failure taxonomy silently assumes. If
//     `trustAutoFloor` ever exceeded `strongAutoFloor`, a frame that PASSES via the strong-only
//     clause could be classified `.periodicityLow` — the instrument would report a refusal that
//     did not happen, and nothing else in this file would notice.
//   · claim 7 (#833) names NO new symbol — unlike claims 1–3 it WOULD compile against its
//     parent (the #832 tree). Graded there by transcription: the exact-block assertions in
//     tests 1 and 3 (and 4's em-dash form) are FORWARD guards (red by suffix absence — one
//     absence, reported once, #486); test 1's window-max assertion and all of test 2 are
//     COUNTERWEIGHTS, green on both trees on purpose (#343).
//   · STRIPPER: measured, not assumed. Each of the SIX source needles was counted raw and
//     through `SourceText.codeOnly` on both trees. Verdict: **PROPHYLAKTISCH (0 of 6 flip)** —
//     every needle is a code form the surrounding prose does not spell. It stays because the
//     prose around this call site is dense and grows (the paragraph above the gate is 20 lines
//     of ⛔ history), so the raw count is one comment away from being wrong; but claiming it is
//     load-bearing today would be the unmeasured boast §2 forbids.
//
// ⛔ THE FIRST VERSION SAID "four needles" AND HAD FOUR. A reviewer found that the instrument
// went SILENT in exactly the case it exists to describe — a stalled or short take never fills a
// window, and nothing flushed a partial one — so the emission moved behind `flushTrustWindow`
// and `stop()` became its second caller. Two needles followed. The count is corrected here
// rather than left to age, because a header that says "four" over a list of six is how the next
// reader stops trusting the grading block at all.

import Foundation
import XCTest
#if canImport(AVFoundation) && canImport(Observation)
@testable import Echoelmusic
#endif

final class TheTrustGateSaysWhichClauseRefusedTests: XCTestCase {

    private static let publisherPath = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    // ⚠️ THE PUBLISHER'S WHOLE FILE is `#if canImport(AVFoundation) && canImport(Observation)`,
    // so every claim that NAMES it carries the SAME pair — not just AVFoundation, which is the
    // guard most siblings reach for when a type needs only that one (`OneDefinitionOfTooBright
    // Tests` states this convention and is the precedent). Claim 3 stays OUTSIDE: it drives
    // `TrustWindowTally`, which is pure Foundation and must run wherever the bundle builds, and
    // so do the source scans, which read text.
    //
    // ⛔ THE FIRST VERSION OF THIS FILE HAD NO GUARD AT ALL. It would not have failed either
    // gate today — `Tests/CISmoke` is the source path of an iOS-only target, and SwiftPM never
    // compiles this directory — so it was latent, not live. Written down rather than silently
    // added, because "it happens to build" is the reason a convention erodes.
    #if canImport(AVFoundation) && canImport(Observation)

    // MARK: - claim 1 (END-TO-END) — the verdict can never disagree with the shipped gate

    /// The single most important assertion here. The instrument's whole value is that the line
    /// it prints describes the decision the bus actually took; a taxonomy that drifts from
    /// `shouldPublish` would report refusals for frames that published and vice versa, and a
    /// device log is exactly where nobody could tell.
    ///
    /// Swept over a grid that straddles all three floors, including the two device-logged bands
    /// this rule exists for. `trustVerdict` gets agreement structurally (it asks `shouldPublish`
    /// first); this assertion is what keeps a later "optimisation" from re-deriving it.
    func testTheVerdictAgreesWithTheShippedPublishGateEverywhere() {
        let bpms = [0.0, -1.0, 0.5, 56.0, 75.0, 180.0]
        let confidences = [0.0, 0.01, 0.34, 0.59, 0.6, 0.62, 0.9, 0.98, 1.0]
        let strengths = [0.0, 0.29, 0.3, 0.39, 0.4, 0.44, 0.59, 0.6, 0.72, 1.0]
        for bpm in bpms {
            for conf in confidences {
                for acf in strengths {
                    let gate = CameraRPPGBioPublisher.shouldPublish(bpm: bpm,
                                                                    confidence: conf,
                                                                    autoStrength: acf)
                    let verdict = CameraRPPGBioPublisher.trustVerdict(bpm: bpm,
                                                                      confidence: conf,
                                                                      autoStrength: acf)
                    XCTAssertEqual(verdict == .published, gate, """
                        `trustVerdict` and `shouldPublish` disagree at bpm=\(bpm) conf=\(conf) \
                        acf=\(acf): gate says \(gate), verdict says \(verdict.rawValue).
                        The breadcrumb these feed is what the next trust-rule decision will be \
                        made on, so a taxonomy that drifts from the gate does not merely \
                        mislabel — it argues for a change to a rule it is describing wrongly. \
                        `trustVerdict` must keep asking `shouldPublish` for its first answer \
                        rather than re-deriving the predicate from the thresholds (#416).
                        """)
                }
            }
        }
    }

    // MARK: - claim 2 (END-TO-END) — and it names the RIGHT clause, on the real device bands

    /// The taxonomy earns its keep only if `conf` high / `acf` low is a DIFFERENT reported event
    /// from "nothing is working". Both bands below are device-logged and both are quoted in
    /// `pulseTrustworthy`'s own doc block, so these are not invented fixtures.
    func testEachRefusalNamesTheClauseThatActuallyRefused() {
        // Device log 2469 (build 10.79.352): conf 0.62 / acf 0.30 — the readout looks convinced,
        // the second witness never arrives. THE case the v10.79.387 logs point at.
        XCTAssertEqual(CameraRPPGBioPublisher.trustVerdict(bpm: 75, confidence: 0.62,
                                                           autoStrength: 0.30),
                       .periodicityLow, """
            A high-confidence / low-periodicity refusal is not reported as such. This is the \
            band the founder's logs sit in; collapsing it into a generic "no signal" is what \
            makes a 2 s snapshot count necessary in the first place.
            """)
        // Device log 1783420026: acf 0.59–0.72 at conf 0.01 — a rock-stable real 56 bpm. Above
        // `strongAutoFloor` this PUBLISHES on the strong-only clause; just below it, the missing
        // witness is confidence, not periodicity.
        XCTAssertEqual(CameraRPPGBioPublisher.trustVerdict(bpm: 56, confidence: 0.01,
                                                           autoStrength: 0.72),
                       .published, """
            The documented strong-periodicity / low-confidence band no longer publishes. That \
            band is real, device-logged, and `pulseTrustworthy`'s strong-only clause exists \
            for it — if this flipped, the gate changed, not the instrument.
            """)
        XCTAssertEqual(CameraRPPGBioPublisher.trustVerdict(bpm: 56, confidence: 0.01,
                                                           autoStrength: 0.44),
                       .confidenceLow, """
            Periodicity cleared its floor and confidence did not, yet the refusal is not \
            reported as a confidence refusal.
            """)
        XCTAssertEqual(CameraRPPGBioPublisher.trustVerdict(bpm: 60, confidence: 0.10,
                                                           autoStrength: 0.10),
                       .bothLow, """
            Neither witness cleared its floor, yet the refusal is not reported as `both`. \
            Distinguishing this from a single-clause refusal is the point of the taxonomy: \
            "no signal at all" and "half the evidence is there" call for different work.
            """)
        for bpm in [0.0, -3.0] {
            XCTAssertEqual(CameraRPPGBioPublisher.trustVerdict(bpm: bpm, confidence: 0.98,
                                                               autoStrength: 0.99),
                           .noEstimate, """
                bpm=\(bpm) with both witnesses high is reported as a clause refusal rather \
                than as "no estimate". The analyzer had nothing to offer; blaming a threshold \
                for that would send the next cycle after the wrong stage entirely.
                """)
        }
    }

    #endif

    // MARK: - claim 3 (END-TO-END) — the tally counts what it was told, and survives a NaN

    func testTheWindowCountsEachVerdictAndReportsTheSpread() {
        var tally = TrustWindowTally()
        XCTAssertNil(tally.bpmSpread, "an empty window claims a spread it never observed")
        XCTAssertFalse(tally.isComplete, "an empty window reports itself complete")

        tally.note(verdict: .published, bpm: 60, confidence: 0.7, autoStrength: 0.5)
        tally.note(verdict: .periodicityLow, bpm: 64, confidence: 0.9, autoStrength: 0.2)
        tally.note(verdict: .periodicityLow, bpm: 58, confidence: 0.8, autoStrength: 0.3)
        tally.note(verdict: .confidenceLow, bpm: 61, confidence: 0.3, autoStrength: 0.5)
        tally.note(verdict: .bothLow, bpm: 59, confidence: 0.1, autoStrength: 0.1)
        tally.note(verdict: .noEstimate, bpm: 0, confidence: 0.0, autoStrength: 0.0)

        XCTAssertEqual(tally.attempts, 6)
        XCTAssertEqual(tally.published, 1)
        XCTAssertEqual(tally.periodicityLow, 2)
        XCTAssertEqual(tally.confidenceLow, 1)
        XCTAssertEqual(tally.bothLow, 1)
        XCTAssertEqual(tally.noEstimate, 1)
        XCTAssertEqual(tally.attempts,
                       tally.published + tally.periodicityLow + tally.confidenceLow
                           + tally.bothLow + tally.noEstimate, """
            The per-verdict counters no longer sum to `attempts`. A line whose parts do not add \
            up is worse than no line: the reader cannot tell whether a case is missing or \
            double-counted, and every conclusion drawn from it inherits the ambiguity.
            """)
        XCTAssertEqual(tally.maxConfidence, 0.9, accuracy: 1e-9)
        XCTAssertEqual(tally.maxPeriodicity, 0.5, accuracy: 1e-9)
        // 58…64 — the zero-bpm attempt must NOT drag the low end to 0, or every window that
        // contains one dropout would report a ~60 bpm spread and look like wild instability.
        XCTAssertEqual(tally.bpmSpread ?? -1, 6, accuracy: 1e-9, """
            The spread includes an attempt with no usable estimate. `bpm=0` is the ABSENCE of a \
            measurement, not a measurement of zero.
            """)
        XCTAssertTrue(tally.summary.contains("1/6 ok"), """
            The summary no longer leads with published/attempts: \(tally.summary)
            """)
        for verdict in PulseTrustVerdict.allCases where verdict != .published {
            XCTAssertTrue(tally.summary.contains("\(verdict.rawValue)="), """
                The summary omits the `\(verdict.rawValue)` count: \(tally.summary)
                A refusal class that is counted but never printed is invisible exactly when it \
                is the binding one.
                """)
        }
    }

    /// NaN at a bio boundary is an edge case, not an impossibility (`engineering.md` §3), and
    /// `max(x, y)` is `y >= x ? y : x` — so the ACCUMULATOR must be the first argument or one
    /// non-finite sample pins the maximum at NaN for the rest of the window and the line reads
    /// `maxConf=nan` for a session that was fine.
    func testOneNonFiniteSampleCannotPoisonTheWindow() {
        var tally = TrustWindowTally()
        tally.note(verdict: .published, bpm: 60, confidence: 0.8, autoStrength: 0.7)
        tally.note(verdict: .bothLow, bpm: .nan, confidence: .nan, autoStrength: .nan)
        tally.note(verdict: .bothLow, bpm: .infinity, confidence: 0.2, autoStrength: 0.1)
        XCTAssertEqual(tally.maxConfidence, 0.8, accuracy: 1e-9, """
            A NaN confidence overwrote the window maximum (\(tally.maxConfidence)). Put the \
            accumulator first in `max` — that is the repo's documented NaN-safe order, and \
            this has caused shipped permanent-silence bugs elsewhere.
            """)
        XCTAssertEqual(tally.maxPeriodicity, 0.7, accuracy: 1e-9)
        XCTAssertEqual(tally.bpmSpread ?? -1, 0, accuracy: 1e-9, """
            A non-finite bpm reached the spread (\(String(describing: tally.bpmSpread))). Only \
            the one finite estimate (60) was observed, so the spread is exactly zero.
            """)
        XCTAssertFalse(tally.summary.contains("nan"), """
            The summary prints "nan": \(tally.summary)
            """)
    }

    /// The window length is pinned as a FLOOR and by being PRINTED, never as the literal 30
    /// (#364): a later cycle hunting a specific behaviour must be able to shorten it without
    /// turning a gate red. What must not change is that the line says how many attempts it
    /// summarises — a bare pass count is unreadable without its denominator.
    func testTheWindowIsBoundedAndPrintsItsOwnDenominator() {
        XCTAssertGreaterThanOrEqual(TrustWindowTally.windowAttempts, 1, """
            A window of zero attempts would emit on every publish tick.
            """)
        var tally = TrustWindowTally()
        for _ in 0..<(TrustWindowTally.windowAttempts - 1) {
            tally.note(verdict: .bothLow, bpm: 0, confidence: 0, autoStrength: 0)
        }
        XCTAssertFalse(tally.isComplete, "the window completed early")
        tally.note(verdict: .bothLow, bpm: 0, confidence: 0, autoStrength: 0)
        XCTAssertTrue(tally.isComplete, "the window never completes — the line would never emit")
        XCTAssertTrue(tally.summary.contains("/\(TrustWindowTally.windowAttempts) ok"), """
            The summary no longer prints the attempt count: \(tally.summary)
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT, END-TO-END) — the floors still stand in the assumed order

    #if canImport(AVFoundation) && canImport(Observation)

    /// Green on both trees, and the point of the file. The failure taxonomy assumes the
    /// strong-only clause is the HARDER one: `.periodicityLow` is reported when confidence
    /// cleared its floor and periodicity did not, which is only a refusal while
    /// `trustAutoFloor <= strongAutoFloor`. Invert them and a frame that publishes via the
    /// strong clause gets classified as a refusal — the instrument would report an event that
    /// did not happen, and claim 1 would still be green because it compares the two predicates
    /// rather than the taxonomy's meaning.
    func testTheTrustFloorsKeepTheOrderTheTaxonomyAssumes() {
        XCTAssertLessThanOrEqual(CameraRPPGBioPublisher.trustAutoFloor,
                                 CameraRPPGBioPublisher.strongAutoFloor, """
            `trustAutoFloor` now exceeds `strongAutoFloor`. The two-evidence clause would then \
            be STRICTER than the strong-only clause it is meant to be the easier of, and the \
            refusal taxonomy would mislabel frames that publish. Retuning either floor is \
            legitimate — inverting them is a different rule and needs this assertion revisited \
            in the same commit.
            """)
        XCTAssertGreaterThan(CameraRPPGBioPublisher.displayThreshold, 0, """
            The confidence floor collapsed to zero or below; `.confidenceLow` could never be \
            reported and the two-evidence rule would be periodicity-only.
            """)
    }

    #endif

    // MARK: - claim 5 (SOURCE SCAN) — the loop actually feeds the instrument

    /// `shouldPublish`'s doc block records the gap this closes in its own words: *"no test
    /// asserts that the publish loop actually CALLS this"*. Behaviour cannot see an instrument
    /// that is never fed — an unfed tally is SILENT, and a silent breadcrumb reads exactly like
    /// a session that produced no windows.
    func testThePublishTickFeedsTheTallyAndSpeaksOnce() throws {
        let src = try source(Self.publisherPath)
        let needles = [
            "let verdict = Self.trustVerdict(bpm: bpm,":
                "the publish gate no longer computes a verdict",
            "let trustNow = verdict == .published":
                "the gate is no longer derived from the verdict — the two can now disagree",
            "self.trustWindow.note(verdict: verdict,":
                "the decision is no longer recorded, so the window counts nothing",
            "self.flushTrustWindow(force: false)":
                "the publish loop no longer speaks when a window fills",
            "flushTrustWindow(force: true)":
                "stop() no longer flushes a partial window — a short or stalled take goes silent",
            "EchoelCrashLog.breadcrumb(\"trust: \" + trustWindow.summary)":
                "the window never reaches the log — the instrument is mute"
        ]
        for (needle, why) in needles {
            let hits = src.components(separatedBy: needle).count - 1
            XCTAssertEqual(hits, 1, """
                `\(needle)` occurs \(hits)× in \(Self.publisherPath), expected exactly one — \
                \(why).
                Exactly one, not "at least one" (#408): a second copy would mean two windows \
                counting the same tick, and the printed pass RATE — the one number the next \
                trust decision rests on — would be halved with nothing else looking wrong. \
                If the call site legitimately moved, re-anchor this scan in the same commit \
                (#454); do not relax the count.
                """)
        }
    }

    // MARK: - claim 6 (COUNTERWEIGHT, SOURCE SCAN) — one spelling of the rule, still

    /// The structural property that makes claim 1 cheap to keep true. If `trustVerdict` ever
    /// re-derives the pass case from the thresholds, agreement stops being free and becomes
    /// something a grid has to police — and a grid only polices the points it samples.
    func testTheVerdictStillAsksTheShippedPredicateFirst() throws {
        let body = try declarationBody(of: "nonisolated static func trustVerdict",
                                       in: Self.publisherPath)
        XCTAssertTrue(body.contains("shouldPublish(bpm: bpm,"), """
            `trustVerdict` no longer asks `shouldPublish` for its pass case. That call is what \
            makes the instrument structurally unable to contradict the gate (#416); without it \
            the `.published` case is a SECOND spelling of `pulseTrustworthy`, and two spellings \
            of one threshold is the defect whether or not they agree today.
            """)
        XCTAssertFalse(body.contains("strongAutoFloor"), """
            `trustVerdict` now names `strongAutoFloor`. The refusal branches run only after \
            `shouldPublish` already said no, where the strong-only clause is known to have \
            failed — re-testing it there is either dead code or a second rule.
            """)
    }

    // MARK: - claim 7 (END-TO-END) — the binding class reports its OWN coincidence (#833)

    /// The v10.79.420 log's window maxima could not answer the one question that decides the
    /// trust-rule debate: on the ticks where ONLY periodicity refused, how close did acf come,
    /// and was the estimate flat? Window-wide maxima are not tuples — `maxAcf=0.45` in a
    /// window can belong to a wild `bothLow` tick while every conf-OK tick sat at 0.30. These
    /// are RAW per-class observations of the SHIPPED verdict (no new threshold, no candidate
    /// rule — the file header's law), so the founder's next log carries the coincidence.
    func testTheAcfOnlyClassReportsItsOwnCoincidence() {
        var tally = TrustWindowTally()
        tally.note(verdict: .periodicityLow, bpm: 52, confidence: 0.90, autoStrength: 0.31)
        tally.note(verdict: .periodicityLow, bpm: 54, confidence: 0.85, autoStrength: 0.38)
        tally.note(verdict: .periodicityLow, bpm: 53, confidence: 0.92, autoStrength: 0.29)
        // A wild tick from ANOTHER class must not contaminate the class stats — this is the
        // entire reason the per-class block exists beside the window-wide maxima.
        tally.note(verdict: .bothLow, bpm: 120, confidence: 0.10, autoStrength: 0.45)
        // Precomputed (#442): class max acf = 0.38, class spread = 54 − 52 = 2.0 — while the
        // window-wide figures read maxAcf=0.45 and bpmSpread=68.0.
        XCTAssertTrue(tally.summary.contains("acfOnly(maxAcf=0.38 bpmSpread=2.0)"), """
            The acf-only class no longer reports its own maxAcf/spread — or another class's \
            samples leaked into it: \(tally.summary)
            Without this block the next device log is again a pile of window maxima that \
            cannot say whether the refused-but-confident ticks were stable near-misses.
            """)
        XCTAssertTrue(tally.summary.contains("maxAcf=0.45"), """
            The window-wide maximum vanished — the class block must be IN ADDITION to it, \
            not a replacement: \(tally.summary)
            """)
    }

    /// A window that never hit the class must not print an empty block — the line is read
    /// by a human in a crash-triage file, and `acfOnly(maxAcf=0.00 …)` would read as a
    /// measurement of nothing (#454's shape, in a log line).
    func testTheAcfOnlyBlockIsAbsentWhenTheClassNeverFired() {
        var tally = TrustWindowTally()
        tally.note(verdict: .published, bpm: 60, confidence: 0.7, autoStrength: 0.5)
        tally.note(verdict: .bothLow, bpm: 59, confidence: 0.1, autoStrength: 0.1)
        XCTAssertFalse(tally.summary.contains("acfOnly"), """
            The class block prints for a window that never saw a periodicity-only refusal: \
            \(tally.summary)
            """)
    }

    /// Same NaN law as the window-wide maxima: accumulator first, one poisoned sample
    /// must not pin the class maximum.
    func testANonFiniteSampleCannotPoisonTheClassMaximum() {
        var tally = TrustWindowTally()
        tally.note(verdict: .periodicityLow, bpm: 52, confidence: 0.9, autoStrength: .nan)
        tally.note(verdict: .periodicityLow, bpm: 53, confidence: 0.9, autoStrength: 0.20)
        XCTAssertTrue(tally.summary.contains("acfOnly(maxAcf=0.20 bpmSpread=1.0)"), """
            One non-finite acf sample poisoned the class maximum (or the class spread \
            counted a non-usable estimate): \(tally.summary)
            """)
        XCTAssertFalse(tally.summary.contains("nan"), "the summary prints nan: \(tally.summary)")
    }

    /// The class can fire with NO usable estimate — the shipped gate filters NaN/≤0 bpm to
    /// `.noEstimate`, but `+∞` passes `bpm > 0` and a defensive caller may classify oddly.
    /// The block must then print the honest em-dash, not a fabricated number (reviewer #833).
    func testAClassTickWithoutAUsableEstimatePrintsTheDash() {
        var tally = TrustWindowTally()
        tally.note(verdict: .periodicityLow, bpm: .infinity, confidence: 0.9, autoStrength: 0.20)
        XCTAssertTrue(tally.summary.contains("acfOnly(maxAcf=0.20 bpmSpread=—)"), """
            A class tick without a usable bpm no longer prints the em-dash — either a \
            non-finite estimate reached the class spread (a fabricated measurement), or \
            the block's absence hid a fired class: \(tally.summary)
            """)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct TrustAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw TrustAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Brace-matched body after `key`, never a line window: this file is ~1 700 lines and its
    /// comment blocks run 20–40 lines, so any fixed window is unsound by construction (#408).
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: key).count - 1
        guard hits == 1 else {
            throw TrustAnchorMissing(reason: """
                `\(key)` occurs \(hits)× in \(relativePath); this extraction needs exactly one \
                so it cannot silently read a different declaration.
                """)
        }
        guard let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw TrustAnchorMissing(reason: "no opening brace after `\(key)`")
        }
        var depth = 0
        var i = open
        var out = ""
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
        throw TrustAnchorMissing(reason: "unbalanced braces after `\(key)` in \(relativePath)")
    }
}
