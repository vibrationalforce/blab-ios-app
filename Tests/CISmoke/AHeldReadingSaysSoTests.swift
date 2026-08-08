// AHeldReadingSaysSoTests.swift
// Echoel — #503. A frozen measurement stops reading as a live one.
//
// #497 made an UNMEASURED channel hand the engine its declared neutral instead of an extreme.
// #498 put the pair (value, measured) on screen so a neutral 0.50 could not be misread as a body
// sitting mid-scale. Neither of them can separate a LIVE body from a frame that ARRIVED ONCE and
// stopped — and that is not a hypothetical: `EngineBus.latestBio` is only ever ASSIGNED. Nothing
// clears it — not `stop()`, not a lost pulse; its single writer is the `publish(bio:)` sink. And
// `isMeasured` is a property of the FRAME, never of its age. So a frame from forty minutes ago
// reported "measured" forever, under a header reading "Always on — body → timbre".
//
// That is the exact ambiguity #497/#498 removed one level down, reintroduced by the surface that
// removed it.
//
// ⭐ IT MARKS RATHER THAN BLANKS, and that is the load-bearing design decision. The sound
// producers poll `latestBio` and dedupe on `timestamp`, so a frozen source does NOT zero the
// timbre — it PARKS it at the last body and leaves it there. (⛔ This said "the FOUR sound
// producers". Four voices SUBSCRIBE; `PolySynthVoice.applyLatestIfFresh` returns at
// `guard bioModulationEnabled` before it reads the bus, and only `polyVoice` has a reachable
// writer for that flag, so TWO reach the frame. The parking argument never depended on the
// count — which is why the wrong number rode along unchallenged.) Blanking the number would claim the
// engine dropped the channel; it did not. The honest reading is "this is what the engine has, and
// it is no longer arriving", so the value stays, the bar stays (dimmed), and one word is added.
// `testTheHeldValueIsTheSameNumber` is what keeps a later "held means blank it" from landing.
//
// ⭐ THE THRESHOLD IS ASKED, NOT COINED (#416/#426). `isHeld` is the exact negation of the two
// comparisons in `EngineBus.usableBio()` against `frame.source.freshnessWindow` — the same line
// the COMPOSER uses to decide whether a take has a body at all. So a held row is a state that
// prints `body=0` in the generate breadcrumb (#500), and retuning a source's window moves both
// together instead of leaving a screen behind. (⛔ This said "precisely the state", which is an
// equivalence and false in one direction: `body=0` is also true with no frame at all and with a
// stale frame whose channels were never measured, and neither shows "held". Held ⇒ `body=0`; the
// converse is not.) `testTheThresholdIsTheSourcesOwnWindow`
// is the counterweight against the obvious later "just use 5 seconds": at age 10 s a camera frame
// is held and a HealthKit frame is NOT, because 6 s and 90 s are different decisions about
// different sensors and one number would erase both.
//
// ⚠️ THE LIMIT FIRST. The BEHAVIOUR half is real end to end — `AlwaysOnBioChannel`,
// `AlwaysOnBioReading` and `BioSampleFrame` are `public` Foundation-only value types, so every
// case below drives the shipped decision. The MOUNT/COPY half is a SOURCE SCAN: `AlwaysOnBioRow`
// is `private` inside a SwiftUI view this bundle cannot instantiate. That the row renders, that
// the tick actually fires once a second on device, that a dimmed bar reads as "parked" at a
// glance, and that VoiceOver's held sentence is useful spoken aloud are FOUR device checks and
// all four are open.
//
// ⚠️ AND THE DEFECT #500 IS ABOUT IS ONLY HALF CLOSED BY THIS. A take composed while every channel
// was held prints `body=0` and sounds like the patch — that is the rPPG ACQUISITION problem
// (#304/#410/#415) and it is device-gated. This slice does not fix acquisition; it stops the one
// surface that claims "always on" from asserting liveness it cannot have.
//
// ⚠️ HONEST GRADING against the pre-#503 tree, and it is the #464 situation said plainly: every
// behaviour case names `AlwaysOnBioChannel.reading(in:now:)` / `AlwaysOnBioReading`, neither of
// which exists there, so the bundle does not compile against it and NO assertion has a verdict.
// Hand-transcribed instead (Python transcription of `SourceText.codeOnly`, run against
// `git show HEAD:` and the working tree rather than reasoned about):
//   · The FIVE source needles are all red on HEAD for their NAMED reason, and none of them is red
//     by anchor absence (#486): `private struct AlwaysOnBioRow` is present on BOTH trees, so the
//     bracket passes and the failures are findings about the row, not about a missing file. (That
//     bracket guards the two ROW scans; the footer scan has no anchor and needs none — it is a
//     positive `contains` on a string, so it cannot go green on nothing.)
//   · The EIGHT behaviour cases drive a type this same commit creates. They could never have been
//     red, and booking them as regressions would be the #433 defect in the flattering direction.
//     Their value is FORWARD, and three are labelled COUNTERWEIGHT: they exist to make the obvious
//     later "cleanups" fail — blanking a held value, coining a single staleness number, or
//     letting "held" appear on a channel that was never measured.
//
// ⚠️ `SourceText.codeOnly` IS PROPHYLACTIC HERE, and that is MEASURED rather than assumed — #484
// and #485 each had to retract the stronger claim once and #486 twice, so it is not asserted for
// flavour. Stripped vs raw differ on **0 of 5** needle verdicts: all five are positive `contains`,
// and although `no longer arriving` does appear twice raw (once in the VoiceOver string, once in
// the doc comment on `accessibilityText(_:)` — NOT in the footer's rationale, which does not carry
// the phrase at all), a positive scan passes either way. It stays because #453 created ONE definition of
// "code, not prose" for the whole blocking bundle, and a private exception is exactly the defect
// that slice removed — and it stops being prophylactic the moment someone writes a retraction here
// quoting a form this file forbids, which is how #486 and #491 became load-bearing.

import XCTest
@testable import Echoelmusic

final class AHeldReadingSaysSoTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"

    /// Reads a repo source file as CODE, never prose (#453). Skips on the DIRECTORY, never on the
    /// individual file: a `fileExists` bracket around each read turns a deletion — the exact
    /// catastrophe this bundle stands against — into a green skip (#475).
    private func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "Sources/ not present in this checkout")
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "\(relative) is empty — the scan below would pass on nothing")
        return SourceText.codeOnly(text)
    }

    /// The text of one declaration: from `anchor` to the matching close of its FIRST `{`.
    ///
    /// Brace-counted rather than line-counted, so an inserted line cannot silently truncate the
    /// slice — and it THROWS rather than returning "" when the anchor is missing, because a scan
    /// that passes on an empty slice is the #367 defect this helper exists to remove. The thrown
    /// description is the failure a reader sees, so it says what to fix.
    ///
    /// ⚠️ It counts braces in whatever it is handed. Comments are already gone (the caller passes
    /// `SourceText.codeOnly` output, #453), but a `{` inside a STRING literal would still be
    /// counted; there is none in the scanned declaration today, and a scan that started spanning
    /// one would truncate loudly rather than silently, because the slice would end early and the
    /// needles below would go red.
    private func block(startingAt anchor: String, in source: String) throws -> String {
        guard let start = source.range(of: anchor) else {
            throw ScanFailure("anchor '\(anchor)' is missing — the always-on row is gone or "
                              + "renamed. Fix the anchor, not the assertions below.")
        }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else {
            throw ScanFailure("anchor '\(anchor)' has no opening brace — the scan has no body "
                              + "to bound and would otherwise search the whole file")
        }
        var depth = 0
        var i = open
        while i < source.endIndex {
            if source[i] == "{" { depth += 1 }
            if source[i] == "}" {
                depth -= 1
                if depth == 0 { return String(source[start.lowerBound...i]) }
            }
            i = source.index(after: i)
        }
        throw ScanFailure("anchor '\(anchor)' never closes — unbalanced braces in the scanned text")
    }

    private struct ScanFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// A fully measured frame on `source`, stamped so that `now = 1000` sees it as `age` old.
    private func frame(age: TimeInterval, source: BioSource, now: TimeInterval = 1000) -> BioSampleFrame {
        BioSampleFrame(timestamp: now - age, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 12, breathPhase: 0.25,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    /// A frame that carries NO channel at all, stamped the same way.
    private func emptyFrame(age: TimeInterval, now: TimeInterval = 1000) -> BioSampleFrame {
        BioSampleFrame(timestamp: now - age, heartRateBPM: 0, hrvNormalized: 0,
                       breathRate: 0, breathPhase: 0,
                       coherence: 0, motionEnergy: 0, source: .cameraPPG)
    }

    // MARK: - Behaviour: arriving vs. parked

    func testAFreshMeasurementIsNotHeld() {
        let f = frame(age: 1, source: .cameraPPG)
        for channel in AlwaysOnBioChannel.allCases {
            let r = channel.reading(in: f, now: 1000)
            XCTAssertTrue(r.isMeasured, "\(channel.name) should be measured on a full frame")
            XCTAssertFalse(r.isHeld,
                           "\(channel.name) is 1 s old on a 6 s window — calling that held would "
                           + "make the mark meaningless")
        }
    }

    func testTheSameFrameBecomesHeldOnceItAgesOut() {
        let f = frame(age: 10, source: .cameraPPG)
        for channel in AlwaysOnBioChannel.allCases {
            let r = channel.reading(in: f, now: 1000)
            XCTAssertTrue(r.isMeasured,
                          "\(channel.name) still carries a measurement — age does not unmeasure it")
            XCTAssertTrue(r.isHeld,
                          "\(channel.name) is 10 s past a 6 s window; `usableBio()` already rejects "
                          + "this frame, so the readout must stop asserting it is arriving")
        }
    }

    /// COUNTERWEIGHT. The obvious later simplification is "held means we have nothing, blank it".
    /// The engine is still being handed this number every poll — blanking would claim a drop that
    /// did not happen. The value must survive the mark byte for byte.
    func testTheHeldValueIsTheSameNumber() {
        let fresh = frame(age: 1, source: .cameraPPG)
        let stale = frame(age: 10, source: .cameraPPG)
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertEqual(channel.reading(in: stale, now: 1000).value,
                           channel.reading(in: fresh, now: 1000).value,
                           accuracy: 0,
                           "\(channel.name): holding must MARK the number, never change it")
            XCTAssertEqual(channel.reading(in: stale, now: 1000).value,
                           channel.value(in: stale), accuracy: 0,
                           "\(channel.name): the shown value is the one the engine receives")
        }
    }

    /// COUNTERWEIGHT, and the sharpest one: the threshold is the SOURCE's own window, not a number
    /// this file coined. At the same age a camera frame is expired and a wrist frame is not —
    /// 6 s and 90 s are two different decisions about two different sensors, and collapsing them
    /// would silently mark every HealthKit reading as dead within seconds of arriving.
    func testTheThresholdIsTheSourcesOwnWindow() {
        let age: TimeInterval = 10
        XCTAssertTrue(AlwaysOnBioChannel.heartRate.reading(in: frame(age: age, source: .cameraPPG),
                                                           now: 1000).isHeld,
                      "camera window is 6 s — 10 s is past it")
        XCTAssertFalse(AlwaysOnBioChannel.heartRate.reading(in: frame(age: age, source: .healthKit),
                                                            now: 1000).isHeld,
                       "HealthKit window is 90 s — a 10 s old wrist reading is still arriving")
        XCTAssertTrue(AlwaysOnBioChannel.heartRate.reading(in: frame(age: 91, source: .healthKit),
                                                           now: 1000).isHeld,
                      "…and it does expire, at ITS window, not at the camera's")
    }

    /// The boundary is inclusive on both sides, exactly as `usableBio()` writes it: `age <= window`
    /// is usable. Pinning it stops a later "off by one second, tighten it" from moving the readout
    /// away from the composer's own answer.
    func testTheBoundaryMatchesUsableBioExactly() {
        let atWindow = frame(age: 6, source: .cameraPPG)
        let pastWindow = frame(age: 6.001, source: .cameraPPG)
        XCTAssertFalse(AlwaysOnBioChannel.coherence.reading(in: atWindow, now: 1000).isHeld,
                       "age == window is USABLE in `usableBio()`; the row must agree")
        XCTAssertTrue(AlwaysOnBioChannel.coherence.reading(in: pastWindow, now: 1000).isHeld)
    }

    /// COUNTERWEIGHT. "Held" only ever qualifies a measurement. An unmeasured channel already shows
    /// "—"; calling that held would add a word without adding a fact, and would read as though the
    /// body had once sent something it never did.
    func testAnUnmeasuredChannelIsNeverHeld() {
        for age in [0, 1, 10, 100, 100_000] as [TimeInterval] {
            let f = emptyFrame(age: age)
            for channel in AlwaysOnBioChannel.allCases {
                let r = channel.reading(in: f, now: 1000)
                XCTAssertFalse(r.isMeasured, "\(channel.name) carries nothing at age \(age)")
                XCTAssertFalse(r.isHeld,
                               "\(channel.name): held must imply measured — at age \(age) it did not")
                XCTAssertEqual(r.value, 0.5, accuracy: 1e-6,
                               "\(channel.name) must still hand the engine its declared neutral")
            }
        }
    }

    func testNoFrameAtAllIsTheNeutralAndNotHeld() {
        for channel in AlwaysOnBioChannel.allCases {
            let r = channel.reading(in: nil, now: 1000)
            XCTAssertEqual(r.value, 0.5, accuracy: 1e-6)
            XCTAssertFalse(r.isMeasured)
            XCTAssertFalse(r.isHeld, "nothing has ever arrived — there is no measurement to hold")
        }
    }

    /// A non-finite stamp fails BOTH comparisons, and a stamp far in the future fails the −1 s skew
    /// tolerance. Both therefore read as HELD — the direction that claims LESS liveness, and the
    /// same answer `usableBio()` gives the composer for the same frame.
    func testANonFiniteOrFutureStampReadsAsHeld() {
        let nanStamp = BioSampleFrame(timestamp: .nan, heartRateBPM: 60, hrvNormalized: 0.4,
                                      breathRate: 12, breathPhase: 0.25,
                                      coherence: 0.7, motionEnergy: 0, source: .cameraPPG)
        let future = frame(age: -10, source: .cameraPPG)
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertTrue(channel.reading(in: nanStamp, now: 1000).isHeld,
                          "\(channel.name): a NaN age must not be read as fresh")
            XCTAssertTrue(channel.reading(in: future, now: 1000).isHeld,
                          "\(channel.name): 10 s in the future is past the 1 s skew tolerance, and "
                          + "the composer is already treating that frame as no body")
        }
    }

    // MARK: - Source: the row actually shows it, and keeps ticking

    /// The mount AND the clock in one assertion, deliberately — and both needles are searched
    /// INSIDE the row's own braces, never file-wide (#367).
    ///
    /// ⛔ THE FILE-WIDE FORM COULD NOT FAIL FOR THE LAW THIS TEST IS NAMED AFTER. The source
    /// comment on `AlwaysOnBioRow` writes that law: the ticker MUST STAY IN THE ROW rather than
    /// wrap the `ForEach` in `AlwaysOnBioView`, because the rows are `Section` children and one
    /// `TimelineView` around all four would put one container where four list rows belong. Take
    /// exactly that "one ticker instead of four" simplification — `frame` is already a local
    /// there — and BOTH needles still match verbatim, all three assertions stay green, and a test
    /// called `testTheRowTicksAndReadsTheWallClock` certifies a row that no longer ticks.
    ///
    /// ⛔ AND THE CLOCK JUSTIFICATION WAS FALSE, in three artifacts at once (this doc, the
    /// assertion message below, and the source comment it describes). It read: "a `TimelineView`
    /// that took its time from the context date would measure age on a DIFFERENT clock than
    /// `usableBio()` — the exact two-clock mismatch #434 paid for one file over." `EngineBus`
    /// states verbatim that its stamps are "`CFAbsoluteTime` … i.e. `CFAbsoluteTimeGetCurrent()` /
    /// `Date.timeIntervalSinceReferenceDate`", so a `Date` from the schedule context is the SAME
    /// clock and the SAME epoch; and #434's mismatch was `frame.timestamp` against the wall clock,
    /// a different SOURCE of time. The DECISION survives on a reason the first version did not
    /// give: a `TimelineSchedule` context date is the SCHEDULED instant, not the redraw instant,
    /// and this body is rebuilt on every `latestBio` publish — each rebuild mints a fresh
    /// `.periodic` with a new phase, so the context date can lag the draw.
    func testTheRowTicksAndReadsTheWallClock() throws {
        let src = try block(startingAt: "private struct AlwaysOnBioRow", in: code(Self.fxView))
        XCTAssertTrue(src.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "the row must tick. `isHeld` flips on the passage of TIME, and the event that "
                      + "makes it true — a source that stopped publishing — is by definition the "
                      + "event that stops invalidating this body. Without a tick the row freezes at "
                      + "the instant the frame arrived and asserts liveness forever, which is worse "
                      + "than the state #500 is about")
        XCTAssertTrue(src.contains("channel.reading(in: frame, now: CFAbsoluteTimeGetCurrent())"),
                      "age must be read when the row DRAWS, not when the schedule entry was minted. "
                      + "`TimelineSchedule` hands the closure the SCHEDULED instant, and this body "
                      + "is rebuilt on every `latestBio` publish — each rebuild starts a fresh "
                      + "`.periodic` with a new phase, so the context date can lag the draw")
    }

    /// Paired with the mount on purpose (#343): a scan that only proved the tick exists would stay
    /// green on a tree that kept the ticker and dropped every trace of the held state. Scoped to
    /// the row's braces for the same reason as the test above.
    func testTheRowRendersTheHeldState() throws {
        let src = try block(startingAt: "private struct AlwaysOnBioRow", in: code(Self.fxView))
        XCTAssertTrue(src.contains("reading.isHeld ? 0.35 : 1"),
                      "the bar must stay DRAWN and be dimmed when held — the engine really is still "
                      + "being handed this value, so removing the bar would claim a drop that did "
                      + "not happen, and leaving it at full opacity would claim a moving body")
        XCTAssertTrue(src.contains("no longer arriving"),
                      "VoiceOver must get the third fact too, and its subject must stay the SIGNAL "
                      + "rather than the body (#484's compliance edge)")
    }

    func testTheFooterExplainsHeldSeparatelyFromNoReading() throws {
        let src = try code(Self.fxView)
        XCTAssertTrue(src.contains("your body has stopped sending it"),
                      "the footer must distinguish the two states it now shows: 'no reading' is a "
                      + "frame that never carried the channel, 'held' is one that did and stopped")
    }
}
