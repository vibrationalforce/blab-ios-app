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
/// Both wired voices end their render block by `memcpy`-ing a solely-owned scratch
/// array into the buffer list unconditionally — whatever the last DSP stage
/// produced goes downstream verbatim. Individual stages ARE hardened
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
/// ── COVERAGE IS DELIBERATELY PARTIAL ────────────────────────────────────────
/// Wired today: `PolySynthVoice` and `BioReactiveSynthVoice` — the two voices that
/// carry both the user-editable FX chain and the live bio path, i.e. the two whose
/// upstream stage list actually changes, and the only two shaped as scratch-then-
/// copy — plus `SubBassVoice` via the scalar form, since it too runs a per-bus
/// insert FX.
///
/// Of the seven render-block writers in the app, four are still unguarded:
/// `DrumSynthVoice` and `SamplerVoice` (both run an insert FX AFTER writing the
/// buffer list, so their sweep has to go after that call, not at the write),
/// `MetronomeVoice` and `SessionEngine`. Separate slice with its own audio review.
/// Note "render-block writers" is narrower than "inputs to `masterMixer`" —
/// `masterPlayerNode`, the clip player and the warp path also feed that mixer and
/// are outside this guard's shape. Do not read this file as a graph-wide invariant.
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
///   since `NaN > peak` is false, sleeping the voice after ~2.5 s. The other two
///   wired voices have no idle detector, so that particular bound is not general.)
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

    /// Scalar form, for the render blocks that write per-sample straight into the
    /// buffer list instead of rendering to a scratch array first. Same rule, same
    /// result — kept as one definition so the two shapes cannot drift.
    @inline(__always)
    public static func silencingNonFinite(_ sample: Float) -> Float {
        sample.isFinite ? sample : 0
    }
}
