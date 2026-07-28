import Foundation

/// Dynamics processors — audio-thread safe (no allocation or locks in the hot
/// loop). Stereo detection is channel-linked (uses the louder channel) so the
/// stereo image is preserved while gain is applied equally to both sides.
///
/// References: Giannoulis, Massberg & Reiss, "Digital Dynamic Range Compressor
/// Design — A Tutorial and Analysis" (JAES 2012); Zölzer, "DAFX".

// MARK: - Compressor

public final class EchoelCompressor: @unchecked Sendable {

    /// Threshold in dBFS (below this, no compression).
    public var thresholdDb: Float = -18
    /// Compression ratio [1, 20] (1 = no compression).
    public var ratio: Float = 3.0
    /// Attack time in milliseconds.
    public var attackMs: Float = 10 { didSet { recalc() } }
    /// Release time in milliseconds.
    public var releaseMs: Float = 120 { didSet { recalc() } }
    /// Soft-knee width in dB.
    public var kneeDb: Float = 6
    /// Make-up gain in dB.
    public var makeupDb: Float = 0

    /// Decay time of the DETECTOR's peak envelope, in ms — deliberately a constant and
    /// deliberately NOT `releaseMs`. See `processStereo` for the measurement that picked it.
    private static let detectorReleaseMs: Float = 40

    private let sr: Float
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var grState: Float = 0   // current gain reduction in dB (≤ 0)
    private var env: Float = 0       // peak envelope, ≥ 0 — the DETECTOR (see processStereo)
    /// `exp(-1/t)` for the detector — the per-sample factor the envelope decays by. A `let`,
    /// computed once: it depends on nothing a control thread can change, so unlike a cached
    /// `1 - releaseCoeff` it can never go stale beside a coefficient `recalc()` just rewrote.
    private let envDecayFactor: Float

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        let t = Swift.max(0.01, Self.detectorReleaseMs) * 0.001 * sampleRate
        self.envDecayFactor = expf(-1.0 / t)
        recalc()
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let peak = Swift.max(abs(inL), abs(inR))

        // Same state-integrity bail as the limiter below, and it closes a REACHABLE
        // permanent-silence path rather than a theoretical one. `Swift.max(peak, 1e-7)`
        // does NOT filter NaN (`1e-7 >= NaN` is false, so it returns `peak`), so one NaN
        // sample makes `inDb` NaN, both knee comparisons fail into the `else`, `target`
        // becomes NaN, `target < grState` is false, and the release branch writes
        // `grState = NaN` — permanently. Every later sample then returns NaN until
        // `reset()`, which the performer can only reach by toggling the compressor off and
        // on again (`EchoelFXChain.compressorEnabled`'s rising edge — see `reset()` below).
        // ⛔ This clause used to read "which nothing calls in production". That was false and
        // it argued the wrong way: it made the latch sound unrecoverable, which is a reason
        // to panic about a guard that already exists rather than to trust it.
        //
        // This stage sits IMMEDIATELY BEFORE the limiter in `EchoelFXChain`, so the
        // limiter's own non-finite hardening cannot help: the NaN would be manufactured
        // downstream of it, inside the chain. `AudioOutputGuard` still silences the result
        // at the source-node output, which is why the symptom is silence rather than a NaN
        // reaching hardware — and why it would present as the "everything is quiet" class
        // of bug with no crash and no log line to point at.
        //
        // ⚠ TEST THE INPUTS, NOT `peak` — and the sentence above ("`Swift.max(peak, 1e-7)`
        // does NOT filter NaN") is right about `max(peak, 1e-7)` but the FIRST version of
        // this guard read `peak.isFinite`, which is not the same test. `Swift.max(x, y)` is
        // `y >= x ? y : x`, so `max(abs(inL), NaN)` returns `abs(inL)` — finite. A NaN in the
        // RIGHT channel walked past that guard.
        //
        // Scope honestly: that did NOT poison `grState` (the state maths only ever reads
        // `peak`, which stayed finite) and it did not silence anything — the NaN sample left
        // the stage either way, which is deliberate (`AudioOutputGuard` sweeps it downstream).
        // What it did was run a full ballistics update on a HALF-VALID frame. Guarding the
        // inputs makes the guard mean what it says and holds the state on any bad frame.
        guard inL.isFinite, inR.isFinite else {
            let held = powf(10.0, (grState + makeupDb) / 20.0)   // rare path; cost is moot
            return (inL * held, inR * held)
        }

        // PEAK ENVELOPE — the detector. Follows a rise instantly, decays at a FIXED 40 ms.
        // Same shape as `EchoelLimiter`'s (#194), one stage earlier in the chain, but with
        // its own constant rather than `releaseMs` — and that difference is the whole design.
        //
        // WITHOUT ANY ENVELOPE the gain computer reads the RAW sample magnitude, which
        // collapses to zero twice per cycle on any periodic signal. The target collapses with
        // it, the ballistics' release branch walks the gain back up between peaks, and the
        // gain ripples at 2f. A gain moving at 2f multiplying a carrier at f is amplitude
        // modulation — its sidebands land on the THIRD HARMONIC. The compressor was
        // manufacturing distortion out of a clean sine, worst where the period is longest, so
        // this was a BASS defect specifically — the range `SubBassVoice` lives in.
        //
        // WHY 40 ms AND NOT `releaseMs`. The obvious version decays the envelope at
        // `releaseCoeff`, which reads as "one release time, one source of truth". It is the
        // error the decoupled-detector topology exists to avoid (Giannoulis/Massberg/Reiss,
        // level detection): the envelope and the ballistics become TWO cascaded one-poles at
        // the same time constant, and the stage then hangs onto reduction long after the peak
        // that caused it. Measured (bit-accurate Float32 simulation of this exact code; gain
        // ripple over the bass range at −6 dBFS, and GR 100 ms after a 5 ms 0 dBFS transient
        // into a body at −20 dBFS — 2 dB UNDER the threshold, so it must be let go):
        //
        //     detector   ripple 30 Hz   ripple 40 Hz   H3 @40 Hz   GR at +100 ms   t63
        //     raw            0.332          0.249       −41.7 dBc     −1.48 dB    ~120 ms
        //     40 ms          0.076          0.044       −56.2 dBc     −6.16 dB    ~145 ms
        //     releaseMs      0.029          0.017       −65.1 dBc     −9.73 dB    ~210 ms
        //
        // ⛔ DO NOT read the +100 ms column against −12·e^(−100/120) = −5.2 dB. An earlier
        // version of this comment did, and every conclusion it drew from that was wrong. The
        // gain computer's TARGET is −12 dB, but a 5 ms transient into a 10 ms attack only ever
        // reaches −4.40 dB, so the decay starts from there. The like-for-like reference is a
        // RIPPLE-FREE detector with these same ballistics: it reads −4.72 dB at the transient
        // and −2.08 dB at +100 ms. Against that, the raw detector (−1.48) is the CLOSEST of
        // the three at this one measurement point, and 40 ms is ~3× deep. The raw detector is
        // still the defect — for the ripple and the third harmonic, which is what this change
        // is actually for. It is not fixing a release-accuracy problem, and claiming so sends
        // the next tuning pass after a target that does not exist.
        //
        // So 40 ms is CHOSEN, not derived. 25–60 ms is the band that satisfies every
        // assertion in `CompressorDetectorTests`; inside it the trade is monotone — shorter
        // holds less after a transient and leaves more ripple in the bass, longer the reverse.
        // 40 sits mid-band. Moving it is a listening decision, not a derivation, and the tests
        // are written so the whole band passes.
        //
        // THE COST, in full, because the first version of this paragraph named only the small
        // half. Sustained material compresses ~0.6 dB harder (mean −7.13 → −7.76 dB) — that is
        // the small half. The large half is post-transient: a peak the detector HOLDS keeps
        // driving the gain computer after the sound is gone, so on that same 5 ms transient
        // the deepest reduction is −9.20 dB and it arrives 18 ms AFTER the transient ended,
        // against −3.40 dB DURING it with the raw detector. On plucked or percussive material
        // that late duck is what a listener would hear, not the 0.6 dB. It is inherent to a
        // hold-y detector ahead of a gain computer, it is why the constant is short, and it is
        // the specific thing to listen for on device.
        let decayed = env * envDecayFactor
        env = peak > decayed ? peak : decayed

        let inDb = 20.0 * log10f(Swift.max(env, 1e-7))

        // Static gain-computer with quadratic soft knee.
        let r = Swift.max(1.0, ratio)
        let slope = (1.0 / r) - 1.0
        let over = inDb - thresholdDb
        let halfKnee = Swift.max(0.0001, kneeDb) * 0.5
        let target: Float
        if over <= -halfKnee {
            target = 0
        } else if over >= halfKnee {
            target = slope * over
        } else {
            let x = over + halfKnee
            target = slope * (x * x) / (4.0 * halfKnee)
        }

        // Ballistics: fast toward more reduction (attack), slow toward less (release).
        if target < grState {
            grState += (target - grState) * attackCoeff
        } else {
            grState += (target - grState) * releaseCoeff
        }

        let gainLin = powf(10.0, (grState + makeupDb) / 20.0)
        return (inL * gainLin, inR * gainLin)
    }

    /// Current gain reduction in dB (≤ 0), for metering.
    public var gainReductionDb: Float { grState }

    /// Clears BOTH pieces of state. The envelope must be cleared with the gain — leaving a
    /// held peak behind would make the stage start already reduced.
    ///
    /// It IS called in production, from exactly ONE live path: `EchoelFXChain`'s
    /// `compressorEnabled` rising edge (`willSet`). That is the point — switching the
    /// compressor on with stale state applies a gain step to running audio, which is the
    /// switch-crackle this clears. (`EchoelFXChain.reset()` calls it too, but that method
    /// has no production caller of its own, so do not count it as a second path.)
    public func reset() {
        grState = 0
        env = 0
    }

    private func recalc() {
        attackCoeff = coeff(forMs: attackMs)
        releaseCoeff = coeff(forMs: releaseMs)
    }

    @inline(__always)
    private func coeff(forMs ms: Float) -> Float {
        // Clamped at BOTH ends, same as the limiter's and for the same reason. The upper
        // bound is the one that was missing: past ~700 s, `1 - expf(-1/t)` rounds to exactly
        // 0 in Float, the coefficient dies, and `grState` can never move back toward 0 —
        // whatever attenuation it held at that moment becomes permanent, which is the "fail
        // to resting, never to silence" law. ⛔ Nothing writes `releaseMs` or `attackMs`
        // today: `FXPreset` persists only threshold, ratio and makeup, and `EchoelFXView`
        // exposes the same three. So this guards a FUTURE control, exactly like the limiter's
        // — an earlier version of this comment claimed a saved preset could restore a release
        // time, which is not true and would have been read as licence to skip the clamp
        // elsewhere.
        let t = Swift.min(Swift.max(0.01, ms), 10_000) * 0.001 * sr
        return 1.0 - expf(-1.0 / t)
    }
}

// MARK: - Limiter (brick-wall)

/// Brick-wall limiter: for FINITE input, output magnitude never exceeds the ceiling, and
/// the gain that achieves that moves CONTINUOUSLY rather than jumping.
///
/// "For finite input" is not a hedge, it is the exact contract. A non-finite sample takes
/// the bypass in `processStereo` and is scaled by the current gain without any ceiling
/// enforcement — an `inf` in is an `inf` out. That is deliberate: this class is a gain
/// computer, and sanitizing samples belongs to `AudioOutputGuard`, which sweeps at the
/// source-node output — the stage immediately DOWNSTREAM of this whole FX chain
/// (`PolySynthVoice` runs `fxChain.processBuffer`, then `copySilencingNonFinite`). What IS
/// guaranteed for such a sample is that the limiter's own state survives it intact.
///
/// Also true and NOT a rounding-free absolute: the ceiling can be exceeded by up to ~2 ulp
/// (measured worst case 108 ppb over 900k fuzzed samples), because `fl(fl(ceiling/env)·peak)`
/// need not round down. Every assertion allows `ceiling * 1.001`, so nothing depends on the
/// stronger reading — but "never exceeds" means "never by more than one rounding step".
///
/// ⛔ WHY THE ATTACK EXISTS (founder 2026-07-27: "Es knistert. Wie CPU overload bei
/// Ableton oder so"). The previous version had zero attack:
///
///     if peak * g > ceiling { g = ceiling / peak }
///
/// Read what that does to the louder channel: its output becomes
/// `in * ceiling/|in| = sign(in) * ceiling` — EXACTLY the ceiling, every time it is
/// crossed. That is not "a limiter with a fast attack". It is algebraically a
/// **per-sample HARD CLIPPER**, and the waveform comes out flat-topped. Un-oversampled
/// at 48 kHz, hard clipping's high-order odd harmonics fold back below Nyquist as
/// INHARMONIC ALIASING — the gritty, digital, "CPU-overload" texture the founder
/// described, not the periodic click an earlier note of mine claimed.
///
/// It fired constantly, not rarely: the poly engine's makeup gain lags a chord attack by
/// ~250 ms, so every sparse→dense entry overshoots the ceiling already at velocity 0.47.
///
/// THE FIX, and why it is this one and not lookahead. Two stages, both required:
/// a PEAK-ENVELOPE detector (holds the peak between cycles) feeding a gain that moves
/// toward its target with a finite ATTACK. Sustained loud material is then SCALED
/// (waveform shape preserved) instead of flat-topped, and the aliasing goes with it. A
/// final per-sample guard keeps the ceiling absolute, so it can still engage on a
/// transient that rises faster than the attack — one brief clip instead of a continuous
/// one. Skipping the detector and running the ballistics off the raw sample does NOT
/// work; `processStereo` says why at the line that computes `env`.
///
/// A lookahead delay line would remove even that residue, but it would put this chain
/// ~1.3 ms behind `SubBassVoice`, which has no such chain — a real phase offset between
/// the bass and the felt layer, traded for a residue that only appears on isolated
/// transients. If the founder still hears grit after this, lookahead is the next step,
/// not a substitute for it.
public final class EchoelLimiter: @unchecked Sendable {

    /// Output ceiling in dBFS.
    public var ceilingDb: Float = -0.3 { didSet { recalc() } }
    /// Attack time in milliseconds — how fast the gain may FALL. Short enough to catch a
    /// note onset, long enough that the gain is a smooth signal rather than a step train.
    public var attackMs: Float = 0.5 { didSet { recalc() } }
    /// Release time in milliseconds.
    public var releaseMs: Float = 60 { didSet { recalc() } }

    private let sr: Float
    private var ceilingLin: Float = 1
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var env: Float = 0       // peak envelope, ≥ 0
    private var gain: Float = 1.0    // ≤ 1

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        recalc()
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let peak = Swift.max(abs(inL), abs(inR))

        // A non-finite sample must not reach the detector. ABSENT ANY GUARD, `inf` would pin
        // `env` at infinity permanently (`inf * decay == inf`) and a NaN in the LEFT channel
        // would reach `env` the same way, so either one would silence the limiter for good —
        // a state bug far worse than the bad sample itself. (Those two are the cases the
        // ORIGINAL `peak.isFinite` guard already caught; the note below is about the one it
        // did not.) Skip the whole state update and apply the
        // gain already held. Cleaning the SAMPLE up remains `AudioOutputGuard`'s job
        // downstream; this only guarantees the limiter survives one.
        //
        // ⚠ Guard the INPUTS, not `peak` — the version I shipped first tested `peak.isFinite`
        // and claimed "NaN propagates through `Swift.max`". It does not, in this argument
        // order: `Swift.max(x, y)` is `y >= x ? y : x`, so `max(abs(inL), NaN)` returns
        // `abs(inL)`. A right-channel NaN passed that guard and ran a full envelope+ballistics
        // update on a half-valid frame. `inf` was always caught in EITHER channel
        // (`inf >= x` is true, so `max` returns it), and a left-channel NaN too — so this is
        // guard hygiene, not a silence bug. It is corrected because the comment was false and
        // false DSP folklore is how the next session builds on sand.
        guard inL.isFinite, inR.isFinite else { return (inL * gain, inR * gain) }

        // PEAK ENVELOPE — decays at the release rate, follows a rise instantly.
        //
        // This stage is not optional. If the detector reads the RAW sample it springs back
        // to a target of unity at every zero crossing (15.8% of samples on a 200 Hz sine at
        // 12 dB over), the slow release walks the gain up between peaks, and that ripple
        // re-engages the absolute guard below — the flat-topping this class exists to
        // remove comes back, periodically instead of continuously.
        //
        // Measured on that signal (bit-accurate simulation of these three variants, DSP
        // review 2026-07-27) — third harmonic, and the inharmonic floor above 1 kHz that IS
        // the audible "grit":
        //
        //     old (no ballistics at all)   H3 −31.2 dBc     floor −80.4 dB
        //     ballistics, RAW detector     H3 −37.9 dBc     floor −86.8 dB
        //     ballistics + this envelope   H3 −73.4 dBc     floor −90.7 dB
        //
        // So the envelope is worth 35 of the 42 dB. The ballistics alone buy ~7.
        // (Two earlier numbers here were mine and were wrong — "walks up ~0.04 per cycle"
        // is really 0.0097, and "a quarter of every cycle" is really 9.2%. They are replaced
        // by the measurements above rather than quietly deleted, because the conclusion
        // survived them and the next session should trust the measurement, not my estimate.)
        // `1 - releaseCoeff` is exactly `exp(-1/t)`, computed here rather than cached as a
        // field. One FSUB per sample, next to a division that already costs far more — and
        // in exchange `releaseCoeff` stays the SINGLE source of truth. A cached `envDecay`
        // would be a value DERIVED from `releaseCoeff` but stored separately, so a control
        // thread running `recalc()` could leave the render thread reading a new
        // `releaseCoeff` beside an old `envDecay` (arm64 gives no store ordering here).
        // Same lesson as `EchoelSVFilter` (see its file doc): do not create a pair that has
        // to stay consistent — remove the pairing instead.
        let decayed = env * (1 - releaseCoeff)
        env = peak > decayed ? peak : decayed

        // ⚠ THE INVARIANT THE CEILING GUARANTEE RESTS ON: `env >= peak`, established by the
        // line above. It is what makes the absolute guard at the bottom sufficient —
        // `target = ceiling/env` gives `peak * target <= ceiling` only because `env >= peak`.
        // If a later change makes this detector an RMS, or smooths its RISE, `env` can fall
        // below `peak` and that guard silently stops clamping. Do not weaken the rise.
        //
        // The gain the envelope WOULD need. `env <= ceiling` ⇒ 1, so quiet material has a
        // target of unity and the smoother simply releases toward it.
        let target = env > ceilingLin ? ceilingLin / env : 1

        // Asymmetric one-pole: fall fast (attack), recover slowly (release). Both are
        // one-poles rather than jumps, so `gain` is a continuous signal — which is the
        // whole point: a discontinuous gain multiplied into audio IS distortion.
        let coeff = target < gain ? attackCoeff : releaseCoeff
        var g = gain + (target - gain) * coeff

        // THE CEILING STAYS ABSOLUTE. The smoother may not have arrived yet on a fast
        // transient; this guard is what keeps the guarantee in the class doc true.
        //
        // On the sustained material that caused the report it engages on ~1.7% of samples
        // rather than 16.7%, and where it does the correction is under 0.01 dB — the
        // smoothed gain settles a hair ABOVE `ceiling/env`, not at or below it. (An earlier
        // version of this comment said "it no longer engages", stated as an absolute. It
        // was not one.)
        if peak * g > ceilingLin { g = target }
        gain = g
        return (inL * g, inR * g)
    }

    /// Current gain reduction in dB (≤ 0), for metering.
    public var gainReductionDb: Float { 20.0 * log10f(Swift.max(gain, 1e-7)) }

    public func reset() { gain = 1.0; env = 0 }

    private func recalc() {
        // Hoisted out of `processStereo`, where `powf(10, ceilingDb/20)` was recomputed
        // for a CONSTANT on every sample — ~200k needless transcendental calls per second
        // across the active chains.
        ceilingLin = powf(10.0, ceilingDb / 20.0)
        attackCoeff = Self.coeff(ms: attackMs, sr: sr)
        releaseCoeff = Self.coeff(ms: releaseMs, sr: sr)
    }

    @inline(__always)
    private static func coeff(ms: Float, sr: Float) -> Float {
        // Clamped at BOTH ends. The upper bound is the one that matters and was missing:
        // past ~700 s, `1 - expf(-1/t)` rounds to exactly 0 in Float, the coefficient dies,
        // and the limiter latches at whatever attenuation it happened to hold — permanent
        // silence, the exact failure mode "fail to resting, never to silence" exists to
        // forbid. No writer can reach that today (nothing sets attackMs/releaseMs), so this
        // is a guard against a future control, not a live bug. 10 s is far beyond any
        // musical release and still leaves the coefficient ~2e-6, comfortably normal.
        let t = Swift.min(Swift.max(0.01, ms), 10_000) * 0.001 * sr
        return 1.0 - expf(-1.0 / t)
    }
}
