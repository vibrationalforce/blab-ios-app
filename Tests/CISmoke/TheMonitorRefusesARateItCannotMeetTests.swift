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
// The input side AGREED with the hardware and the app aborted one rung later anyway. The
// disagreement is between the input edge and the MASTER GRAPH: `setupMasterEngine` wires that
// graph ONCE at launch from `outputNode.outputFormat` and never re-wires it. Feeding a 48 kHz
// input chain into a 44.1 kHz graph forces AVAudioEngine to place a converter on the INPUT
// node's own edge, and `false == isInputConnToConverter` is that assert by name.
//
// ⛔ #958b — HOW #954's SUBSTITUTION IS RULED OUT, because #958 ruled it out INVALIDLY. It
// argued "edge == session, so the substitution never fired". That inference is backwards: when
// the substitution DOES fire it BUILDS `inFmt` from the session's rate, so afterwards the two
// agree BY CONSTRUCTION. Agreement is what a fired substitution looks like. The valid evidence
// is the ABSENCE of the `input format from session fallback` line, which that path logs
// unconditionally before assigning — and the founder's log does not contain it. Same
// conclusion, but reached from a fact instead of from a coincidence.
//
// ⚠️ AND THE VERDICT IS "FAVOURED", NOT "DECIDED". One log is one device, one route and one
// launch. It rules the master-graph mismatch IN as consistent with everything observed; it
// cannot rule every other cause OUT. #958's prose said "Ein Gerätelauf hat entschieden" and
// that was a stronger word than one run can carry.
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
// ⚠️ HONEST GRADING (§3) — REWRITTEN AT #958b, AND THE OLD ONE IS QUOTED BECAUSE IT WAS A
// blocker a reviewer had to find. It said "**8 RED on the parent, 0 on the worktree** — seven
// of this file's claims plus the neighbour pin", and neither half survived re-derivation: this
// file had SIX methods then, not seven, and a neighbour pin was counted into a figure whose
// own sentence said "this file". The UNIT was never stated either, so "8" could mean methods,
// claims or assertion sites — three different numbers. Both defects are the same one: a count
// written from memory instead of driven.
//
// DRIVEN (Python transcription of `SourceText.codeOnly` plus each predicate, run against
// `git show <rev>:AudioEngine.swift` for every tree):
//
//   | tree                  | RED test methods | of |
//   |-----------------------|------------------|----|
//   | ca5ddec (great-gp)    | 6                | 7  |
//   | 9fac52f (#958)        | 4                | 7  |
//   | 54fea65 (#958b)       | 1                | 7  |
//   | worktree (#958c)      | 0                | 7  |
//
// 15 assertion SITES (Python, lines whose first token is `XCTAssert`/`XCTFail`; one sits
// inside a loop, so executed assertions are more — sites are what is countable). This file
// names no symbol any of these commits creates, so it COMPILES against every older tree and
// each claim has a real verdict there.
//
// ⭐ THE FOUR STILL RED ON #958 ARE THE POINT OF ROUND TWO. #958 shipped the right IDEA —
// make the hardware follow the graph, then refuse — with a read-back off the input NODE, the
// one source this very method has already MEASURED to be stale (#823). On the founder's
// device that read returns the cached pre-request value, so the refusal fires whether or not
// iOS granted the rate: monitoring would simply never turn on again. Claims 2 and 2b hold
// that out, and they are RED on #958 by construction.
//
// ⭐ THE ONE STILL RED ON #958b IS THE POINT OF ROUND THREE, and it is a defect I introduced
// while fixing one. #958b's refusal path called `setPreferredSampleRate(0)` and the comment
// called that "handing the preference back". It is not: this app HOLDS a standing preference
// of `AudioConfiguration.preferredSampleRate` (48 kHz) from launch, and every buffer-duration
// calculation in `AudioConfiguration` assumes it. Zero CLEARS it, so a refusal would have left
// every later activation negotiating against no preference at all. Claim 6's first assertion
// is that regression guard. **A "restore" that writes a different value than the one that was
// held is not a restore** — and it was pinned by a guard I wrote in the same commit, which is
// how it survived my own grading and needed a reviewer.
//
// GREEN on ALL FOUR trees, and therefore a COUNTERWEIGHT in the strict #343 sense:
// `testStepThreeStillHasExactlyOneRung`. It pins what this slice must NOT do — add a fourth
// `on 3/5` rung, which would both redden `TheEngineLifecycleSpeaksInTheDiagLogTests` (its
// equality there detects the ON path collapsing its ~15 AVFAudio calls into one line) and put
// phantom steps into a five-step ladder. Claim 4's second half (no NUMBERED `REFUSED`) is a
// counterweight too, but its METHOD is red on the older trees because its first half is.
//
// ⛔ THREE NEIGHBOUR PINS WENT RED ACROSS THESE ROUNDS, EACH INSIDE THE COMMIT THAT MADE IT
// WRONG, AND TWO OF THEM I CAUSED MYSELF: `RecordRouteOwnershipTests` (releases 4 → 5) and
// `MonitoringCannotStrandTheEngineStoppedTests` (restore sites 4 → 5) from #958's new rate
// exit; `TheMonitoringSurvivesEngineRecoveryTests` (tune disarms 1 → 2) from #958c's recycle
// undo. Also amended: `TheInputEdgeFollowsTheHardwareFormatTests` went 1 → 2 at #958 and back
// to 1 at #958b, because the ARGUMENT for two was itself the defect. **The rule those four
// keep re-teaching: a new exit costs a count somewhere, and the failure messages already say
// so** — #631 wrote it down in two of these very files, one cycle before it happened again.
//
// ⛔ THE GRADING CAUGHT TWO VACUOUS ASSERTIONS OF MY OWN, one each in rounds one and two
// (round three's defect was not vacuity but a wrong VALUE — see the #958b block above).
// #958: claim 2's read-back was `contains("inFmt = input.inputFormat(forBus: 0)")`, a SUBSTRING of the
// declaration `var inFmt = …`, so it was green on a tree with no re-read at all (#367). #958b:
// the positional replacement compared `readBack.lowerBound > ask.upperBound` on a range that
// had ALREADY been searched from `ask.upperBound` — it could not fail. Claim 2 is now a
// POSITIVE check on the session read plus a NEGATIVE one on the node read, and both flip
// between the trees.
//
// ⚠️ WHAT THIS DOES NOT PROVE. That the rate reconciliation SUCCEEDS on his device. iOS may
// decline the graph's rate, in which case the monitor refuses and the log says so. AND — the
// sharper half, added #958c — that the abort is GONE. `session.sampleRate` is a fresher proxy,
// not the authority: if iOS renegotiates ASYNCHRONOUSLY it can report the new rate while the
// HAL has not settled, and `start()` at rung 4/5 runs ~7 ms later against a node whose real
// bus is still the old one. This NARROWS the window; it does not close it — the same
// retraction `#954b` already made about the same read. HYPOTHESIS #5 (`masterEngine.prepare()`
// then re-read the NODE) is what would close it, and claims 2 and the sibling count pin are
// deliberately written so that building it is a COUNT to raise, never a law to route around. It also does
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

    /// claim 2 (THE FIX) — the session is asked for the GRAPH's rate, and the GRANTED number
    /// is read from the SESSION. A preference is a request; only the granted value can face
    /// the assert — and the one place it must NOT be read from is the input node.
    func testTheGrantIsReadFromTheSessionAndNotFromTheStaleNode() throws {
        let code = try source()
        guard let ask = code.range(of: "setPreferredSampleRate(outFmt.sampleRate)") else {
            XCTFail("""
                Nothing asks the session for the master graph's rate. The graph is wired ONCE                 at launch and cannot follow the hardware, so the hardware has to follow it —                 that is one session call, against a re-wire of the path the whole instrument                 runs on.
                """)
            return
        }
        let after = String(code[ask.upperBound...])
        XCTAssertTrue(after.contains("let grantedRate = session.sampleRate"), """
            The granted rate is never read back from the SESSION after the request.             `setPreferredSampleRate` is a REQUEST; acting on the requested number instead of             the granted one is how a fix reports success and aborts anyway.
            """)
        // ⛔⛔ THE ONE THAT COST A REVIEW ROUND (#958 → #958b). #958's read-back was
        // `inFmt = input.inputFormat(forBus: 0)` — the input NODE, which is the single source
        // this same method has already MEASURED to be stale: the #823 comment ~150 lines above
        // says "the node can still hand back its placeholder right after the claim (the I/O
        // unit rebuilds lazily on `start()`)". Nothing between the request and the read starts
        // or prepares the engine, so the node returns its CACHED pre-request value — and the
        // refusal below then fires whether or not the grant happened. Net effect on exactly
        // the device the slice targets: monitoring never turns on. That is a fix that
        // introduces a new failure (#364), and only a NEGATIVE claim can hold it out.
        // ⚠️ Scoped to AFTER the request on purpose: the declaration `var inFmt =
        // input.inputFormat(forBus: 0)` at the top of the ON path is CORRECT and must stay.
        //
        // ⛔⛔ AND THE BAN IS CONDITIONAL, BECAUSE THE FLAT VERSION FORBADE CORRECT WORK
        // (#364, found by the #958b reviewer). The staleness argument has a PREMISE —
        // "nothing between the request and the read starts or prepares the engine".
        // `AudioEngine.swift`'s own HYPOTHESIS #5 is to call `masterEngine.prepare()` there,
        // which rebuilds the I/O unit WITHOUT starting it; after that the node is no longer
        // stale, and re-reading it becomes the AUTHORITATIVE confirmation that the hardware
        // really moved — the one thing `session.sampleRate` cannot give (it is a fresher
        // proxy, not the authority, which is why the async-renegotiation window survives).
        // A flat `XCTAssertFalse` would have gone red on that correct tree and taught the
        // next session to read around this file. The forbidden WINDOW ends where the
        // premise ends.
        let rebuildNeedles = ["masterEngine.prepare()", "masterEngine.start()",
                              "try masterEngine.start"]
        let windowEnd = rebuildNeedles
            .compactMap { after.range(of: $0)?.lowerBound }
            .min() ?? after.endIndex
        XCTAssertFalse(after[..<windowEnd].contains("input.inputFormat(forBus: 0)"), """
            The granted rate is read back from the input NODE after the request and BEFORE \
            anything rebuilds the I/O unit. This file measures that node to be STALE until \
            `start()` rebuilds it (#823), so the comparison runs on the pre-request value \
            and the monitor refuses even when iOS granted the rate — monitoring off forever \
            on the device this slice targets (#958 -> #958b). Either read \
            `session.sampleRate` (the party that grants), or call `masterEngine.prepare()` \
            FIRST and then re-read the node — that second form is SANCTIONED, and it is \
            HYPOTHESIS #5 in `AudioEngine.swift`. If you take it, the sibling count pin in \
            `TheInputEdgeFollowsTheHardwareFormatTests` goes from 1 to 2 in the same commit.
            """)
    }

    /// claim 2b (THE FIX) — the rebuilt connect format is validated on RATE **and** CHANNELS.
    /// #958 validated only the rate, so a node reporting 0 channels at a matching rate walked
    /// straight into `connect` and aborted — a new crash path opened by the crash fix.
    func testTheRebuiltFormatIsValidatedOnChannelsToo() throws {
        let code = try source()
        // ⚠️ #958c — HONEST ABOUT WHAT THIS CHECK IS: it is BELT-AND-BRACES, not the only
        // thing standing between a 0-channel edge and the abort. `AVAudioFormat(
        // standardFormatWithSampleRate:channels: 0)` returns nil, so the `guard let` would
        // fire anyway. The first version of this message claimed the explicit test PREVENTS
        // the crash; it does not — it makes the requirement legible at the site instead of
        // resting on a failable initialiser's documented behaviour, which is the house style
        // ("prefer explicit, readable code"). The pin still earns its place: it is what stops
        // a later refactor from swapping in a NON-failable construction and losing the check
        // silently. Overstating a guard's power is the expensive kind of comment here.
        XCTAssertTrue(code.contains("&& inFmt.channelCount > 0"), """
            The format rebuilt from the granted rate no longer states a usable CHANNEL count \
            as a condition. Today the failable initialiser also catches 0 channels, so this \
            is redundancy on purpose — it keeps the requirement legible at the site and \
            survives a swap to a construction that does NOT return nil. A 0-channel edge \
            reaching `masterEngine.connect` is the same uncatchable ObjC abort this slice \
            exists to prevent (#958's rate-only check was the hole; #958b closed it).
            """)
        XCTAssertTrue(code.contains("channels: inFmt.channelCount"), """
            The rebuilt format no longer keeps the NODE's channel count.             `session.inputNumberOfChannels` is clamped 1...2 elsewhere in this method, so             substituting it can force a stereo edge onto a mono input — manufacturing the             very converter this slice removes, on hardware that was healthy (#954).
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
        XCTAssertTrue(code.contains("\"on REFUSED — the session granted "), """
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
        guard let refusal = code.range(of: "\"on REFUSED — the session granted ") else {
            XCTFail("no rate refusal to check — claim 4 owns that failure")
            return
        }
        // ⛔ #958b: this used to be `.prefix(700)` and the repair pushed the last call to 720
        // — a byte window is a DATE, and it went stale in the commit that fixed the code it
        // guards. The exit path is bounded STRUCTURALLY: from the refusal line to the
        // `return false` that ends it. That cannot drift when the message grows.
        let rest = code[refusal.lowerBound...]
        let tail = rest.range(of: "return false").map { String(rest[..<$0.upperBound]) }
            ?? String(rest.prefix(1200))
        // ⛔ #958c: this pinned `setPreferredSampleRate(0)` and the ZERO WAS THE BUG. This app
        // HOLDS a standing preference of `AudioConfiguration.preferredSampleRate` (48 kHz),
        // set once at launch, and every buffer-duration calculation in that file assumes it.
        // Writing 0 CLEARS it — so the "restore" destroyed a value the app deliberately owns,
        // and the guard pinned the destruction. Restoring means putting back what was held.
        XCTAssertTrue(tail.contains("setPreferredSampleRate(AudioConfiguration.preferredSampleRate)"), """
            The rate refusal returns without RESTORING the process-wide sample-rate \
            preference. `setPreferredSampleRate` outlives this method: the app holds \
            `AudioConfiguration.preferredSampleRate` from launch and its latency maths assume \
            it, so leaving the declined rate in place — or clearing it to 0 — makes every \
            later activation negotiate against a number nobody owns.
            """)
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
