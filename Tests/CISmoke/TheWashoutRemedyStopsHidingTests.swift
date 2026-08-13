// TheWashoutRemedyStopsHidingTests.swift
// Echoel — #569. Closes the gap `TheStallRemedyReachesTheScreenTests` recorded and left open:
// `.tooBright` says "Too bright" on screen and keeps its remedy ("Press a little lighter") for
// VoiceOver and a doorless view. The intuitive move on a washed-out reading is to press
// HARDER, so the one cue whose fix is counter-intuitive is the one whose fix was invisible.
//
// WHY IT WAS LEFT OPEN, and why that reason is a design constraint rather than an excuse:
// `placementCue` derives `.tooBright` from `analyzer.brightness`/`redChannel`, which move per
// FRAME. Putting a WRAPPING sentence into `BioStripView`'s reserved slot on that signal would
// resize the slot at the publisher's rate — the #382 shove with a faster clock, in a stack that
// carries the explanatory line, "Open Routing" and the Health opt-in row underneath it. The
// recorded remedy was "a fixed-height slot or a latch, i.e. its own slice". This is the latch.
//
// WHAT SHIPPED. `CameraRPPGBioPublisher` steps a `BioTrustLatch` (#566, reused rather than a
// fifth private counter) over `placementCue == .tooBright` in the existing 10 Hz tick, and
// exposes `cueWarrantsFullHintOnScreen` = the enum's answer OR a LATCHED `.tooBright`. The enum
// is untouched: "how long has this held" is a fact about a running take, not about strings
// (#416) — and that split is why the sibling guard's `XCTAssertFalse(PulseCue.tooBright
// .warrantsFullHintOnScreen)` still stands and must keep standing.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claim 1 is END-TO-END BEHAVIOUR over `BioTrustLatch`, driven at the rate the objection
//     is about (a 30 Hz flap) and at the boundary (3.9 s vs 4.0 s). It is the real proof that
//     the slot cannot resize at frame rate.
//   · claims 2–5 are SOURCE SCANS. `CameraRPPGBioPublisher` is `@MainActor` and owns a live
//     `AVCaptureSession`; no test here can run its tick, so the wiring is pinned as text.
//   · DEVICE PROBE, open: does the sentence arriving after four seconds read as helpful or as
//     a jolt, and does the slot growth shove the rows under it? Source cannot answer either —
//     the same honest limit `LockCueDoesNotShoveTheControlsTests` states for its own branch.
//
// ⚠️ HONEST GRADING (§3), transcribed in Python against the parent (`703f194`) and this tree,
// raw and stripped:
//   · claim 1 drives `BioTrustLatch`, which EXISTS on the parent (#566), so this file DOES
//     compile there and claim 1 has a verdict: GREEN on both. It is a COUNTERWEIGHT — it pins
//     the timing property the whole slice rests on, so a later retune of the latch that broke
//     run-based semantics would surface here rather than as a flickering banner on a device.
//   · claims 2–4 are REGRESSIONS on the parent for their named reason: `cueWarrantsFullHintOn
//     Screen`, the change-guarded write and the `placementCue`-driven step are all new here.
//     Three needles, three distinct facts — NOT one absence reported three times (#486): each
//     could be lost on its own without the others.
//   · claim 5 is a COUNTERWEIGHT, green on both trees: it pins that the reset sites still exist
//     as a PAIR, which is a #454 law the parent already satisfied for its two siblings.
//   · STRIPPER: TRAGEND, 2 of 8 needle verdicts flip — measured. `BioStripView`'s replaced
//     comment block and `PulseCue`'s doc both spell `cueWarrantsFullHintOnScreen` in PROSE, so
//     claim 2's "the publisher declares it" scan and claim 4's exclusion scan read differently
//     raw vs. stripped. Without `SourceText.codeOnly` this file would pass on a tree where the
//     property had been deleted and only the comments survived.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheWashoutRemedyStopsHidingTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    // MARK: - claim 1 (COUNTERWEIGHT, END-TO-END) — the slot cannot resize at frame rate

    /// The objection, executable. A per-frame washout signal that alternates must never engage
    /// the latch, no matter how long it runs: `BioTrustLatch` is RUN-based, so any interruption
    /// restarts the run. If it were ever made integrating, a flickering `.tooBright` would
    /// accumulate to the threshold and the banner would start appearing on a jitter — which is
    /// precisely the resize this slice exists to avoid.
    func testAPerFrameFlapNeverOpensTheBanner() {
        var latch = BioTrustLatch(engageSeconds: 4, releaseSeconds: 3)
        var engagedEver = false
        // 30 s at 30 fps, alternating every frame — far longer than the 4 s window.
        for i in 0..<900 {
            let engaged = latch.step(trustworthy: i % 2 == 0, now: Double(i) / 30.0)
            engagedEver = engagedEver || engaged
        }
        XCTAssertFalse(engagedEver, """
            A washout signal that flips every frame engaged the latch. The latch must be \
            RUN-based, not integrating: `placementCue` recomputes `.tooBright` from per-frame \
            brightness, so an integrating latch would put a WRAPPING sentence into a reserved \
            slot on jitter — the #382 shove with a faster clock, which is the exact objection \
            that kept this remedy off the screen until now.
            """)
    }

    /// The boundary, and the release side. Together these are the bound the slice claims: at
    /// most one resize per release window.
    func testTheBannerNeedsASustainedWashoutAndLingersAfterIt() {
        var latch = BioTrustLatch(engageSeconds: 4, releaseSeconds: 3)
        // 3.9 s of continuous washout: not yet.
        var t = 0.0
        while t < 3.9 {
            _ = latch.step(trustworthy: true, now: t)
            t += 0.1
        }
        XCTAssertFalse(latch.isEngaged, """
            The banner opened before the washout had held its full window. A shorter effective \
            window than declared means a fingertip shifting across the exposure line can still \
            grow the slot.
            """)
        XCTAssertTrue(latch.step(trustworthy: true, now: 4.0), """
            Four seconds of uninterrupted washout did not open the banner. Then the remedy \
            never arrives at all and the cue is back to being a two-word diagnosis whose fix is \
            the opposite of the intuitive move.
            """)
        // A one-second flicker of "not washed out" must NOT close it — that would be a resize
        // per flicker, i.e. the bug wearing the fix's clothes.
        var u = 4.1
        while u < 5.1 {
            XCTAssertTrue(latch.step(trustworthy: false, now: u), """
                The banner closed after a \(u - 4.0) s clear stretch. The release window is what \
                stops the slot bouncing; a user who has just been told to press lighter also \
                needs the sentence to survive long enough to read.
                """)
            u += 0.1
        }
        // Three seconds clear: now it may close.
        XCTAssertFalse(latch.step(trustworthy: false, now: 7.2), """
            The banner never closed after the washout cleared for longer than the release \
            window. A remedy that outlives its cause is a lying instruction.
            """)
    }

    // MARK: - claim 2 — the publisher owns the time half, and it must agree with the cue

    func testTheGateLivesOnThePublisherAndAgreesWithTheCue() throws {
        let gate = try declarationBody(of: "public var cueWarrantsFullHintOnScreen: Bool")
        XCTAssertTrue(gate.contains("brightHintLatched"), """
            `cueWarrantsFullHintOnScreen` no longer consults the washout latch, so `.tooBright` \
            is back to a two-word diagnosis on screen with its remedy in VoiceOver only.
            """)
        XCTAssertTrue(gate.contains("warrantsFullHintOnScreen"), """
            The publisher's gate no longer delegates to `PulseCue.warrantsFullHintOnScreen`. \
            `.stalled` is a fact about the STRINGS and belongs on the enum (#416); a second \
            copy of that answer here is the defect, whether or not the two agree today.
            """)
        XCTAssertTrue(gate.contains("== .tooBright"), """
            The gate no longer checks that the cue IS `.tooBright` while the latch is engaged. \
            The consumer renders `acquisitionCue.fullHint`, so latch and cue must name the same \
            sentence — without this, a latch still standing inside its release window would \
            authorise a full-height banner for whatever the cue had become, "Locked" included.
            """)
    }

    // MARK: - claim 3 — the published flag must not invalidate at 10 Hz

    /// The freeze law (10.76.41/50) in its `@Observable` form: the macro calls `withMutation`
    /// on EVERY set, equal value or not. An unconditional assignment in the publish tick would
    /// make this flag a 10 Hz invalidation source on a publisher whose observers include the
    /// header pill — i.e. it would re-create the menu-freeze this file has been fixed for twice.
    func testTheLatchedFlagIsWrittenOnlyOnAChange() throws {
        let code = try publisherCode()
        XCTAssertTrue(code.contains("if brightNow != self.brightHintLatched"), """
            The washout flag is no longer written behind a change test. `@Observable` notifies \
            on every set regardless of equality, so an unconditional write inside the 10 Hz \
            tick adds a 10 Hz invalidation to every observer of this publisher — the exact \
            shape of the two menu-freeze regressions this file already paid for.
            """)
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let decl = lines.firstIndex(where: { $0.contains("var brightHintLatched") }) else {
            throw WashoutAnchorMissing(reason: """
                `brightHintLatched` is gone from \(Self.publisher). Re-anchor this scan (#454).
                """)
        }
        // ⛔ THE DECLARATION LINE ITSELF, not "the nearest code line above it". The first draft
        // walked backwards past blank lines to find an attribute — and `SourceText.codeOnly`
        // BLANKS a doc comment while PRESERVING its lines, so that walk skipped the whole 8-line
        // comment and landed on `brightHintLatch`'s declaration, which IS `@ObservationIgnored`.
        // Red on correct code (#367), and the hand transcription is what caught it. This file's
        // style puts the attribute on the same line as the property, which is also the only
        // placement a scan can read without inventing a scope.
        XCTAssertFalse(lines[decl].contains("@ObservationIgnored"), """
            `brightHintLatched` became `@ObservationIgnored`. Then nothing invalidates when the \
            washout latches, and the banner appears only if some OTHER tracked field happens to \
            churn in the same instant — a surface that works by luck. Its siblings \
            (`stallWasRhythmless`, `acquisitionSince`) are ignored precisely because they move \
            on most ticks; this one moves at most every few seconds, which is why it is tracked.
            """)
    }

    // MARK: - claim 4 — one classification, not a private re-test of brightness

    func testTheLatchIsDrivenByTheSameCueTheScreenShows() throws {
        let code = try publisherCode()
        XCTAssertTrue(code.contains("self.brightHintLatch.step(trustworthy: self.placementCue == .tooBright"), """
            The washout latch is no longer stepped from `placementCue`. This file holds THREE \
            brightness lines that each mean "flooded" in their own words \
            (`strictLockBrightness`, `maxLockBrightness`, `isWashedOut`); a latch that re-tests \
            any of them directly is a fourth spelling, and a retune of `isWashedOut` would then \
            leave the coaching behind (#416). The stall clock two blocks up asks the same \
            classification for the same reason.
            """)
        // A floor, not an equality: the numbers are tuning and a designer may move them (#364).
        // What must never happen is a sub-second window, which is the frame-rate resize itself.
        guard let ctor = code.split(separator: "\n").first(where: { $0.contains("BioTrustLatch(engageSeconds:") })
        else {
            throw WashoutAnchorMissing(reason: """
                \(Self.publisher) no longer constructs a `BioTrustLatch` for the washout hint. \
                If the hysteresis moved, move this guard with it in the same commit (#456).
                """)
        }
        let numbers = ctor.split(whereSeparator: { !"0123456789.".contains($0) })
            .compactMap { Double($0) }
        XCTAssertEqual(numbers.count, 2, "expected two windows in: \(ctor.trimmingCharacters(in: .whitespaces))")
        XCTAssertGreaterThanOrEqual(numbers.first ?? 0, 2, """
            The engage window dropped below two seconds: \(ctor.trimmingCharacters(in: .whitespaces))
            Retuning is legitimate and this guard is a FLOOR, not a pin — but a sub-second \
            window is not a tuning choice, it is the per-frame resize the latch exists to stop.
            """)
        XCTAssertGreaterThanOrEqual(numbers.last ?? 0, 1, """
            The release window dropped below one second: \(ctor.trimmingCharacters(in: .whitespaces))
            Release is what bounds how often the slot can shrink; at zero the banner blinks out \
            on the first frame that clears the exposure line and returns four seconds later.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the latch is cleared wherever its siblings are

    /// #454's law, one field further: a per-take latch that a failed start or a `stop()` forgets
    /// is a PREVIOUS take's washout, and it would authorise a wrapping banner before this take
    /// had measured anything. `acquisitionSince` and `stallWasRhythmless` are cleared at exactly
    /// two sites; the latch must be cleared at both of them.
    func testTheLatchIsClearedAtBothSitesItsSiblingsAre() throws {
        let code = try publisherCode()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // ⛔ COUNTING `stallWasRhythmless = nil` GIVES **THREE**, NOT TWO — measured, after the
        // first draft asserted two and would have been red on correct code (#367). The third is
        // in the publish TICK, where the stall WINDOW is restarted every time the contact stops
        // being `.finding`; that is a per-frame reset, not a take boundary, and the washout latch
        // must NOT be cleared there (it would never accumulate its 4 s). So the anchor is the
        // PAIRING, not a count of the sibling: each `resetBrightHint()` call must sit directly
        // under a take-boundary clear.
        let callSites = lines.indices.filter {
            lines[$0].contains("resetBrightHint()") && !lines[$0].contains("private func")
        }
        XCTAssertEqual(callSites.count, 2, """
            The washout latch is cleared at \(callSites.count) sites, not the two take \
            boundaries (the failed-start branch and `stop()`). #454's law: per-take state that a \
            boundary forgets is a PREVIOUS take's number — here, a latch that survives would \
            authorise a wrapping banner over the next take's first seconds, before anything had \
            been measured. If a third boundary appeared, add it here in the same commit.
            """)
        // A WINDOW, NOT STRICT ADJACENCY (#364). `SourceText.codeOnly` blanks a comment but keeps
        // its line, so demanding the sibling immediately above would go red the day somebody
        // writes an explanatory line between the two — a legitimate edit, and the `stop()` site
        // already carries one. Four lines is enough to prove "same block" without forbidding
        // prose. (The first draft demanded adjacency and was red on this very tree.)
        for site in callSites {
            let window = lines[Swift.max(0, site - 4)..<site]
            XCTAssertTrue(window.contains { $0.contains("stallWasRhythmless = nil") }, """
                A `resetBrightHint()` call is no longer next to its siblings' clear: \
                \(lines[site].trimmingCharacters(in: .whitespaces))
                The three per-take anchors (`acquisitionSince`, `stallWasRhythmless`, the \
                washout latch) are only ever reset as a SET. Separating them is how one of them \
                gets forgotten at the next boundary somebody adds.
                """)
        }
    }

    // MARK: - source access

    private struct WashoutAnchorMissing: Error { let reason: String }

    private func publisherCode() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(Self.publisher)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WashoutAnchorMissing(reason: """
                \(Self.publisher) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// The brace-matched body following `key` — never a line window (#408).
    private func declarationBody(of key: String) throws -> String {
        let text = try publisherCode()
        guard let start = text.range(of: key) else {
            throw WashoutAnchorMissing(reason: """
                \(Self.publisher) no longer declares `\(key)`. Re-anchor this scan (#454).
                """)
        }
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw WashoutAnchorMissing(reason: "no opening brace after `\(key)`")
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
        throw WashoutAnchorMissing(reason: "unbalanced braces after `\(key)` in \(Self.publisher)")
    }
}
