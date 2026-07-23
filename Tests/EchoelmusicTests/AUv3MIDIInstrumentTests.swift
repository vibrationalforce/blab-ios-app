// AUv3MIDIInstrumentTests.swift
// B1 (augn→aumu): the AUv3 is now a playable music-device instrument. These tests
// pin the pure MIDI decode used by its render block, and prove — without a live
// AUAudioUnit (which needs a host) — that a decoded MIDI note-on drives EchoelDDSP
// to audible output. Foundation + Accelerate only, deterministic.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class AUv3MIDIInstrumentTests: XCTestCase {

    // MARK: - Pure MIDI decode

    func testFrequency_A4_is440() {
        XCTAssertEqual(EchoelMIDIDecode.frequency(forNote: 69), 440, accuracy: 0.01)
        // One octave up doubles the frequency.
        XCTAssertEqual(EchoelMIDIDecode.frequency(forNote: 81), 880, accuracy: 0.02)
    }

    func testAction_noteOn_decodesFrequencyAndVelocity() {
        guard case let .noteOn(frequency, velocity) =
                EchoelMIDIDecode.action(status: 0x90, data1: 69, data2: 127) else {
            return XCTFail("0x90 with velocity>0 must be a note-on")
        }
        XCTAssertEqual(frequency, 440, accuracy: 0.01)
        XCTAssertEqual(velocity, 1.0, accuracy: 0.001)   // 127/127
    }

    func testAction_noteOnVelocityZero_isNoteOff() {
        // Running-status convention: 0x90 with velocity 0 is a note-off.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0x90, data1: 60, data2: 0), .noteOff)
    }

    func testAction_noteOff_isNoteOff() {
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0x80, data1: 60, data2: 64), .noteOff)
    }

    func testAction_channelIsIgnored_statusMasked() {
        // Note-on on channel 5 (0x94) still decodes as a note-on (low nibble ignored).
        guard case .noteOn = EchoelMIDIDecode.action(status: 0x94, data1: 72, data2: 90) else {
            return XCTFail("the channel nibble must not defeat note-on detection")
        }
    }

    func testAction_nonNoteMessage_isIgnored() {
        // Control Change (0xB0) — the bio drone must keep playing, so: ignore.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xB0, data1: 7, data2: 100), .ignore)
        // Pitch bend (0xE0) — also ignored by the mono note path.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xE0, data1: 0, data2: 64), .ignore)
    }

    func testAction_allNotesOff_isPanic() {
        // MIDI panic: CC 123 (All Notes Off) must FORCE-release the mono voice — otherwise
        // a host's transport-stop / panic leaves the AUv3 drone stuck on. It decodes to
        // `.panic`, NOT `.noteOff`, so last-note priority in the render block never gates
        // it on a key match (its data1 is the controller number 123, not a note).
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xB0, data1: 123, data2: 0), .panic)
    }

    func testAction_allSoundOff_isPanic() {
        // CC 120 (All Sound Off) likewise force-stops the voice.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xB0, data1: 120, data2: 0), .panic)
    }

    func testAction_ordinaryCC_stillIgnored() {
        // Regression guard: a normal CC must NOT stop the voice. Channel 5 (0xB5) also
        // exercises the channel mask on the CC path.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xB5, data1: 7, data2: 100), .ignore)
        // Sustain pedal (CC 64) is not a note-stop either.
        XCTAssertEqual(EchoelMIDIDecode.action(status: 0xB0, data1: 64, data2: 127), .ignore)
    }

    // MARK: - Decode → synth → audible output (the instrument contract)

    func testMIDINoteOn_drivesSynthToAudibleOutput() {
        // Mirror exactly what the AUv3 render block does on a note-on event.
        let synth = EchoelDDSP(sampleRate: 48000)
        synth.amplitude = 0.6
        guard case let .noteOn(frequency, velocity) =
                EchoelMIDIDecode.action(status: 0x90, data1: 69, data2: 100) else {
            return XCTFail("expected a note-on")
        }
        synth.noteVelocity = velocity
        synth.noteOn(frequency: frequency)

        var buffer = [Float](repeating: 0, count: 4096)
        synth.render(buffer: &buffer, frameCount: buffer.count)

        let peak = buffer.reduce(Float(0)) { Swift.max($0, abs($1)) }
        XCTAssertGreaterThan(peak, 0, "a MIDI note-on must make the instrument render audible output")
        XCTAssertTrue(peak.isFinite, "render output must stay finite")
    }

    func testNoNote_synthStillRendersFreeRunningTone() {
        // The founder contract: with no MIDI note, the free-running bio tone plays.
        // allocateRenderResources arms amplitude + a default note; reproduce that and
        // confirm output without any MIDI event.
        let synth = EchoelDDSP(sampleRate: 48000)
        synth.amplitude = 0.6
        synth.noteOn(frequency: 220)   // the default drone armed at allocate time
        var buffer = [Float](repeating: 0, count: 4096)
        synth.render(buffer: &buffer, frameCount: buffer.count)
        let peak = buffer.reduce(Float(0)) { Swift.max($0, abs($1)) }
        XCTAssertGreaterThan(peak, 0, "the free-running bio tone must be audible with no MIDI input")
    }
}
#endif
