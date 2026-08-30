// TheVoiceDoorFeedsTheCaptureTests.swift
// Echoel — the capture door exists, feeds the engine, and adds no modal cost. #592b.
//
// WHAT THIS GUARDS. The wiring half of the EchoelVoice capture: `MicrophoneManager`
// hands its existing main-thread sample blocks to `captureSampleSink` (riding the
// per-buffer hop that already exists — zero new thread crossings), the "Voice timbre"
// row is mounted inside `soundPanel` (a panel child, NOT a presentation modifier), and
// the controller that joins them is owned by `EchoelStudioView` so a capture survives
// the panel closing mid-take. Every claim here is a JOIN between two files — the class
// of defect where renaming one side leaves a door pointing at nothing (#351).
//
// ⚠️ HONEST LIMITS. 9 tests, 32 `XCTAssert*` STATEMENTS — 3+3+3+2+5+2+4+7+3, measured with
// `awk` per `func test`, not by eye. ⛔ Three hand-counts in this header have now been
// wrong (12, then 16, then 20 with a bogus 3+3+3+2+5+4 split); the command that settles it
// is in the SESSION_LOG for #892, and a fourth hand-count is not the fix — reading the
// number as a DATE is. Two nuances the raw number hides: claim 6 runs one of its two
// statements more than once through a `for` loop, so a green run makes MORE evaluations
// than statements — ⛔ #894: the exact number stood here as "19", was not updated when the
// statement count went 18 → 22, and became the FIFTH wrong hand-count in this header. It is
// DELETED rather than corrected, because unlike the statement count it has no command behind
// it: nothing can re-derive it without hand-expanding every loop. The statement count is the
// measurement; the evaluation count was decoration that rotted.
// A whole-file `grep -c` on the assertion name is likewise NOT the measurement — this header
// quotes assertion names in prose, so writing ABOUT the count changes it. That is not
// hypothetical: the sentence that first stated a grep figure here was made wrong by its own
// words before the commit (#753, the marker is also a noun). Count inside `func test`
// bodies only. The `XCTUnwrap`s also fail their tests and stay deliberately outside this
// count, which counts assertions, not failure points. ALL
// are SOURCE-TEXT JOINS: the controller's begin/cancel/apply flow drives a real
// `MicrophoneManager` + mic permission machinery that a test host cannot exercise
// honestly (its `startRecording` requests permission), and the engine underneath is
// already END-TO-END covered by `TheCaptureTurnsAToneIntoAProfileTests`. What no test
// here can prove: that the row RENDERS, that the mic actually flows on device, and how
// the captured timbre SOUNDS — the device probe, founder (NEEDS-FOUNDER-VERIFY: hold a
// tone via Sound panel → Capture, then play). Presentation-modifier budget is pinned by
// `ResetSoundClearsWhatTheLaunchLineReportsTests`, not re-counted here (#416).
//
// ⚠️ THE STAKES OF THAT ONE PROBE CHANGED ON 2026-08-24, AND NOTHING ELSE RECORDS IT.
// The ask itself is unchanged — do not file a second marker for it (#790: one question,
// one place). What changed is what rides on the answer. Until #795 the capability was
// sold only in `release_notes.txt`, which is version-scoped and scrolls away. #795 put it
// in `description.txt` in both locales and #797 put it on `docs/faq.html`,
// `docs/architecture.html` and `docs/dev/FEATURE_MATRIX.md`. Both moves were correct —
// the feature ships, is doored and is guard-pinned, and leaving it unsold was the
// under-claim those cycles existed to end — but a permanent App Store line is what a
// 2.3 review reads, and it is now backed by a probe nobody has run. That makes this the
// highest-stakes entry in the `scripts/founder-verify.py` backlog, not merely one of ~50.
//
// ⭐ #891 ADDED A FIFTH CLAIM, and it guards a JOIN the other four do not: what the
// controller does when `startRecording()` REFUSES. Three of that function's four silent
// early exits leave no tap, so no sample can ever arrive and the take would sit on
// `.capturing` 0 % until the user cancels — a hang, on the exact path the founder's #890
// device probe walks. The claim pins the abort AND its two counterweights (#343): the
// `hasPermission` discriminator, whose removal would abort the legitimate permission wait
// instead, and the deliberate absence of `releaseMic()` on that path, which would write a
// three-rung stop ladder for a mic that never started (#882).
//
// ⛔ #897 — AND FOR ONE CLASS OF USER THE ARC HAD FIXED NOTHING AT ALL. Every abort returns
// the take to `.idle`, so the Capture button keeps its label, hint and value: to VoiceOver the
// tap changes nothing on the focused control, and the sentence five slices worked on is an
// unfocused sibling `Text`. Blind users still had the dead button the arc set out to remove.
// The ninth claim pins the announcement AND that its text is `caption` itself — a hand-written
// second copy would drift the first time either is reworded, and the two would then disagree
// about what just happened. ⚠️ WHAT NO TEST HERE CAN PROVE: that VoiceOver actually SPEAKS it.
// That is a device probe and it is filed as one, not implied by a green bundle.
//
// ⛔ #896 — THE HANG SURVIVED FOUR SLICES BECAUSE ONE SENTENCE WAS NEVER MEASURED. #891
// wrote that the undetermined permission `return` "RESOLVES by itself"; #892 retracted it
// for DENIED only; #895 re-inspected the state space and signed the remainder off. Measured:
// `requestPermission()`'s continuation writes `hasPermission = true` and nothing else (since
// #825 it deliberately starts nothing), `startRecording()` has exactly ONE production caller
// — the line in `begin()` that has already returned — and nothing in `Sources/` observes
// `hasPermission`. So the user taps Allow and the row sits at 0 % under a caption claiming a
// live capture. That is the FIRST capture of every new user: the most common instance of the
// class, excluded from the fix on the strength of a premise nobody checked.
//
// ⛔ AND THE GUARD MADE IT WORSE, in both directions at once. The assertion #895 called "THE
// HIGHEST-VALUE" one forbade `if !mic.isRecording {` — (a) on that same false premise, so it
// would now forbid CORRECT work (#364), and (b) it could never fire for the failure it named,
// because collapsing the branches necessarily deletes an anchor `XCTUnwrap`ped above it: the
// method throws and the line is never reached. Vacuous on EVERY tree, not just the parent.
// ⭐ THE TRANSFERABLE LESSON: an assertion placed AFTER an unwrap of the thing it describes
// is unreachable for exactly the edit it guards against. Put the negative FIRST, or assert on
// something that edit cannot delete.
//
// ⭐ §3 GRADING OF #896: five of the eighth claim's checks are red on the parent `a80a2c4`
// (the single gate, the undetermined branch, one-teardown — it counted 2 there — every flag
// cleared in `clearApplied`, and the caption's three-way order). The two `MicrophoneManager`
// assertions stay green: they are #895's and unchanged. No vacuous counterweight is added
// this time; the one that existed was deleted for being vacuous.
//
// ⭐ #895 ADDED AN EIGHTH CLAIM AND CLOSED THE CASE #891 LEFT OPEN. Three slices in a row
// removed a 0 % hang and none of them removed it for a user who has DENIED the microphone:
// iOS shows no prompt for that user and returns immediately, so `hasPermission` stayed false
// and the refusal branch — which asks "granted?" — never fired. The flag that could have
// told the truth, `MicrophoneManager.permissionDenied`, was written ONLY inside the request
// callback, so at launch it read "not denied" while the system said denied. ⭐ THE REASON
// NOBODY CAUGHT IT: the flag had ZERO readers repo-wide. An unread flag cannot be observed
// to lie, which is why its first reader and its repair have to ship together.
//
// ⭐ §3 GRADING OF THE EIGHTH CLAIM: 4 of its 5 assertions do not hold on the parent
// `e55cfcb` — two are plainly red (the derived flag, the refresh before the guard) and two
// fail through `XCTUnwrap` on an anchor that does not exist there yet (the denied branch in
// `begin()`, the denied branch in `caption`), which is a failure POINT rather than an
// assertion and is named as such. The fifth is the negative one below: GREEN on the parent
// and vacuously so, because the bare test it forbids was never written. That is the THIRD
// vacuous counterweight in this file — they are listed, never counted as forward-red.
//
// ⚠️ THE HIGHEST-VALUE ASSERTION OF THAT CLAIM IS THE NEGATIVE ONE: `begin()` must NOT hold
// a bare `if !mic.isRecording {`. Undetermined is a THIRD state — neither granted nor denied
// — and the system prompt is open in it. Collapsing the two checks into one reads like tidy
// deduplication and aborts the very first capture every new user ever tries.
//
// ⛔ #894 — REVIEWER PASS ON #893, AND THREE OF ITS FOUR FINDINGS WERE PROSE THAT THE
// RENAME FALSIFIED. #893 moved four NEEDLES and missed the RATIONALES: `cancel()`'s comment
// still said the write was "always already false because begin() clears the flag" — the line
// #893 had just deleted — and this file's `why` for the same write repeated it. That write is
// now LOAD-BEARING (refusal → tap again → the mic starts → Cancel), so both texts invited
// deleting the one line standing between the player and a caption that reports a failed
// microphone after a take that DID start. ⭐ THE LESSON: a rename sweep must grep the
// ARGUMENTS FOR the code, not only the code.
//
// ⭐ #894 ALSO TIGHTENED CLAIM 7's `ingest` WINDOW, and this one is a STRENGTHENING, not a
// forward-red claim — it is green on the parent `b502a02` too, because the reset was already
// in the right place. What changed is that it can now FAIL for a reason that exists (#367):
// the old window ran to END OF FILE, so a `micRefusals = 0` hoisted to the top of `ingest`
// (clearing the streak on the first sample of any take that merely STARTS) passed
// identically. Proven with a negative control rather than asserted: hoisting the reset in a
// simulated tree flips the new assertion red and left the old one green. Reported as a
// strengthening BECAUSE calling a both-trees-green assertion "forward-red" is the over-claim
// this file has already had to retract twice.
//
// ⭐ #893 ADDED A SEVENTH CLAIM AND RENAMED FOUR NEEDLES IN THE SAME COMMIT (#655/#656).
// `micUnavailable: Bool` became `micRefusals: Int`, because a Bool answered the wrong
// question: a second refusal rendered BYTE-IDENTICAL to the first — same sentence, same
// button, same phase — and the founder's open #890 probe asks for a capture "twice in a
// row". A count is the smallest thing that changes on a repeat. §3 GRADING: 3 of the
// seventh claim's 4 assertions are red on the parent `9a99c3c` (the breadcrumb count, the
// completion reset, the caption's suppress-at-1). The fourth — `begin()` must NOT reset the
// streak — is GREEN on the parent and VACUOUSLY so, because the property did not exist
// there; on the parent `begin()` in fact DID reset the old Bool. It is a counterweight for
// the future, not evidence for this slice, and it is the highest-value assertion in the
// file: a tidy-up that "restores" the reset would delete the whole feature while looking
// like hygiene. Same shape as the fifth claim's `releaseMic()` counterweight — two of them
// now, both named rather than counted as forward-red.
//
// ⛔ #892 ADDED A SIXTH CLAIM BECAUSE #891'S FIFTH DID NOT COVER WHAT IT ASSUMED. The
// caption put the refusal message FIRST on the premise that the flag "can only be true
// with no profile applied". That argues about the moment the flag is SET, not the moment
// it is READ — `PolySynthVoice.apply(_:)` installs a voice profile from any recalled patch
// (#593c), and the preset bar that does it sits directly above the row. Two independent
// reviewers found it the same hour. The sixth claim pins the REPAIR: the applied-profile
// branch outranks the refusal message, and both non-`begin()` exits clear the flag so it
// cannot outlive the situation it describes. ⭐ The lesson is not "order your branches":
// it is that a rationale about WHERE A BUTTON IS RENDERED is a claim about the view, and
// the view is the thing most likely to change underneath it.
//
// ⭐ GRADING OF THE SIXTH CLAIM (§3): all three of its assertion EVALUATIONS are red on
// the parent (`d29c68f`) and green here — the branch order was literally inverted there,
// and neither exit wrote the flag. Measured, not assumed. Stripper: 0 of 3 needle verdicts
// flip raw-vs-stripped, so for THIS claim the stripper is prophylactic — unlike the fifth
// one below, where it is load-bearing. Two claims in one file, two different answers: that
// is why §3 asks per claim rather than per file.
//
// ⭐ GRADING OF THAT FIFTH CLAIM (§3), separately because it does NOT match the eight
// needles below. FOUR of its five assertions are red on the parent by absence, honestly
// FORWARD. The fifth — `XCTAssertFalse(releaseMic())` — is GREEN on the parent, and
// vacuously so: the window exists there and simply holds no such call. It is kept because
// it can still fail for a reason that exists (#367) — a later reader "tidying" the abort
// into the shared teardown is exactly the plausible edit — but it is a REGRESSION guard,
// not evidence for this slice, and calling it forward-red would be the over-claim.
//
// ⚠️ AND FOR THIS CLAIM THE STRIPPER IS LOAD-BEARING, not prophylactic — measured, 1 of 5
// needle verdicts FLIPS. The abort carries a ⛔ comment that NAMES `releaseMic()` to explain
// why it is absent. On the RAW text that comment sits inside the window, so the negative
// assertion would be red on a correct tree; stripped, it is green. That is the #404/#453
// defect in miniature, caught only because §3 asks for the raw-vs-stripped measurement
// instead of assuming it.
//
// ⭐ GRADING (§3). Every needle names code this same commit writes — the file compiles
// against the parent (it names no new Swift symbol, only string needles) but every
// join assertion is red there by ANCHOR ABSENCE: one absence per file-pair, reported
// once (#486), honestly FORWARD. Stripper: all EIGHT needles of this file measured raw
// vs stripped on both trees (sink decl, sink call ×2 forms, mount, @State, struct,
// apply, load-absence) — every worktree count identical raw and stripped, so 0 of 8
// verdicts flip → PROPHYLAKTISCH (the doc mentions of `captureSampleSink` in prose ARE
// stripped, which is exactly why the needles carry the call/argument syntax).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceDoorFeedsTheCaptureTests: XCTestCase {

    /// The mic half: the sink exists and is called INSIDE `processExtractedAudio` —
    /// the existing main-thread landing point — before any early return.
    func testTheMicHandsItsSamplesToTheSink() throws {
        let mic = try source("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertTrue(mic.contains("var captureSampleSink: (([Float], Double) -> Void)?"),
                      "the sink declaration left MicrophoneManager")
        let fn = try XCTUnwrap(
            mic.range(of: "private func processExtractedAudio(_ samples: [Float], "
                        + "frameLength: Int, sampleRate: Double) {"),
            "the main-thread landing point was renamed — re-anchor (#454)")
        // The FIRST non-blank stripped line after the declaration — not merely "within
        // the first 200 chars", which a guard-return inserted above the call would pass
        // (review #592b, #367): the named law is "before any early return", so test it.
        let firstLine = mic[fn.upperBound...]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        XCTAssertEqual(firstLine, "captureSampleSink?(samples, sampleRate)",
                       "the sink call must be the FIRST statement of "
                       + "processExtractedAudio — any early return above it (a level "
                       + "gate, a guard) would starve the capture quietly")
        XCTAssertEqual(codeOccurrences(of: "captureSampleSink?(", in: mic), 1,
                       "one call site — a second would double-feed the engine")
    }

    /// The door half: the row is mounted in the studio, exactly once, and the
    /// controller is owned by the VIEW (not the row), so a capture survives the
    /// panel closing mid-take.
    func testTheRowIsMountedAndTheControllerIsViewOwned() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "VoiceCaptureRow(controller:", in: studio), 1,
                       "the door must be mounted exactly once (in soundPanel)")
        XCTAssertTrue(studio.contains("@State private var voiceCapture = VoiceCaptureController()"),
                      "the controller must be owned by EchoelStudioView — owned by the "
                      + "row, a mid-take panel close would abandon the capture")
        XCTAssertTrue(studio.contains("private struct VoiceCaptureRow: View"),
                      "the leaf row struct left the studio file")
    }

    /// The freeze law at this row: the ~12 Hz observable reads (`controller.progress`,
    /// `controller.hearingYou`) occur ONLY inside the leaf struct's body, never in the
    /// panel that mounts it (10.76.41/50 — an ancestor read would rebuild the whole
    /// root at capture rate and tear down open menus).
    func testTheProgressReadsStayInTheLeaf() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let leafStart = try XCTUnwrap(studio.range(of: "private struct VoiceCaptureRow: View"))
        let beforeLeaf = studio[..<leafStart.lowerBound]
        XCTAssertFalse(beforeLeaf.contains("voiceCapture.progress")
                       || beforeLeaf.contains("voiceCapture.hearingYou"),
                       "a capture-rate observable read leaked ABOVE the leaf — the "
                       + "menu-freeze class (10.76.50) returned")
        // The panel hands over the REFERENCE only.
        //
        // ⛔ #631: the needle was `VoiceCaptureRow(controller: voiceCapture)` — with a
        // CLOSING PAREN — and #593c added a second argument (`, patch: $currentPatch`), so
        // this assertion had been UNCONDITIONALLY RED ever since, with no failure message at
        // all to say why. The same file gets it right one test up, at the `codeOccurrences`
        // call, by matching the PREFIX. A guard pinned to a full argument list breaks on the
        // next argument, which is exactly what happened; the property being defended is that
        // the panel passes the OBJECT and not a read value, and the prefix carries that.
        XCTAssertTrue(beforeLeaf.contains("VoiceCaptureRow(controller: voiceCapture"),
                      "the panel must hand over the reference, not a read value — a "
                      + "capture-rate read at the mount site is the menu-freeze class "
                      + "(10.76.50). Mount: `EchoelStudioView`'s soundPanel.")
        XCTAssertFalse(studio[leafStart.upperBound...].contains("voiceCapture.progress"),
                       "nothing after the leaf declaration may read the state either — "
                       + "the leaf reads its own `controller`, not the view's property")
    }

    /// The completion join: the controller applies through the #591a drain-surviving
    /// pathway, never through `loadTimbreProfile` directly (which the next patch
    /// recall would silently wipe — trap 1).
    func testTheControllerAppliesThroughTheSurvivingPathway() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        XCTAssertTrue(controller.contains("applyVoiceProfile(profile)"),
                      "completion must go through PolySynthVoice.applyVoiceProfile — "
                      + "the staged, reasserted pathway")
        XCTAssertFalse(controller.contains("loadTimbreProfile("),
                       "a direct loadTimbreProfile call would be wiped by the next "
                       + "patch recall (trap 1) — the defect #591a exists to prevent")
    }

    /// #891 — a refused mic aborts the take instead of leaving it armed at 0 % forever,
    /// and the caption says so. Five assertions: the re-read, the discriminator, the
    /// state reset, the ladder counterweight, and the row join.
    func testARefusedMicAbortsTheTakeInsteadOfHanging() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        let start = try XCTUnwrap(controller.range(of: "mic.startRecording()"),
                                  "the controller stopped starting the mic — re-anchor (#454)")
        let end = try XCTUnwrap(controller.range(of: "func cancel()", range: start.upperBound..<controller.endIndex),
                                "cancel() moved above begin() — re-anchor this window (#454)")
        let afterStart = String(controller[start.upperBound..<end.lowerBound])

        // ⛔ #896: this needle was `if !mic.isRecording, mic.hasPermission {` — the shape
        // before the three states were folded behind one gate. Left as it was it would have
        // gone RED on correct code (#364). The invariant it protects is unchanged: begin()
        // must RE-READ isRecording after calling startRecording().
        XCTAssertTrue(afterStart.contains("if !mic.isRecording {")
                        && afterStart.contains("} else if mic.hasPermission {"),
                      "begin() must RE-READ isRecording after startRecording(): every exit "
                      + "of that function except one installs no tap, so the take would sit "
                      + "on .capturing 0 % with only Cancel to escape (#891/#896)")
        XCTAssertTrue(afterStart.contains("mic.hasPermission"),
                      "the hasPermission discriminator is a COUNTERWEIGHT, not decoration: "
                      + "the no-permission exit also leaves isRecording false, but that wait "
                      + "RESOLVES once the system prompt is answered. Without this half the "
                      + "abort would fire on the first capture every new user ever tries")
        XCTAssertTrue(afterStart.contains("micRefusals += 1"),
                      "the abort must record WHY nothing happened — the row's caption is the "
                      + "only thing standing between the user and a button that looks dead")
        XCTAssertFalse(afterStart.contains("releaseMic()"),
                       "the abort must NOT go through releaseMic(): it calls stopRecording(), "
                       + "which walks a three-rung stop ladder and releases the record route "
                       + "a second time — rungs for a teardown of a mic that never started "
                       + "are exactly the lie the ladder law forbids (#882)")

        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("if controller.micRefusals > 0 {"),
                      "the flag needs its reader: without the caption branch the abort is "
                      + "silent and a refused capture still looks like a dead button (#891)")
    }

    /// #892 — the refusal message cannot outlive the situation it describes. TWO assertion
    /// statements (⛔ #894: this said "Four"): the branch ORDER inside `caption`, and one
    /// clearing-write check run once per phase exit that `begin()` does not cover.
    func testTheRefusalMessageCannotOutliveItsSituation() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let capStart = try XCTUnwrap(studio.range(of: "private var caption: String {"),
                                     "VoiceCaptureRow's caption was renamed — re-anchor (#454)")
        let caption = try captionBody(of: studio, from: capStart)
        let profileAt = try XCTUnwrap(caption.range(of: "if synth.appliedVoiceProfile != nil {"),
                                      "the applied-profile branch left the caption")
        let refusalAt = try XCTUnwrap(caption.range(of: "if controller.micRefusals > 0 {"),
                                      "the #891 refusal branch left the caption")
        XCTAssertTrue(profileAt.lowerBound < refusalAt.lowerBound,
                      "what the instrument is DOING NOW must outrank a report about a take "
                      + "that did not happen: a recalled patch can install a voice profile "
                      + "without ever entering begin() (#593c), and with the refusal branch "
                      + "first the row showed \"Tap Capture again\" beside a Clear button "
                      + "— a control that is not on screen (#892)")

        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        for (fn, why) in [("func cancel()",
                           "Cancel: LOAD-BEARING since #893, not defensive — #892's "
                           + "\"always already false\" died when begin() stopped clearing "
                           + "the streak. Reachable: refusal (streak 1), tap Capture again, "
                           + "the mic starts this time, Cancel. Without this write the "
                           + "caption then reports a failed microphone after a take that "
                           + "DID start (#894)"),
                          ("func clearApplied(synth: PolySynthVoice)",
                           "Clear: reachable with the flag still true (refusal → recalled "
                           + "patch with a profile → Clear), and without the write the "
                           + "microphone-failure sentence returns as the caption for a "
                           + "successful, unrelated action")] {
            let at = try XCTUnwrap(controller.range(of: fn),
                                   "\(fn) was renamed — re-anchor this window (#454)")
            let end = try XCTUnwrap(controller.range(of: "\n    }", range: at.upperBound..<controller.endIndex),
                                    "\(fn) has no closing brace at method indentation")
            let body = String(controller[at.upperBound..<end.lowerBound])
            XCTAssertTrue(body.contains("micRefusals = 0"), why)
        }
    }

    /// #893 — a REPEATED refusal is visible. Four assertions: `begin()` must not reset the
    /// streak (the counterweight — a tidy-up there silently deletes the whole feature), the
    /// caption suppresses the count at 1, a completed take ends the streak, and the
    /// breadcrumb carries the count so the exported log answers the probe on its own.
    func testASecondRefusalInARowLooksDifferent() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        let beginAt = try XCTUnwrap(controller.range(of: "func begin(mic: MicrophoneManager, synth: PolySynthVoice) {"),
                                    "begin() was renamed — re-anchor (#454)")
        let cancelAt = try XCTUnwrap(controller.range(of: "func cancel()", range: beginAt.upperBound..<controller.endIndex),
                                     "cancel() moved above begin() — re-anchor this window (#454)")
        let begin = String(controller[beginAt.upperBound..<cancelAt.lowerBound])
        // ⛔ #895b: this window used to be ALL of `begin()`, and the message only ever spoke
        // about ARM TIME. When the denied branch legitimately ended a streak, the assertion
        // would have gone red on correct code — a guard that forbids correct work is the
        // #364 defect. Bounded to the arm block, it now asserts exactly what it says.
        // ⛔ #896: this boundary was `if micStartedByUs {`, one line short of the thing the
        // message names — a reset placed as the first statement INSIDE that block, before
        // `startRecording()`, is an arm-time reset in effect and passed. The window now ends
        // at the start call itself.
        let armEnd = try XCTUnwrap(begin.range(of: "mic.startRecording()"),
                                   "the arm block's boundary moved — re-anchor (#454)")
        XCTAssertFalse(String(begin[..<armEnd.lowerBound]).contains("micRefusals = 0"),
                       "ARMING must NOT clear the streak: it is not where a run of refusals "
                       + "ends, and a reset here makes \"in a row\" impossible while looking "
                       + "like ordinary hygiene. Nothing renders the count during .capturing "
                       + "anyway — the caption's switch takes its own branch (#893). A reset "
                       + "inside an ABORT branch is a real end of the run and is allowed")
        XCTAssertTrue(begin.contains("(\\(micRefusals)x in a row)"),
                      "the breadcrumb must carry the count, so the exported log answers the "
                      + "#890 probe's \"twice in a row\" even when nobody watched the screen")

        // ⛔ #894: this window used to run to END OF FILE, so a `micRefusals = 0` placed at
        // the TOP of ingest — clearing the streak on the first sample of any take rather
        // than on completion — passed identically while breaking the property the message
        // names. Claim 6 three tests above bounds its windows for exactly this reason.
        let ingestAt = try XCTUnwrap(controller.range(of: "private func ingest("),
                                     "ingest() was renamed — re-anchor (#454)")
        let ingestEnd = try XCTUnwrap(controller.range(of: "\n    }", range: ingestAt.upperBound..<controller.endIndex),
                                      "ingest() has no closing brace at method indentation")
        let ingest = String(controller[ingestAt.upperBound..<ingestEnd.lowerBound])
        let doneAt = try XCTUnwrap(ingest.range(of: "if engine.state == .done {"),
                                   "the completion branch was renamed — re-anchor (#454)")
        let resetAt = try XCTUnwrap(ingest.range(of: "micRefusals = 0"),
                                    "a completed take is the strongest end of a refusal "
                                    + "streak; without this the next failure would report a "
                                    + "count carried over from before a success")
        XCTAssertTrue(resetAt.lowerBound > doneAt.upperBound,
                      "the reset must sit INSIDE the completion branch. Above it, the streak "
                      + "would clear on the first sample of any take that merely STARTS — "
                      + "which is not what \"a completed take ends the streak\" means, and no "
                      + "other assertion would notice (#894)")

        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("controller.micRefusals == 1 ? \"\""),
                      "the count is suppressed at 1 — a single ordinary failure must not read "
                      + "like a tally; the number is new information only when it repeats")
    }

    /// #895/#896 — EVERY permission state ends the take instead of hanging it: denied,
    /// undetermined, and the placeholder refusal, behind one gate with one teardown.
    /// Seven assertion statements (three of them run once per flag through a loop).
    ///
    /// ⛔ Renamed from `…AndUndeterminedStillWaits` (#374): that name described a procedure
    /// the code no longer takes, and it was the very behaviour #896 had to remove.
    func testEveryPermissionStateEndsTheTakeInsteadOfHangingIt() throws {
        let mic = try source("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertTrue(mic.contains("permissionDenied = status == .denied"),
                      "permissionDenied must be DERIVED from the system status, not written "
                      + "only inside the request callback — as a callback-only flag it read "
                      + "\"not denied\" at launch for a user who had denied earlier, and "
                      + "nothing noticed because it had zero readers repo-wide (#895)")
        let startAt = try XCTUnwrap(mic.range(of: "func startRecording() {"),
                                    "startRecording() was renamed — re-anchor (#454)")
        let guardAt = try XCTUnwrap(mic.range(of: "guard hasPermission else {", range: startAt.upperBound..<mic.endIndex),
                                    "the permission guard moved — re-anchor (#454)")
        XCTAssertTrue(String(mic[startAt.upperBound..<guardAt.lowerBound]).contains("checkPermission()"),
                      "the permission state must be re-read from the system BEFORE the guard: "
                      + "checkPermission() otherwise runs once in init, so a user who fixed "
                      + "the permission in Settings was refused on the next tap (#895)")

        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        let beginAt = try XCTUnwrap(controller.range(of: "func begin(mic: MicrophoneManager, synth: PolySynthVoice) {"),
                                    "begin() was renamed — re-anchor (#454)")
        let cancelAt = try XCTUnwrap(controller.range(of: "func cancel()", range: beginAt.upperBound..<controller.endIndex),
                                     "cancel() moved above begin() — re-anchor (#454)")
        let begin = String(controller[beginAt.upperBound..<cancelAt.lowerBound])
        // ⛔ #896 DELETED THE ASSERTION THAT STOOD HERE, and it was wrong in BOTH directions.
        // It forbade `if !mic.isRecording {` on the premise that undetermined must not abort.
        // (a) That premise is false — nothing restarts the take after the grant, so the
        // undetermined path was the hang, and the code now MUST contain that exact line;
        // keeping the assertion would forbid correct work, the #364 defect. (b) Even for the
        // failure it named it could never fire: collapsing the branches necessarily deletes
        // one of the anchors unwrapped above it, `XCTUnwrap` throws, and the method aborts
        // before reaching it. Vacuous on every tree, not only the parent. ⭐ THE LESSON: an
        // assertion placed AFTER an unwrap of the thing it describes is unreachable for
        // exactly the edit it guards against — put the negative first, or assert on
        // something the edit cannot delete.
        XCTAssertTrue(begin.contains("if !mic.isRecording {"),
                      "the three permission states share ONE gate and ONE teardown: #895 "
                      + "carried two near-identical exits and a third would have made "
                      + "divergence a matter of time (#896)")
        XCTAssertTrue(begin.contains("micAwaitingPermission = true"),
                      "UNDETERMINED must be handled, not fallen through. requestPermission()'s "
                      + "continuation writes hasPermission and nothing else (#825), and "
                      + "startRecording() has one production caller which has already "
                      + "returned — so answering the system alert restarts nothing and the "
                      + "take hung at 0 % under a caption claiming a live capture. That is "
                      + "the FIRST capture of every new user (#896)")
        XCTAssertEqual(codeOccurrences(of: "mic.captureSampleSink = nil", in: begin), 1,
                       "exactly one teardown in begin(): three reasons may differ in what "
                       + "they record, never in what they tear down")

        let clearAt = try XCTUnwrap(controller.range(of: "func clearApplied(synth: PolySynthVoice)"),
                                    "clearApplied was renamed — re-anchor (#454)")
        let clearEnd = try XCTUnwrap(controller.range(of: "\n    }", range: clearAt.upperBound..<controller.endIndex),
                                     "clearApplied has no closing brace at method indentation")
        let clearBody = String(controller[clearAt.upperBound..<clearEnd.lowerBound])
        for flag in ["micRefusals = 0", "micAccessDenied = false", "micAwaitingPermission = false"] {
            XCTAssertTrue(clearBody.contains(flag),
                          "clearApplied must clear EVERY flag the row can render (\(flag) "
                          + "missing): denied abort → recall a patch carrying a voice profile "
                          + "→ tap Clear, and the microphone-failure sentence returns as the "
                          + "caption for a successful, unrelated action. #895 added a flag and "
                          + "not this line, which is the #892 defect reintroduced (#896)")
        }

        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let capAt = try XCTUnwrap(studio.range(of: "private var caption: String {"),
                                  "VoiceCaptureRow's caption was renamed — re-anchor (#454)")
        let caption = try captionBody(of: studio, from: capAt)
        let capAwaiting = try XCTUnwrap(caption.range(of: "if controller.micAwaitingPermission {"),
                                        "the awaiting-permission message left the caption")
        let capDenied = try XCTUnwrap(caption.range(of: "if controller.micAccessDenied {"),
                                      "the denied message left the caption")
        let capRefusal = try XCTUnwrap(caption.range(of: "if controller.micRefusals > 0 {"),
                                       "the refusal message left the caption")
        XCTAssertTrue(capAwaiting.lowerBound < capDenied.lowerBound
                        && capDenied.lowerBound < capRefusal.lowerBound,
                      "three failure reports, most transient first. The two permission ones "
                      + "outrank the refusal count because neither of their remedies is "
                      + "\"tap again\" — no number of taps answers a dialog or changes a "
                      + "denied permission (#896)")
    }

    /// #897 — the abort reaches VoiceOver, and it says the same thing the screen says.
    /// Three assertions: the announcement exists, it is gated on the aborted phase, and it
    /// carries `caption` rather than a second string that could drift from it.
    func testTheAbortIsAnnouncedAndSaysWhatTheScreenSays() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let capAt = try XCTUnwrap(studio.range(of: "Button(\"Capture\") {"),
                                  "the Capture button was renamed — re-anchor (#454)")
        // ⛔ NOT `prefix(N)`. `SourceText.codeOnly` blanks a comment's TEXT but KEEPS its
        // leading whitespace, so a stripped comment line still costs its indentation — at 28
        // spaces a doc block of two dozen lines eats a 700-character window on its own, and
        // this claim was red on its own correct code until the window was bounded by an
        // anchor instead of a constant. The general form of the #894 lesson: a window must be
        // bounded by the thing it describes, never by a number someone guessed. Any guard in
        // this bundle still using `prefix(N)` over a comment-heavy region has the same fault
        // line, and only its MARGIN is keeping it green.
        let actionEnd = try XCTUnwrap(
            studio.range(of: ".accessibilityHint(\"Hold a tone;", range: capAt.upperBound..<studio.endIndex),
            "the Capture button's hint moved — re-anchor this window (#454)")
        let action = String(studio[capAt.upperBound..<actionEnd.lowerBound])
        XCTAssertTrue(action.contains("AccessibilityNotification.Announcement(caption).post()"),
                      "the abort must be ANNOUNCED, and with `caption` itself: on every abort "
                      + "the button keeps its label, hint and value, so a VoiceOver user gets "
                      + "no change on the focused control and the new sentence is an unfocused "
                      + "sibling Text. A hand-written second string would drift from the "
                      + "visible one the first time either is reworded (#897)")
        XCTAssertTrue(action.contains("if controller.phase == .idle {"),
                      "gated on the ABORTED phase. begin() is synchronous, so .idle on this "
                      + "line means it aborted; a take that started sits on .capturing, where "
                      + "the button is REPLACED by Cancel — focus moves and speaks for itself, "
                      + "and announcing there would talk over it")
        XCTAssertFalse(action.contains("Announcement(\""),
                       "THE COUNTERWEIGHT, and it is placed BEFORE nothing it depends on so it "
                       + "can actually fire (#896's lesson): a STRING LITERAL inside the "
                       + "announcement is the drift this claim exists to prevent — it would "
                       + "still pass a naive \"is it announced\" check while saying something "
                       + "the screen does not")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    /// The caption's body, bounded by its LAST branch rather than by a character count.
    ///
    /// ⛔ #897 — BOTH CALLERS USED `prefix(N)` AND BOTH WERE ONE PROSE BLOCK FROM RED ON
    /// CORRECT CODE. `SourceText.codeOnly` blanks a comment's TEXT but keeps its leading
    /// whitespace, so at this nesting a stripped doc line still costs ~29 characters. Measured
    /// when this helper was written: 703 characters of headroom on the 2000 window and 1303 on
    /// the 2600 one — about 24 and 45 comment lines. In a repo that writes ⛔ blocks by the
    /// dozen that is not headroom, it is a countdown. The ninth claim did go red on its own
    /// correct code for exactly this, which is how the pattern was found.
    ///
    /// ⭐ THE GENERAL FORM OF THE #894 LESSON: bound a window by the thing it describes, never
    /// by a number someone guessed. A guessed bound does not fail when it is wrong — it fails
    /// later, on unrelated work, pointing at the wrong culprit.
    private func captionBody(of studio: String, from start: Range<String.Index>) throws -> String {
        let end = try XCTUnwrap(
            studio.range(of: "return \"Hold a tone for a few seconds;", range: start.upperBound..<studio.endIndex),
            "the caption's last branch moved — re-anchor this window (#454)")
        return String(studio[start.upperBound..<end.lowerBound])
    }

    private struct DoorAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DoorAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
