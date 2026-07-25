import Foundation

/// Non-finite sweep at a voice's SOURCE-NODE OUTPUT — the point where a render
/// block hands its scratch buffer to CoreAudio's `AudioBufferList`.
///
/// It is NOT the last word before the hardware. Three nodes sit downstream of every
/// source node (`AudioEngine.attachSourceNode` → `AudioEngine.prepareGraph`):
///
///     sourceNode → masterMixer → AutoMixChain(EQ → gain) → mainMixerNode → output
///
/// The `AutoMixChain` EQ is itself recursive and can go non-finite on its own. This
/// guard stops a voice POISONING that chain; it does not certify what leaves it.
///
/// ── WHY IT EXISTS ────────────────────────────────────────────────────────────
/// A render block's last act is to put its samples in the buffer list, and it does
/// so unconditionally — whatever the final DSP stage produced goes downstream
/// verbatim. Individual stages ARE hardened
/// (`EchoelDDSP.applyBioReactive` sanitizes its bio inputs, `EchoelSVFilter`
/// flushes non-finite state), but that is per-stage defence over a mutable,
/// growing list of stages, and it demonstrably has holes: `EchoelDDSP` sweeps its
/// mix, then runs the fast-tanh `x·(27 + x²)/(27 + 9x²)` — a finite-but-large `x`
/// overflows `x²` to `inf`, and `inf/inf` is NaN, produced AFTER that sweep.
///
/// Nothing downstream cleans it up. The limiter makes it worse, not better:
/// `EchoelLimiter.processStereo` is a gain computer, not a clamp — for `peak = inf`
/// it solves `g = ceiling / peak = 0` and returns `inf * 0`, i.e. it CONVERTS an
/// infinity into a NaN. NaN then fails every comparison, so it survives the
/// remaining branches untouched and poisons each recursive node it reaches.
///
/// ── COVERAGE ────────────────────────────────────────────────────────────────
/// All seven of the app's `AVAudioSourceNode` render blocks are wired. WHICH ENTRY
/// POINT each needs is decided by where the last write happens, not by whether the
/// voice uses a scratch array:
/// * `PolySynthVoice`, `BioReactiveSynthVoice` — buffer form. The copy out of
///   scratch IS the last write, so the sweep folds into it.
/// * `SubBassVoice`, `MetronomeVoice`, `SessionEngine` — scalar form. No scratch;
///   they compute and write one sample at a time.
/// * `DrumSynthVoice`, `SamplerVoice` — in-place form. Both DO use a scratch
///   array, but they then run a per-channel insert FX over the hardware buffer
///   afterwards, so the copy is not the last write and there is nothing left to
///   fold into.
///
/// THE INVARIANT IS EXACTLY THIS AND NO WIDER: every SOUNDING path of every
/// render block of ours passes the samples IT WRITES through this guard. It says
/// nothing about bytes a block never touches — most blocks write channel 0 only
/// (`PolySynthVoice` writes 0 and 1), so a buffer list presenting more channels
/// than that would leave the surplus holding whatever it already held. That is
/// unreachable today: it needs the nil-format fallback at each node's
/// construction, and `AVAudioFormat(standardFormatWithSampleRate:channels:)` does
/// not fail. The non-sounding paths — the
/// `silence(...)` helpers and the launch-silence / not-playing early-outs — bypass
/// the guard, which is correct: they write literal zeros, and a zero is finite by
/// construction.
///
/// The `AVAudioPlayerNode`s that feed the same mixer are covered SEPARATELY, by
/// `AudioOutputGuard.sweepNonFinite(_ buffer: AVAudioPCMBuffer)` in `Audio/`. Do
/// not dismiss them as Apple nodes replaying decoded PCM — they replay buffers WE
/// build (baked fade envelopes, `WSOLAStretcher` renders in `AudioClipPlayer` /
/// `TimelineAudioSink`) carrying user-imported audio no finiteness check touches.
/// Those sweep at FILL time; see that file for why not at schedule time.
///
/// ── THE REMAINING GAP, NAMED ────────────────────────────────────────────────
/// `TimelineAudioSink`'s Clean path uses `scheduleSegment(file:startingFrame:
/// frameCount:)`, which streams straight from the `AVAudioFile`. There is no
/// buffer of ours in that path to sweep, so a float32 file carrying NaN/inf bit
/// patterns still reaches `masterMixer` through it. Closing that would mean
/// decoding the file ourselves purely to sanitise it — a real cost on the main
/// playback path for a fault nobody has reported. Deliberately open.
///
/// Nor does any of this say anything about what leaves `AutoMixChain`.
///
/// A NEW render block does not inherit this. Wire it, and add it to the list above.
///
/// ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────
/// * **No clamping to [-1, 1].** That is a limiter's job and belongs where it can
///   be shaped; doing it here would silently change the sound of every loud patch
///   and hide a real gain-staging bug behind a safety net.
/// * **No muting the block on a bad sample.** An isolated poisoned sample replaced
///   by zero is a single-sample click; muting the whole block would turn it into an
///   audible dropout, the worse failure. This bounds the damage of an ISOLATED
///   fault only. Under a SUSTAINED one the voice goes quiet either way, and the
///   guard offers no recovery — it cleans the OUTPUT, never the recursive state
///   behind it. (In `PolySynthVoice` that shows up as the idle detector, which
///   measures block peak before this guard and scores an all-NaN block as silent
///   since `NaN > peak` is false, sleeping the voice after ~2.5 s. None of the four
///   other wired voices has an idle detector, so that bound is not general.)
///
/// Audio-thread safe: no allocation, no locks, no ObjC, no I/O, and branch-free per
/// sample by construction — the ternary has no data-dependent control flow.
///
/// There is no vDSP equivalent worth reaching for: `vDSP_vclip`/`vmin`/`vmax` are
/// comparison-based, so NaN passes through them untouched — exactly the case this
/// exists for. Building it correctly out of vDSP needs a mask buffer and three
/// passes, i.e. more memory traffic than this one fused pass.
public enum AudioOutputGuard {

    /// Copy `count` samples from `src` to `dst`, replacing any non-finite sample
    /// with silence. Finite audio is passed through bit-exact.
    ///
    /// Writes exactly `count` samples and never one more — callers zero-fill the
    /// remainder of the hardware buffer themselves.
    @inline(__always)
    public static func copySilencingNonFinite(
        from src: UnsafePointer<Float>,
        to dst: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard count > 0 else { return }
        for i in 0..<count {
            dst[i] = silencingNonFinite(src[i])
        }
    }

    /// In-place form, for the render blocks that have already written the buffer
    /// list and then process it further (a per-channel insert FX applied over the
    /// hardware buffer). The sweep has to come after that stage, so there is no
    /// copy left to fold it into.
    ///
    /// Must be called unconditionally, NOT inside the insert-FX loop: that loop is
    /// skipped entirely on a clean channel, which is exactly the path where nothing
    /// else would catch a bad sample from the voice itself.
    @inline(__always)
    public static func sweepNonFinite(
        _ buffer: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard count > 0 else { return }
        for i in 0..<count {
            buffer[i] = silencingNonFinite(buffer[i])
        }
    }

    /// Scalar form, for the render blocks that write per-sample straight into the
    /// buffer list instead of rendering to a scratch array first. Same rule, same
    /// result — the buffer forms delegate here so the shapes cannot drift.
    @inline(__always)
    public static func silencingNonFinite(_ sample: Float) -> Float {
        sample.isFinite ? sample : 0
    }
}
