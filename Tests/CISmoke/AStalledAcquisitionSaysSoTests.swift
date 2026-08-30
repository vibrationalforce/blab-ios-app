// AStalledAcquisitionSaysSoTests.swift
// Echoel — #484. "Hold still — finding your pulse…" has to stop being the answer eventually.
//
// WHAT THIS GUARDS. Device log 2490 ran 97 s of camera acquisition with no lock and no change
// of message. Nothing on screen was FALSE — checked rather than assumed, and it is THREE
// independent checks, not four:
//   · the "exposure locked on finger" line is an `EchoelCrashLog.breadcrumb`, so it is not on
//     the measurement surface at all. ⛔ The first version of this header said "log file only,
//     NEVER RENDERED", which is false — `EchoelStudioView`'s reachable "Diagnostics" row
//     renders the diag log (`EchoelCrashLog.diagnosticsExport()` since #916, `currentLog()`
//     before it). The sharper reading is that the opt-in
//     Diagnostics sheet is plausibly HOW that line reached a human and misled one.
//   · `signalQuality` has zero UI consumers — its one consumer is the 2 s breadcrumb. ⛔ "zero
//     consumers" was too strong.
//   · `displayBPM` never advanced. ⛔ The first version listed `isLocked` as a FOURTH check; it
//     is the SAME fact — both are `pulseTrustworthy` byte-for-byte, so they cannot disagree,
//     and a corroboration list containing a duplicate corroborates less than it looks like.
// What was missing was TIME. `.finding` means "wait"; after long enough that stops being true,
// and no surface knew how long it had been saying it.
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
// ⭐ AND A LATCH, NOT A COMPUTED SPLIT — the correction the #484 review forced. WHICH stall it
// is (`hasRhythmlessSignal`) is decided ONCE, in the tick, the instant the window elapses. The
// first version re-derived it on every read of `acquisitionCue`, i.e. ~10 Hz on a leaf that
// re-renders at that rate, from two values sitting right at their thresholds — and
// `CameraAnalyzer.isUncorroboratedRipple` actively bleeds `bpmConfidence *= 0.9` per peak pass
// THROUGH the 0.6 line. A stuck take therefore flipped the header between two labels and the
// card between two OPPOSITE instructions several times a second.
//
// ⚠️ HONEST GRADING, because the flattering version is available and wrong. This file cannot
// be graded per-assertion against the pre-#484 tree AT ALL: every test references
// `PulseCue.stalled`, which does not exist there, so the bundle does not compile and no
// assertion has a verdict. That is the #464 situation stated plainly rather than dressed up as
// "only the source scans could have been red". What the file is FOR is forward: the scans
// catch a later removal, and the behavioural assertions are counterweights against the tidy-ups
// this change invites — making `.finding` actionable too (which collapses the whole
// distinction), re-teaching the strap route in the hint (which `bioPanel` already carries
// verbatim — #416), collapsing the two labels, and reverting to a wording whose subject is the
// user's body.
//
// ⚠️ WHAT NO ASSERTION HERE CAN DO. `CameraRPPGBioPublisher` lives behind
// `#if canImport(AVFoundation)`, `acquisitionSince` and `stallWasRhythmless` are private, and
// driving them needs a camera — so the wiring half is source text, not a run. That 45 s reads
// right to a waiting person, and that the amber header tile actually leads them to the panel,
// are device checks.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, and that is said rather than overclaimed. The
// first version called it LOAD-BEARING. Measured instead: strip-vs-raw changes the verdict of
// ZERO assertions in this file today — the scanned needles are code-shaped enough that the
// prose mentions do not collide. It stays because #453 made one definition of "code, not
// prose" for the whole blocking bundle and a private exception is the defect that skill exists
// to remove; it is not what makes any assertion here sound.

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

    /// The brace-matched block that STARTS at `anchor`. Windowing matters here for the same
    /// reason it did in #453/#358: `acquisitionSince = 0` now appears TWICE in the publisher
    /// (the failed-start path and `stop()`), so a whole-file `contains` would report both as
    /// present when only one is. Comments are already stripped by `code(_:)`; a `{` inside a
    /// string literal would still skew the count and none of the windows used here has one.
    private func block(startingAt anchor: String, in src: String) -> String? {
        guard let a = src.range(of: anchor),
              let open = src.range(of: "{", range: a.lowerBound..<src.endIndex) else { return nil }
        var depth = 0
        var i = open.lowerBound
        while i < src.endIndex {
            let c = src[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return String(src[a.lowerBound...i]) }
            }
            i = src.index(after: i)
        }
        return nil
    }

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let cue = "Sources/Echoelmusic/Bio/PulseCue.swift"

    // MARK: - The case says two different things, because it means two different things

    func testTheTwoStallVariantsGiveOppositeAdvice() {
        let rhythmless = PulseCue.stalled(hasRhythmlessSignal: true)
        let nothing = PulseCue.stalled(hasRhythmlessSignal: false)

        XCTAssertNotEqual(rhythmless.fullHint, nothing.fullHint, """
            Both stall variants now give the SAME guidance, which makes the associated value \
            decoration. They exist because the two failures need opposite advice: at least one \
            channel carrying something means the lens HAS a signal and it is the wrong shape \
            (re-place the finger); neither channel having anything, above the `pressGently` \
            amplitude floor, is a perfusion problem and re-gripping the same finger is the \
            least likely fix.
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

    /// The compliance edge, and it is the one assertion in this file whose absence would cost
    /// something outside engineering. The first version of `.stalled` said "Signal, but no
    /// steady rhythm" with the short label "No rhythm" — rendered inside a tile whose
    /// accessibility label is *Heart rate*, so VoiceOver spoke "Heart rate. Signal, but no
    /// steady rhythm." That is one parse from "your heartbeat is irregular", and low
    /// autocorrelation with a still-firing peak counter is *also* what an irregular rhythm
    /// looks like on a PPG trace — so the sentence could be misread as a cardiac observation
    /// AND be accidentally correct as one. Worst combination available to a non-medical
    /// instrument, and nothing in the design needed the word.
    func testNeitherStallVariantMakesTheBodyTheSubject() {
        for cue in [PulseCue.stalled(hasRhythmlessSignal: true),
                    PulseCue.stalled(hasRhythmlessSignal: false)] {
            for text in [cue.fullHint, cue.shortLabel] {
                let lowered = text.lowercased()
                for word in ["rhythm", "irregular", "heartbeat", "your heart", "arrhythm"] {
                    XCTAssertFalse(lowered.contains(word), """
                        A stall string describes the USER'S BODY rather than the signal: \
                        "\(text)" contains "\(word)". These strings render inside a tile \
                        labelled *Heart rate*, so VoiceOver composes them into a sentence \
                        about the person's heart — and this app is explicitly not a diagnostic \
                        instrument ("data for self-observation, NOT medical diagnosis"). The \
                        subject of both sentences is the SIGNAL: what the lens is or is not \
                        giving us. Rewrite, do not delete this assertion.
                        """)
                }
            }
            // The header monitor tile is narrow chrome — a label that wraps or truncates is a
            // label that stops coaching. Every other `PulseCue` label is ≤12 characters.
            XCTAssertLessThanOrEqual(cue.shortLabel.count, 12, """
                The stall header label "\(cue.shortLabel)" is \(cue.shortLabel.count) \
                characters. `PulseMeasurementView` and the compact header monitor budget for \
                the length of the existing labels ("Press gently" is the longest at 12); \
                longer than that truncates in the one place the case is visible while playing.
                """)
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

    /// COUNTERWEIGHT. The obvious "improvement" is to end both stall hints with "or try a chest
    /// strap". `EchoelStudioView.bioPanel` already carries that route — since #616 as the
    /// visible "Bio source" ROW (`bioSourceRow`, right under the panel's lead sentence), no
    /// longer as a caption naming the long-press. Same #416 argument, stronger: the route is
    /// now a CONTROL, and a control cannot go stale the way a describing sentence could.
    /// ⛔ The first version of this comment called `bioPanel` "the panel that hosts the
    /// measurement card" and said a VoiceOver user reaches the route "immediately before the
    /// card": both wrong. The panel hosts `BioStripView`; the source row comes AFTER it,
    /// and "immediately before" was borrowed from a comment about the Open Routing button. The
    /// chain that gets a stuck user there is `isActionable` → the header tile goes amber and
    /// shows a label at all; TAPPING the tile opens the panel (the colour only draws the eye).
    func testTheStallHintsDoNotRestateTheSourceRoute() {
        for cue in [PulseCue.stalled(hasRhythmlessSignal: true),
                    PulseCue.stalled(hasRhythmlessSignal: false)] {
            let hint = cue.fullHint.lowercased()
            for word in ["strap", "bluetooth", "source", "simulation", "demo"] {
                XCTAssertFalse(hint.contains(word), """
                    A stall hint now names the bio-source route ("\(word)"): \
                    "\(cue.fullHint)". That route has ONE owner — the "Bio source" row in \
                    `bioPanel` (#616), which is on screen with this card. A second copy here \
                    is the two-definitions defect, and it is the copy that will go stale, \
                    because the entries it would describe live in `BioSourceOption`.
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
            log 2490 ran 97 s with no lock. A threshold there means the case never fires on \
            the take that motivated it.
            """)

        // The WINDOW is what is defended, not the number: 45 is a choice inside it, and the
        // upper bound rests on n = 1. See `stalledAfterSeconds`' own comment for how unequally
        // checkable the three numbers are.
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

        // WINDOWED, because `acquisitionSince = 0` is now written in two places and a
        // whole-file `contains` would let either one alone satisfy both claims.
        guard let stopBody = block(startingAt: "public func stop()", in: src) else {
            return XCTFail("could not window `stop()` — re-anchor rather than delete this")
        }
        XCTAssertTrue(stopBody.contains("acquisitionSince = 0")
                      && stopBody.contains("stallWasRhythmless = nil"), """
            `stop()` no longer clears BOTH stall anchors — #454's law, one field later. A \
            per-take anchor a stop forgets is a previous take's number read as this one's: an \
            idle publisher would accumulate a 45 s "stall" and report it the moment the next \
            take places a finger. They are cleared as a PAIR because `acquisitionCue` reads \
            the latch and guards on the clock; leaving one set is a half-armed case.
            """)

        guard let failedStart = block(startingAt: "if gen == startGeneration", in: src) else {
            return XCTFail("could not window the failed-start path — re-anchor, do not delete")
        }
        XCTAssertTrue(failedStart.contains("acquisitionSince = 0")
                      && failedStart.contains("stallWasRhythmless = nil"), """
            A camera start that FAILS undoes `isRunning` but leaves the stall clock armed, so \
            an idle publisher carries a non-zero anchor — contradicting that field's own \
            documented sentinel ("0 means no take is running"). Whatever undoes `isRunning` \
            must undo the clock in the same branch.
            """)

        XCTAssertTrue(src.contains("if self.placementCue != .finding || self.capture.isInterrupted {"), """
            The publish tick no longer resets the stall clock by asking the classification \
            (and suppressing on interruption). Asking `placementCue` is what makes the clock \
            mean "uninterrupted time in `.finding`" without restating the brightness / motion \
            / amplitude / lock tests anywhere — re-deriving them here would be two definitions \
            of `.finding`. The `isInterrupted` half is the one case that did NOT fall out for \
            free: nothing stops this publisher on `scenePhase`, and every input to \
            `placementCue` freezes while iOS holds the session, so a take frozen in `.finding` \
            accrued the whole interruption and came back blaming the user's finger for a gap \
            iOS caused.
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
            The publish tick no longer reads the shared threshold. A local literal is the \
            #416 shape: the number would live in two places, and the one in `PulseCue` — the \
            one carrying the measurements that justify it — is not the one that ships.
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

    /// The anti-flicker half, and the reason it is a separate test from the wiring: the defect
    /// it guards is not "the split is wrong" but "the split is re-decided at 10 Hz".
    func testWhichStallItIsIsLatchedOnceAndNotRecomputedPerRead() throws {
        let src = try code(Self.publisher)

        XCTAssertTrue(src.contains("@ObservationIgnored private var stallWasRhythmless: Bool?"), """
            The stall-variant latch is gone or changed shape. It must be optional (`nil` = the \
            window has not elapsed, which is also what `acquisitionCue` guards on) and \
            `@ObservationIgnored` — this publisher is under the freeze law (10.76.41/50) and \
            a tracked field written in the 10 Hz tick adds an invalidation source to a root \
            that hosts menu Pickers.
            """)

        guard let cueBody = block(startingAt: "public var acquisitionCue: PulseCue", in: src) else {
            return XCTFail("could not window `acquisitionCue` — re-anchor, do not delete")
        }
        XCTAssertTrue(cueBody.contains("stallWasRhythmless"), """
            `acquisitionCue` no longer reads the latch. If it derives the variant itself it is \
            re-deriving it on every read — ~10 Hz on a leaf that re-renders at that rate, from \
            two values sitting right at their thresholds, one of which \
            (`CameraAnalyzer.isUncorroboratedRipple`) actively bleeds confidence THROUGH the \
            display line. That flipped the header between two labels and the card between two \
            OPPOSITE instructions several times a second.
            """)
        for constant in ["displayThreshold", "trustAutoFloor", "lastAutoStrength"] {
            XCTAssertFalse(cueBody.contains(constant), """
                `acquisitionCue` reads `\(constant)` — i.e. it classifies the stall itself \
                instead of reading the latched answer. That is the flicker defect above, and \
                it is also a second copy of a threshold pair the trust gate already owns.
                """)
        }

        XCTAssertTrue(src.contains("self.stallWasRhythmless = self.confidence >= Self.displayThreshold")
                      && src.contains("|| self.analyzer.lastAutoStrength >= Self.trustAutoFloor"), """
            The rhythmless/no-signal split changed shape. Two things are pinned here and both \
            were wrong once. (1) It must ask the SAME two constants `pulseTrustworthy` uses — \
            the split is only meaningful as "the band the trust gate rejects", and hard-coding \
            either number lets a retune leave this classification pointing at a band that no \
            longer exists. (2) It must be `||`, NOT `&&`: the first version tested `conf >= \
            display && acf < trust`, which made the FALSE branch a catch-all sweeping up conf \
            0.5 / acf 0.5 — genuine corroborated periodicity that merely had not cleared the \
            strong-only clause, i.e. exactly what `strongAutoFloor` exists for — and told \
            those users to warm their hands.
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

    /// The next log has to be able to answer the question this whole slice had to INFER: was
    /// the take continuously `.finding`, and did `.stalled` ever fire? `stalledAfterSeconds`'
    /// upper bound rests on "97 s with no change of message", and that phrase was derived from
    /// `finger/R/bright/amp/pk/acf`, not read off — the breadcrumb carried no cue string.
    func testTheBreadcrumbCarriesTheCueSoTheNextLogNeedNotInfer() throws {
        let src = try code(Self.publisher)
        XCTAssertTrue(src.contains("cue=%@"), """
            The 2 s diagnostic breadcrumb no longer prints the cue. Without it a device log \
            can only reconstruct the coaching state from the raw fields, which is exactly the \
            inference that left log 2490's "no change of message" unverifiable.
            """)
        XCTAssertTrue(src.contains("self.acquisitionCue.shortLabel"), """
            The breadcrumb prints something other than the cue's own label. It must print the \
            SAME derivation the screen shows — a separately formatted string in the log is a \
            second definition, and the log is where the next session's evidence comes from.
            """)
    }
}
