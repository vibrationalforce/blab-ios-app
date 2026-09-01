// TheInputEdgeFollowsTheHardwareFormatTests.swift
// Echoel — #954. Blocking bundle. SOURCE-TEXT SCAN throughout (`Tests/CISmoke/CLAUDE.md`
// §1): every member this pins is inside a `@MainActor` method on `AudioEngine` that no test
// bundle can drive without an audio device, so the honest claim is where the decision sits,
// never that it behaves.
//
// ⭐ THE DEFECT IS DEVICE-MEASURED, NOT INFERRED. Founder log v10.79.433:
//
//     monitor: on 1/5: stopping engine + claiming record route
//     route: claim inputMonitoring → holders inputMonitoring
//     session: raise 1/2 — setCategory(.playAndRecord)
//     session: raise 2/2 — setActive
//     monitor: on: touching the input node + reading its format
//     monitor: on 2/5 … on 3/5 … on 4/5: restarting engine with the monitor chain
//     CRASH exception: required condition is false: false == isInputConnToConverter
//
// The lifecycle ladder (#859–#862b) did exactly the job it was built for: it NAMED the dying
// op. The abort is inside the `start()` at rung 4/5, and the assert is named after the input
// node being connected to a converter.
//
// ⭐ WHAT THE LOG PROVES BY ABSENCE, and it is the whole reason this slice exists: NEITHER
// #823 line appears. No "input format from session fallback", no "input format unusable".
// So the node handed back a PLAUSIBLE, NON-ZERO format and the old guard had nothing to
// catch. #823 closed the placeholder case; this is the placeholder's quieter sibling — a
// stale but well-formed format, read one millisecond after `setActive` (both stamps are
// …251.430) and forced onto the input edge 7 ms before `start()` rebuilt the I/O unit
// against the record route.
//
// ⭐ WHY THE SESSION IS THE AUTHORITY FOR THE RATE: `start()` rebuilds the I/O unit from the
// SESSION, so its sample rate is not a second opinion about the hardware — it is what
// `start()` will use. #823 already trusted it for the zero case; #954 widens the SAME trust
// to disagreement. When node and session agree (the ordinary path) the connect format is
// bit-identical to before.
//
// ⚠️ AND THE CHANNEL COUNT IS DELIBERATELY NOT PART OF IT — the half of this slice that could
// have made things WORSE, named here because a later reader will otherwise "complete" it.
// `session.inputNumberOfChannels` is clamped to 1...2 at the substitution site, and a route
// can legitimately have the node reporting mono while the session offers two. Substituting
// there would force a stereo edge onto a mono input and MANUFACTURE the converter this slice
// removes, on hardware that was healthy. So the disagreement test is rate-only, and the
// substitution KEEPS the node's own channel count — the node is the only party that has
// looked at the input scope. A fix that can introduce the crash it prevents is not a fix
// (#364), and there is no device here to tell the two cases apart. Claim 4 pins this by
// anchoring on the leading `&&`, so a channel term cannot quietly come back.
//
// ⚠️ HONEST GRADING (§3). **9 assertions.** Against `7e33d36`, where the file COMPILES (it
// names no new symbol — every needle is a string):
//   · **ONE FINDING, reported by FOUR assertions (#486)** — claims 1 (×2), 4 and 6 all go
//     red there for the single absence of the #954 decision. They are **FORWARD** guards:
//     they pin text this same commit creates, so none of them could ever have caught a
//     pre-existing defect, and booking four of them as regression catches would be the
//     flattering-direction defect §3 names.
//   · **FIVE COUNTERWEIGHTS** — claims 2 (×2), 3 and 5 (×2) are green on BOTH trees, and
//     they are the content (#343): they pin that the widened branch still cannot invent a
//     format, that #823's zero case survived the edit, and that the input edge is still
//     connected exactly once with the DECIDED format rather than a fresh node read.
//   · 0 red on the worktree, driven by transcription (§0 — there is no local toolchain).
//
// ⚠️ STRIPPER (§2): `SourceText.codeOnly` is **PROPHYLACTIC — 0 of 9 verdicts flip.** Measured
// raw vs. stripped on both trees. It is not decorative all the same: the doc block around the
// patched region quotes `nodeDisagreesWithHardware` and `#954` in prose, so a future comment
// edit is exactly how a raw scan would start reading its own explanation as the code.
//
// ⚠️ WHAT THIS GUARD DOES NOT CLAIM. It cannot prove the crash is fixed — that needs a device
// run, and the fix is labelled HYPOTHESIS #4 at its site for that reason. What it pins is
// that the DECISION stays where the log can settle it: the `on 3/5` rung now prints the
// format it forces onto the edge beside the session's view, so the next founder log
// discriminates a matching edge from a mismatched one either way. NEEDS-FOUNDER-VERIFY.
//
// ⚠️ NOT A DUPLICATE OF `TheEngineLifecycleSpeaksInTheDiagLogTests` (#416). That file pins
// that the five `on N/5` rungs EXIST and that 4/5 precedes its `start()`. This one pins what
// the input-format decision is and what rung 3/5 SAYS. They met once already, usefully: this
// slice's own first draft rewrote rung 3/5 as a `"""` block, which broke
// `scripts/diag-ladder.py --source` ("'on' 1..5 — 4/5 steps, MISSING STEP(S): [3]") — and
// the sibling's `occurrences(of: "logMonitorOutcome(\"on 3/5") == 1` would have gone red on
// it too. No claim for that is added here; it is covered, and a second spelling would be the
// thing §2 forbids.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheInputEdgeFollowsTheHardwareFormatTests: XCTestCase {

    private static let enginePath = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    private func engineCode() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let text = try String(contentsOf: root.appendingPathComponent(Self.enginePath),
                              encoding: .utf8)
        return SourceText.codeOnly(text)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// claim 1 (FORWARD, 2 assertions) — **THE FIX ITSELF.** The input-connect format is
    /// decided against the hardware the session reports, not only against a zero node.
    func testTheFormatDecisionCoversDisagreementAndNotOnlyZero() throws {
        let code = try engineCode()
        XCTAssertGreaterThan(occurrences(of: "nodeDisagreesWithHardware", in: code), 0, """
            The input-monitoring path decides its connect format from the node alone again. \
            Founder log v10.79.433 aborted in the `on 4/5` start() with \
            `false == isInputConnToConverter` and carried NEITHER #823 line — so the node's \
            format was plausible and non-zero and simply did not match what start() then \
            rebuilt the I/O unit to. `start()` reads the SESSION; a format that disagrees \
            with it is a converter on the input edge, which is the assert's own name.
            """)
        XCTAssertGreaterThan(
            occurrences(of: "if nodeFormatUnusable || nodeDisagreesWithHardware {", in: code), 0, """
            The disagreement flag exists but no longer opens the session-fallback branch. \
            A computed flag nothing branches on is the #431/#440 shape: it appears in no \
            diff and changes nothing. Both cases must reach the substitution.
            """)
    }

    /// claim 2 (COUNTERWEIGHT, 2 assertions) — the widened branch must still be unable to
    /// invent a format. #823's own words: never an invented constant; a connect format that
    /// disagrees with hardware raises an ObjC exception no Swift `catch` sees. Widening WHEN
    /// the substitution happens must not widen WHAT it may substitute.
    func testTheSubstitutionStillOnlyUsesWhatTheSessionReports() throws {
        let code = try engineCode()
        XCTAssertGreaterThan(occurrences(of: "session.isInputAvailable", in: code), 0, """
            The session-fallback no longer checks that an input exists at all. With the \
            branch widened to disagreement, an unavailable input would now substitute a \
            format for a device that is not there — strictly worse than the node's own read.
            """)
        XCTAssertGreaterThan(occurrences(of: "sessionRate > 0", in: code), 0, """
            The session rate is no longer checked before it is used as the connect format. \
            A 0 Hz session would build an unusable format and hand it to the input edge.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — #823's zero case must survive the edit. The v10.79.420 log
    /// (four identical "input format unusable" lines over ~10 s) is what that guard was
    /// written for; a slice that replaces it with a disagreement test would re-open it.
    func testTheZeroFormatCaseSurvives() throws {
        let code = try engineCode()
        XCTAssertGreaterThan(
            occurrences(of: "inFmt.sampleRate <= 0 || inFmt.channelCount == 0", in: code), 0, """
            #823's placeholder test is gone. A node that reports 0 Hz / 0 ch right after the \
            claim would now be compared against the session for DISAGREEMENT instead of \
            being recognised as unusable — a different message, a different exit, and the \
            v10.79.420 shape back.
            """)
    }

    /// claim 4 (FORWARD) — the disagreement test is a RATE TOLERANCE, and nothing else.
    /// Two properties in one claim, both about not making things worse. (a) A tolerance, not
    /// equality: a hardware rate arrives as a `Double` and can round (44100.000000000007), so
    /// equality would substitute a format on healthy hardware (#364). (b) The needle carries
    /// the leading `&&`, which pins that the rate test is the WHOLE condition — a channel-count
    /// term must not come back. `session.inputNumberOfChannels` is clamped to 1...2 and a route
    /// can legitimately have a mono node under a two-channel session; substituting there would
    /// force a stereo edge onto a mono input and MANUFACTURE the converter this slice removes,
    /// on hardware that was fine. A fix that can introduce the crash it prevents is not a fix,
    /// and there is no device here to tell the two cases apart.
    func testTheRateComparisonHasATolerance() throws {
        let code = try engineCode()
        XCTAssertGreaterThan(occurrences(of: "&& abs(inFmt.sampleRate - hwRate) > 1", in: code), 0, """
            The node/session rate comparison is no longer a tolerance. Exact equality on two \
            `Double` sample rates fires on rounding alone, so the healthy path would start \
            substituting a format it did not need to — the failure direction #364 names, in \
            the one method this repo has already crashed in five times.
            """)
    }

    /// claim 5 (COUNTERWEIGHT, 2 assertions) — one input edge, connected with the DECIDED
    /// format. The whole decision above is worthless if a later line re-reads the node.
    func testTheInputEdgeIsConnectedOnceWithTheDecidedFormat() throws {
        let code = try engineCode()
        XCTAssertEqual(
            occurrences(of: "masterEngine.connect(input, to: notchEQ, format: inFmt)", in: code), 1, """
            The input edge is no longer connected exactly once with the decided format. \
            Either a second connect appeared on this node — every extra stop-rewire-start \
            cycle on the input-fed chain is a fresh chance at the #858 abort — or the connect \
            now uses something other than `inFmt`, which discards the decision above it.
            """)
        XCTAssertEqual(occurrences(of: "input.inputFormat(forBus: 0)", in: code), 1, """
            The input node's raw format is read more than once on this path. The decision \
            must happen ONCE and be carried in `inFmt`; a second raw read re-introduces \
            exactly the stale value the founder log ended on.
            """)
    }

    /// claim 6 (FORWARD) — rung 3/5 must NAME the format it forces onto the edge. Until #954
    /// the ON path printed a format only on its failure exits, so a log that CRASHED at 4/5
    /// carried no way to tell a matching edge from a mismatched one — precisely the question
    /// the abort asks. This is what makes the next device run decisive either way.
    func testTheConnectRungNamesTheFormatItForces() throws {
        let code = try engineCode()
        let rung = code.split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.contains("logMonitorOutcome(\"on 3/5") }
        guard let rung else {
            XCTFail("""
                the `on 3/5` rung is gone — re-anchor (§4). Its existence is pinned by \
                `TheEngineLifecycleSpeaksInTheDiagLogTests.testTheMonitorOnPathIsStaged`; \
                this claim is only about what it SAYS.
                """)
            return
        }
        XCTAssertTrue(rung.contains("edgeSummary"), """
            Rung `on 3/5` no longer carries the format it is about to force onto the input \
            edge. A founder log that aborts in the 4/5 start() then says only THAT the edge \
            was made, never with what — and the mismatch is the whole question. Keep the \
            summary on the rung's own line: a multi-line literal hides the rung from \
            `scripts/diag-ladder.py --source`, which reads a healthy run as a death at 3.
            """)
    }
}
