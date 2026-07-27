#if canImport(AVFoundation)
import AVFoundation
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

    // MARK: - Render path
    //
    // Everything above this line reads the `@Observable` CONTROL properties. That is
    // exactly the blind spot these tests close: a `didSet` that stops writing its
    // `nonisolated(unsafe)` audio mirror leaves every control-surface test green while
    // the click goes silent on the device. Nothing in the suite drove the real render
    // block until 2026-07-27, which made any future change to the metronome's render
    // state a blind 4-minute-CI edit. These drive the real render function through the
    // `_testRender` seam — the same code the `AVAudioSourceNode` closure runs — so the
    // mirrors are on the path under test.
    //
    // HONEST LIMIT, so nobody reads a green gate as proof of these: this FILE is not
    // compiled by the blocking gate. `ci.yml` tests the `Echoelmusic` scheme → the
    // `EchoelmusicTests` target, whose `sources` in `project.yml` is `Tests/CISmoke`.
    // `Tests/EchoelmusicTests` is built only by the `EchoelmusicFullTests` scheme in
    // `full-tests.yml`, where every xcodebuild step is `continue-on-error` by design.
    // So these tests currently REPORT rather than gate; they start protecting the
    // metronome the moment task #139 lands and the main scheme adopts the full target.
    // (The source-side `_testRender` seam IS gated — it lives in the app target.)

    /// Render `frames` frames of the voice into a mono buffer and return the samples,
    /// via the same raw-`AudioBufferList` seam `SamplerVoiceTests` uses.
    /// The buffer is POISONED with a non-zero sentinel first: without it,
    /// "the render wrote nothing at all" is indistinguishable from "the render wrote
    /// silence", and the disarmed-silence assertion below would pass on a no-op.
    private func render(_ m: MetronomeVoice, frames: Int) -> [Float] {
        let out = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        out.initialize(repeating: 1234.5, count: frames)
        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee.mNumberBuffers = 1
        abl.pointee.mBuffers.mNumberChannels = 1
        abl.pointee.mBuffers.mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        abl.pointee.mBuffers.mData = UnsafeMutableRawPointer(out)
        defer {
            out.deinitialize(count: frames)
            out.deallocate()
            abl.deallocate()
        }
        m._testRender(frameCount: frames, audioBufferList: abl)
        return Array(UnsafeBufferPointer(start: out, count: frames))
    }

    /// Frame indices where a click STARTS: a non-zero sample preceded by a long run of
    /// exact zeros. At MODERATE TEMPI the envelope decays below the render's `1e-4`
    /// floor between clicks and the output is then written as exactly `0`, so the gaps
    /// are real — at 120 BPM the measured gap is 12 490 zeros against the 64 required.
    /// The qualifier is not decoration: the tail is ~11 500 samples, so above roughly
    /// 250 BPM it exceeds a beat and this helper silently reports ONE onset for the
    /// whole buffer. Do not reuse it at fast tempi without re-checking that.
    ///
    /// A sine's own zero-crossings cannot fake an onset. `clickPhase` is advanced
    /// BEFORE `sinf`, so the argument is never the exact 0 that would return exact 0 —
    /// and even a lone accidental zero resets the run, since 64 CONSECUTIVE zeros are
    /// required.
    private func clickOnsets(in samples: [Float]) -> [Int] {
        var onsets: [Int] = []
        var zeroRun = 64   // the start of the buffer counts as "after silence"
        for (i, s) in samples.enumerated() {
            if s == 0 {
                zeroRun += 1
            } else {
                if zeroRun >= 64 { onsets.append(i) }
                zeroRun = 0
            }
        }
        return onsets
    }

    func testRender_enabledDidSetReachesTheRenderMirror_andDisarmingReturnsExactZero() {
        let m = MetronomeVoice()
        m.level = 0.6
        m.enabled = true

        let armed = render(m, frames: 48_000)
        let energy = armed.reduce(Float(0)) { $0 + $1 * $1 }
        XCTAssertGreaterThan(energy, 0,
                             "An armed metronome rendered no energy — the `enabled` didSet never reached `audioEnabled`.")
        // The poison sentinel cuts both ways, and this closes the second edge: it
        // rescues the disarmed assertion below (a no-op render can't pass as silence),
        // but on its own it would ALSO let a no-op pass `energy > 0`, since
        // 48 000 x 1234.5² is a lot of energy. Bounding the samples to real audio
        // range is what makes the armed half prove the render actually wrote.
        XCTAssertTrue(armed.allSatisfy { $0.isFinite && Swift.abs($0) <= 1 },
                      "armed output left audio range — the render did not write these samples")

        m.enabled = false
        let disarmed = render(m, frames: 4_800)
        XCTAssertEqual(disarmed.count, 4_800)
        XCTAssertTrue(disarmed.allSatisfy { $0 == 0 },
                      "Disarming must produce exact zero — the launch/idle silence contract, not merely a quiet click.")
    }

    func testRender_beatSpacingMatchesTempo() {
        let m = MetronomeVoice()
        // 90, NOT the default 120, and that is the whole point of the test: at the
        // default tempo a `bpm` didSet that had stopped writing `audioSamplesPerBeat`
        // would still leave the mirror at its correct 24 000 default, so the test would
        // pass while claiming to have proven the didSet. 90 BPM = 32 000 frames/beat.
        m.bpm = 90
        m.level = 0.6
        m.enabled = true

        let onsets = clickOnsets(in: render(m, frames: 96_000))   // 2 s
        guard onsets.count >= 3 else {
            return XCTFail("expected at least 3 clicks in 2 s at 90 BPM, got \(onsets.count)")
        }

        // The FIRST gap is one frame short by construction: arming sets the counter to
        // exactly `perBeat`, so the very first increment fires at frame 0 and leaves the
        // counter at 1 rather than 0. That one frame (21 µs) is inaudible and is not
        // worth "fixing"; it is asserted rather than hidden so a future change to the
        // resync path can't silently drift the whole grid instead.
        XCTAssertEqual(onsets[1] - onsets[0], 31_999, "first gap after arm")
        for i in 2..<onsets.count {
            XCTAssertEqual(onsets[i] - onsets[i - 1], 32_000,
                           "beat \(i) landed off the grid — `bpm` didSet → `audioSamplesPerBeat` is wrong")
        }
    }

    func testRender_armingFiresAnAccentedDownbeatImmediately() {
        let m = MetronomeVoice()
        m.bpm = 120
        m.level = 0.6
        m.accentDownbeat = true
        m.enabled = true      // sets pendingResync → the next beat is beat 1 of the bar

        let samples = render(m, frames: 48_000)
        let onsets = clickOnsets(in: samples)
        XCTAssertEqual(onsets.first, 0,
                       "Arming must click on the very first frame — the performer taps the click on and hears the downbeat, not a wait of up to one beat.")
        guard onsets.count >= 2 else {
            return XCTFail("need a second, unaccented click to compare against; got \(onsets.count)")
        }

        // The accent is a fifth up (1568 Hz vs 1046 Hz) AND louder (env 1.0 vs 0.7).
        // Pitch is measured by sign changes, which needs no FFT and no tolerance games:
        // 2·f·t crossings, i.e. ~31 at 1568 Hz over 10 ms vs ~21 at 1046 Hz.
        func signChanges(from start: Int, count: Int) -> Int {
            var changes = 0
            for i in (start + 1)..<(start + count) where (samples[i] < 0) != (samples[i - 1] < 0) { changes += 1 }
            return changes
        }
        let downbeatCrossings = signChanges(from: onsets[0], count: 480)
        let plainCrossings = signChanges(from: onsets[1], count: 480)
        XCTAssertGreaterThan(downbeatCrossings, plainCrossings,
                             "the downbeat must be the HIGHER pitch (accentHz), not the plain beatHz")
        XCTAssertEqual(Double(downbeatCrossings), 31.4, accuracy: 3, "downbeat should sit at ~1568 Hz")
        XCTAssertEqual(Double(plainCrossings), 20.9, accuracy: 3, "plain beat should sit at ~1046 Hz")

        let downbeatPeak = samples[onsets[0]..<(onsets[0] + 480)].map { Swift.abs($0) }.max() ?? 0
        let plainPeak = samples[onsets[1]..<(onsets[1] + 480)].map { Swift.abs($0) }.max() ?? 0
        XCTAssertGreaterThan(downbeatPeak, plainPeak, "the downbeat must also be the louder click")
    }

    func testRender_accentOff_makesTheDownbeatPlain() {
        // The test above sets `accentDownbeat = true`, which is already the DEFAULT —
        // so on its own it proves nothing about the `accentDownbeat` didSet reaching
        // `audioAccent`. This one drives the mirror off its default. Without it, the
        // accent toggle could be dead and the suite would still be green.
        let m = MetronomeVoice()
        m.bpm = 120
        m.level = 0.6
        m.accentDownbeat = false
        m.enabled = true

        let samples = render(m, frames: 48_000)
        guard let first = clickOnsets(in: samples).first else {
            return XCTFail("no click at all with the accent switched off")
        }
        XCTAssertEqual(first, 0, "switching the accent off must not delay the click")

        var crossings = 0
        for i in (first + 1)..<(first + 480) where (samples[i] < 0) != (samples[i - 1] < 0) { crossings += 1 }
        XCTAssertEqual(Double(crossings), 20.9, accuracy: 3,
                       "with the accent off the first beat must sound at beatHz (~1046 Hz), not accentHz")
    }

    func testRender_outOfRangeLevelIsClamped() {
        // CORRECTION to my first version of this test, which asserted only
        // `allSatisfy { $0.isFinite }` on a NaN level. That could not fail: the render
        // already sweeps every sample through `AudioOutputGuard.silencingNonFinite`, so
        // NaN becomes 0 whether or not the `level` clamp exists — and the buffer's
        // poison sentinel is finite too, so even a no-op render passed it. It asserted
        // the output guard, not the clamp.
        //
        // The clamp is only OBSERVABLE through finite out-of-range input, which the
        // output guard cannot mask. Both directions are checked, because they fail
        // differently: too loud is a speaker-damaging click, too quiet is silence.
        let loud = MetronomeVoice()
        loud.level = 2.0            // must clamp to 1.0
        loud.enabled = true
        let loudPeak = render(loud, frames: 24_000).map { Swift.abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(loudPeak, 1.0, "level 2.0 escaped the upper clamp and doubled the click")
        XCTAssertGreaterThan(loudPeak, 0.9, "clamped to 1.0, the click should still be near full scale")

        let inverted = MetronomeVoice()
        inverted.level = -1.0       // must clamp to 0 → silence, not a phase-flipped click
        inverted.enabled = true
        XCTAssertTrue(render(inverted, frames: 24_000).allSatisfy { $0 == 0 },
                      "a negative level must silence the click, not invert it")

        // NaN resolves to the LOWER bound (`FloatingPointClamp`), i.e. it fails quiet
        // rather than loud. Asserting the exact zero pins that choice; asserting mere
        // finiteness would not, since the output guard delivers that for free.
        let nan = MetronomeVoice()
        nan.level = .nan
        nan.enabled = true
        XCTAssertTrue(render(nan, frames: 24_000).allSatisfy { $0 == 0 },
                      "a NaN level must fail quiet (lower bound), not loud")
    }

    func testRender_nonFiniteTempoDoesNotStallTheBeat() {
        // The failure mode here is the one NO output guard can see. Against a NaN
        // `audioSamplesPerBeat` the render's `sampleCounter >= perBeat` test is false
        // forever: the samples stay a perfectly finite 0 and the click never fires
        // again. Only asserting that the click still FIRES catches it.
        let n = MetronomeVoice()
        n.bpm = .nan                // must clamp to 20 BPM = 144 000 frames/beat
        n.level = 0.6
        n.enabled = true

        let samples = render(n, frames: 24_000)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "a NaN tempo produced non-finite samples")
        XCTAssertFalse(clickOnsets(in: samples).isEmpty,
                       "a NaN tempo silenced the click — the clamp must fall back to a real tempo, not stall the beat counter")
    }
}
#endif
