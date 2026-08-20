// TheNotchIsSlewedAndMonitorOnlyTests.swift
// Echoel — the feedback notch ramps, holds, and lives in the monitor path only. #595.
//
// WHAT THIS GUARDS. The notch half of FeedbackGuard: `slewedNotchGainDB` (the pure
// slew brain), `MonitorTapWindow` (the 10.76.48 lock queue between the tap thread and
// the ~15 Hz guard tick), and the AudioEngine wiring joins — chain order
// input → notchEQ → [voiceTunePitch #599] → monitorMixer (the music never passes
// through the notch; the optional tune stage sits BEHIND it, never before), the tap
// installed only after every failure path, removed on the OFF path, and the band gain
// written ONLY through the slew. The engage condition is a JOIN of two independent
// signatures (`ducking && ringingBin`) so a loud clean note is never notched.
//
// ⚠️ HONEST LIMITS. 8 tests, 29 `XCTAssert*` statements (in file order,
// 5+3+4+4+4+4+3+2 — the two `XCTUnwrap`s in test 6 also fail their test and sit
// deliberately outside this count, which counts assertions, not failure points).
// ⛔ #658: this census read `28` and `5+3+4+4+4+3+3+2`, and BOTH halves were wrong —
// #655 added a fourth `XCTAssertEqual` to test 6 (the uniqueness check on the renamed
// `logMonitorOutcome("engine restart failed` anchor) and did not touch the header. The
// per-test split had it at test 7. Re-derive, do not re-type:
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'   # -> 29
// (the filter is not decoration: the first draft of this recipe said "30 lines, minus
// THIS comment block", and writing the comment moved the raw count to 32 — a recipe
// that its own edit falsifies is the #480 failure, one file later.)
// A census is a measurement with a date on it; the commit that changes the count owns it.
// Tests 1–4 are END-TO-END BEHAVIOUR on shipped pure types
// (`FeedbackGuard.slewedNotchGainDB`, `MonitorTapWindow`); tests 5–8 are SOURCE-TEXT
// SCANS of `AudioEngine.swift` — the graph calls sit on a `@MainActor` engine no test
// host can run honestly. What no test here can prove: that the notch SOUNDS right,
// that it takes the whistle and not the voice on a real speaker — the device probe
// (NEEDS-FOUNDER-VERIFY: speaker monitoring, provoke a howl, hear it die as a ramp).
// ⚠️ KNOWN BLIND SPOT (#595 reviewer F1): the tap-count scan covers AudioEngine.swift
// only. `MultiTrackRecorder.prepareForRecording(engine:)` taps the SAME node/bus and
// is invisible here — today unreachable (doorless + flag-gated off, #204); the
// mutual-exclusion requirement is written at BOTH `installTap` sites, and the #204
// door slice owns turning it into an enforced law (a scan here could not observe
// reachability, only text — it would be green through the exact collision it names).
//
// ⭐ GRADING (§3). This file names `MonitorTapWindow` and `slewedNotchGainDB`, both
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

    /// Chain order: the mic goes THROUGH the notch into the monitor mixer, and the old
    /// direct input→monitorMixer connect is gone — present, it would bypass the notch.
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
                                       in: engine), 2,
                       "the #595 build path AND the #599 setVoiceTune off-branch — "
                       + "sibling guard TheVoiceTuneSnapsToTheSessionKeyTests pins the "
                       + "same fact; the two counts must move together")
        XCTAssertEqual(codeOccurrences(of: "connect(input, to: monitorMixer", in: engine), 0,
                       "a surviving direct input→monitorMixer connect would bypass the notch "
                       + "— the mic reaches monitorMixer only through notchEQ (since #599 "
                       + "optionally via the voice-tune stage BEHIND the notch)")
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

    /// The engage condition and the slew: the notch requires the duck's signature
    /// (`if ducking,`) AND a dominant bin, and the band gain is written ONLY through
    /// `slewedNotchGainDB` — one slewed write, plus bare `= 0` resets.
    func testTheNotchEngagesOnlyWhileDuckingAndIsAlwaysSlewed() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "if ducking,", in: engine), 1,
                       "the notch must key off the duck's own verdict — two independent "
                       + "feedback signatures, so a loud clean note is never notched")
        XCTAssertEqual(codeOccurrences(of: "FeedbackGuard.ringingBin(", in: engine), 1)
        XCTAssertEqual(
            codeOccurrences(of: "notchGainDB = FeedbackGuard.slewedNotchGainDB(current: notchGainDB",
                            in: engine), 1,
            "the gain state must advance through the slew — a direct assignment would "
            + "be the audible step the slew law exists to prevent")
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
