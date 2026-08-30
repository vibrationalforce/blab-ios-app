// TheMIDIOutRearmsOnForegroundTests — pins #837.
//
// THE MEASURED EVENT (founder log v10.79.424, build 2542, the relaunch 5 s after a
// SIGABRT): the launch enable hit `midiout: client create failed (-2)` — a transient
// midiserver refusal while the daemon recovered — and the session then ran without
// MIDI out, because the only retriggers were an enable edge and a transport Play.
// The SAME log shows "scene: audio resumed" 30 s later: the foreground return is the
// user's natural recovery gesture and it was already reaching a handler — it just
// never re-poked MIDI. #837 adds `MIDIOutput.rearmIfDead()` (a guarded no-op in
// every healthy state) and calls it on the `.active` transition, OUTSIDE the
// audio-resume gate on purpose: that gate can stay shut (a deliberate stop wins)
// while MIDI out still deserves its retry.
//
// KIND (§1): SOURCE-TEXT SCANS. No CoreMIDI runs in a test host — instantiating
// MIDIOutput and flipping `enabled` would create a REAL client/port on the runner,
// so the behavioural half ("-2 heals on foreground") is a DEVICE PROBE, open,
// answered by a future log showing `re-arm after failed create` followed by
// `ready (virtual source 'Echoelmusic'…)`.
//
// GRADING (§3): claims 1–2 name text the #837 commit writes and claim 3 names the
// #838b dispose helper (the #838 reuse design it replaced is retracted in claim 3's
// doc block) — on each slice's parent the new needles are red as ONE absence per
// slice (#486). Claim 4 is a COUNTERWEIGHT, green on both trees. Driven in Python
// against parent and worktree before push.
//
// #364: nothing here forbids moving the call site — a redesign re-anchors claim 2
// in the same commit and pulls the #837 comments in both source files (#456).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMIDIOutRearmsOnForegroundTests: XCTestCase {

    private func text(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return SourceText.codeOnly(contents)
    }

    // MARK: - 1. The re-arm exists and is a guarded no-op in every healthy state

    func testTheRearmGuardsOnRouteAndReadiness() {
        let midi = text("Sources/Echoelmusic/Audio/MIDIOutput.swift")
        guard !midi.isEmpty else { return }
        guard let fn = midi.range(of: "func rearmIfDead()") else {
            return XCTFail("""
                MIDIOutput.rearmIfDead() is gone — the measured -2 launch failure \
                (v10.79.424 relaunch) then stays dead for the whole session again. \
                If the retry moved, re-anchor this claim in the same commit (#456).
                """)
        }
        // ⛔ #898: this was `.prefix(300)` and it had a MEASURED margin of 140 characters —
        // five to ten comment lines from red on correct code, because `codeOnly` keeps a
        // blanked comment's indentation. A line budget counts CODE, so prose above the
        // assertions cannot walk them out of the window. Needles land at 4 code lines; 12 is
        // the budget. (An end ANCHOR would be better still, but this function has no stable
        // one to name — see `SourceText.codeWindow`.)
        let body = SourceText.codeWindow(midi, from: fn.lowerBound, lines: 12)
        XCTAssertTrue(body.contains("guard enabled, !isReady else { return }"), """
            The re-arm lost its healthy-state guard. Without BOTH conjuncts it either \
            opens a port the routing said not to (route off) or re-runs client \
            creation on a live port (already ready) on every foreground return.
            """)
        XCTAssertTrue(body.contains("startIfNeeded()"), """
            The re-arm no longer routes through startIfNeeded() — the one port-open \
            path that reads the persisted MPE/expression prefs first (#713/#714). A \
            second creation path would fork the lifecycle this file spent #713–#716 \
            unifying.
            """)
    }

    // MARK: - 2. The foreground transition actually calls it

    func testTheActiveTransitionCallsTheRearm() {
        let app = text("Sources/Echoelmusic/EchoelmusicApp.swift")
        guard !app.isEmpty else { return }
        XCTAssertEqual(app.components(separatedBy: "midiOut.rearmIfDead()").count - 1, 1, """
            Exactly ONE foreground re-arm call is expected in the app entry — zero \
            means the #837 heal is gone; two means a second lifecycle owner appeared \
            (the BLE-3 class of defect).
            """)
        guard let resumed = app.range(of: "EchoelCrashLog.breadcrumb(\"scene: audio resumed\")"),
              let rearm = app.range(of: "midiOut.rearmIfDead()") else {
            return XCTFail("""
                The audio-resumed breadcrumb or the re-arm call is gone from \
                EchoelmusicApp — re-anchor this ordering claim (§4).
                """)
        }
        XCTAssertTrue(resumed.lowerBound < rearm.lowerBound
                      && app.distance(from: resumed.lowerBound, to: rearm.lowerBound) < 900, """
            The re-arm no longer sits in the .active transition beside the resume \
            gate. It must run on the SAME gesture the founder's log shows healing \
            audio ("scene: audio resumed", 30 s after the -2) — and OUTSIDE the \
            gate, which can stay shut while MIDI still deserves its retry. (The 900 \
            is a bounded window over stripped code — ~200 chars at writing; if \
            legitimate code grew between gate and call, widen it here, #364.)
            """)
    }

    // MARK: - 3. A failed attempt leaves the TRUE launch state behind (#838/#838b)

    /// #837 made retries more frequent, and its review measured the cost: a retry
    /// after a port/source-stage failure re-ran the CLIENT create into a live ref —
    /// one leaked midiserver connection per attempt. ⛔ #838's first fix REUSED
    /// nonzero refs and the follow-up review refuted it: nothing anywhere resets a
    /// ref, so one stale client (the daemon dying mid-sequence is the likeliest
    /// cause of a half-built state) would be reused forever — a permanent-failure
    /// trap where the old code leaked but recovered. The shipped design is ATOMIC:
    /// a later-stage failure disposes the half-built lifecycle and nulls all refs.
    func testALaterStageFailureDisposesTheHalfBuiltLifecycle() {
        let midi = text("Sources/Echoelmusic/Audio/MIDIOutput.swift")
        guard !midi.isEmpty else { return }
        // THREE: the declaration line contains the same substring as a call — the
        // Python drive caught this claim asserting 2 and being red on the correct
        // tree (#408, the decl-substring hazard, caught before CI ever saw it).
        XCTAssertEqual(midi.components(separatedBy: "disposeHalfBuiltLifecycle()").count - 1, 3, """
            One declaration + TWO later-stage failure calls (port, source) is the \
            #838b shape. Fewer calls restores either the per-retry leak or the \
            stale-ref trap; a third create stage brings its own call.
            """)
        guard let helper = midi.range(of: "private func disposeHalfBuiltLifecycle()") else {
            return XCTFail("""
                The dispose helper is gone. A later-stage failure must return the \
                lifecycle to the true launch state (dispose + all three refs zeroed) \
                or retries either leak or reuse a stale client forever (#838b). If \
                redesigned, re-anchor this claim in the same commit (#456).
                """)
        }
        let body = String(midi[helper.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("MIDIClientDispose(client)"), """
            The helper no longer disposes the client — zeroing without disposing is \
            the #837-review leak again, one midiserver connection per failed retry.
            """)
        for reset in ["client = 0", "outputPort = 0", "virtualSource = 0"] {
            XCTAssertTrue(body.contains(reset), """
                The helper no longer resets `\(reset)` — a nonzero ref survives into \
                the next attempt, which is the stale-ref trap the #838b review \
                refuted the reuse design over.
                """)
        }
    }

    // MARK: - 4. COUNTERWEIGHT: readiness still gates every note

    /// Green on both trees. The re-arm is only honest because an un-created client
    /// can never be sent to — remove this guard and a failed create turns into
    /// silent sends into MIDIRef 0 instead of a visible re-arm.
    func testNotesStillRefuseWhileNotReady() {
        let midi = text("Sources/Echoelmusic/Audio/MIDIOutput.swift")
        guard !midi.isEmpty else { return }
        // ≥ 2, not `contains` (review LOW, #367): the needle sits in BOTH noteOn and
        // noteOff — a bare contains stayed green if one of the two lost its guard,
        // green for a reason other than this message.
        XCTAssertGreaterThanOrEqual(
            midi.components(separatedBy: "guard enabled, isReady, (0...127).contains(pitch)").count - 1,
            2, """
            noteOn/noteOff no longer BOTH refuse while the port never came up — the \
            #837 re-arm story depends on unready meaning SILENT, not on sends into a \
            zero ref.
            """)
    }
}
