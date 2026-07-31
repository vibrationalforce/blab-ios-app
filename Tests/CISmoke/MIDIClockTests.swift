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
//   • NOT sample-accurate. The pulse rides a main-queue `DispatchSourceTimer`, the same class
//     the step sequencer and the meter poll use. Jitter is bounded by main-queue latency, not
//     by the audio clock. A tight rig should still slave Echoel to hardware, not the reverse —
//     and that is exactly what Link would fix.
//   • NOT Song Position Pointer. Receivers start from zero, which is correct here because
//     `Transport.play()` always resets position to zero.
//
// These tests are RUNTIME tests of the pure encoder plus a source scan of the wiring. The
// timer itself and the actual bytes on the wire are device-verify — no CoreMIDI here, and
// there is no simulator in this environment.

import Foundation
import XCTest
@testable import Echoelmusic

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

    /// ⚠️ A TEMPO THAT CANNOT PRODUCE AN INTERVAL MUST RETURN nil, NOT A NUMBER. Arming a
    /// repeating `DispatchSourceTimer` with NaN or 0 is not a wrong tempo — it is undefined
    /// scheduler behaviour, and the caller can no longer decide.
    ///
    /// NaN is rejected by POSITION, not by an `isNaN` check inside the comparison: `bpm > 0`
    /// is FALSE for NaN. Same property the repo's `clamped(to:)` note depends on.
    func testClockIntervalRefusesATempoItCannotUse() {
        for bad in [Double.nan, 0, -120, .infinity, -.infinity] {
            XCTAssertNil(UMPEncoder.clockInterval(bpm: bad), """
            `clockInterval(bpm: \(bad))` returned a value instead of nil. Every caller arms a \
            repeating timer with this; a non-finite or non-positive interval is undefined \
            behaviour in the scheduler, not a slow clock.
            """)
        }
        XCTAssertNil(UMPEncoder.clockInterval(bpm: 120, ppqn: 0), """
        a ppqn of 0 divided by zero instead of returning nil.
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

    // MARK: - The wiring

    /// ⭐ ALL THREE TRANSPORT EDGES, OR THE CLOCK IS WORSE THAN NONE. Start without Stop
    /// leaves a receiver running forever; tempo without start emits Start while stopped.
    func testTheClockRidesAllThreeTransportEdges() throws {
        let app = try codeLines("Sources/Echoelmusic/EchoelmusicApp.swift").joined(separator: "\n")
        for (api, why) in [
            ("addPlaySubscriber(\"midi.clock\")",
             "no Start (0xFA) is sent when the transport starts — receivers never begin"),
            ("addStopSubscriber(\"midi.clock\")",
             "no Stop (0xFC) is sent — a receiver keeps running on a clock that stopped pulsing"),
            ("onTempoChange(id: \"midi.clock\")",
             "the pulse interval never follows the body's tempo — the DAW drifts apart from Echoel")
        ] {
            XCTAssertTrue(app.contains(api), "`\(api)` is gone: \(why).")
        }
    }

    /// ⚠️ THE SUBSCRIBER LIST MUST BE CLEARED BY THE TEARDOWN THAT CLEARS THE OTHERS. A new
    /// list that `removeSubscriber` forgets is a leak that only shows up as a callback firing
    /// against a dead object — `Transport`'s own doc comment says exactly this about tempo.
    func testRemoveSubscriberClearsThePlayListToo() throws {
        let transport = try codeLines("Sources/Echoelmusic/Core/Transport.swift").joined(separator: "\n")
        let teardown = slice(of: transport, from: "public func removeSubscriber(", to: "\n    }")
        XCTAssertFalse(teardown.isEmpty, "`removeSubscriber` is gone from Transport.swift")
        XCTAssertTrue(teardown.contains("playSubs[id] = nil"), """
        `removeSubscriber` no longer clears `playSubs`. The list was added by #300 and the \
        method's own comment records tempo being forgotten once already for the same reason.
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
            so they SKIP rather than reporting a green they did not earn. The encoder tests \
            above are real runtime tests and run regardless.
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
