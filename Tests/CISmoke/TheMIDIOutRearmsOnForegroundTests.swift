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
// GRADING (§3): claims 1–2 name text this same commit writes — on the parent both
// are red as ONE absence (#486, the slice absent). Claim 3 is a COUNTERWEIGHT,
// green on both trees. Driven in Python against parent and worktree before push.
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
        let body = String(midi[fn.lowerBound...].prefix(300))
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
            gate, which can stay shut while MIDI still deserves its retry.
            """)
    }

    // MARK: - 3. COUNTERWEIGHT: readiness still gates every note

    /// Green on both trees. The re-arm is only honest because an un-created client
    /// can never be sent to — remove this guard and a failed create turns into
    /// silent sends into MIDIRef 0 instead of a visible re-arm.
    func testNotesStillRefuseWhileNotReady() {
        let midi = text("Sources/Echoelmusic/Audio/MIDIOutput.swift")
        guard !midi.isEmpty else { return }
        XCTAssertTrue(midi.contains("guard enabled, isReady, (0...127).contains(pitch)"), """
            noteOn no longer refuses while the port never came up — the #837 re-arm \
            story depends on unready meaning SILENT, not on sends into a zero ref.
            """)
    }
}
