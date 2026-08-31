//
//  MetronomeVoice.swift
//  Echoelmusic
//
//  A production/performance metronome — a steady click track. Self-driving on the
//  audio thread (a sample counter, NOT the MainActor sequencer timer) so the click
//  stays rock-steady regardless of UI-timer jitter and works even when the
//  sequencer is stopped (practice click). `resync()` re-aligns the downbeat to the
//  transport when playback starts.
//
//  Threading mirrors SubBassVoice / PolySynthVoice exactly: control plane on
//  MainActor (enabled / bpm / level setters), render closure on the audio thread.
//  Every value the render reads is a `nonisolated(unsafe)` mirror written in a
//  MainActor `didSet` — a MainActor property can't be read from the nonisolated
//  render block. All click-oscillator state mutates ONLY on the audio thread.
//
//  Launch-silent: `enabled` defaults false → the render emits pure zero until the
//  performer turns the click on. Audio-thread rules (.claude/rules/swift-audio.md):
//  no malloc / locks / ObjC / GCD / file IO in the render path — only pre-allocated
//  scalars + arithmetic + sinf/expf (C math).
//

#if canImport(Observation)
import Observation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

@MainActor
@Observable
public final class MetronomeVoice {

    /// Click on/off. Default false — the metronome is silent on launch and first
    /// play; the performer arms it explicitly. The audio thread reads `audioEnabled`.
    public var enabled: Bool = false {
        didSet {
            audioEnabled = enabled
            // Arming the click starts a fresh bar so beat 1 lands immediately.
            if enabled { pendingResync = true }
        }
    }

    /// Tempo in BPM. Kept in sync with the transport by the host view. The audio
    /// thread reads `audioSamplesPerBeat` (derived) — never `bpm` directly.
    public var bpm: Double = 120 {
        didSet { recomputeTiming() }
    }

    /// How many beats before the click accents again — the accent lands on index 0.
    ///
    /// ⛔ NOT the project's time signature, and this doc said "(time-signature numerator)"
    /// until #930. `Transport.beatsPerBar` is a hard `static let 4`; nothing here reaches it.
    /// Set this to 3 and the click accents every third beat while sequencer, automation and
    /// clip grid stay in 4 — the two bars coincide once at start, then diverge. The UI row is
    /// named "Accent every" for that reason. It also has NO effect while `accentDownbeat` is
    /// off: the render test is `(beatIndex == 0) && audioAccent`.
    public var beatsPerBar: Int = 4 {
        didSet { audioBeatsPerBar = max(1, min(beatsPerBar, 16)) }
    }

    /// Click level [0...1]. The accent beat is rendered a little louder/brighter.
    public var level: Float = 0.6 {
        // NaN-safe `clamped(to:)` — `min(max(level, 0), 1)` passes NaN straight
        // through (every comparison against NaN is false). A NaN here would make
        // every click sample non-finite; the output guard would then zero them, so
        // the metronome would vanish silently with nothing to diagnose.
        didSet { audioLevel = level.clamped(to: 0...1) }
    }

    /// Accent the first beat of the bar (higher pitch + louder). Default on.
    public var accentDownbeat: Bool = true {
        didSet { audioAccent = accentDownbeat }
    }

    // MARK: - Audio-thread-readable mirrors (written on MainActor didSet)

    @ObservationIgnored nonisolated(unsafe) private var audioEnabled = false
    @ObservationIgnored nonisolated(unsafe) private var audioSamplesPerBeat: Double = 48_000 * 60 / 120
    @ObservationIgnored nonisolated(unsafe) private var audioBeatsPerBar = 4
    @ObservationIgnored nonisolated(unsafe) private var audioLevel: Float = 0.6
    @ObservationIgnored nonisolated(unsafe) private var audioAccent = true
    /// Set on MainActor (resync / arm), consumed on the audio thread. Bool is
    /// atomic-width → no torn read; a one-frame race only shifts the first click by
    /// a single buffer, which is inaudible.
    @ObservationIgnored nonisolated(unsafe) private var pendingResync = false

    // MARK: - Audio-thread-only click state

    @ObservationIgnored nonisolated(unsafe) private var sampleCounter: Double = 0
    /// The beat length the counter was last measured against, so a tempo change can rescale
    /// `sampleCounter` proportionally instead of leaving it stranded (#934). Audio-thread-only,
    /// like `sampleCounter` itself.
    ///
    /// ⚠️ SEEDED WITH 0, WHICH MEANS "NOT MEASURED YET" AND IS NOT A PLACEHOLDER. The first
    /// draft seeded it with `48_000 * 60 / 120`, copying `audioSamplesPerBeat`'s default — a
    /// second spelling of one number, which is the duplicate-threshold defect this repo names
    /// in its own rules (#416): the two would agree today and diverge the day someone changes
    /// the default tempo in one place. Zero costs nothing and reads correctly: the rescale is
    /// guarded on `lastPerBeat > 0`, so the FIRST armed buffer skips it and simply records the
    /// beat length. There is nothing to rescale at that point — the counter is either 0 or
    /// about to be overwritten by the resync two lines below.
    @ObservationIgnored nonisolated(unsafe) private var lastPerBeat: Double = 0
    @ObservationIgnored nonisolated(unsafe) private var beatIndex: Int = 0
    @ObservationIgnored nonisolated(unsafe) private var clickEnv: Float = 0   // 0…1 decaying amplitude
    @ObservationIgnored nonisolated(unsafe) private var clickPhase: Float = 0
    @ObservationIgnored nonisolated(unsafe) private var clickFreq: Float = 1046  // C6, retuned per beat

    @ObservationIgnored nonisolated private static let sampleRate: Double = 48_000
    /// Click body pitches — accent (bar start) sits a fifth above the plain beat.
    @ObservationIgnored nonisolated private static let beatHz: Float = 1046    // ~C6
    @ObservationIgnored nonisolated private static let accentHz: Float = 1568  // ~G6
    /// Per-sample exponential decay. ~26 ms TIME CONSTANT, which is a ~240 ms tail
    /// down to the render's 1e-4 floor — the older "~35 ms click tail" here was
    /// wrong by an order of magnitude. Correcting it matters now, not cosmetically:
    /// `MetronomeVoiceTests` detects click onsets by the run of exact zeros BETWEEN
    /// clicks, so the tail must stay well under one beat. At 0.99981 or slower the
    /// tail would exceed a beat at moderate tempi and the detector would silently
    /// see one long click. Raise this constant only together with those tests.
    @ObservationIgnored nonisolated private static let decay: Float = 0.9992

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    public init() {}

    private func recomputeTiming() {
        audioSamplesPerBeat = Self.samplesPerBeat(bpm: bpm, sampleRate: Self.sampleRate)
    }

    /// Frames between beats for a tempo. Pure + clamped (20…400 BPM) so it's unit
    /// testable without the audio graph. Exposed for tests.
    ///
    /// The clamp is NaN-safe, and that is not cosmetic: `min(max(bpm, 20), 400)`
    /// passes NaN through, and a NaN `audioSamplesPerBeat` makes the render's
    /// `sampleCounter >= perBeat` test false FOREVER — the click never fires again
    /// and the counter grows unbounded. The output guard cannot catch that one: the
    /// samples stay a perfectly finite 0. It is silence, not a bad sample.
    public nonisolated static func samplesPerBeat(bpm: Double, sampleRate: Double = 48_000) -> Double {
        let safeBPM = bpm.clamped(to: 20...400)
        return sampleRate * 60 / safeBPM
    }

    // MARK: - Engine attachment

    /// Attach BEFORE `audioEngine.start()` (the hot-attach rule).
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }

    // MARK: - Control plane

    /// Re-align the click so the next beat is the bar's downbeat. Call when the
    /// transport starts so the click and the sequencer share a downbeat.
    public func resync() { pendingResync = true }

    // MARK: - Source node (audio thread)

    private func makeSourceNode() -> AVAudioSourceNode {
        nonisolated(unsafe) let weakSelf = WeakMetronome(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                MetronomeVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        // Disarmed → pure zero (launch + idle silence, and no CPU on the click).
        // Re-arming sets `pendingResync` in the `enabled` didSet, so a fresh bar is
        // always guaranteed when the click comes back on.
        guard audioEnabled else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }

        // Snapshotted once per buffer, ABOVE the resync branch since #934 needs it there.
        // One buffer stays internally consistent; a mid-buffer tempo change lands on the next
        // one, which is 5–21 ms away and inaudible.
        let perBeat = audioSamplesPerBeat

        // ⭐ #934 — THE TEMPO CHANGE RESCALES THE COUNTER INSTEAD OF STRANDING IT, and this
        // is the COMPLETE repair of what #933 could only bound.
        //
        // A beat in progress has a POSITION IN THE BEAT, not a number of samples: "40 % of the
        // way through" survives a tempo change, "20 000 samples in" does not. #933 kept the
        // absolute count and folded away the overflow, which stopped the click BURST but left
        // the in-progress beat landing at an arbitrary point of the new one. Measured over
        // every alignment, the share of jumps that still fired twice inside 10 ms: fold 2.0 %
        // (60 → 180), 2.0 % (40 → 160), 6.3 % (20 → 400) — with the proportional rescale,
        // 0.0 % in all three, worst case exactly one fire.
        //
        // ⭐ IT ALSO FIXES A DIRECTION #933 NEVER TOUCHED. On a tempo DROP (180 → 60) the fold
        // never runs at all, so a musician 99 % through a beat had to wait a FULL new beat for
        // the click. Proportionally they are still 99 % through, and the click lands almost at
        // once. Measured: fold fires 0 times in the first 480 frames for every alignment,
        // rescale fires once where the position calls for it.
        //
        // ⭐ AND IT FIXES THE ORDINARY PATH, WHICH IS THE REAL FINDING (#934b, reviewer).
        // #933's framing — "a glide is unaffected, only a JUMP reaches this" — understated the
        // damage, because a glide is MANY tiny jumps and the fold's error accumulates in one
        // direction. Simulated over a 60 s glide 120 → 160 BPM stepping at 20 Hz: the fold
        // fires 140 clicks and drifts up to 2 559 frames = 53.3 ms EARLY (it plays an
        // accelerando the transport never asked for); the rescale fires 139 clicks and deviates
        // from the ideal beat grid by 0 frames on every single one. The fold was quietly wrong
        // on the path the metronome actually takes, not only on the rare one.
        //
        // This is the phase-accumulator idiom — changing an oscillator's frequency keeps its
        // phase and changes its increment; it never restarts or jumps the phase. Two compares,
        // one divide and one multiply per BUFFER (not per frame), all audio-thread legal.
        //
        // NEEDS-FOUNDER-VERIFY: a THIRD policy is defensible and only an ear can choose it —
        // finish the current beat at the OLD duration and apply the new tempo from the next
        // beat down (the DAW tempo-map convention). It is not obviously worse: it never moves a
        // click a player is already waiting for, at the price of one beat of lag after a jump.
        // Device probe: set a tempo mid-beat with the click running and say whether the FIRST
        // click after the change feels early, right, or late.
        if perBeat != lastPerBeat {
            // Guard the division rather than trusting the 20…400 clamp two types away: a zero
            // or negative `lastPerBeat` would produce inf/NaN and latch the counter dead, the
            // silent-death mode `samplesPerBeat` documents. Cheaper to check than to reason.
            if lastPerBeat > 0 { sampleCounter *= perBeat / lastPerBeat }
            lastPerBeat = perBeat
        }

        if pendingResync {
            pendingResync = false
            sampleCounter = perBeat               // fire on the very next frame
            beatIndex = audioBeatsPerBar - 1      // → next beat becomes index 0 (downbeat)
        }

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let sr = Float(Self.sampleRate)
        let twoPi: Float = 2 * .pi
        let bars = max(1, audioBeatsPerBar)

        for frame in 0..<frameCount {
            sampleCounter += 1
            if sampleCounter >= perBeat {
                sampleCounter -= perBeat
                // ⛔ #933 — ONE SUBTRACTION IS NOT ENOUGH AFTER A TEMPO JUMP, and the
                // symptom is a click BURST plus a scrambled accent, not a drift.
                // `perBeat` is re-derived on the MainActor (`bpm` didSet) and lands
                // BETWEEN buffers, while `sampleCounter` still carries the count it had
                // accumulated toward the OLD, longer beat. Subtracting once then leaves it
                // a whole beat or more ahead, so this test fires again on the very next
                // frame — and again, and again. Simulated against this exact loop:
                // 60 → 180 BPM gives up to 3 clicks in 3 consecutive SAMPLES, the flow
                // servo's own 40 → 160 clamp gives 4, and the 20 → 400 extreme gives 20.
                // Each spurious click also advances `beatIndex`, which is how the accent
                // ends up on the wrong beat afterwards.
                //
                // ⭐ #934 MADE THIS A BACKSTOP RATHER THAN THE REPAIR. The proportional
                // rescale above keeps `sampleCounter` inside [0, perBeat) across every tempo
                // change, so this branch should now never be taken on a tempo path at all. It
                // is KEPT because it costs one predicted-false compare and it is the only
                // thing standing between a future writer of `sampleCounter` and the burst —
                // a guard that is cheap and currently unreachable is not dead code, it is a
                // floor. The paragraph below is the measurement of what it alone achieved.
                //
                // ⚠️ THIS BOUNDS THE DAMAGE, IT DOES NOT ELIMINATE IT (#933b, found in
                // review). The folded remainder can land within one buffer of the next beat,
                // so ONE extra fire survives: swept over every alignment, the share of jumps
                // with two fires inside 10 ms falls from 34.3 % to 2.0 % (60 → 180), 50.7 % to
                // 2.0 % (40 → 160) and 90.3 % to 6.3 % (20 → 400), while the worst case falls
                // from three, four and TWENTY fires to two in every case. Never worse than
                // before on any alignment — but a mitigation, not a cure, and the guard pins
                // that bound rather than pretending otherwise.
                //
                // ⛔ #933c: the first figure read 34.4 %, taken from a sweep of every SEVENTH
                // alignment while the sentence said "swept over every alignment". The
                // exhaustive run says 34.3 %. One tenth of a point is not the point — the
                // sampling grid belongs to the number (#448), and the 20 → 400 row is here
                // because that same run produced it and it is the strongest evidence in the
                // set: the case this repair helps most was the one left out.
                //
                // It is not rare, which is why it deserves the fold rather than a note:
                // the spurious count is `floor(sampleCounter / perBeat) − 1` — the total fire
                // count less the legitimate beat — with the counter uniform over the old beat,
                // so a 3× tempo jump misfires on ONE THIRD of jumps (swept over all 48 000
                // alignments of 60 → 180: 33.4 %). ⛔ #933b: the `− 1` was missing here and the
                // figure read TWO THIRDS, which is `P(the beat fires at all)`.
                //
                // It stayed unheard because a GLIDE shrinks `perBeat` by a sliver
                // per step (120 → 124 measured: exactly one click, correct spacing), and a
                // glide is how the tempo usually moves here.
                //
                // `truncatingRemainder` is `fmod` — a C math call, so audio-thread legal
                // (no lock, no allocation, no ObjC). It folds instead of zeroing on
                // purpose: zeroing would discard the sub-beat phase and put the next click
                // a full new beat away, turning one artefact into a different one.
                //
                // `perBeat` is POSITIVE because `samplesPerBeat` clamps bpm to 20…400, so it
                // lies in [7 200, 144 000] — NOT because of the `>=` above. ⛔ #933b: that is
                // what this comment claimed, and it is checkable and false: `perBeat == 0`
                // SATISFIES `sampleCounter >= perBeat`, and `fmod(x, 0)` is NaN, which would
                // latch the counter NaN and kill the click forever — exactly the silent-death
                // mode `samplesPerBeat`'s own doc describes. What the `>=` does add is NaN
                // exclusion: a NaN `perBeat` makes the comparison false and skips the fold.
                // A "not dangerous" note with a false reason is worse than none.
                if sampleCounter >= perBeat {
                    sampleCounter = sampleCounter.truncatingRemainder(dividingBy: perBeat)
                }
                beatIndex = (beatIndex + 1) % bars
                let isDownbeat = (beatIndex == 0) && audioAccent
                clickFreq = isDownbeat ? Self.accentHz : Self.beatHz
                clickEnv = isDownbeat ? 1.0 : 0.7   // accent a touch louder
                clickPhase = 0
            }

            var out: Float = 0
            if clickEnv > 1e-4 {
                clickPhase += twoPi * clickFreq / sr
                if clickPhase > twoPi { clickPhase -= twoPi }
                out = sinf(clickPhase) * clickEnv * audioLevel
                clickEnv *= Self.decay
            } else {
                clickEnv = 0
            }

            // Source-node output boundary. Swept once here rather than per buffer,
            // since the same `out` goes to every channel. See `AudioOutputGuard`.
            out = AudioOutputGuard.silencingNonFinite(out)

            for buffer in abl {
                guard let raw = buffer.mData else { continue }
                raw.assumingMemoryBound(to: Float.self)[frame] = out
            }
        }
    }

    nonisolated private static func silence(
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in abl {
            guard let raw = buffer.mData else { continue }
            raw.assumingMemoryBound(to: Float.self).update(repeating: 0, count: frameCount)
        }
    }
}

// MARK: - Test hooks

extension MetronomeVoice {
    /// Test-only: renders one block synchronously, exactly as the
    /// `AVAudioSourceNode` closure does on the audio thread — the same seam
    /// `SamplerVoice._testRender` provides, and legal against `private` because a
    /// same-file extension shares the file scope.
    ///
    /// Until 2026-07-27 the metronome had ZERO render-path coverage: every test read
    /// the `@Observable` control properties, so a `didSet` that stopped writing its
    /// `nonisolated(unsafe)` mirror would leave the whole suite green while the click
    /// went silent on the device. That is precisely the regression a future change to
    /// the render state would invite, so the seam is opened before such a change, not
    /// after it.
    ///
    /// `nonisolated` on purpose, and it is load-bearing: the real caller is the
    /// `AVAudioSourceNode` closure, which is nonisolated. A `@MainActor` seam would
    /// still compile and the tests would still pass if someone later dropped
    /// `nonisolated` from `renderOnAudioThread` — while the actual render closure
    /// broke. Matching the seam's isolation to the real caller turns that into a
    /// same-file compile error instead of a green suite over a broken instrument.
    nonisolated func _testRender(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        renderOnAudioThread(frameCount: frameCount, audioBufferList: audioBufferList)
    }
}

/// Weak holder so the audio-thread render closure references the MainActor voice
/// without retaining it (mirrors WeakSub in SubBassVoice).
private final class WeakMetronome: @unchecked Sendable {
    weak var value: MetronomeVoice?
    init(_ value: MetronomeVoice) { self.value = value }
}
