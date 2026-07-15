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
    func testTransport_nilMirror_isPureAsBefore() {
        let transport = Transport()   // no mirror wired (unit-test purity law)
        transport.setTempo(150)
        transport.play()
        transport.tick(step: 1)
        transport.stop()              // must not crash or touch any global
        XCTAssertEqual(HostMusicalState.shared.tempo, 120,
                       "the shared mirror stays untouched when unwired")
    }
}
