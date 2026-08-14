// TheCaptureTurnsAToneIntoAProfileTests.swift
// Echoel — a held tone in, a timbre profile out; nothing else gets through. #592a.
//
// WHAT THIS GUARDS. `VoiceCaptureEngine` is the capture coordinator of the EchoelVoice
// plan (`scratchpads/PLAN_ECHOEL_VOICE.md` slice 3, core half): it aggregates incoming
// mic chunks into 4096-sample analysis windows (trap 3 — the shipped tap's 1024 frames
// are too short for a 70 Hz fundamental), runs `VoiceAnalyzer` (F0 + voicing) and
// `EchoelRealFFT` per window on the CONTROL thread, feeds `VoiceTimbreProfiler`, and
// finishes with the profile once enough VOICED windows accumulated. Silence and noise
// must never progress it — the voicing gate is what makes the capture consent-shaped:
// only a deliberately held tone can fill it.
//
// ⚠️ HONEST LIMITS. 7 tests, 29 assertion statements — hand-counted per test
// (9+3+2+6+2+3+4), because `grep -c "XCTAssert"` on this file counts THIS sentence's
// own mention too (review #592a caught the self-inflated count; the number typed before
// counting at all was 24, the §3 class again). One assertion runs in a loop over the
// finished profile's taps.
// ALL are END-TO-END BEHAVIOUR over the shipped chain (real analyzer, real FFT, real
// profiler — synthetic signals, no mocks). NOT covered: the actual mic tap wiring and
// the `soundPanel` door (slice #592b), the batching of the tap's per-buffer main-hop
// (trap 2 — belongs to the wiring slice), and how a REAL voice sounds through it
// (device probe, founder). No source-text scans, so no stripper grading applies.
//
// ⭐ GRADING (§3). The file names `VoiceCaptureEngine`, created by this same commit — it
// does NOT COMPILE against the parent; no assertion has a verdict there. ONE
// forward-looking finding (#486). Transcribed instead (§0): the ENGINE's own logic
// (window accumulation, chunk-size independence, state machine, cancel/restart, the
// voiced-frame counter) was reimplemented in Python with a stubbed analyzer/FFT and
// driven through every scenario below. The analyzer/FFT halves are NOT re-derived
// there — they are the shipped, separately-tested pieces (`VoiceAnalyzerTests` pins
// 220 Hz voiced ±5 Hz and refuses silence/noise; the FFT bin contract was measured in
// #590) — so the tone test's spectral assertions lean on pinned behaviour plus loose
// tolerances rather than on a second implementation.

import Foundation
import XCTest
@testable import Echoelmusic

#if canImport(Accelerate)   // VoiceCaptureEngine exists only with Accelerate

final class TheCaptureTurnsAToneIntoAProfileTests: XCTestCase {

    private let sr = 48_000.0

    /// A voice-like held tone: harmonic series at `hz`, amplitudes 1/k (5 partials).
    private func tone(_ n: Int, hz: Double = 140) -> [Float] {
        (0..<n).map { i in
            let t = Double(i) / sr
            var v = 0.0
            for k in 1...5 { v += (0.4 / Double(k)) * sin(2 * .pi * hz * Double(k) * t) }
            return Float(v)
        }
    }

    /// Deterministic broadband noise ±0.3 (seeded LCG — no SystemRandomNumberGenerator,
    /// so the test cannot flake). ⛔ The first draft shifted by 33 bits over a 32-bit
    /// divisor — one-sided −0.3…0, not the "±" its comment claimed (review #592a).
    private func noise(_ n: Int) -> [Float] {
        var s: UInt64 = 0x9E3779B97F4A7C15
        return (0..<n).map { _ in
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(s >> 32) / Double(UInt32.max) - 0.5) * 0.6
        }
    }

    func testAHeldToneBecomesAProfile() throws {
        let engine = VoiceCaptureEngine(targetVoicedFrames: 8)
        engine.start()
        XCTAssertEqual(engine.state, .capturing)
        // Feed in the shipped tap's chunking (1024) until done — cap well above need.
        let samples = tone(20 * VoiceCaptureEngine.windowSize)
        var i = 0
        while i < samples.count, engine.state != .done {
            engine.ingest(Array(samples[i..<min(i + 1024, samples.count)]), sampleRate: sr)
            i += 1024
        }
        XCTAssertEqual(engine.state, .done, "a held tone must fill the capture")
        XCTAssertEqual(engine.progress, 1)
        let profile = try XCTUnwrap(engine.profile)
        // Against the profiler's own default, not a fourth spelling of 64 (#416): the
        // socket-width decision lives with the profiler and its behavioral drift guard.
        XCTAssertEqual(profile.count, VoiceTimbreProfiler().harmonicCount)
        XCTAssertEqual(profile.max() ?? 0, 1, accuracy: 1e-6, "max-normalized")
        // The 1/k series: the strongest tap is a LOW harmonic and the series decays.
        let maxIndex = try XCTUnwrap(profile.firstIndex(of: profile.max() ?? 1))
        XCTAssertLessThan(maxIndex, 3, "the fundamental region must dominate a 1/k series")
        XCTAssertLessThan(profile[7], 0.35,
                          "beyond the 5-partial series the envelope must have decayed")
        XCTAssertGreaterThan(engine.lastPitchHz, 100)
        XCTAssertLessThan(engine.lastPitchHz, 200)
    }

    func testSilenceNeverProgresses() {
        let engine = VoiceCaptureEngine(targetVoicedFrames: 4)
        engine.start()
        engine.ingest([Float](repeating: 0, count: 10 * VoiceCaptureEngine.windowSize),
                      sampleRate: sr)
        XCTAssertEqual(engine.state, .capturing, "silence must not finish a capture")
        XCTAssertEqual(engine.voicedFrames, 0)
        XCTAssertNil(engine.profile)
    }

    /// The consent shape: broadband noise (breath, room, handling) is not a voice and
    /// must not fill the capture. Leans on the analyzer's own pinned refusal.
    func testNoiseIsNotAVoice() {
        let engine = VoiceCaptureEngine(targetVoicedFrames: 4)
        engine.start()
        engine.ingest(noise(10 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.voicedFrames, 0, "broadband noise must read as unvoiced")
        XCTAssertNil(engine.profile)
    }

    func testCancelClearsEverythingAndRestartWorks() {
        // Target 8, feed 4 windows: the cancel lands MID-capture (review #592a — the
        // first draft's 4/4 finished before cancelling and tested the weaker property).
        let engine = VoiceCaptureEngine(targetVoicedFrames: 8)
        engine.start()
        engine.ingest(tone(4 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertGreaterThan(engine.voicedFrames, 0, "precondition: the tone was landing")
        XCTAssertEqual(engine.state, .capturing, "precondition: still mid-capture")
        engine.cancel()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.voicedFrames, 0)
        XCTAssertNil(engine.profile)
        engine.start()
        engine.ingest(tone(10 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.state, .done, "a cancelled engine must capture again cleanly")
    }

    /// Chunking must not change the result: one big ingest and 1024-sized chunks over
    /// the same samples land the same voiced-frame count (the window aggregation is the
    /// unit under test here — everything downstream is deterministic).
    func testChunkingDoesNotChangeTheOutcome() {
        let samples = tone(6 * VoiceCaptureEngine.windowSize)
        let whole = VoiceCaptureEngine(targetVoicedFrames: 100)
        whole.start()
        whole.ingest(samples, sampleRate: sr)
        let chunked = VoiceCaptureEngine(targetVoicedFrames: 100)
        chunked.start()
        var i = 0
        while i < samples.count {
            chunked.ingest(Array(samples[i..<min(i + 1024, samples.count)]), sampleRate: sr)
            i += 1024
        }
        XCTAssertEqual(whole.voicedFrames, chunked.voicedFrames)
        XCTAssertGreaterThan(whole.voicedFrames, 0, "precondition: the tone lands at all")
    }

    /// A NaN block (a glitching route) must neither crash nor poison: the analyzer reads
    /// it as unvoiced (NaN comparisons are false), and the finished profile is finite.
    func testANaNBlockCannotPoisonTheCapture() throws {
        let engine = VoiceCaptureEngine(targetVoicedFrames: 4)
        engine.start()
        engine.ingest([Float](repeating: .nan, count: 2 * VoiceCaptureEngine.windowSize),
                      sampleRate: sr)
        XCTAssertEqual(engine.voicedFrames, 0, "a NaN window must read as unvoiced")
        engine.ingest(tone(8 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.state, .done)
        for v in try XCTUnwrap(engine.profile) {
            XCTAssertTrue(v.isFinite)
        }
    }

    func testIngestOutsideACaptureIsIgnored() {
        let engine = VoiceCaptureEngine(targetVoicedFrames: 4)
        engine.ingest(tone(4 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.state, .idle, "no start, no capture — the #277 arm shape")
        XCTAssertEqual(engine.voicedFrames, 0)
        // A finished engine stops listening too: its profile is the take, frozen.
        engine.start()
        engine.ingest(tone(8 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.state, .done)
        let frozen = engine.profile
        engine.ingest(noise(2 * VoiceCaptureEngine.windowSize), sampleRate: sr)
        XCTAssertEqual(engine.profile, frozen, "ingest after done must not mutate the take")
    }
}

#endif  // canImport(Accelerate)
