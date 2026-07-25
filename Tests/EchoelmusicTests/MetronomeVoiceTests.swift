#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

@MainActor
final class MetronomeVoiceTests: XCTestCase {

    // MARK: - Timing math (pure, audio-graph-free)

    func testSamplesPerBeat_120BPM_isHalfSecond() {
        // 120 BPM = 2 beats/sec → 0.5 s/beat → 24000 frames at 48 kHz.
        XCTAssertEqual(MetronomeVoice.samplesPerBeat(bpm: 120, sampleRate: 48_000), 24_000, accuracy: 0.001)
    }

    func testSamplesPerBeat_60BPM_isOneSecond() {
        XCTAssertEqual(MetronomeVoice.samplesPerBeat(bpm: 60, sampleRate: 48_000), 48_000, accuracy: 0.001)
    }

    func testSamplesPerBeat_clampsTooSlowTempo() {
        // Anything below 20 BPM is clamped to 20 (no divide-by-tiny / runaway gap).
        let at5 = MetronomeVoice.samplesPerBeat(bpm: 5, sampleRate: 48_000)
        let at20 = MetronomeVoice.samplesPerBeat(bpm: 20, sampleRate: 48_000)
        XCTAssertEqual(at5, at20, accuracy: 0.001)
    }

    func testSamplesPerBeat_clampsTooFastTempo() {
        let at1000 = MetronomeVoice.samplesPerBeat(bpm: 1000, sampleRate: 48_000)
        let at400 = MetronomeVoice.samplesPerBeat(bpm: 400, sampleRate: 48_000)
        XCTAssertEqual(at1000, at400, accuracy: 0.001)
    }

    func testSamplesPerBeat_honoursItsClampContractForNaN() {
        // The doc says "clamped (20…400 BPM)". `min(max(bpm, 20), 400)` did NOT honour
        // that for NaN — every comparison against NaN is false, so both clamps passed
        // it through. A NaN result makes the render's `sampleCounter >= perBeat` test
        // false forever: the click never fires again and the counter grows unbounded.
        //
        // Note the output guard cannot catch this one. The samples stay a perfectly
        // finite 0 — the failure is silence, not a bad sample.
        let fromNaN = MetronomeVoice.samplesPerBeat(bpm: .nan, sampleRate: 48_000)
        XCTAssertTrue(fromNaN.isFinite, "a NaN tempo escaped the clamp")
        XCTAssertEqual(fromNaN, MetronomeVoice.samplesPerBeat(bpm: 20, sampleRate: 48_000),
                       accuracy: 0.001, "NaN must resolve to the slow end, like any out-of-range tempo")
        // ±inf went through the old form correctly; pin that it still does.
        XCTAssertEqual(MetronomeVoice.samplesPerBeat(bpm: .infinity, sampleRate: 48_000),
                       MetronomeVoice.samplesPerBeat(bpm: 400, sampleRate: 48_000), accuracy: 0.001)
        XCTAssertEqual(MetronomeVoice.samplesPerBeat(bpm: -.infinity, sampleRate: 48_000),
                       MetronomeVoice.samplesPerBeat(bpm: 20, sampleRate: 48_000), accuracy: 0.001)
    }

    // MARK: - Control surface

    func testDefault_isLaunchSilent() {
        let m = MetronomeVoice()
        XCTAssertFalse(m.enabled, "The metronome must be off on launch (no surprise click).")
    }

    func testDefaults_areSensible() {
        let m = MetronomeVoice()
        XCTAssertEqual(m.beatsPerBar, 4)
        XCTAssertEqual(m.bpm, 120, accuracy: 0.001)
        XCTAssertTrue(m.accentDownbeat)
    }
}
#endif
