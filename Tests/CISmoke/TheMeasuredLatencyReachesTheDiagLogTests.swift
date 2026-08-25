// TheMeasuredLatencyReachesTheDiagLogTests.swift
// Echoel — #653: the app measured its own round-trip latency and showed it to nobody.
//
// WHAT THIS GUARDS. `AudioConfiguration.latencyStats()` builds a tidy report — sample rate,
// IO buffer, input latency, output latency, total, a target and a ✅/⚠️/❌ verdict. Measured
// before this slice: it had exactly ONE caller (`AudioEngine.prepareGraph`), and that caller
// wrote it to `log.audio`, which is `os_log` plus a write-only in-memory ring. Neither sink
// reaches `echoel_diag.log`, the file the founder exports. No view rendered the number either.
// `git grep -n 'breadcrumb(.*[lL]atency' -- Sources` returned NOTHING.
//
// ⛔ ONE SENTENCE OF THE #653 COMMIT BODY IS RETRACTED HERE: it said neither the founder
// nor this session could name ONE latency figure. `AudioInputPickerView.swift:259` renders
// "~150–250 ms" for a Bluetooth output route. That is a CLASS estimate, not a measurement
// of his hardware, so the slice's purpose stands — but the sentence as written was false,
// and it was false about a surface this very feature already ships.
//
// ⭐ THIS IS THE #650 HOLE ONE LAYER UP, AND NAMING THAT IS THE POINT. #650 found the input
// monitoring path fully instrumented into the unexportable sink and moved it to the breadcrumb
// file; the founder's monitoring failure was never a missing diagnosis, it was a diagnosis
// written where he could not read it. The latency report is the same shape: five slices of
// careful measurement, addressed to a console nobody attaches. The founder's literal ask is
// "Alle Latenzen und Kombinationen optimiert für Sessions" — and neither he nor this session
// could name ONE measured latency figure from his hardware.
//
// ⚠️ THE ROUTE IS PART OF THE MEASUREMENT. The same phone reports a different round-trip on
// the built-in mic, a wired interface and a Bluetooth headset (~150-250 ms on A2DP), and
// "Kombinationen" is the founder's word for exactly that. A latency number without its route
// cannot be compared against another line in the same log, which is why `route` is a required
// parameter and not an optional embellishment. The founder's device signal names an HI-X25BT —
// a Bluetooth headphone — so this is not hypothetical for the very next take.
//
// KIND (§1): MIXED, and claim 1 is the BEHAVIOURAL half — it calls `latencyLine` and asserts
// on the string it returns, so the formatting law is executed, not described. Claims 2-5 are
// source-text scans over the wiring, which needs a live `AVAudioSession`, a route and hardware
// that nothing here can provide. **DEVICE PROBE, open:** what the numbers actually ARE on the
// founder's phone, wired and over Bluetooth. That is the whole reason the line exists.
//
// ⛔ #654 — AND #653 SHIPPED A NUMBER THAT LIED IN FOUR WAYS. The audio review found two
// CRITICAL and two HIGH, all re-measured before acting, and all of them are the same failure:
// a measurement outranks prose, so an over-claiming figure is worse than no figure.
//   1. `total=` claimed to be the round trip. It is `in + out + ONE` buffer period; the
//      app-observable round trip needs at least two. Renamed `floor=`.
//   2. It omitted the PITCH STAGE while being addressed to `monitor on`.
//      `AudioInputPickerView` already warns "The pitch stage adds a little latency to the
//      monitor only" — so the number contradicted the app's own UI on the same feature, and
//      a number wins that argument. `tune=on|off` now states whether the stage is in chain.
//   3. The session CATEGORY was missing, in a line whose stated purpose is comparability.
//      `start` is `.playback` + A2DP; `monitor on` is `.playAndRecord` + `.defaultToSpeaker`
//      (+ `.allowBluetooth`/HFP mono only behind the #824 opt-in). Two incomparable
//      regimes, one stem, no field to tell them apart.
//   4. `in=0.0` was a fabrication on the MOST COMMON path — no input route means
//      `inputLatency == 0`, which is finite and non-negative, so the `?` mechanism could not
//      see it and the founder read a measurement that was never taken.
// Plus one defect this slice INTRODUCED into a neighbour: port names are the first
// externally controlled string this repo writes to the diagnostics file, and
// `EchoelCrashLog.looksLikeUnseenCrash` triggers on the bare substring "CRASH". A paired
// device named for it would auto-open the crash sheet on every later launch.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (24adff7), both trees, raw and
// stripped. Numbers written after the run.
// **Scan half — 9 verdicts: 3 REGRESSIONS, 6 COUNTERWEIGHTS.**
//   · REGRESSION — claims 3c, 3d and 6: the parent passes no category, no `inputAvailable`
//     and no tune state, which are exactly lies 3, 4 and 2.
//   · COUNTERWEIGHTS — the other six: the three call sites, the exportable sink, the route,
//     the surviving console report, and the #650 monitor-ON pairing. They are what stops a
//     later "cleanup" from undoing #653 while fixing #654.
//
// ⚠️ THE FOUR BEHAVIOURAL CLAIMS CANNOT BE GRADED AGAINST THE PARENT, and saying so is the
// §3 requirement rather than a defect: `latencyLine` has a different signature there and
// `sanitisedRoute` does not exist, so this file does not compile against 24adff7. All four
// were driven against a Python transcription and PASS — `floor=9.0ms` from 5.0+1.5+2.5 with
// `tune=on`; a NaN/negative set yielding `?` per field plus ` partial` and NO `tune=`; a
// no-input set yielding `in=n/a`, `floor=7.5ms` (NOT folding a phantom zero) and ` partial`;
// and a forged "CRASH Bandits" device name masked while the route survives.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH — 0 of 18
// scan verdicts flip** (9 claims × 2 trees). Every needle carries call syntax or an argument
// label, which is narrower than any prose quoting the bare name — the third consecutive
// measurement of that, and the reason the prediction is written after the run.
//
// ⭐ #657 ADDED CLAIM 7 AND CLOSED THE ITEM #655 REGISTERED RATHER THAN FIXED. The
// `engine reconfigured` call sat inside the observer's `if self.masterEngine.isRunning {`
// branch, which left open the exact failure its own comment promised to close: a headset
// connected while the engine is STOPPED took the `recoverEngine` path and emitted nothing,
// and `prepareGraph` is once-only, so the log's only latency line would then describe a
// configuration that is no longer live. The handler is entered for every configuration
// change; only the BRANCH depends on `isRunning`. One hoist.
//
// GRADING for #657, DRIVEN against the parent (4d8b477), both trees, raw and stripped:
// **12 scan verdicts: 1 REGRESSION, 11 COUNTERWEIGHTS.** The single regression is claim 7c
// (the call now precedes the gate); 7a and 7b — the two uniqueness assertions the ordering
// rests on — are green on both trees by design, which is what makes 7c mean anything. The
// four behavioural claims are unchanged and unaffected by this slice. Stripper again
// **PROPHYLAKTISCH — 0 of 24**.
//
// ⚠️ #364: emitting the line from MORE places (a take starting, an export, an interface
// swap) is expected and must never redden claim 2, which is why it is a floor. What is
// forbidden silently is routing this measurement back into a sink the founder cannot export,
// or dropping the route from the line.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMeasuredLatencyReachesTheDiagLogTests: XCTestCase {

    private static let engine = "Echoelmusic/Audio/AudioEngine.swift"
    private static let config = "Echoelmusic/Audio/AudioConfiguration.swift"

    // MARK: - 1: behavioural — the formatting law, executed

    /// 1a — a plausible wired set: the parts are reported and the floor is their sum.
    func testTheLineReportsThePartsAndTheirFloor() {
        let line = AudioConfiguration.latencyLine(
            reason: "monitor on",
            category: "AVAudioSessionCategoryPlayAndRecord",
            sampleRate: 48_000,
            ioBufferSeconds: 0.005,      // 5.0 ms
            inputSeconds: 0.001_5,       // 1.5 ms
            outputSeconds: 0.002_5,      // 2.5 ms
            inputAvailable: true,
            tuneStage: true,
            // #667: this fixture is the `monitor on` line, so it is the one that carries
            // stages. `notch` at 0 is deliberate — an AU that reports nothing is the case
            // #654 warned about, and the field has to render it rather than hide it.
            insertMilliseconds: [("notch", 0), ("tune", 21.33)],
            route: "Built-In Microphone→Speaker")
        // #667 — EXECUTED, not scanned. Claim 8 checks that the FIELD exists in the source;
        // only this can check what it RENDERS. A 0 must print as `notch=0.00`, because the
        // whole purpose of the field is to let one founder log answer "does this AU report a
        // real number or a zero?", and a hidden zero answers nothing.
        XCTAssertTrue(line.contains("inserts[notch=0.00,tune=21.33]ms"), """
            The insert field stopped rendering, or changed shape. It must name each stage and \
            print its raw AU-reported value — including a 0. Got: \(line)
            """)
        // And it must NOT move the floor. 5.0 + 1.5 + 2.5 = 9.0, with 21.33 ms of pitch stage
        // sitting right next to it in the same line and staying out of the sum (#654/#666).
        XCTAssertTrue(line.contains("floor=9.0ms"), """
            The AU-reported insert latency leaked into `floor=`. `floor` is a lower bound on \
            the HARDWARE path; folding in a self-reported figure that may be a meaningless 0 \
            would corrupt the one number the log already carries. Got: \(line)
            """)
        XCTAssertTrue(line.hasPrefix("latency: monitor on "), """
            The line no longer opens with `latency: <reason> `. The prefix is what makes the \
            measurement greppable in a founder log that also carries `monitor:`, `rPPG:` and \
            `launch` lines. Got: \(line)
            """)
        XCTAssertTrue(line.contains("cat=AVAudioSessionCategoryPlayAndRecord"), """
            The session CATEGORY is gone, and it is the field that decides whether two lines \
            can be compared at all (#654). `start` is measured under `.playback` with A2DP; \
            `monitor on` under `.playAndRecord` with `.defaultToSpeaker` (and, only behind \
            the #824 opt-in, `.allowBluetooth` — the HFP mono call codec). Same stem, same \
            format, incomparable regimes. Got: \(line)
            """)
        XCTAssertTrue(line.contains("sr=48000"), "sample rate missing or reshaped: \(line)")
        XCTAssertTrue(line.contains("buf=5.0"), "IO buffer missing or mis-scaled: \(line)")
        XCTAssertTrue(line.contains("in=1.5"), "input latency missing or mis-scaled: \(line)")
        XCTAssertTrue(line.contains("out=2.5"), "output latency missing or mis-scaled: \(line)")
        // 5.0 + 1.5 + 2.5 = 9.0.
        XCTAssertTrue(line.contains("floor=9.0ms"), """
            The floor is not the sum of the three parts. Got: \(line)
            """)
        XCTAssertFalse(line.contains("total="), """
            The figure calls itself `total=` again. It is NOT the round trip: it is hardware \
            in + out plus ONE buffer period, while the app-observable round trip needs at \
            least two (fill the input buffer, drain the output buffer) and the monitor \
            chain's own nodes on top. #654 renamed it `floor=` because that is what it always \
            measured, and a figure that overstates its own scope is worse than none — a \
            number outranks the prose warning in `AudioInputPickerView`. Got: \(line)
            """)
        XCTAssertFalse(line.contains(" partial"), """
            A complete set was marked partial. Got: \(line)
            """)
        XCTAssertTrue(line.contains("tune=on"), """
            The pitch stage is no longer reported. The monitor chain is \
            `input → notchEQ → [voiceTunePitch] → monitorMixer`, `AVAudioUnitTimePitch` is a \
            phase vocoder with real algorithmic delay, and NONE of it is in `floor=`. \
            `AudioInputPickerView` warns about it in prose on the same feature; a number that \
            silently omits it contradicts that warning and wins. Got: \(line)
            """)
        XCTAssertTrue(line.contains("route=Built-In Microphone→Speaker"), """
            The route is gone. A latency figure without the combination it was measured on \
            cannot be compared against another line in the same log. Got: \(line)
            """)
    }

    /// 1b — a session queried mid-teardown answers with anything. It must not print `nanms`.
    func testANonFiniteMeasurementDoesNotPoisonTheLine() {
        let line = AudioConfiguration.latencyLine(
            reason: "engine reconfigured",
            category: "AVAudioSessionCategoryPlayback",
            sampleRate: .nan,
            ioBufferSeconds: .nan,
            inputSeconds: -1,
            outputSeconds: 0.010,
            inputAvailable: true,
            tuneStage: nil,
            insertMilliseconds: [],
            route: "none→none")
        XCTAssertFalse(line.lowercased().contains("nan"), "non-finite leaked: \(line)")
        // ⛔ #654: this used to assert `!line.contains("-")`, which passed only because the
        // fixture's route had no hyphen — and the commit's OWN example route is
        // "Built-In Microphone", which does. It tested "no hyphen anywhere", not "no
        // negative", and would have gone spuriously red the moment the fixture got realistic.
        // A negative would render as `=-1.0`, so that is what is banned.
        XCTAssertFalse(line.contains("=-"), "a negative measurement leaked: \(line)")
        XCTAssertFalse(line.contains("inserts["), """
            An EMPTY stage list must omit the field entirely, not print `inserts[]ms`. This \
            line describes a reconfiguration with no monitor chain up; an empty bracket would \
            read as "measured, and there is nothing", which is a different fact (#667).
            """)
        XCTAssertTrue(line.contains("sr=?"), "an unusable sample rate must read `?`: \(line)")
        XCTAssertTrue(line.contains("buf=?"), "an unusable buffer must read `?`: \(line)")
        XCTAssertTrue(line.contains("in=?"), "a negative input latency must read `?`: \(line)")
        XCTAssertTrue(line.contains("out=10.0"), "the usable part was dropped: \(line)")
        XCTAssertTrue(line.contains("floor=10.0ms"), """
            The floor must sum the parts that ARE readable. Got: \(line)
            """)
        XCTAssertTrue(line.contains(" partial"), """
            An incomplete set is no longer marked. `buf=? in=? out=10.0 floor=10.0ms` reads \
            as a complete 10 ms path unless something says otherwise — the `?`s are adjacent, \
            which mitigates and does not fix it (#654).
            """)
        XCTAssertFalse(line.contains("tune="), """
            A line that is not about the monitor chain reported a pitch-stage state. `nil` \
            must omit the field, not render a default — a `tune=off` on the `start` line \
            would read as "the pitch stage is off in the monitor chain", which that line \
            knows nothing about.
            """)
    }

    /// 1c — #654's CRITICAL: "no input route" and "input measured at zero" are different facts.
    ///
    /// At `prepareGraph` the session is `.playback` unless a record route is needed, so there
    /// is no input and `inputLatency` reports 0 — finite and non-negative, so the `?`
    /// mechanism could not see it. The founder read "input latency measured at zero
    /// milliseconds" where the truth was "no input was configured". This is the most common
    /// path in the app, not an edge case.
    func testNoInputRouteIsNotReportedAsZeroLatency() {
        let line = AudioConfiguration.latencyLine(
            reason: "start",
            category: "AVAudioSessionCategoryPlayback",
            sampleRate: 48_000,
            ioBufferSeconds: 0.005,
            inputSeconds: 0,          // what a session with no input route actually answers
            outputSeconds: 0.002_5,
            inputAvailable: false,
            tuneStage: nil,
            insertMilliseconds: [],
            route: "none→Speaker")
        XCTAssertTrue(line.contains("in=n/a"), """
            A session with no input route reports `inputLatency == 0`, and printing that as \
            `in=0.0` claims a measurement that was never taken. Got: \(line)
            """)
        XCTAssertFalse(line.contains("in=0.0"), "the fabricated zero is back: \(line)")
        XCTAssertTrue(line.contains("floor=7.5ms"), """
            The floor must be over the parts that exist — 5.0 + 2.5 — and must NOT fold in a \
            zero for an input that was never measured. Got: \(line)
            """)
        XCTAssertTrue(line.contains(" partial"), """
            A line missing a whole half of the path is not complete. Got: \(line)
            """)
    }

    /// 1d — port names are the first EXTERNALLY CONTROLLED string this repo writes into the
    /// diagnostics file, and that file has a bare-substring trigger.
    func testAPairedDeviceNameCannotForgeACrashMarker() {
        let forged = AudioConfiguration.sanitisedRoute("Built-In Microphone→CRASH Bandits")
        XCTAssertFalse(forged.contains(EchoelCrashLog.crashMarker), """
            A paired device name can put `\(EchoelCrashLog.crashMarker)` into the diagnostics \
            file. `EchoelCrashLog.looksLikeUnseenCrash` returns true for ANY log containing \
            that bare substring, so every later launch would auto-open the crash sheet on a \
            session that never crashed — undiagnosable from the outside. Got: \(forged)
            """)
        XCTAssertTrue(forged.hasPrefix("Built-In Microphone→"), """
            Masking must not destroy the route itself; the point is still to say which \
            combination was measured. Got: \(forged)
            """)
        let long = AudioConfiguration.sanitisedRoute(String(repeating: "x", count: 400))
        XCTAssertLessThanOrEqual(long.count, 81, """
            An unbounded route name lands in a file `currentLog()` reads whole into one \
            String for the share sheet. Got \(long.count) characters.
            """)
    }

    // MARK: - 2-6: the wiring

    /// 2 — a FLOOR (#364). Emitting from more places is expected; emitting from none is the bug.
    func testTheLineIsEmittedFromTheEngine() throws {
        let code = try Self.codeText(Self.engine)
        let sites = Self.count(of: "AudioConfiguration.latencyBreadcrumb(reason:", in: code)
        // ⛔ #655: the count alone was satisfied by three copies of ONE reason, while the
        // message below promised three distinct questions. An assertion that cannot fail for
        // the reason its message states is #367 in the mirror, so the three reasons are
        // pinned individually — and the count stays as the floor that keeps a FOURTH free.
        for reason in ["\"start\"", "\"engine reconfigured\"", "\"monitor on\""] {
            XCTAssertTrue(code.contains("latencyBreadcrumb(reason: " + reason), """
                The `\(reason)` latency line is gone. The three are not interchangeable: \
                `start` says what the device costs at rest, `engine reconfigured` catches the \
                only change that happens with no user action, and `monitor on` is the one \
                addressed to the decision the founder is actually making. Dropping one is a \
                real decision — say which question stopped mattering.
                """)
        }
        XCTAssertGreaterThanOrEqual(sites, 3, """
            Only \(sites) `latencyBreadcrumb` call sites in `AudioEngine`; #653 wired THREE, \
            and each answers a different question: `start` (what does this device cost at \
            rest), `engine reconfigured` (a Bluetooth headset connecting is the only event \
            that changes the granted buffer with no user action), and `monitor on` (the \
            moment that decides whether monitoring is usable at all). Removing one is a real \
            decision — say which question stopped mattering.
            """)
    }

    /// 3 — the whole point: it must reach the sink the founder can EXPORT, with its regime.
    func testTheEmitterWritesToTheExportableSink() throws {
        let code = try Self.codeText(Self.config)
        guard let body = Self.body(of: "static func latencyBreadcrumb", in: code) else {
            return XCTFail("`latencyBreadcrumb` is no longer uniquely declared — re-anchor (#454).")
        }
        XCTAssertTrue(body.contains("EchoelCrashLog.breadcrumb"), """
            `latencyBreadcrumb` no longer writes to `EchoelCrashLog`. That is the ENTIRE \
            slice: `log.audio` is `os_log` plus a write-only in-memory ring, and neither \
            reaches `echoel_diag.log`. It is the same hole #650 closed for the monitoring path.
            """)
        // ⛔ #655: `contains("route:")` would have stayed green if a refactor introduced an
        // unrelated `let route: String` inside this body while dropping the ARGUMENT. Pinned
        // to the argument-plus-value form, which only the call can produce.
        // ⛔ #658: this was `||`, and that let the SHIPPING branch drop its route while the
        // macOS branch alone kept the claim green — the one arm no device ever runs holding
        // up an assertion about the one every device runs.
        // ⛔ #664 — AND #663 BROKE BOTH OF THESE ON A CORRECT TREE, in the same session that
        // repaired this exact defect class twice. It split the platform gathering out of
        // `latencyBreadcrumb` into `currentSessionLatency`, so this body became nine lines of
        // `v.`-prefixed forwarding: neither `route: routeName` nor `route: "macOS HAL"` is in
        // it any more, and `routeName` as an identifier is gone from `Sources/` entirely.
        // That is #456 — a guard over a changed surface must move in the SAME commit —
        // violated by the author of the two commits that enforced it. Nothing caught it:
        // `scripts/dead-needles.py` only reads `XCTUnwrap(range(of:))` and
        // `codeOccurrences(of:)`, and these are `XCTAssertTrue(contains(…))`. Widening that
        // script is registered, not done here (#665).
        // The two arms now live in the GATHERING, so that is what is anchored — and the
        // forwarding is pinned separately, because a breadcrumb that gathers correctly and
        // then drops the route on the floor would satisfy the arms alone.
        XCTAssertTrue(body.contains("route: v.route"), """
            `latencyBreadcrumb` stopped forwarding the gathered route to `latencyLine`. \
            `route=` is what makes two latency lines comparable — a number without the port \
            that produced it cannot be read against another (#653/#655/#658/#664).
            """)
        guard let gathering = Self.body(of: "private static func currentSessionLatency",
                                        in: code) else {
            return XCTFail("`currentSessionLatency` is no longer uniquely declared — re-anchor (#454).")
        }
        XCTAssertTrue(gathering.contains("route: inName + \"→\" + outName"), """
            The iOS/tvOS branch stopped building a route from the live port names. This is the \
            arm every device runs; #658 exists because the macOS arm alone once held this \
            claim green.
            """)
        XCTAssertTrue(gathering.contains("route: \"macOS HAL\""),
                      "the macOS branch stopped passing its route to the gathering (#658/#664).")
        XCTAssertTrue(body.contains("category:"), """
            The session category stopped being passed. Two lines measured under `.playback` \
            and `.playAndRecord` are not comparable, and comparability is why the line exists \
            (#654).
            """)
        XCTAssertTrue(body.contains("inputAvailable:"), """
            `inputAvailable` stopped being passed, so a session with no input route reports \
            `in=0.0` again — a measurement that was never taken (#654).
            """)
    }

    /// 4 — COUNTERWEIGHT. The console report was ADDED TO, not replaced.
    func testTheConsoleReportSurvives() throws {
        let config = try Self.codeText(Self.config)
        XCTAssertTrue(config.contains("static func latencyStats()"), """
            `latencyStats()` is gone. #653 deliberately kept BOTH: the report carries the \
            target and the verdict for someone with a console attached, the breadcrumb \
            carries the comparable one-liner for a shared log.
            """)
        let engine = try Self.codeText(Self.engine)
        XCTAssertTrue(engine.contains("log.audio(AudioConfiguration.latencyStats())"), """
            The console report is no longer logged at graph preparation. Two sinks, two readers.
            """)
    }

    /// 5 — the #650 pairing: the monitor-ON fact and its measurement must stay together.
    func testTheMonitorOnFactAndItsLatencySitTogether() throws {
        let code = try Self.codeText(Self.engine)
        // ⛔ #655 — UNIQUENESS IS PART OF WRITING THE SCAN, NOT OF REVIEWING IT
        // (`Tests/CISmoke/CLAUDE.md`, #408). Both anchors happened to be unique, so this was
        // latent rather than live — but `range(of:)` silently takes the FIRST match, and a
        // second occurrence would have made the ordering assertion below describe a pair
        // nobody chose. Two sibling guards in this bundle already assert this; this one did
        // not, in the same commit family that spent a paragraph on #408.
        for anchor in ["logMonitorOutcome(\"ON (gain ",
                       "AudioConfiguration.latencyBreadcrumb(reason: \"monitor on\""] {
            XCTAssertEqual(Self.count(of: anchor, in: code), 1, """
                `\(anchor)` no longer occurs exactly once, so the ordering check below would \
                silently compare the wrong pair. Re-anchor (#408) rather than accepting the \
                first match.
                """)
        }
        guard let onSite = code.range(of: "logMonitorOutcome(\"ON (gain "),
              let latency = code.range(of: "AudioConfiguration.latencyBreadcrumb(reason: \"monitor on\""),
              onSite.upperBound < latency.lowerBound else {
            return XCTFail("""
                The monitor-ON breadcrumb and its latency line are no longer both present with \
                the fact first — re-anchor claim 5 (#454). An extraction that finds nothing \
                would make the assertion below vacuously green.
                """)
        }
        // ⚠️ NOT A CHARACTER WINDOW. #652 measured the previous guard in this family at TEN
        // characters from a false red because it bounded a region with `suffix(600)`. The
        // question here is "does anything RETURN between the fact and its measurement", and a
        // `return` is the exact token that would separate them.
        //
        // ⚠️ WHAT IT DOES NOT PROVE, stated because a sibling guard already carries this
        // disclaimer and this one did not (#655): this is TEXTUAL adjacency, not control
        // flow. A `throw`, a `fatalError`, or the breadcrumb wrapped in a never-taken `if`
        // all pass. It also false-reds on any identifier merely CONTAINING `return`
        // (`returning`, `returnValue`) in the region — none today. The real guarantee is that
        // the two statements sit in one straight-line block, which a human read.
        let between = String(code[onSite.upperBound..<latency.lowerBound])
        XCTAssertFalse(between.contains("return"), """
            A `return` now sits between the "monitor ON" breadcrumb and its latency line, so \
            every successful start logs the fact and never its cost. The pair is the \
            deliverable.
            """)
    }

    /// 6 — #654. The monitor line must report the REAL pitch-stage state, not a placeholder.
    func testTheMonitorLineReportsTheActualTuneState() throws {
        let code = try Self.codeText(Self.engine)
        guard let range = code.range(of: "reason: \"monitor on\"") else {
            return XCTFail("the monitor-on latency call is gone — re-anchor claim 6 (#454).")
        }
        // Bounded at the call's own closing paren rather than by a character count (#652):
        // the argument list is exactly the region the question is about.
        guard let close = code[range.upperBound...].firstIndex(of: ")") else {
            return XCTFail("the monitor-on latency call is not closed — re-anchor (#454).")
        }
        let args = String(code[range.upperBound..<close])
        XCTAssertTrue(args.contains("tuneStage: voiceTuneEnabled"), """
            The monitor line no longer reports whether the pitch stage is in the chain — or \
            reports a literal instead of the engine's actual state. `voiceTuneEnabled` is the \
            only writer-owned flag for it (`setVoiceTune` owns the graph rewire), and \
            `floor=` deliberately excludes the node's own delay, so this field is the only \
            thing telling a founder that the figure is missing a phase vocoder. Got: \(args)
            """)
    }

    /// 7 — #657. The reconfigure line must fire whether or not the engine is RUNNING.
    ///
    /// #653 put this call inside the observer's `if self.masterEngine.isRunning {` branch,
    /// which left open the exact failure its own comment promised to close: a headset
    /// connected while the engine is STOPPED takes the `recoverEngine` path and emits
    /// nothing — and `prepareGraph` is once-only (`guard !graphPrepared`), so the log's ONLY
    /// latency line would then describe a configuration that is genuinely no longer live.
    /// The handler is entered for every configuration change; only the BRANCH depends on
    /// `isRunning`, so the call belongs above it.
    func testTheReconfigureLineIsNotGatedOnARunningEngine() throws {
        let code = try Self.codeText(Self.engine)
        guard let watchdog = Self.body(of: "private func registerConfigurationChangeWatchdog",
                                       in: code) else {
            return XCTFail("""
                `registerConfigurationChangeWatchdog` is no longer uniquely declared — \
                re-anchor claim 7 (#454). An extraction that returns nothing would make the \
                ordering assertion below vacuously green.
                """)
        }
        let call = "latencyBreadcrumb(reason: \"engine reconfigured\""
        let gate = "if self.masterEngine.isRunning {"
        // Uniqueness first, because `range(of:)` silently takes the FIRST match and the
        // ordering claim would then describe a pair nobody chose (#408).
        XCTAssertEqual(Self.count(of: call, in: watchdog), 1, """
            The reconfigure latency call no longer occurs exactly once in the watchdog — \
            re-anchor (#408) rather than accepting the first match.
            """)
        XCTAssertEqual(Self.count(of: gate, in: watchdog), 1, """
            The `isRunning` branch is no longer a single anchor in the watchdog — re-anchor \
            (#408).
            """)
        guard let callAt = watchdog.range(of: call), let gateAt = watchdog.range(of: gate) else {
            return XCTFail("watchdog anchors vanished between the count and the search (#454).")
        }
        XCTAssertTrue(callAt.lowerBound < gateAt.lowerBound, """
            The reconfigure latency line sits INSIDE (or after) the `isRunning` branch again. \
            A headset connected while the engine is stopped then emits no line at all, and \
            since `prepareGraph` runs once per launch the log's only latency figure would \
            describe a configuration that is no longer live — which is precisely what the \
            comment above the call claims to prevent. Put it above the branch.
            """)
        // ⚠️ WHAT THIS DOES NOT PROVE: textual position, not control flow. A `guard … else
        // { return }` inserted between the handler's entry and this call would still pass.
        // The real guarantee is that the two statements sit in one straight-line prologue,
        // which a human read (#655, same disclaimer as claim 5).
    }

    // MARK: - 8. #666 — the AU-reported insert latencies reach the LOG and nothing else

    /// #654 refused to print a measured pitch-stage figure and said reading `auAudioUnit.latency`
    /// is "its own slice, gated on someone verifying the value on a device". #666 is that slice,
    /// shaped so the gate stays CLOSED while the observation is collected: the value goes into
    /// `echoel_diag.log` and nowhere a user can see it. This test is what keeps those apart.
    func testTheInsertLatenciesAreObservedInTheLogAndClaimedNowhere() throws {
        let config = try Self.codeText(Self.config)
        let engine = try Self.codeText(Self.engine)

        // 8a — the field is PRINTED, and printed raw.
        guard let line = Self.body(of: "static func latencyLine", in: config) else {
            return XCTFail("`latencyLine` is no longer uniquely declared — re-anchor (#454).")
        }
        XCTAssertTrue(line.contains("inserts["), """
            `latencyLine` stopped printing the `inserts[…]` field. That field is the entire \
            #666 slice: it is the only way #654's gate ("verify the value on a device") can \
            be passed without asking the founder for a special probe.
            """)

        // 8b — and NOT folded into `floor=`. This is the whole safety property: `floor` is a
        // lower bound on the HARDWARE path, and adding an AU's self-report (which may be a
        // meaningless 0) into it would make the one number the log already carries worse.
        guard let floorFn = Self.body(of: "static func latencyFloorSeconds", in: config) else {
            return XCTFail("`latencyFloorSeconds` is no longer uniquely declared — re-anchor.")
        }
        XCTAssertFalse(floorFn.contains("insert"), """
            The AU-reported insert latencies were folded into `latencyFloorSeconds`. They must \
            not be: `floor=` is a lower bound on the hardware path, an `auAudioUnit.latency` of \
            0 is "the AU reports nothing" rather than "there is nothing", and mixing an \
            uninformative self-report into a measured sum is exactly the over-claim #654 \
            retracted four of.
            """)

        // 8c — no default, at BOTH signatures (#431/#440/#443).
        XCTAssertEqual(Self.count(of: "insertMilliseconds: [(String, Double)]", in: config), 2, """
            Expected the parameter declared exactly twice with NO default — on `latencyLine` \
            and on `latencyBreadcrumb`. A defaulted argument that no call site writes appears \
            in no diff, which is how a field silently stops being stated (#431/#440/#443).
            """)
        XCTAssertFalse(config.contains("insertMilliseconds: [(String, Double)] ="), """
            `insertMilliseconds` gained a default value. Every call site must state its own — \
            `[]` at session start MEANS "no monitor node exists yet", and a default would make \
            that statement indistinguishable from an omission.
            """)

        // 8d — every call site states it. Three breadcrumbs, three values.
        XCTAssertEqual(Self.count(of: "insertMilliseconds:", in: engine), 3, """
            Expected all three `latencyBreadcrumb` call sites to pass `insertMilliseconds:`. \
            Found \(Self.count(of: "insertMilliseconds:", in: engine)). If a fourth caller is \
            added it states its own value here too — that is the point of having no default.
            """)

        // 8e — the value is READ FROM THE NODES, not written down.
        guard let gather = Self.body(of: "var monitorInsertLatencyMilliseconds", in: engine) else {
            return XCTFail("the insert-latency gatherer is gone or duplicated — re-anchor (#454).")
        }
        XCTAssertEqual(Self.count(of: "auAudioUnit.latency", in: gather), 2, """
            The gatherer stopped asking the graph nodes what they report, or gained a third \
            stage without this guard moving with it (#456). A hardcoded figure here would be \
            the fabrication #654 refused to ship, only harder to notice because it would look \
            measured.
            """)
        XCTAssertTrue(gather.contains("guard isInputMonitoring else { return [] }"), """
            The gatherer stopped checking that monitoring is actually on. An unconnected node \
            reports 0, and a `notch=0.00` logged while the chain is DOWN reads as a measurement \
            of a running chain — a fact about nothing, formatted as a fact about something.
            """)

        // 8f — ⭐ THE GATE. #654's condition was "do not show a user a number from this API
        // until someone has verified it on a device". Nothing has. So the observation must
        // reach the log and stop there.
        let picker = try Self.codeText("Echoelmusic/Studio/AudioInputPickerView.swift")
        XCTAssertFalse(picker.contains("monitorInsertLatencyMilliseconds"), """
            The on-screen readout started consuming the AU-reported insert latencies. #654's \
            gate is still CLOSED: `auAudioUnit.latency` returns 0 for an attached-but-\
            uninitialised node, so until one real founder log shows what these values actually \
            are, putting them on screen would ship exactly the fabricated 0 that retraction \
            exists to prevent. Open the gate deliberately, with a log quoted in the commit — \
            not as a side effect of wiring a readout (#364: this is not a ban, it is a \
            sequence).
            """)
        XCTAssertFalse(picker.contains("auAudioUnit"), """
            A view started reading `auAudioUnit` directly. Besides the gate above, this is an \
            ObjC property read on the graph — it belongs in `AudioEngine`, which owns the \
            nodes, not in a `body` that SwiftUI may evaluate at any rate.
            """)
    }

    // MARK: - helpers

    private static func count(of needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    private static func body(of key: String, in text: String) -> String? {
        guard text.components(separatedBy: key).count - 1 == 1,
              let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return nil
    }

    private static func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent("Sources").appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            struct Missing: Error, CustomStringConvertible {
                let p: String
                var description: String { "Sources/\(p) is missing — re-anchor this scan (#454)." }
            }
            throw Missing(p: relative)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
