// MIDIClockTests.swift
// Echoel — #300. Blocking bundle.
//
// ⭐ WHAT THIS SLICE ANSWERS. The founder asked "Sync für Ableton etc.?" and the honest answer
// was: nothing. No Ableton Link (`Package.swift` `dependencies: []`, no LinkKit), and no MIDI
// clock either — `git grep` for 0xF8 / 0xFA / 0xFC over `Sources/` returned nothing, in either
// direction. Echoel could send bio data, light and space to a rig, but it and the DAW ran on
// different clocks. This makes Echoel a MIDI clock MASTER: zero dependencies, CoreMIDI was
// already there, and any sequencer in the room can slave to the body's tempo.
//
// ⚠️ WHAT IT IS NOT, said plainly so nobody reads more into it than is there:
//   • NOT Ableton Link. Link is bidirectional, phase-aligned and needs no cable; MIDI clock is
//     one-way and pulse-only. Link stays deferred (#111) because it would be this project's
//     FIRST external dependency — see decisions.csv.
//   • NOT a clock FOLLOWER. `Transport.clockSource` still has exactly one value in practice
//     (`.internal`); receiving external clock is a separate slice.
//   • NOT sample-accurate. The pulse rides a main-queue `DispatchSourceTimer`. Jitter is
//     bounded by main-queue latency, not by the audio clock, and Echoel's own step grid
//     (a self-rescheduling one-shot timer) drifts against it over a long take with nothing
//     to re-sync them. A tight rig should still slave Echoel to hardware, not the reverse —
//     and that is exactly what Link would fix.
//   • NOT Song Position Pointer — which is precisely why the clock is a PLAY-EDGE feature.
//     Routing MIDI out on mid-take starts no clock: without SPP the only thing that could go
//     out is Start, which means "go to bar 1". See `testRoutingMIDIOutMidTakeStartsNoClock`.
//
// These tests are RUNTIME tests of the pure encoder and of `Transport`'s play fan-out, plus a
// source scan of the wiring that needs CoreMIDI. The timer itself and the actual bytes on the
// wire are device-verify — there is no simulator in this environment.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class MIDIClockTests: XCTestCase {

    // MARK: - The interval

    /// ⭐ 24 PPQN is the MIDI spec, and the arithmetic is the whole clock.
    func testClockIntervalIs24PulsesPerQuarterNote() {
        // 120 bpm = 2 beats/s → 48 pulses/s → 20.8333 ms.
        XCTAssertEqual(UMPEncoder.clockInterval(bpm: 120) ?? 0, 1.0 / 48.0, accuracy: 1e-9, """
        the clock interval at 120 bpm is not 1/48 s. Either the PPQN default moved off 24 \
        (the spec value every receiver assumes) or the formula changed.
        """)
        // Halving the tempo doubles the gap — the property a receiver's tempo readout tracks.
        let slow = UMPEncoder.clockInterval(bpm: 60) ?? 0
        let fast = UMPEncoder.clockInterval(bpm: 120) ?? 0
        XCTAssertEqual(slow, fast * 2, accuracy: 1e-9, """
        halving the tempo did not double the pulse gap (60 bpm → \(slow) s, 120 bpm → \
        \(fast) s). A receiver derives its tempo from this ratio.
        """)
    }

    /// The encoder's PPQN and the transport's must be the SAME 24, or the pulse count per
    /// step stops being `Transport.ppqPerStep` and nothing in the code says so.
    func testEncoderPPQNMatchesTheTransportResolution() {
        let oneQuarter = (UMPEncoder.clockInterval(bpm: 60) ?? 0) * Double(Transport.ppqResolution)
        XCTAssertEqual(oneQuarter, 1.0, accuracy: 1e-9, """
        `UMPEncoder.clockInterval`'s default ppqn and `Transport.ppqResolution` \
        (\(Transport.ppqResolution)) disagree — \(Transport.ppqResolution) pulses at 60 bpm \
        spanned \(oneQuarter) s instead of one quarter note.
        """)
    }

    /// ⚠️ A TEMPO THAT CANNOT PRODUCE AN INTERVAL MUST RETURN nil, NOT A NUMBER. Arming a
    /// repeating `DispatchSourceTimer` with NaN or 0 is not a wrong tempo — it is undefined
    /// scheduler behaviour, and the caller can no longer decide.
    func testClockIntervalRefusesATempoItCannotUse() {
        let bad: [Double] = [.nan, 0, -120, .infinity, -.infinity]
        for value in bad {
            XCTAssertNil(UMPEncoder.clockInterval(bpm: value), """
            `clockInterval(bpm: \(value))` returned a value instead of nil. Every caller arms \
            a repeating timer with this; a non-finite or non-positive interval is undefined \
            behaviour in the scheduler, not a slow clock.
            """)
        }
        XCTAssertNil(UMPEncoder.clockInterval(bpm: 120, ppqn: 0), """
        a ppqn of 0 divided by zero instead of returning nil.
        """)
    }

    // MARK: - The step delay (the thing that keeps Start on the downbeat)

    /// ⭐ SIX CLOCK PULSES PER STEP — the identity that makes the deferred Start correct.
    /// `Transport.stepDuration` is what the sequencer waits before step 0 sounds AND what
    /// the clock waits before its first pulse; if they stop agreeing, the DAW's bar 1 and
    /// Echoel's separate again.
    func testOneStepIsSixClockPulses() {
        let step = Transport.stepDuration(atTempo: 120)
        let pulse = UMPEncoder.clockInterval(bpm: 120) ?? 0
        XCTAssertEqual(step / pulse, Double(Transport.ppqPerStep), accuracy: 1e-9, """
        one step at 120 bpm is \(step / pulse) clock pulses, not \(Transport.ppqPerStep). \
        The step grid and the 24-PPQN clock have stopped describing the same music.
        """)
        XCTAssertEqual(step, 0.125, accuracy: 1e-9, """
        a 16th at 120 bpm is 125 ms; got \(step) s.
        """)
    }

    /// A non-usable tempo must still produce a schedulable delay — this one is NOT optional
    /// precisely because both callers hand it straight to a timer.
    func testStepDurationIsAlwaysSchedulable() {
        let unusable: [Double] = [.nan, 0, -120, .infinity, -.infinity]
        for value in unusable {
            let d = Transport.stepDuration(atTempo: value)
            XCTAssertTrue(d.isFinite && d > 0, """
            `stepDuration(atTempo: \(value))` returned \(d). It is handed to \
            `DispatchSourceTimer.schedule` and to `startClock(startingIn:)`; a non-finite or \
            non-positive deadline is undefined behaviour, not a slow start.
            """)
        }
        XCTAssertEqual(Transport.stepDuration(atTempo: .nan),
                       Transport.stepDuration(atTempo: Transport.minTempo), accuracy: 1e-9, """
        NaN no longer maps to the slowest legal tempo. `clamped(to:)` maps NaN to the lower \
        bound by contract — if that changed, every NaN-safe clamp in the repo needs re-reading.
        """)
    }

    // MARK: - The bytes

    /// ⭐ THE ONE THAT WOULD SILENTLY EMIT GARBAGE. System Real Time is UMP message type 0x1;
    /// the channel-voice builder emits type 0x2 and masks its data bytes to 7 bits.
    func testRealTimeUsesItsOwnUMPMessageType() {
        let clock = UMPEncoder.systemRealTime(status: UMPEncoder.RealTime.clock.rawValue)
        XCTAssertEqual(clock, 0x10F8_0000, """
        Clock encoded as \(String(clock, radix: 16)) instead of 0x10f80000 \
        ([mt 0x1 | group 0 | 0xF8 | 0 | 0]).
        """)
        XCTAssertEqual(clock >> 28, 0x1, """
        message type is \(clock >> 28), not 0x1. Type 0x2 is channel voice — a receiver would \
        decode this as a malformed channel message rather than a clock pulse.
        """)
        // And it is genuinely a DIFFERENT word than the channel-voice path would produce, so
        // "just reuse midi1ChannelVoice" is refuted by the test, not only by the comment.
        let wrong = UMPEncoder.midi1ChannelVoice(status: 0xF8, data1: 0, data2: 0)
        XCTAssertNotEqual(clock, wrong, """
        the real-time and channel-voice encoders produced the SAME word for 0xF8. One of them \
        is no longer setting its message type, and the distinction this function exists for \
        is gone.
        """)
    }

    /// ⚠️ THE RAW VALUES THEMSELVES. The mask test below round-trips whatever `rawValue`
    /// says, so it would happily pass with Start declared as 0xFB (Continue). These three
    /// numbers are the MIDI spec and nothing else in the repo pins them.
    func testRealTimeStatusBytesAreTheSpecValues() {
        XCTAssertEqual(UMPEncoder.RealTime.clock.rawValue, 0xF8, "Clock must be 0xF8")
        XCTAssertEqual(UMPEncoder.RealTime.start.rawValue, 0xFA, "Start must be 0xFA")
        XCTAssertEqual(UMPEncoder.RealTime.stop.rawValue, 0xFC, "Stop must be 0xFC")
        // Continue (0xFB) is deliberately NOT declared — see the enum's own comment. It has
        // no producer without a resume-from-position transport, and #300's Nachlese removed
        // the one path that had made it look necessary.
        XCTAssertNil(UMPEncoder.RealTime(rawValue: 0xFB), """
        Continue (0xFB) has been declared. That is a real decision, not a typo: it needs a \
        transport that resumes from a position and a Song Position Pointer to resume TO. \
        Update `UMPEncoder.RealTime`'s comment in the same commit or delete the case.
        """)
    }

    /// ⚠️ THE STATUS MUST NOT BE MASKED. Every other builder in `UMPEncoder` writes
    /// `status | (channel & 0x0F)` — copying that reflex here turns Start (0xFA) into 0x0A.
    /// Real-time messages have no channel nibble; the status byte IS the whole message.
    func testRealTimeStatusIsNotMaskedLikeAChannelNibble() {
        for message in [UMPEncoder.RealTime.clock, .start, .stop] {
            let word = UMPEncoder.systemRealTime(status: message.rawValue)
            let status = UInt8((word >> 16) & 0xFF)
            XCTAssertEqual(status, message.rawValue, """
            \(message) encoded status 0x\(String(status, radix: 16)) instead of \
            0x\(String(message.rawValue, radix: 16)) — the high nibble was masked away, which \
            is what happens when the channel-voice pattern is copied without reading it.
            """)
        }
    }

    /// The group nibble still behaves, so a future multi-group setup does not silently
    /// collide with group 0.
    func testRealTimeCarriesItsGroup() {
        let word = UMPEncoder.systemRealTime(status: 0xF8, group: 3)
        XCTAssertEqual((word >> 24) & 0x0F, 3, "group nibble lost")
    }

    // MARK: - The transport edge (runtime — no CoreMIDI involved)

    /// ⭐ THE MOST LOAD-BEARING LINE IN THE SLICE, AND NOTHING PINNED IT UNTIL NOW.
    /// Delete the `for cb in playSubs.values { cb() }` in `Transport.play()` and the entire
    /// clock dies silently — every source-scan test in this file would still be green,
    /// because the wiring it greps for would still be there, wired to a fan-out that no
    /// longer happens. This is why the reviewer's rule "prefer a runtime test where the type
    /// is pure" is not style advice.
    func testTransportPlayFansOutToPlaySubscribers() {
        let transport = Transport()
        var fired = 0
        transport.addPlaySubscriber("test") { fired += 1 }
        XCTAssertEqual(fired, 0, """
        `addPlaySubscriber` fired immediately on subscribe. `onTempoChange` does that \
        deliberately; play must NOT, or the MIDI clock would emit Start at app launch with \
        no transport running.
        """)
        transport.play()
        XCTAssertEqual(fired, 1, """
        `Transport.play()` did not call its play subscribers. MIDI Start (0xFA) is never \
        sent, so no receiver ever begins — and no source-scan test can see this.
        """)
    }

    /// ⚠️ THE SUBSCRIBER LIST MUST BE CLEARED BY THE TEARDOWN THAT CLEARS THE OTHERS. A new
    /// list that `removeSubscriber` forgets is a leak that only shows up as a callback firing
    /// against a dead object — `Transport`'s own doc comment says exactly this about tempo.
    func testRemoveSubscriberClearsThePlayListToo() {
        let transport = Transport()
        var fired = 0
        transport.addPlaySubscriber("test") { fired += 1 }
        transport.removeSubscriber("test")
        transport.play()
        XCTAssertEqual(fired, 0, """
        `removeSubscriber` no longer clears `playSubs` — the callback fired after teardown. \
        The list was added by #300 and the method's own comment records tempo being \
        forgotten once already for the same reason.
        """)
    }

    // MARK: - The wiring that needs CoreMIDI (source scan)

    /// ⭐ ALL THREE TRANSPORT EDGES, WITH THEIR BODIES CHECKED. Start without Stop leaves a
    /// receiver running forever; tempo without start emits Start while stopped. Each marker
    /// is sliced to its own closure so an emptied body fails instead of passing.
    func testTheClockRidesAllThreeTransportEdgesWithRealBodies() throws {
        let app = try codeLines("Sources/Echoelmusic/EchoelmusicApp.swift").joined(separator: "\n")
        for (marker, call, why) in [
            ("addPlaySubscriber(\"midi.clock\")", "startClock(",
             "no Start (0xFA) is sent when the transport starts — receivers never begin"),
            ("addStopSubscriber(\"midi.clock\")", "stopClock()",
             "no Stop (0xFC) is sent — a receiver keeps running on a clock that stopped pulsing"),
            ("onTempoChange(id: \"midi.clock\")", "setClockTempo(",
             "the pulse interval never follows the body's tempo — the DAW drifts from Echoel")
        ] {
            let body = slice(of: app, from: marker, to: "\n                }")
            XCTAssertFalse(body.isEmpty, "`\(marker)` is gone: \(why).")
            XCTAssertTrue(body.contains(call), """
            the `\(marker)` closure no longer calls `\(call)`: \(why).
            """)
        }
    }

    /// ⭐ START MUST WAIT ONE STEP. The play edge is when the transport DECIDES to play;
    /// `PatternEngine` sounds step 0 one 16th later. Passing no delay put every slaved DAW
    /// a 16th ahead of Echoel, permanently, from the first bar — a sync feature out of sync.
    func testStartIsDelayedByOneStepSoItLandsOnTheDownbeat() throws {
        let app = try codeLines("Sources/Echoelmusic/EchoelmusicApp.swift").joined(separator: "\n")
        let body = slice(of: app, from: "addPlaySubscriber(\"midi.clock\")", to: "\n                }")
        XCTAssertTrue(body.contains("startingIn: Transport.stepDuration(atTempo:"), """
        the play subscriber calls `startClock` without `startingIn:`. Start (0xFA) then goes \
        out on the play edge, one whole step before Echoel's own bar 1 sounds.
        """)
        // …and the sequencer must read the SAME helper, or the two can drift apart again.
        let engine = try codeLines("Sources/Echoelmusic/Sequencer/PatternEngine.swift")
            .joined(separator: "\n")
        let play = slice(of: engine, from: "public func play(", to: "\n    }")
        XCTAssertTrue(play.contains("Transport.stepDuration(atTempo:"), """
        `PatternEngine.play()` computes its first-tick gap itself again instead of reading \
        `Transport.stepDuration`. Two copies of `60.0 / tempo / 4.0` is exactly how the \
        clock's Start and the first audible step drift apart without anything failing.
        """)
    }

    /// ⚠️ NO CLOCK FROM `applyRouting`. Routing MIDI out on mid-take cannot "catch up":
    /// without a Song Position Pointer the only message available is Start, which tells the
    /// receiver to jump to ITS bar 1 while Echoel is at bar 37. #300 shipped with exactly
    /// that call and the Nachlese removed it.
    func testRoutingMIDIOutMidTakeStartsNoClock() throws {
        let app = try codeLines("Sources/Echoelmusic/EchoelmusicApp.swift").joined(separator: "\n")
        let routing = slice(of: app, from: "private func applyRouting() {", to: "\n    }")
        XCTAssertFalse(routing.isEmpty, "`applyRouting` is gone from EchoelmusicApp.swift")
        XCTAssertFalse(routing.contains("startClock("), """
        `applyRouting` starts the clock again. Without SPP that emits a bare Start mid-song, \
        which resets the receiver to bar 1 — worse than no clock, and silently so. If a \
        mid-take join is genuinely wanted, it needs Song Position Pointer first, and \
        `UMPEncoder.RealTime`'s Continue argument has to be revisited in the same commit.
        """)
    }

    /// ⭐ THE TEMPO RE-ARM MUST PRESERVE PHASE. `PatternEngine.advance` relays the tempo on
    /// every tick during a glide (~8×/s at 120 bpm), so re-arming from `.now()` throws away
    /// part of every interval and the receiver reads a tempo LOWER than Echoel is playing —
    /// failing at exactly the moment the slice exists for, a body-driven tempo.
    func testTempoChangeReArmsOnTheExistingPulsePhase() throws {
        let out = try codeLines("Sources/Echoelmusic/Audio/MIDIOutput.swift").joined(separator: "\n")
        let reArm = slice(of: out, from: "public func setClockTempo(", to: "\n    }")
        XCTAssertFalse(reArm.isEmpty, "`setClockTempo` is gone from MIDIOutput.swift")
        XCTAssertTrue(reArm.contains("lastPulseAt"), """
        `setClockTempo` no longer anchors the next deadline to the last pulse that went out. \
        A re-arm from `.now()` drops the elapsed part of the current interval on every tempo \
        relay — the pulse train thins out for the whole glide.
        """)
    }

    /// Un-routing MIDI out must stop the clock while the port is still alive.
    func testDisablingMIDIOutStopsTheClock() throws {
        let out = try codeLines("Sources/Echoelmusic/Audio/MIDIOutput.swift").joined(separator: "\n")
        let didSet = slice(of: out, from: "public var enabled = false {", to: "\n    }")
        XCTAssertTrue(didSet.contains("stopClock()"), """
        turning `midi.out` off no longer stops the clock. The timer would keep pulsing into a \
        port the user un-routed, and no Stop (0xFC) would ever reach the receiver.
        """)
    }

    /// ⚠️ The timer must be cancelled on dealloc. An ACTIVE `DispatchSourceTimer` is retained
    /// by the dispatch runtime: `[weak self]` makes the handler a no-op but does NOT stop the
    /// source, so it fires forever, unreachable.
    func testTheClockTimerIsCancelledOnDealloc() throws {
        let out = try codeLines("Sources/Echoelmusic/Audio/MIDIOutput.swift").joined(separator: "\n")
        XCTAssertTrue(out.contains("deinit"), """
        `MIDIOutput` has no `deinit`. Its clock timer would outlive the object.
        """)
        let deinitBody = slice(of: out, from: "deinit {", to: "\n    }")
        XCTAssertTrue(deinitBody.contains("clockTimer?.cancel()"), """
        the `deinit` no longer cancels `clockTimer`.
        """)
    }

    // MARK: - Helpers

    private func slice(of text: String, from: String, to: String) -> String {
        guard let start = text.range(of: from) else { return "" }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: to) else { return "" }
        return String(rest[..<end.lowerBound])
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — the wiring tests inspect source text, \
            so they SKIP rather than reporting a green they did not earn. The encoder and \
            transport tests above are real runtime tests and run regardless.
            """)
        }
        return root
    }

    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
