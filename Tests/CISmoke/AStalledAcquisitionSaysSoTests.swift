// AStalledAcquisitionSaysSoTests.swift
// Echoel — #484. "Hold still — finding your pulse…" has to stop being the answer eventually.
//
// WHAT THIS GUARDS. Device log 2490 ran 97 s of camera acquisition with no lock and no change
// of message. Nothing on screen was FALSE — checked rather than assumed: the "exposure locked
// on finger" line is an `EchoelCrashLog.breadcrumb` (log file only, never rendered),
// `signalQuality` has zero consumers, `displayBPM` never advanced and `isLocked` was false
// throughout. What was missing was TIME. `.finding` means "wait"; after long enough that
// stops being true, and no surface knew how long it had been saying it.
//
// ⭐ THE SHAPE THAT MAKES THIS ONE DEFINITION AND NOT TWO. `acquisitionCue` now has two
// layers: `placementCue` (instantaneous — is anything wrong with the contact right now) and
// the duration upgrade on top. The publish tick resets the stall clock by asking
// `placementCue != .finding` rather than re-testing brightness / motion / amplitude / lock,
// so the tick and the screen can never disagree about what `.finding` is (#416). Three
// consequences fall out of that one line instead of needing their own code: a lock resets the
// window, the permission dialog does not count toward it, and a user who spends a minute
// fighting `.tooBright` starts their 45 s from the moment the contact finally comes good.
//
// ⚠️ HONEST GRADING, because the flattering version is available and wrong. Only the SOURCE
// SCANS could have been red before this commit — every behavioural assertion drives a case
// this same commit adds, so calling them regressions would be the #433 defect. The rest are
// counterweights against the tidy-ups this change invites: making `.finding` actionable too
// (which collapses the whole distinction), and re-teaching the strap route in the hint (which
// `bioPanel` already carries verbatim — #416, and that panel's own comment: "Saying it three
// times is not thoroughness").
//
// ⚠️ WHAT NO ASSERTION HERE CAN DO. `CameraRPPGBioPublisher` lives behind
// `#if canImport(AVFoundation)`, `acquisitionSince` is private, and driving it needs a camera
// — so the wiring half is source text, not a run. That 45 s reads right to a waiting person,
// and that the amber header tile actually leads them to the panel, are device checks.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING, not hygiene: both scanned files quote every one
// of these tokens in their own ⛔/⭐ prose, several times each.

import Foundation
import XCTest
@testable import Echoelmusic

final class AStalledAcquisitionSaysSoTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — the wiring half of this file \
                inspects source text, so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func code(_ path: String) throws -> String {
        SourceText.codeOnly(
            try String(contentsOf: try repoRoot().appendingPathComponent(path), encoding: .utf8))
    }

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let cue = "Sources/Echoelmusic/Bio/PulseCue.swift"

    // MARK: - The case says two different things, because it means two different things

    func testTheTwoStallVariantsGiveOppositeAdvice() {
        let rhythmless = PulseCue.stalled(hasRhythmlessSignal: true)
        let nothing = PulseCue.stalled(hasRhythmlessSignal: false)

        XCTAssertNotEqual(rhythmless.fullHint, nothing.fullHint, """
            Both stall variants now give the SAME guidance, which makes the associated value \
            decoration. They exist because the two failures need opposite advice: confidence \
            at display grade with no autocorrelation means something IS coupling to the lens \
            and it is not a heartbeat (re-place the finger); neither channel having anything, \
            above the `pressGently` amplitude floor, is a perfusion problem and re-gripping \
            the same finger is the least likely fix.
            """)
        XCTAssertNotEqual(rhythmless.shortLabel, nothing.shortLabel, """
            The two stall variants collapsed to one header label. The header is where a user \
            decides whether to keep waiting, so it is the surface that most needs to \
            distinguish "the lens has something and it is the wrong shape" from "the lens has \
            nothing".
            """)

        XCTAssertFalse(nothing.shortLabel.lowercased().contains("weak"), """
            The no-signal stall label reads as a WEAK signal: "\(nothing.shortLabel)". That \
            collides with `.pressGently`, whose entire trigger is the amplitude floor this \
            case has already cleared — two cues for two different states saying the same word \
            is how a coaching line stops being coaching.
            """)

        for cue in [rhythmless, nothing] {
            XCTAssertFalse(cue.fullHint.isEmpty, "a stall hint is empty")
            XCTAssertFalse(cue.shortLabel.isEmpty, "a stall label is empty")
        }
    }

    /// The ONLY thing the header renders differently for `.stalled` than for `.finding`.
    /// `HeaderMonitors.showCue` is `!locked && (cue?.isActionable ?? false)`, so without this
    /// the case would be invisible to the person it was written for — while playing, the
    /// header is the only pulse surface on screen.
    func testAStallIsActionableAndPlainWarmupIsNot() {
        XCTAssertTrue(PulseCue.stalled(hasRhythmlessSignal: true).isActionable)
        XCTAssertTrue(PulseCue.stalled(hasRhythmlessSignal: false).isActionable)

        XCTAssertFalse(PulseCue.finding.isActionable, """
            `.finding` became actionable. That is the tidy-up this slice most invites and it \
            collapses the distinction: the header would go amber for every normal warm-up, \
            and an amber that is always on carries no information when the acquisition really \
            has stalled. `.finding` means WAIT and must stay silent.
            """)
        XCTAssertFalse(PulseCue.locked.isActionable, "a locked pulse is not a problem to fix")
    }

    /// COUNTERWEIGHT (green before and after). The obvious "improvement" is to end both stall
    /// hints with "or try a chest strap". `EchoelStudioView.bioPanel` — the panel that hosts
    /// the measurement card — already carries that route verbatim and correctly, and a
    /// VoiceOver user reaches that line immediately before the card. #416, and that panel's
    /// own comment about saying it three times.
    func testTheStallHintsDoNotRestateTheSourceRoute() {
        for cue in [PulseCue.stalled(hasRhythmlessSignal: true),
                    PulseCue.stalled(hasRhythmlessSignal: false)] {
            let hint = cue.fullHint.lowercased()
            for word in ["strap", "bluetooth", "source", "simulation", "demo"] {
                XCTAssertFalse(hint.contains(word), """
                    A stall hint now names the bio-source route ("\(word)"): \
                    "\(cue.fullHint)". That route has ONE owner — the sentence in \
                    `bioPanel`, which is on screen with this card. A second copy here is the \
                    two-definitions defect, and it is the copy that will go stale, because \
                    the menu entry it describes lives in `HeaderMonitors`.
                    """)
            }
        }
    }

    // MARK: - The threshold sits inside a window this repo measured

    func testTheStallThresholdIsAboveEveryObservedSuccessAndBelowTheObservedFailure() {
        let t = PulseCue.stalledAfterSeconds

        XCTAssertGreaterThan(t, 32, """
            The stall threshold is \(t) s, at or under the slowest acquisition this repo has \
            watched SUCCEED — ~19 s to re-acquire after a stop (#415) and ~32 s from cold in \
            device log 2490. Below that line the app calls a normal acquisition stalled, \
            which is worse than the silence it replaces: it teaches the user to distrust a \
            message that is usually wrong.
            """)
        XCTAssertLessThan(t, 97, """
            The stall threshold is \(t) s, at or past the failure it exists to name — device \
            log 2490 ran 97 s with no lock and no change of message. A threshold there means \
            the case never fires on the take that motivated it.
            """)

        // The window is what is defended, not the number: 45 is a choice inside it.
        XCTAssertTrue(t.isFinite && t > 0, "the stall threshold must be a real duration")
    }

    // MARK: - The wiring (source text — see the header for what this cannot prove)

    func testTheStallClockIsArmedResetAndAdvanced() throws {
        let src = try code(Self.publisher)

        XCTAssertTrue(src.contains("acquisitionSince = CFAbsoluteTimeGetCurrent()"), """
            `start(publishing:)` no longer arms the stall clock. It must be set synchronously \
            with `isRunning`, before the camera-permission await, because zero is this \
            field's "no take is running" sentinel and `acquisitionCue` guards on it — an \
            unarmed clock means the case can never fire.
            """)
        XCTAssertTrue(src.contains("acquisitionSince = 0"), """
            `stop()` no longer clears the stall clock — #454's law, one field later. A \
            per-take anchor a stop forgets is a previous take's number read as this one's, \
            and here specifically: an idle publisher would accumulate a 45 s "stall" and \
            report it the moment the next take places a finger. Zero, not a wall-clock value, \
            because zero is the sentinel `acquisitionCue` tests.
            """)
        XCTAssertTrue(src.contains("if self.placementCue != .finding { self.acquisitionSince = nowT }"), """
            The publish tick no longer resets the stall clock by asking the classification. \
            This one line is what makes the clock mean "uninterrupted time in `.finding`" \
            without restating the brightness / motion / amplitude / lock tests anywhere — \
            re-deriving them here would be two definitions of `.finding`, and the tick and \
            the screen would eventually disagree about which one the user is in.
            """)
    }

    func testTheDurationLayerSitsOnTopOfTheInstantaneousOne() throws {
        let src = try code(Self.publisher)

        XCTAssertTrue(src.contains("private var placementCue: PulseCue"), """
            The instantaneous placement classification is gone or was renamed. It has to \
            exist as its own member: it is what the publish tick asks, and folding it back \
            into `acquisitionCue` makes that question circular (the cue would read the clock \
            the tick is about to set).
            """)
        XCTAssertTrue(src.contains("PulseCue.stalledAfterSeconds"), """
            `acquisitionCue` no longer reads the shared threshold. A local literal here is \
            the #416 shape: the number would live in two places, and the one in `PulseCue` — \
            the one carrying the measurements that justify it — is not the one that ships.
            """)
        XCTAssertTrue(src.contains("Self.displayThreshold") && src.contains("Self.trustAutoFloor"), """
            The rhythmless/no-signal split no longer asks the SAME two constants the trust \
            gate uses. That split is only meaningful as "the band `pulseTrustworthy` \
            rejects"; hard-coding either number lets a retune of the trust gate leave this \
            classification pointing at a band that no longer exists.
            """)

        // ORDER. `placementCue` reads `confidence`/`detectedBPM`, so the tick's reset has to
        // run AFTER this tick's values are stored — otherwise the clock is being reset (or
        // not) on the PREVIOUS tick's numbers, which is exactly the class of defect #447 was.
        guard let stored = src.range(of: "self.detectedBPM = self.analyzer.estimatedBPM"),
              let reset = src.range(of: "if self.placementCue != .finding") else {
            return XCTFail("""
                Could not locate both the value store and the stall-clock reset in the \
                publish tick — re-anchor this ordering assertion in the same commit rather \
                than deleting it.
                """)
        }
        XCTAssertLessThan(stored.lowerBound, reset.lowerBound, """
            The stall clock is reset BEFORE this tick's confidence/BPM are stored, so \
            `placementCue` classifies on the previous tick's numbers. One tick of skew is \
            harmless on its own; what is not harmless is that the tick and the screen would \
            then be reading different states, which is the single thing the two-layer split \
            exists to prevent.
            """)
    }

    func testTheCaseAndItsThresholdLiveInThePureFile() throws {
        let src = try code(Self.cue)

        XCTAssertTrue(src.contains("case stalled(hasRhythmlessSignal: Bool)"), """
            `PulseCue.stalled` is gone or changed shape. The string/label/actionable mapping \
            has to stay in this Foundation-only file so it is testable on every platform — \
            the publisher decides WHICH case holds, never what it says.
            """)
        XCTAssertTrue(src.contains("public static let stalledAfterSeconds"), """
            The stall threshold left `PulseCue`. It belongs next to the case it governs, \
            with the measurements that bound it (#415's ~19 s, log 2490's ~32 s success and \
            97 s failure) — a constant separated from its justification is a constant the \
            next session retunes blind.
            """)
    }
}
