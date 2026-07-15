// HostMusicalStateTests.swift
// H9b — the pure beat maths hosted plugins' context blocks compute from, and
// the Transport→mirror write path (the ONE clock feeds the ONE mirror).

import XCTest
@testable import Echoelmusic

final class HostMusicalStateTests: XCTestCase {

    // MARK: - HostBeatMath (render-thread arithmetic, Linux-tested)

    func testBeats_fromAbsoluteStep_sixteenthsToQuarters() {
        XCTAssertEqual(HostBeatMath.beats(fromAbsoluteStep: 0), 0)
        XCTAssertEqual(HostBeatMath.beats(fromAbsoluteStep: 4), 1, "4 sixteenths = 1 beat")
        XCTAssertEqual(HostBeatMath.beats(fromAbsoluteStep: 16), 4, "one 4/4 bar = 4 beats")
        XCTAssertEqual(HostBeatMath.beats(fromAbsoluteStep: 6), 1.5)
        XCTAssertEqual(HostBeatMath.beats(fromAbsoluteStep: 4, stepsPerBeat: 0), 0,
                       "degenerate stepsPerBeat guards to 0, never divides by zero")
    }

    func testMeasureDownbeat_flooredToBar() {
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: 0), 0)
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: 3.75), 0)
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: 4), 4)
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: 9.5), 8)
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: .nan), 0, "NaN guards to 0")
        XCTAssertEqual(HostBeatMath.measureDownbeat(beat: 9.5, beatsPerBar: 0), 0)
    }

    func testSamplePosition_beatTimesSecondsPerBeatTimesRate() {
        // 120 BPM → 0.5 s/beat → beat 4 = 2 s = 96000 samples @ 48k.
        XCTAssertEqual(HostBeatMath.samplePosition(beat: 4, tempo: 120, sampleRate: 48_000),
                       96_000, accuracy: 1e-9)
        XCTAssertEqual(HostBeatMath.samplePosition(beat: 0, tempo: 120, sampleRate: 48_000), 0)
        XCTAssertEqual(HostBeatMath.samplePosition(beat: 4, tempo: 0, sampleRate: 48_000), 0,
                       "tempo 0 guards to 0, never divides by zero")
        XCTAssertEqual(HostBeatMath.samplePosition(beat: -1, tempo: 120, sampleRate: 48_000), 0,
                       "never negative")
        XCTAssertEqual(HostBeatMath.samplePosition(beat: .infinity, tempo: 120, sampleRate: 48_000), 0)
    }

    func testSamplesToNextBeat_zeroOnBeat_fractionOff() {
        XCTAssertEqual(HostBeatMath.samplesToNextBeat(beat: 4, tempo: 120, sampleRate: 48_000), 0,
                       "exactly ON a beat ⇒ 0")
        // beat 3.75 @120: 0.25 beat = 0.125 s = 6000 samples.
        XCTAssertEqual(HostBeatMath.samplesToNextBeat(beat: 3.75, tempo: 120, sampleRate: 48_000),
                       6_000, accuracy: 1e-9)
        XCTAssertEqual(HostBeatMath.samplesToNextBeat(beat: .nan, tempo: 120, sampleRate: 48_000), 0)
        XCTAssertEqual(HostBeatMath.samplesToNextBeat(beat: 1, tempo: 0, sampleRate: 48_000), 0)
    }

    // MARK: - Accumulated sample position (review HIGH: monotone under glides)

    func testMirror_advanceAccumulates_resetRelocates() {
        let m = HostMusicalState()
        m.sampleRate = 48_000
        m.tempo = 120
        m.advanceSamplePosition(bySteps: 4, stepsPerBeat: 4)   // 1 beat @120 = 0.5 s
        XCTAssertEqual(m.samplePosition, 24_000, accuracy: 1e-9)
        m.advanceSamplePosition(bySteps: 0, stepsPerBeat: 4)   // guards: no-op
        m.advanceSamplePosition(bySteps: 1, stepsPerBeat: 0)
        XCTAssertEqual(m.samplePosition, 24_000, accuracy: 1e-9)
        m.resetSamplePosition(toBeat: 4)
        XCTAssertEqual(m.samplePosition, 96_000, accuracy: 1e-9)
        m.resetSamplePosition(toBeat: 0)
        XCTAssertEqual(m.samplePosition, 0)
    }

    @MainActor
    func testTransport_samplePosition_monotoneUnderTempoGlide() {
        // The review-HIGH scenario: the bio tempo-glide raises tempo per tick.
        // Derived beat×tempo ran BACKWARD; the accumulated field must not.
        let transport = Transport()
        let mirror = HostMusicalState()
        transport.hostStateMirror = mirror
        transport.setTempo(75)
        transport.play()
        var last = mirror.samplePosition
        var bpm = 75.0
        for s in 1...32 {
            bpm = Swift.min(140, bpm * 1.09)
            transport.setTempo(bpm)
            transport.tick(step: s % Transport.stepsPerBar)
            XCTAssertGreaterThan(mirror.samplePosition, last,
                                 "accumulated position runs forward through a glide (step \(s))")
            last = mirror.samplePosition
        }
    }

    // MARK: - Transport → mirror (the one write point)

    @MainActor
    func testTransport_writesMirror_onPlayTickStopAndTempo() {
        let transport = Transport()
        let mirror = HostMusicalState()
        transport.hostStateMirror = mirror

        transport.setTempo(140)
        XCTAssertEqual(mirror.tempo, 140)

        transport.play()
        XCTAssertTrue(mirror.isPlaying)
        XCTAssertEqual(mirror.beatPosition, 0)

        for s in 1...6 { transport.tick(step: s) }   // 6 sixteenths = 1.5 beats
        XCTAssertEqual(mirror.beatPosition, 1.5)

        transport.stop()
        XCTAssertFalse(mirror.isPlaying)
        XCTAssertEqual(mirror.beatPosition, 0, "stop resets position — mirror follows")
    }

    @MainActor
    func testTransport_barWrap_advancesMirrorBeats() {
        let transport = Transport()
        let mirror = HostMusicalState()
        transport.hostStateMirror = mirror
        transport.play()
        for s in 1...15 { transport.tick(step: s) }
        transport.tick(step: 0)   // 15→0 wrap = bar 1
        XCTAssertEqual(mirror.beatPosition, 4, "bar 1 downbeat = beat 4")
    }

    @MainActor
    func testTransport_wiring_pushesCurrentStateImmediately() {
        // Review MEDIUM: tempo set BEFORE the mirror is wired must land at
        // wire time, not at the next edit.
        let transport = Transport()
        transport.setTempo(97)
        let mirror = HostMusicalState()
        transport.hostStateMirror = mirror
        XCTAssertEqual(mirror.tempo, 97, "didSet pushes the current state")
    }

    @MainActor
    func testTransport_seek_relocatesMirror() {
        let transport = Transport()
        let mirror = HostMusicalState()
        mirror.sampleRate = 48_000
        transport.hostStateMirror = mirror
        transport.setTempo(120)
        transport.seek(toBar: 4)           // bar 4 = beat 16
        XCTAssertEqual(mirror.beatPosition, 16)
        XCTAssertEqual(mirror.samplePosition, 16 * 0.5 * 48_000, accuracy: 1e-9,
                       "a seek is an honest relocation jump")
    }

    @MainActor
    func testTransport_nilMirror_isPureAsBefore() {
        // Snapshot-compare (order-safe): an UNWIRED transport must leave the
        // process-wide shared mirror exactly as it found it.
        let before = HostMusicalState.shared.tempo
        let transport = Transport()   // no mirror wired (unit-test purity law)
        transport.setTempo(150)
        transport.play()
        transport.tick(step: 1)
        transport.stop()              // must not crash or touch any global
        XCTAssertEqual(HostMusicalState.shared.tempo, before,
                       "the shared mirror stays untouched when unwired")
    }
}
