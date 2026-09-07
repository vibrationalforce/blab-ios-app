// TheNotchIsSlewedAndMonitorOnlyTests.swift
// Echoel — the feedback notches ramp, hold, and live in the monitor path only. #595/#848.
//
// WHAT THIS GUARDS. The notch half of FeedbackGuard: `slewedNotchGainDB` (the pure
// slew brain), `MonitorTapWindow` (the 10.76.48 lock queue between the tap thread and
// the ~15 Hz guard tick), and the AudioEngine wiring joins — chain order
// input → notchEQ → [voiceTunePitch #599] → monitorMixer (the music never passes
// through the notch; the optional tune stage sits BEHIND it, never before), the tap
// installed only after every failure path, removed on the OFF path, and every band
// gain written ONLY through the slew.
// ⛔ #848 RETIRED THE `ducking && ringingBin` JOIN this header praised: the notch is
// PREVENTIVE now — the FFT runs on every guard tick and `HowlDetector`'s four-signature
// join (dominance · persistence · growth · no harmonic/subharmonic partner, pinned
// END-TO-END by `AHowlIsCaughtBeforeItIsHeardTests`) is what keeps a loud clean note
// un-notched, at low level, before audibility (founder: "es soll erst gar kein Piepsen
// entstehen"). Four dynamic bands instead of one; the duck is the broadband last resort.
//
// ⚠️ HONEST LIMITS. 10 tests, 41 `XCTAssert*` statements (in file order,
// 5+3+4+4+4+4+4+2+5+6 — the two `XCTUnwrap`s in test 6 also fail their test and sit
// deliberately outside this count, which counts assertions, not failure points;
// #848 rewrote test 7 from 3 to 4, #848b appended test 9, #850 appended test 10,
// each owning its census per the rule below).
// ⛔ #658: this census read `28` and `5+3+4+4+4+3+3+2`, and BOTH halves were wrong —
// #655 added a fourth `XCTAssertEqual` to test 6 (the uniqueness check on the renamed
// `logMonitorOutcome("engine restart failed` anchor) and did not touch the header. The
// per-test split had it at test 7. Re-derive, do not re-type:
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'   # -> 29
// (the filter is not decoration: the first draft of this recipe said "30 lines, minus
// THIS comment block", and writing the comment moved the raw count to 32 — a recipe
// that its own edit falsifies is the #480 failure, one file later.)
// A census is a measurement with a date on it; the commit that changes the count owns it.
// Tests 1–4, 9 and 10 are END-TO-END BEHAVIOUR on shipped pure types
// (`FeedbackGuard.slewedNotchGainDB`, `MonitorTapWindow`, `sameBandHalfWidthHz`;
// test 10's last assertion is a labeled SOURCE-TEXT SCAN of the engine's freshness
// join); tests 5–8 are SOURCE-TEXT SCANS of `AudioEngine.swift` — the graph calls
// sit on a `@MainActor` engine no test host can run honestly. What no test here can prove: that the notch SOUNDS right,
// that it takes the whistle and not the voice on a real speaker — the device probe
// (NEEDS-FOUNDER-VERIFY BLOCKED-BY-#1024: speaker monitoring, provoke a howl, hear it die as a ramp).
// ⚠️ KNOWN BLIND SPOT (#595 reviewer F1): the tap-count scan covers AudioEngine.swift
// only. `MultiTrackRecorder.prepareForRecording(engine:)` taps the SAME node/bus and
// is invisible here — today unreachable (doorless + flag-gated off, #204); the
// mutual-exclusion requirement is written at BOTH `installTap` sites, and the #204
// door slice owns turning it into an enforced law (a scan here could not observe
// reachability, only text — it would be green through the exact collision it names).
//
// ⭐ GRADING of #848's rewrite (§3): test 7's four needles name wiring that commit
// creates (`howlDetector.observe(`, `applyNotchDefence`, the per-band slew write,
// `howlDetector.reset()`) — against its parent (27258b4) all four are red by ONE
// anchor absence (#486: the wiring did not exist), never for test 7's named reasons.
// Every other test is untouched and green on both trees. Driven by transcription (§0);
// the census above moved 29→30 in the same commit.
//
// ⭐ GRADING of #848b (§3): test 9 is a FORWARD guard — `sameBandHalfWidthHz` is
// created by the same commit, so against its parent (fa21d28) the file does not
// compile and no assertion has a verdict there; all five expectations were derived
// by algebra and re-driven in Python against the worktree (§0, #442). Tests 1–8 are
// COUNTERWEIGHTS for this slice: the predicate #848b widened (engaged-or-releasing,
// windowed match) sits between test 7's needles, none of which pin it.
//
// ⭐ GRADING of #850 (§3): test 10 is a FORWARD guard — `writeStamp` is created by
// the same commit, so against its parent (96fa9d0) the file does not compile and no
// assertion has a verdict there; the stamp algebra was driven in Python against the
// worktree, and the one scan needle counts exactly 1 there. Tests 1–9 are
// COUNTERWEIGHTS: #850 adds one condition ahead of `howlDetector.observe(`, whose
// count in test 7 is unchanged.
//
// ⭐ GRADING of the original #595 commit (historical). This file names `MonitorTapWindow` and `slewedNotchGainDB`, both
// created by this same commit — against the parent tree the file DOES NOT COMPILE, so
// no assertion has a verdict there (§3's exact wording; hand-transcribed instead: the
// slew and window logic were re-driven in Python against the worktree). All join
// assertions are FORWARD guards; the duck assertions in test 8 are COUNTERWEIGHTS
// (green on both trees — the point is that #595 did not disturb the level half).
// Stripper: all 11 source needles measured raw vs stripped on the worktree — every
// count identical raw and stripped → PROPHYLAKTISCH (0 of 11 verdicts flip). Kept
// stripped anyway: the #595 comments name the members freely, and the needles carry
// call/argument syntax precisely so prose mentions cannot collide later.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheNotchIsSlewedAndMonitorOnlyTests: XCTestCase {

    // MARK: - 1–2. The slew (END-TO-END, pure)

    /// Engaging is a RAMP: 0 → −24 in ±4 dB steps, six ticks, no overshoot, and the
    /// terminal value is a fixed point.
    func testEngagingRampsAndNeverOvershoots() {
        var g: Float = 0
        var trace: [Float] = []
        for _ in 0..<8 {
            g = FeedbackGuard.slewedNotchGainDB(current: g, target: -24)
            trace.append(g)
        }
        XCTAssertEqual(trace.prefix(6), [-4, -8, -12, -16, -20, -24],
                       "the engage ramp must descend in exact 4 dB steps")
        XCTAssertEqual(trace[6], -24, "at target the slew must be a fixed point")
        XCTAssertEqual(trace[7], -24)
        // From one step above target it lands exactly, never past.
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: -22, target: -24), -24)
        // Releasing ramps back up, same discipline.
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: -24, target: 0), -20)
    }

    /// Poison handling: a non-finite CURRENT restarts from 0 (one tick toward target);
    /// a non-finite TARGET reads as release; a degenerate step clamps to 0.1.
    func testNonFiniteInputsCannotPropagate() {
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: .nan, target: -24), -4,
                       "a poisoned state variable must restart from 0, not propagate NaN")
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: -24, target: .infinity), -20,
                       "a non-finite target must read as release (0)")
        XCTAssertEqual(FeedbackGuard.slewedNotchGainDB(current: 0, target: -1, stepDB: 0), -0.1,
                       "a zero step must clamp to 0.1, or the slew would freeze forever")
    }

    // MARK: - 3–4. The window (END-TO-END, lock queue)

    /// The window reports nothing until it has filled ONCE, then returns the latest
    /// `size` samples in time order, overwriting the oldest.
    func testTheWindowFillsOnceThenKeepsTheLatest() {
        let w = MonitorTapWindow(size: 64)
        var out = [Float](repeating: 0, count: 64)
        let chunk = (0..<48).map { Float($0) }
        chunk.withUnsafeBufferPointer { w.push($0.baseAddress!, count: 48) }
        XCTAssertFalse(w.copyLatest(into: &out),
                       "a part-filled window must refuse — a half window of zeros would "
                       + "hand the FFT a fabricated spectrum")
        let rest = (48..<70).map { Float($0) }
        rest.withUnsafeBufferPointer { w.push($0.baseAddress!, count: 22) }
        XCTAssertTrue(w.copyLatest(into: &out), "70 pushed samples must fill a 64 window")
        XCTAssertEqual(out.first, 6, "the oldest 6 samples must have been overwritten")
        XCTAssertEqual(out.last, 69, "the newest sample must be last (time order)")
    }

    /// The refusal edges: a mismatched buffer, and `clear()` re-arming the fill gate
    /// so a stale window from the LAST monitoring session cannot trigger a notch.
    func testTheWindowRefusalEdges() {
        let w = MonitorTapWindow(size: 64)
        var wrong = [Float](repeating: 0, count: 32)
        var right = [Float](repeating: 0, count: 64)
        let fill = [Float](repeating: 1, count: 64)
        fill.withUnsafeBufferPointer { w.push($0.baseAddress!, count: 64) }
        XCTAssertFalse(w.copyLatest(into: &wrong),
                       "a wrong-size buffer must refuse, not truncate")
        XCTAssertTrue(w.copyLatest(into: &right))
        w.clear()
        XCTAssertFalse(w.copyLatest(into: &right),
                       "clear() must re-arm the fill gate — a stale window surviving "
                       + "into the next session is exactly what clear() exists to prevent")
        XCTAssertEqual(MonitorTapWindow(size: 8).size, 64,
                       "the size floor (64) must hold — a tiny window cannot carry a spectrum")
    }

    // MARK: - 5–7. The wiring joins (SOURCE-TEXT)

    /// Chain order: the mic goes THROUGH the notch (and since #858 through the
    /// permanently wired tune stage) into the monitor mixer, and the old direct
    /// input→monitorMixer connect is gone — present, it would bypass the notch.
    /// ⛔ The notchEQ→monitorMixer count stood at 1 and went RED with #599, which added
    /// the voice-tune off-branch's restore of the same connect (setVoiceTune) — #599
    /// applied the §4 move-the-guard discipline to its OWN file and never grepped THIS
    /// sibling for the shorter substring needle. Found by the pre-release sweep, one
    /// commit later; the red hid under #396 the whole time (#445 — absence from the
    /// run log proves nothing). Both sites keep the notch FIRST in the chain.
    func testTheNotchSitsInsideTheMonitorChain() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "connect(input, to: notchEQ, format: inFmt)",
                                       in: engine), 1)
        XCTAssertEqual(codeOccurrences(of: "connect(notchEQ, to: monitorMixer, format: inFmt)",
                                       in: engine), 0,
                       "RETIRED by #858: the notch reaches monitorMixer only through "
                       + "the permanently wired (possibly bypassed) voice-tune stage — "
                       + "a direct connect returning means the graph re-split into the "
                       + "two shapes whose live rewire five device logs killed. Sibling "
                       + "guard TheVoiceTuneSnapsToTheSessionKeyTests pins the same "
                       + "count; the two must move together")
        XCTAssertEqual(codeOccurrences(of: "connect(input, to: monitorMixer", in: engine), 0,
                       "a surviving direct input→monitorMixer connect would bypass the notch "
                       + "— the mic reaches monitorMixer only through notchEQ, then the "
                       + "voice-tune stage BEHIND it (permanent since #858, bypassed when off)")
        XCTAssertEqual(codeOccurrences(of: "connect(notchEQ, to: masterMixer", in: engine), 0,
                       "the notch must NEVER touch the master path — monitor only, "
                       + "like the duck (the music does not pass through it)")
    }

    /// Tap discipline: ONE tap on the engine's input, installed AFTER the last failure
    /// path (so no `return false` can leave a live tap), removed on the OFF path.
    func testTheTapInstallsAfterEveryFailurePath() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "input.installTap(onBus: 0,", in: engine), 1)
        // ⛔ #655 — THIS ANCHOR WAS DEAD FOR FIVE COMMITS AND THIS TEST WAS RED ON A
        // CORRECT TREE THE WHOLE TIME. It read `"Input monitoring: engine restart failed"`.
        // #650 routed every monitoring outcome through `logMonitorOutcome`, which OWNS the
        // `"Input monitoring: "` prefix and prepends it — so the call site now reads
        // `logMonitorOutcome("engine restart failed (\(error))")` and the old literal
        // matches nothing. `XCTUnwrap` on nil is a FAILURE, and `source()` below only skips
        // when `Sources/` is absent, so nothing skipped it.
        //
        // ⭐ WHY NOBODY NOTICED, and it is the expensive half: #396 makes CI/CD report
        // `failure` on EVERY push, and #445 established that a test name MISSING from the
        // job log proves nothing about whether it ran. A guard that goes red inside that
        // fog is indistinguishable from the host dying. The lesson is not "re-anchor" —
        // it is that a slice which RENAMES a logged string must grep the blocking bundle
        // for the old literal in the SAME commit (#456), because no gate will say so.
        //
        // Anchored on the surviving call, whose uniqueness is asserted rather than assumed
        // (#408, `Tests/CISmoke/CLAUDE.md` §: checking uniqueness is part of writing the
        // scan). The `logMonitorOutcome(` prefix is what makes it a CALL and not prose.
        XCTAssertEqual(codeOccurrences(of: "logMonitorOutcome(\"engine restart failed",
                                       in: engine), 1,
                       "the restart-failure exit is no longer a single named call — "
                       + "re-anchor (#408/#454) rather than widening the needle")
        let restartFailure = try XCTUnwrap(
            engine.range(of: "logMonitorOutcome(\"engine restart failed"),
            "the restart-failure path was renamed — re-anchor (#454)")
        let tapInstall = try XCTUnwrap(engine.range(of: "input.installTap(onBus: 0,"))
        XCTAssertTrue(restartFailure.lowerBound < tapInstall.lowerBound,
                      "the tap must be installed AFTER the engine-restart failure exit — "
                      + "installed before it, that `return false` leaves a live tap on a "
                      + "bus the next ON would tap again, which traps")
        XCTAssertEqual(codeOccurrences(of: "masterEngine.inputNode.removeTap(onBus: 0)",
                                       in: engine), 1,
                       "the OFF path must remove the tap — a monitoring session must not "
                       + "leave the input tapped")
    }

    /// #848 — the engage path and the slew. The detector (not the duck) decides, it is
    /// consulted on EVERY guard tick, and every band's gain advances ONLY through the
    /// slew. (The pre-#848 needles here were `if ducking,` and `FeedbackGuard.ringingBin(`
    /// — the reactive join this slice retired; asserting their absence would be a
    /// negative scan over prose that legitimately cites them as history, #491.)
    func testTheNotchIsDetectorDrivenAndAlwaysSlewed() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "howlDetector.observe(", in: engine), 1,
                       "exactly ONE consult of the early detector per guard tick — the "
                       + "four-signature join is what keeps a loud clean note un-notched "
                       + "now that the duck no longer gates the notch")
        XCTAssertEqual(codeOccurrences(of: "applyNotchDefence(candidates:", in: engine), 2,
                       "one declaration + one call: every candidate reaches the bands "
                       + "through the ONE assignment/slew path")
        XCTAssertEqual(
            codeOccurrences(of: "notchBands[i].gainDB = FeedbackGuard.slewedNotchGainDB(",
                            in: engine), 1,
            "every band's gain state must advance through the slew — a direct "
            + "assignment would be the audible step the slew law exists to prevent")
        XCTAssertEqual(codeOccurrences(of: "howlDetector.reset()", in: engine), 1,
                       "monitoring OFF/rollback must forget the detector's persistence — "
                       + "a half-built track must never survive into the next world "
                       + "(both exits funnel through resetNotchDefence)")
    }

    // MARK: - 8. Counterweight — the duck (the level half) is undisturbed

    /// #595 added the frequency half; the level half must still read exactly as #298
    /// wired it. Green on both trees — that is the point (§2 #343).
    func testTheDuckHalfIsUndisturbed() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "FeedbackGuard.gainReductionDB(rmsHistory: monitorLevelHistory)",
                                       in: engine), 1)
        XCTAssertEqual(codeOccurrences(of: "monitorMixer.outputVolume = base * factor",
                                       in: engine), 1)
    }

    // MARK: - 9. The same-band window (#848b, END-TO-END, pure)

    /// `sameBandHalfWidthHz` is the WIDER of two arms. Every expectation here is exact
    /// Float algebra (#442): binWidth 20, ratio 0.05, floor 1.5 → the absolute arm is
    /// 30 (= 20 · 1.5), the relative arm is f · 0.05, and the crossover sits at exactly
    /// f = 600 (600 · 0.05 = 30). Degenerate inputs collapse their arm to 0 — a fully
    /// degenerate call returns a 0 window, which no positive distance satisfies.
    func testTheSameBandWindowIsTheWiderOfItsTwoArms() {
        XCTAssertEqual(FeedbackGuard.sameBandHalfWidthHz(
            frequencyHz: 100, binWidthHz: 20, ratio: 0.05, binFloor: 1.5), 30,
            "below the crossover the bin floor governs (F1: jitter > percentage)")
        XCTAssertEqual(FeedbackGuard.sameBandHalfWidthHz(
            frequencyHz: 1000, binWidthHz: 20, ratio: 0.05, binFloor: 1.5), 50,
            "above the crossover the percentage governs")
        XCTAssertEqual(FeedbackGuard.sameBandHalfWidthHz(
            frequencyHz: 600, binWidthHz: 20, ratio: 0.05, binFloor: 1.5), 30,
            "at the exact crossover both arms agree")
        XCTAssertEqual(FeedbackGuard.sameBandHalfWidthHz(
            frequencyHz: .nan, binWidthHz: 20, ratio: 0.05, binFloor: 1.5), 30,
            "a poisoned frequency collapses ONLY the relative arm")
        XCTAssertEqual(FeedbackGuard.sameBandHalfWidthHz(
            frequencyHz: .nan, binWidthHz: 0, ratio: 0.05, binFloor: 1.5), 0,
            "fully degenerate inputs yield a 0 window — nothing false-matches")
    }

    // MARK: - 10. A frozen window cannot feed the detector (#850, F4)

    /// Assertions 1–5 are END-TO-END on `MonitorTapWindow.writeStamp` (the freshness
    /// signal); assertion 6 is a SOURCE-TEXT SCAN pinning the engine's join on it.
    /// The failure this retires: an engine halt that bypasses `stop(reason:)` leaves
    /// the guard tick observing one frozen spectrum forever — a track whose growth
    /// already crossed the threshold then re-emits a candidate every tick and parks a
    /// band at −24 dB until the next start (#848 review, F4, registered then).
    func testAFrozenWindowCannotFeedTheDetector() throws {
        let window = MonitorTapWindow(size: 64)
        let before = window.writeStamp()
        var samples = [Float](repeating: 0.25, count: 64)
        samples.withUnsafeBufferPointer { p in
            window.push(p.baseAddress!, count: p.count)
        }
        let afterPush = window.writeStamp()
        XCTAssertNotEqual(before, afterPush,
                          "a push must move the stamp — it IS the 'new audio arrived' signal")
        var out = [Float](repeating: 0, count: 64)
        XCTAssertTrue(window.copyLatest(into: &out),
                      "the window filled in one push of exactly `size` samples")
        XCTAssertEqual(window.writeStamp(), afterPush,
                       "READING must not move the stamp — a reader that bumps it would " +
                       "hide the very freeze it exists to expose")
        samples.withUnsafeBufferPointer { p in
            window.push(p.baseAddress!, count: p.count)
        }
        XCTAssertNotEqual(window.writeStamp(), afterPush,
                          "every push moves it again — monotone identity of writes")
        let stampBeforeClear = window.writeStamp()
        window.clear()
        XCTAssertEqual(window.writeStamp(), stampBeforeClear,
                       "clear() must NOT reset the stamp — resetting could alias a value " +
                       "a reader still remembers, turning a frozen window back into a fresh one")
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "if stamp != lastSpectrumStamp,", in: engine), 1, """
            The freshness join is gone from the notch half — without it the detector \
            observes a frozen spectrum every tick after a non-stop(reason:) engine \
            halt, and a crossed-threshold track parks a band at full depth. If the \
            join was redesigned, re-anchor here in the same commit (#456).
            """)
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct NotchAnchorMissing: Error { let reason: String }

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
            throw NotchAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
