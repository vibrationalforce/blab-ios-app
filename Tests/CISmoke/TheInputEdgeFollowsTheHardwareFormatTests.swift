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
// ⭐ WHY THE SESSION IS THE BETTER SOURCE FOR THE RATE — a FRESHER PROXY, not an authority.
// ⛔ #954b: the first draft of this paragraph said "WHY THE SESSION IS THE AUTHORITY … which
// makes this structural rather than a fourth guess", and it sat twenty lines above the source
// comment labelling itself HYPOTHESIS #4. Both cannot be right and the source one is correct
// (#425 — a slice must not carry a claim and its own refutation). What `start()` uses is the
// ROUTE's HAL format at start time; a `session.sampleRate` read 7 ms earlier is merely closer
// to it than the node's cached value, and on a Bluetooth route still negotiating it can be
// mid-flight itself. **This is a cheap, well-instrumented, low-regression GUESS**, and the
// whole rhetorical weight of the old wording rested on a word the code never claimed. What is
// true: the window narrows, the ordinary path is bit-identical, and the rung below makes the
// next device log decisive either way.
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
// ⚠️ HONEST GRADING (§3). **11 assertions** (#954b added two to claim 4; the count was 9 and
// is written out rather than looped over, because a loop hides its own arithmetic and has
// cost a grading in this bundle three times). Against `68b301e`, where the file COMPILES —
// it names no new symbol, every needle is a string:
//   · **SIX assertions RED there, for ONE decision that is absent** — claims 1 (×2), 4 (×3)
//     and 6. They are **FORWARD** guards: they pin text the #954/#954b commits create, so
//     none could ever have caught a pre-existing defect, and booking them as regression
//     catches would be the flattering-direction defect §3 names. (#486 says one absence
//     reported N times is ONE finding; calling it one here is the conservative reading —
//     three distinct identifiers at three sites are arguably three absences.)
//   · **FIVE COUNTERWEIGHTS** — claims 2 (×2), 3 and 5 (×2) are green on BOTH trees, and
//     they are the content (#343): they pin that the widened branch still cannot invent a
//     format, that #823's zero case survived the edit, and that the input edge is still
//     connected exactly once with the DECIDED format rather than a fresh node read.
//   · 0 red on the worktree, driven by transcription (§0 — there is no local toolchain).
//
// ⚠️ AND THAT PARAGRAPH GRADES #954, WHOSE PARENT IS `7e33d36`. **This file now ships in TWO
// commits, so #954b needs its OWN block or it is the stale-epoch defect** that
// `TheLawFileStaysUnderItsCeilingTests` records twice (#707: "the block is required to
// describe THE parent of the commit that ships it, and a stale one is worse than none").
// **Against #954b's parent `68b301e`: 0 red, 11 COUNTERWEIGHTS.** That is the honest and
// unflattering reading — #954b changes no behaviour the guard can see. What it buys is that
// three assertions stop being able to pass for the wrong reason: claim 2a was anchored on a
// bare `session.isInputAvailable`, which also occurs inside a failure-exit MESSAGE string
// that the stripper preserves; claim 4's channel property was pinned by a leading `&&` that
// an appended `|| inFmt.channelCount != …` would have satisfied. Both were green then and are
// green now — the difference is what they would do on a tree that broke them.
//
// ⚠️ EPOCH THREE — #958b/#959, and the file now ships in FOUR commits, so this block grades
// its OWN parents rather than letting the paragraphs above read as current. **16 assertion
// SITES** today, not the 11 the #954 block counts (Python, first token `XCTAssert`/`XCTFail`;
// written out, not looped, because a loop hides its arithmetic and has cost a grading here).
//
// **#958b (parent `9fac52f`):** the raw-`inputFormat` pin went 1 → 2 at #958 and BACK to 1,
// because the ARGUMENT for two was itself the defect — #958 called its post-grant node re-read
// "the only place a fresh number can legitimately appear", and it is the one place a fresh
// number CANNOT appear (#823: the node holds its placeholder until `start()`). That claim is
// RED on `9fac52f` and green on both sides of it. Its doc now names the ONE sanctioned second
// read — after `masterEngine.prepare()`, HYPOTHESIS #5 — so building that is a COUNT to raise,
// never a law to route around (#364).
//
// **#959 (parent `46b9013`), driven by transcription (§0):**
//   · **THREE assertions RED on the parent, all genuine regressions**: the output-scope count
//     (1 vs. the pinned 2), the `nodeBusNow` binding (absent), and the shape check that it is
//     consumed by the rung's own log line (vacuously absent with it).
//   · **0 red on the worktree.**
//   · The count claim alone would have been a WEAK guard, and saying why is the point: a bare
//     `== 2` cannot tell a DIAGNOSTIC read from a second DECISION, so the extra count could be
//     spent on a silent `connect(…, format: input.outputFormat(forBus: 0))` and the pin would
//     wave it through. The shape claim is what makes the number mean the law.
//
// ⚠️ STRIPPER (§2): `SourceText.codeOnly` is **PROPHYLACTIC — 0 of 9 verdicts flip.** Measured
// raw vs. stripped on both trees. ⚠️ That "9" is the #954-epoch denominator and is left as
// written: re-measuring 16 needles raw-vs-stripped is a claim I have not made, and quietly
// widening a measured figure to cover assertions it never covered is the defect this file
// keeps recording. The stripper's role has not changed.
// ⛔ #954b — THE REASON THE FIRST DRAFT GAVE FOR KEEPING IT WAS FALSE. It said the doc block
// "quotes `nodeDisagreesWithHardware` … in prose". Measured: that identifier occurs exactly
// TWICE in `AudioEngine.swift` and both are CODE. `#954` does occur in prose, but it is not a
// needle in any of the nine assertions. The VERDICT was right and the JUSTIFICATION invented —
// the worse half of the pair, because this repo's own law is that a note with a false
// justification is worse than none: the next session cannot refute it. What is actually true:
// no needle here occurs in prose today, and the stripper is insurance against a future comment
// that quotes one — which is exactly what these doc blocks keep doing.
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
        // ⛔ #954b — THE FIRST NEEDLE HERE WAS THE BARE `session.isInputAvailable` AND IT WAS
        // THE #367 MIRROR: that identifier occurs TWICE in `AudioEngine.swift`, once in this
        // guard and once inside the #628/#823 failure-exit MESSAGE, which `SourceText.codeOnly`
        // preserves because it is a string literal. Delete the guard and the assertion stays
        // green at count 1 while its message says the check is gone. Anchored on the whole
        // condition instead, which occurs once and fails for the reason it names.
        XCTAssertGreaterThan(
            occurrences(of: "sessionRate > 0, session.isInputAvailable,", in: code), 0, """
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

    /// claim 4 (FORWARD, 3 assertions) — the disagreement test is a RATE TOLERANCE, and
    /// **nothing else**. Two properties, both about not making things worse.
    ///
    /// (a) A TOLERANCE, not equality. Comparing two `Double`s that crossed a framework
    /// boundary with `==` is a latent trap, and anything a converter would care about is
    /// orders of magnitude larger than 1 Hz. (⛔ #954b: the first draft justified this with
    /// "a hardware rate can round (44100.000000000007)" — speculative; HAL rates come back
    /// exact. The tolerance is right anyway, so it is stated as DEFENSIVE rather than as a
    /// measured phenomenon.)
    ///
    /// (b) The rate test is the WHOLE condition — no channel-count term may come back.
    /// `session.inputNumberOfChannels` is clamped to 1...2 at the substitution site, and a
    /// route can legitimately have a mono node under a two-channel session; substituting
    /// there would force a stereo edge onto a mono input and MANUFACTURE the converter this
    /// slice removes, on hardware that was fine. A fix that can introduce the crash it
    /// prevents is not a fix (#364), and there is no device here to tell the two apart.
    ///
    /// ⛔ #954b — (b) WAS ORIGINALLY PINNED BY A LEADING `&&` IN THE NEEDLE, AND THAT PINNED
    /// NOTHING. `&& abs(inFmt.sampleRate - hwRate) > 1` still matches after someone appends
    /// `|| inFmt.channelCount != hwChannels`, so the assertion would have been green for a
    /// reason other than the one its message gave — the mirror case `Tests/CISmoke/CLAUDE.md`
    /// §2 calls the worse one, in the very claim written to keep the dangerous half out. It
    /// now EXTRACTS the expression and asserts what it must not contain. Found by the
    /// mandatory reviewer.
    ///
    /// ⚠️ The extraction is anchor-checked before it is asserted on (#926): both anchors occur
    /// exactly once, and a missed anchor would make `!contains` vacuously true — a green that
    /// means nothing.
    func testTheDisagreementTestIsARateToleranceAndNothingElse() throws {
        let code = try engineCode()
        XCTAssertGreaterThan(occurrences(of: "abs(inFmt.sampleRate - hwRate) > 1", in: code), 0, """
            The node/session rate comparison is no longer a tolerance. Exact equality on two \
            `Double` sample rates crossing a framework boundary is a latent trap, so the \
            healthy path could start substituting a format it did not need to — the failure \
            direction #364 names, in the one method this repo has already crashed in five \
            times.
            """)
        let openAnchor = "let nodeDisagreesWithHardware"
        let closeAnchor = "if nodeFormatUnusable"
        guard let a = code.range(of: openAnchor), let b = code.range(of: closeAnchor, range: a.upperBound..<code.endIndex)
        else {
            XCTFail("""
                the disagreement expression could not be extracted — `\(openAnchor)` … `\(closeAnchor)` \
                no longer both occur in order. Re-anchor (§4); do NOT relax this into a \
                whole-file scan, which is how (b) became vacuous the first time.
                """)
            return
        }
        XCTAssertEqual(occurrences(of: openAnchor, in: code), 1, """
            `\(openAnchor)` occurs more than once, so the extraction below is anchored on whichever \
            came first and proves nothing about the other (#408).
            """)
        let expression = String(code[a.lowerBound..<b.lowerBound])
        XCTAssertFalse(expression.contains("channelCount"), """
            A channel-count term is back in the disagreement test:

            \(expression.trimmingCharacters(in: .whitespacesAndNewlines))

            That is the half #954 deliberately did NOT take. `inputNumberOfChannels` is \
            clamped to 1...2 and a route may legitimately report mono at the node under a \
            two-channel session; substituting there forces a stereo edge onto a mono input \
            and MANUFACTURES the converter this slice exists to remove — on hardware that \
            was healthy. If a device log ever justifies the channel half, it needs its own \
            slice, its own evidence, and this claim rewritten rather than deleted.
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
        // ⛔ #958 AMENDED THIS FROM ONE TO TWO, and the amendment is the point rather than a
        // concession. The law was "the decision must happen ONCE and be carried in `inFmt`;
        // a second raw read re-introduces exactly the stale value the founder log ended on."
        // His v10.79.435 log then showed the opposite failure: the input side AGREED with the
        // hardware (`edge 48000/1, session 48000/1`) and the app still aborted, because the
        // MASTER GRAPH was at `out 44100/2`. The repair asks the session for the graph's rate
        // and must then RE-READ what was granted — a preference is a request, and only the
        // granted number can be trusted against the assert. That second read is the opposite
        // of stale; forbidding it would have kept a law that blocks its own purpose (#364).
        //
        // ⛔ #958 RAISED THIS TO TWO AND #958b PUT IT BACK TO ONE — the round trip is kept
        // because the ARGUMENT for two was the defect, not just the number. #958 added a
        // re-read after `setPreferredSampleRate` and called it "the only place a fresh number
        // can legitimately appear". It is the one place a fresh number CANNOT appear: this
        // very file's #823 note measures the input node to hold its placeholder until
        // `start()` rebuilds the I/O unit, and nothing between the request and that read
        // starts the engine. The read returned the CACHED pre-request value, so #958's
        // refusal would have fired whether or not iOS granted the rate — monitoring off
        // forever on the device the slice targeted. #958b reads `session.sampleRate` instead,
        // which is the party that grants and is the same source #823/#954 already trust.
        //
        // ⚠️ ONE, NOT "AT LEAST ONE". A second raw read is exactly the drift this law was
        // written against, and the one candidate anybody would add — a post-grant refresh —
        // has now been tried and measured to be stale. The single sanctioned site:
        //   · `var inFmt = input.inputFormat(forBus: 0)` — the DECISION, before the connect.
        //
        // ⚠️ ONE LEGITIMATE SECOND READ EXISTS AND THIS PIN MUST NOT BE READ AS BANNING IT
        // (#364, added #958c after a reviewer found the flat form). `AudioEngine.swift`'s
        // HYPOTHESIS #5 calls `masterEngine.prepare()` to rebuild the I/O unit WITHOUT
        // starting it; after that the node is no longer stale and re-reading it is the
        // authoritative confirmation the hardware moved — which `session.sampleRate`, a
        // fresher proxy, cannot give. That is a COUNT to raise to 2 in the same commit, not
        // a law to route around. The failure message says so.
        XCTAssertEqual(occurrences(of: "input.inputFormat(forBus: 0)", in: code), 1, """
            The input node's raw format is read \
            \(occurrences(of: "input.inputFormat(forBus: 0)", in: code)) times, not once. \
            Exactly ONE read is sanctioned: the DECISION at the top of the ON path. A SECOND \
            read is almost always a "refresh after asking the session for a rate" — that is \
            #958's defect, and it reads a node this file has measured to be STALE until \
            `start()` (#823/#958b). Read `session.sampleRate` for a granted rate. ⚠️ BUT a \
            second read AFTER a `masterEngine.prepare()` is CORRECT — that is HYPOTHESIS #5 \
            in `AudioEngine.swift`, and it is the only thing that closes the \
            async-renegotiation window a proxy leaves open. If you build it, raise this count \
            to 2 HERE and widen the sibling window in \
            `TheMonitorRefusesARateItCannotMeetTests` in the SAME commit. ZERO means the \
            decision itself is gone and the connect format comes from nowhere.
            """)
        // ⭐ #956 AMENDED THIS LAW AND THE AMENDMENT IS PINNED HERE, not left implicit. The
        // TAP deliberately asks the node again at its own rung, because `installTap` validates
        // its format against the node's OWN bus and `inFmt` may be a session substitute the
        // node never reported — a second uncatchable abort, one rung later. That read uses the
        // OUTPUT scope (what a tap validates against, and what every other tap in this repo
        // reads), so the assertion above stays literally true: the raw `inputFormat` DECISION
        // is still made exactly once. ⚠️ The scopes agreeing is not the point — writing the
        // tap's read in the same accessor as the decision's would silently merge two rules
        // that exist for different reasons.
        // ⭐ #959 RAISED THIS FROM ONE TO TWO, and the distinction is the reason the pin is
        // still worth having. The law is "the input edge DECIDES its format once" — a read
        // that feeds `connect` or `installTap` is a DECISION. The second read is a pure
        // DIAGNOSTIC: rung 4/5 prints the node's real bus beside the format the edge was
        // connected with, immediately before the `start()` that carries the abort. It cannot
        // change graph state, because its only consumer is a log string. A bare count cannot
        // tell those apart, so the claim below adds the shape: the diagnostic read must sit
        // inside a `logMonitorOutcome` summary. Without that, this count could be spent on a
        // silent THIRD decision and the pin would wave it through.
        XCTAssertEqual(occurrences(of: "input.outputFormat(forBus: 0)", in: code), 2, """
            The output-scope reads changed. TWO belong in this file: the DECISION at rung \
            5/5 that `installTap` is handed (#956), and the DIAGNOSTIC at rung 4/5 that \
            prints the node's real bus beside the connected format (#959) — the comparison \
            the `isInputConnToConverter` assert actually makes, on the line every founder \
            log in this family ends at. Fewer means one of those is gone: without the first \
            the tap is back on a carried format (the abort this pins against); without the \
            second the next crash log again says only THAT the engine was restarted. MORE \
            means a third read, and a third read is a second DECISION unless it is inside a \
            log summary — see the claim below.
            """)
        // ⚠️ The shape check that makes the count above mean something. `nodeBusNow` is bound
        // and used ONLY to build the rung's summary string; if a future edit binds it to a
        // `connect` or `installTap` argument, the count stays 2 and the law is gone.
        guard let diag = code.range(of: "let nodeBusNow = input.outputFormat(forBus: 0)") else {
            XCTFail("""
                Rung 4/5's diagnostic read is gone or renamed (#959). That line is what makes \
                the next founder log say WHETHER the connected format and the node's real bus \
                agreed at the moment of the aborting `start()` — the question three slices \
                have had to infer instead of read.
                """)
            return
        }
        let afterDiag = String(code[diag.upperBound...].prefix(400))
        XCTAssertTrue(afterDiag.contains("logMonitorOutcome(\"on 4/5"), """
            The rung-4/5 output-scope read is no longer consumed by the rung's own log line. \
            It exists to be PRINTED; a read whose value reaches `connect` or `installTap` \
            instead is a second format DECISION wearing a diagnostic's name, and the count \
            above would wave it through.
            """)
    }

    /// claim 6 (FORWARD) — rung 3/5 must NAME the format it forces onto the edge. Until #954
    /// the ON path printed a format only on its failure exits, so a log that CRASHED at 4/5
    /// carried no way to tell a matching edge from a mismatched one — precisely the question
    /// the abort asks. This is what makes the next device run decisive either way.
    ///
    /// ⚠️ #958b — THE RUNG NAMES THE EDGE AS DECIDED, WHICH IS NOT ALWAYS THE EDGE CONNECTED.
    /// Since #958 the rate block below may REPLACE `inFmt` with a format rebuilt from the rate
    /// the session granted. A log therefore carries the rung's `edgeSummary` AND, when the
    /// block ran, a `rate: session granted … Hz — edge and graph agree, continuing` line; the
    /// second one wins. Said here rather than moved into the rung, because folding a
    /// conditional value into the rung would either make it lie on the common path or make it
    /// a multi-line literal, which hides the rung from `scripts/diag-ladder.py --source`.
    ///
    /// ⭐ #959 CLOSED THE OTHER HALF OF THAT GAP, at the rung where it matters. Rung 4/5 now
    /// prints the format the edge was ACTUALLY connected with, beside the node's real bus and
    /// the session's granted rate — so a log no longer needs 3/5 to be the whole story. 3/5
    /// says what was DECIDED; 4/5 says what was CONNECTED and what the hardware says at the
    /// instant before the aborting `start()`. Read 4/5 first when triaging this crash family.
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
