// TheMonitorRefusesARateItCannotMeetTests.swift
// Echoel — #958. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1): every
// claim reads `Sources/Echoelmusic/Audio/AudioEngine.swift` through `SourceText.codeOnly`.
// Nothing here starts an engine; the defect is an ABORT inside Apple's code, which no test in
// this bundle could survive observing.
//
// ⭐ THE FOUNDER'S v10.79.435 LOG SETTLED A TWO-WAY QUESTION THAT #954b HAD WRITTEN DOWN, and
// it settled it AGAINST the fix that was shipped. The `on 3/5` rung printed:
//
//     edge 48000.0 Hz/1 ch, session 48000.0 Hz/1 ch, out 44100.0 Hz/2 ch
//
// The input side AGREED with the hardware — #954's substitution never fired — and the app
// aborted one rung later anyway. The disagreement is between the input edge and the MASTER
// GRAPH: `setupMasterEngine` wires that graph ONCE at launch from `outputNode.outputFormat` and
// never re-wires it. Feeding a 48 kHz input chain into a 44.1 kHz graph forces AVAudioEngine to
// place a converter on the INPUT node's own edge, and `false == isInputConnToConverter` is that
// assert by name. The rung was built to discriminate exactly these two, and one device run did.
//
// ⭐ AND THE SAME LOG NAMED WHY THE GRAPH WAS AT 44.1 kHz — through SILENCE, which is this
// repo's rung law working as designed. It reads `session: configure 1/4 — setCategory(.playback)`
// and then nothing more from that four-step ladder. Between rung 1/4 and rung 2/4 there is a
// single `try`, so `setCategory` threw; `prepareGraph`'s `catch` wrote only to `os_log`, which
// `echoel_diag.log` does not carry. Consequence: `setPreferredSampleRate(48000)` at rung 2/4
// never ran, the graph was built at the untouched 44.1 kHz, and the 48 kHz record route later
// collided with it. Claim 5 pins the breadcrumb that ends that silence.
//
// ⚠️ THE REPAIR ORDER IS DELIBERATE AND IS THE MOST IMPORTANT THING IN THIS FILE: make the
// HARDWARE follow the GRAPH, then REFUSE. Rebuilding the master graph under a live session
// would put a re-wire on the path that carries the whole instrument, for a defect the evidence
// says can be fixed with one session call. If iOS declines the rate, monitoring does NOT turn
// on — a reported refusal instead of an uncatchable abort, which is what the founder asked for
// ("Absturz beim Audio Input Monitor einschalten vermeiden"). A refusal is a visible loss; an
// abort is a dead app that loses the take as well.
//
// ⚠️ HONEST GRADING (§3). **9 assertion SITES** (⛔ a draft of this line said 10 — I replaced
// one `XCTAssert` with a `guard`+`XCTFail`+`XCTAssert` pair and predicted the count instead of
// re-running it; the fifth time a number in this bundle was written before it was measured) (Python, lines whose first token is
// `XCTAssert`; one sits inside a loop, so executed assertions are more — sites are what is
// countable). This file names no symbol the commit creates, so it COMPILES against the parent
// and every claim has a verdict there. Transcribed against `ca5ddec`: **8 RED on the parent,
// 0 on the worktree** — seven of this file's claims plus the neighbour pin #958 had to amend
// (`TheInputEdgeFollowsTheHardwareFormatTests`' "the raw format is read once", now two with
// both sites named). Claims 3 and 4 are GREEN on both and are COUNTERWEIGHTS in the strict
// #343 sense — they pin what this slice must NOT do (add a fourth `on 3/5` rung; number a
// terminator that RETURNS).
//
// ⛔ AND THE GRADING CAUGHT A VACUOUS ASSERTION OF MY OWN before it shipped: claim 2's
// read-back check was `contains("inFmt = input.inputFormat(forBus: 0)")`, a SUBSTRING of the
// declaration `var inFmt = …`, so it was green on a tree with no re-read at all (#367). It is
// positional now. That is the fourth time in this bundle that driving the predicate — rather
// than reading it — found the defect.
//
// ⚠️ WHAT THIS DOES NOT PROVE. That the rate reconciliation SUCCEEDS on his device. iOS may
// decline the graph's rate, in which case the monitor refuses and the log says so. It also does
// not prove why `setCategory(.playback)` threw at launch — claim 5 only makes the next log say
// it. Both are device questions, and this file is a source scan.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMonitorRefusesARateItCannotMeetTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    private func source() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.engine), encoding: .utf8))
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// claim 1 (THE FIX) — the input edge and the master graph are compared before the connect.
    func testTheRatesAreComparedBeforeTheInputIsConnected() throws {
        let code = try source()
        guard let check = code.range(of: "abs(inFmt.sampleRate - outFmt.sampleRate) > 1"),
              let connect = code.range(of: "masterEngine.connect(input, to: notchEQ") else {
            XCTFail("""
                No comparison of the input edge against the master graph's rate, or the input \
                connect is gone, in \(Self.engine). That comparison is the whole of #958: the \
                founder's log showed edge 48000 Hz against a 44100 Hz graph, and connecting \
                across that gap is what puts a converter on the input edge and aborts.
                """)
            return
        }
        XCTAssertTrue(check.upperBound <= connect.lowerBound, """
            The rate comparison sits AFTER the input connect. By then the converter is already \
            in the graph and the next `start()` aborts — a check after the fact reports a \
            crash it could have prevented.
            """)
    }

    /// claim 2 (THE FIX) — the session is asked for the GRAPH's rate, and what it GRANTED is
    /// read back. A preference is a request; only the granted number can face the assert.
    func testTheSessionIsAskedForTheGraphsRateAndTheGrantIsReadBack() throws {
        let code = try source()
        XCTAssertTrue(code.contains("setPreferredSampleRate(outFmt.sampleRate)"), """
            Nothing asks the session for the master graph's rate. The graph is wired ONCE at \
            launch and cannot follow the hardware, so the hardware has to follow it — that is \
            one session call, against a re-wire of the path the whole instrument runs on.
            """)
        // ⛔ THE FIRST DRAFT OF THIS ASSERTION WAS VACUOUS AND THE GRADING CAUGHT IT (#367).
        // It asked for `code.contains("inFmt = input.inputFormat(forBus: 0)")` — which is a
        // SUBSTRING of the DECLARATION `var inFmt = input.inputFormat(forBus: 0)` at the top
        // of the ON path. It was therefore GREEN on the parent tree, where no re-read exists
        // at all: a claim that cannot fail for the reason its name gives. The property is
        // POSITIONAL — the read must follow the request — so the check is too.
        guard let ask = code.range(of: "setPreferredSampleRate(outFmt.sampleRate)"),
              let readBack = code.range(of: "inFmt = input.inputFormat(forBus: 0)",
                                        range: ask.upperBound..<code.endIndex) else {
            XCTFail("""
                The granted rate is never read back AFTER the request.                 `setPreferredSampleRate` is a REQUEST; acting on the requested number instead                 of the granted one is how a fix reports success and aborts anyway.
                """)
            return
        }
        XCTAssertTrue(readBack.lowerBound > ask.upperBound, """
            The re-read does not follow the request. Reading before asking returns the OLD             rate, so the comparison below would pass on a number the session is about to             replace.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — the detail lines added inside step 3 are NOT rungs. A fourth
    /// `logMonitorOutcome("on 3/5` would redden `TheEngineLifecycleSpeaksInTheDiagLogTests`,
    /// whose equality there is deliberate (it detects the ON path collapsing its ~15 AVFAudio
    /// calls into one line), and would put three phantom steps into a five-step ladder.
    func testStepThreeStillHasExactlyOneRung() throws {
        let code = try source()
        XCTAssertEqual(occurrences(of: "logMonitorOutcome(\"on 3/5", in: code), 1, """
            Step 3 of the monitor ladder has more than one rung line. The rate detail belongs \
            INSIDE step 3, not as extra steps: the rung above already announced it, and the \
            sibling guard's equality on this needle is what detects a collapsed ON path.
            """)
    }

    /// claim 4 (COUNTERWEIGHT, and the one that keeps a refusal readable) — the exit terminator
    /// carries the ladder prefix and NO rung number. Without the prefix `diag-ladder` does not
    /// see a terminator at all and a log ending there reads as a DEATH at step 3, sending a
    /// triager after a crash that did not happen. With a number it would violate guard (c3):
    /// in a log, the walks-on form and the returns form are the same string.
    func testTheRefusalIsAnUnnumberedTerminatorOnTheLadderPrefix() throws {
        let code = try source()
        XCTAssertTrue(code.contains("\"on REFUSED — input "), """
            The rate refusal does not announce itself as an `on … REFUSED` terminator. A log \
            ending on an unrecognised line reads as a DEATH at step 3 (#907/#908) — the tool \
            would point the founder at an abort that never happened.
            """)
        for numbered in ["on 3/5 REFUSED", "on 4/5 REFUSED", "on 5/5 REFUSED"] {
            XCTAssertFalse(code.contains(numbered), """
                A terminator that RETURNS is numbered (`\(numbered)`). Guard (c3) forbids it: \
                a numbered skip that walks on and one that returns are the SAME STRING in a \
                log, so only an unnumbered terminator may rescue a short ladder.
                """)
        }
    }

    /// claim 5 (THE FIX, and the reason the cause took two builds to find) — the launch
    /// session failure speaks in the file the founder shares.
    func testTheLaunchSessionFailureReachesTheExportedLog() throws {
        let code = try source()
        XCTAssertTrue(code.contains("session: configure FAILED"), """
            `prepareGraph`'s catch still writes only to `os_log`, which `echoel_diag.log` does \
            not carry (#859: breadcrumb FIRST, os_log second). That is why the founder's log \
            showed `session: configure 1/4` and then silence — the rung law's own signal for a \
            death inside step 1 — while the consequence (no `setPreferredSampleRate`, so a \
            44.1 kHz graph under a 48 kHz record route) stayed invisible for two builds.
            """)
    }

    /// claim 6 (COUNTERWEIGHT) — the refusal hands the record route back and un-strands the
    /// engine, like every other failure exit on this path. A refusal that leaves the route
    /// raised silences the whole app, music included (#611/#625b).
    func testTheRefusalReleasesTheRouteAndRestoresTheEngine() throws {
        let code = try source()
        guard let refusal = code.range(of: "\"on REFUSED — input ") else {
            XCTFail("no rate refusal to check — claim 4 owns that failure")
            return
        }
        let tail = String(code[refusal.lowerBound...].prefix(700))
        XCTAssertTrue(tail.contains("releaseRecordRoute(.inputMonitoring)"), """
            The rate refusal returns without handing the record route back. The claim is \
            already registered by then, so the session stays raised for the rest of the run.
            """)
        XCTAssertTrue(tail.contains("restoreEngineIfStranded(wasRunning"), """
            The rate refusal returns without restoring the engine. The route claim above may \
            already have stopped it, so this exit would leave the WHOLE app silent — music \
            included — with only a monitor line to explain it (#625b).
            """)
    }
}
