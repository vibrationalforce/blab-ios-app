import Foundation

/// Real-time granular texture stage — sprays short windowed grains of the recent
/// input back over the dry signal, optionally pitch-shifted. Audio-thread safe:
/// one pre-allocated delay line, a fixed-size grain pool, no allocation, no
/// locks, no branches into Foundation on the hot path.
///
/// ⭐ WHY IT EXISTS: the founder's vocal-chain ask names it directly ("Monitoring
/// und komplette Vocal chain mit Autotune …, Harmonizer, Voice clone!?, Granular
/// Effekt"). The chain had fifteen stages and none was granular; every `granular`
/// hit in `Sources/` was the unrelated word "granularity" or `EchoelHarmonizer`
/// describing its own delay-line technique.
///
/// ⭐ WIRED SINCE #687, and the ⛔ block that stood here said "PURE CORE ONLY … NOT
/// a stage of `EchoelFXChain`". It is now a stage, at six sites: the declaration,
/// the `granularEnabled` bypass with the switch-crackle `willSet`, construction at
/// the chain's sample rate, the render path, `reset()`, and — the site a careless
/// wiring misses — `noteRenderSleeping()`, which matters here more than anywhere
/// else in the chain because this stage holds the longest buffer in it.
///
/// ⛔ WHAT IS STILL MISSING, so this note does not simply flip to a rosier lie:
/// **it is not persisted and it has no door.** `FXPreset` carries no granular
/// field, so a preset save/recall silently drops whatever was dialled in, and no
/// panel row can turn it on. Both are registered next slices. The stage is inert
/// twice over until then — `granularEnabled` is false AND `mix` is 0 — so nothing
/// can hear it yet. Do not cite it as a shipping effect.
///
/// METHOD. A ring buffer holds the recent past. A scheduler launches grains at a
/// rate derived from `density` and `grainMilliseconds`; each grain picks a start
/// point within `spraySeconds` of the write head and plays forward at the ratio
/// `pitchSemitones` asks for, under a raised-cosine window that starts and ends at
/// exactly zero — that window is the whole reason a grain cannot click. Grains sum
/// and are scaled by the expected overlap, so density cannot run the output away.
///
/// ⚠️ THE RNG IS LOCAL ON PURPOSE, and it is not an oversight to be deduplicated.
/// `SeededRNG` lives in `Sequencer/BioComposer.swift`, and `DSP/` must not reach
/// for a Core or Sequencer type — the one-way dependency rule guarded by
/// `TheDSPLayerStaysFoundationOnlyTests`. A DSP file that imports a sequencer type
/// has stopped being a pure processor. Hence the six-line LCG below.
public final class EchoelGranular: @unchecked Sendable {

    // MARK: - Control-plane parameters (plain reads on the audio thread)

    /// Wet blend [0…1]. **0 is an exact bypass**: the stage returns its (sanitised)
    /// input untouched and does not advance a single grain. That is the house
    /// switch-crackle behaviour — a bypassed stage freezes rather than decaying,
    /// so re-enabling it starts from silence instead of from stale audio.
    public var mix: Float = 0
    /// Grain length in milliseconds. Short reads as texture/stutter, long as a
    /// smeared cloud. Clamped to 10…500 on use.
    public var grainMilliseconds: Float = 80
    /// 0…1 → how thickly grains overlap. 1 is a continuous cloud, 0 the sparsest
    /// stream this stage will schedule (it never stops scheduling entirely — a
    /// silent-but-enabled effect is indistinguishable from a broken one).
    public var density: Float = 0.5
    /// How far back into the recent past a grain may start, in seconds.
    public var spraySeconds: Float = 0.05
    /// Grain playback transposition in semitones. 0 = the grain plays at source
    /// pitch and the stage is a pure texture/smear.
    public var pitchSemitones: Float = 0
    /// 0 = every grain centred, 1 = grains scattered hard left/right.
    public var stereoSpread: Float = 0.5

    // MARK: - Limits

    /// The grain pool size. A hard cap, not a target: the scheduler drops a launch
    /// rather than growing anything, because growing would allocate.
    public static let maxGrains = 8

    /// The raised-cosine grain envelope, exposed because it carries the no-click
    /// promise and a pure function is the only honest way to test it.
    /// `position01` outside 0…1 returns 0 — a grain past its end contributes
    /// nothing rather than wrapping into a discontinuity.
    @inline(__always)
    public static func window(_ position01: Float) -> Float {
        guard position01.isFinite, position01 >= 0, position01 <= 1 else { return 0 }
        return 0.5 - 0.5 * cosf(2.0 * Float.pi * position01)
    }

    // MARK: - State

    private struct Grain {
        var active = false
        var delay: Float = 0        // current read distance behind the write head
        var delayStep: Float = 0    // added per output sample; encodes the pitch ratio
        var position: Float = 0     // 0 … length, in output samples
        var length: Float = 1
        var gainL: Float = 1
        var gainR: Float = 1
    }

    private let sr: Float
    private let lineL: EchoelDelayLine
    private let lineR: EchoelDelayLine
    private let maxDelay: Float
    private var grains: [Grain]
    private var spawnAccumulator: Float = 0
    private var rngState: UInt64
    private let seed: UInt64

    /// `seed` is explicit and defaulted so a test can pin the grain pattern. Two
    /// instances with the same seed produce identical output for identical input.
    public init(sampleRate: Float = 48000, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        // `.isFinite` as well as `> 0`: NaN is rejected by the comparison alone, but
        // `.infinity` passes it and then reaches `Int((inf * sr).rounded(.up))` inside
        // `EchoelDelayLine.init`, which TRAPS. Init-time, not the audio thread — still a
        // crash, and one word closes it.
        self.sr = (sampleRate.isFinite && sampleRate > 0) ? sampleRate : 48000
        // 1 s holds the widest spray plus the delay swing a half-second grain can
        // accumulate at the lowest supported ratio, with room to spare.
        self.lineL = EchoelDelayLine(maxDelaySeconds: 1.0, sampleRate: self.sr)
        self.lineR = EchoelDelayLine(maxDelaySeconds: 1.0, sampleRate: self.sr)
        self.maxDelay = Float(lineL.maxDelaySamples - 2)
        self.grains = [Grain](repeating: Grain(), count: Self.maxGrains)
        self.seed = seed
        self.rngState = seed
    }

    /// How many grains are sounding right now. Test-facing; nothing on the audio
    /// thread reads it.
    public var activeGrainCount: Int { grains.reduce(0) { $0 + ($1.active ? 1 : 0) } }

    // MARK: - Render

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        // Sanitise at the boundary, ALWAYS — before the bypass test, so a single
        // NaN can never enter the ring buffer and poison every later grain. This
        // is why "exact bypass" is stated for FINITE input only.
        let dryL = inL.isFinite ? inL : 0
        let dryR = inR.isFinite ? inR : 0
        lineL.write(dryL)
        lineR.write(dryR)

        let m = Swift.min(Swift.max(mix.isFinite ? mix : 0, 0), 1)
        guard m > 0 else { return (dryL, dryR) }

        let lengthSamples = Swift.min(Swift.max(grainMilliseconds.isFinite ? grainMilliseconds : 80,
                                                10), 500) * 0.001 * sr
        let dens = Swift.min(Swift.max(density.isFinite ? density : 0.5, 0), 1)
        // Overlap 0.5 … 3.5 grains. Never zero: an enabled effect that schedules
        // nothing reads as broken, so the floor is deliberate.
        let overlap = 0.5 + 3.0 * dens
        let grainsPerSample = overlap / lengthSamples

        spawnAccumulator += grainsPerSample
        while spawnAccumulator >= 1 {
            spawnAccumulator -= 1
            spawn(lengthSamples: lengthSamples)
        }

        var wetL: Float = 0
        var wetR: Float = 0
        for i in 0..<grains.count where grains[i].active {
            let g = Self.window(grains[i].position / grains[i].length)
            // `clamped(to:)`, NOT `min(max(…))`: the latter is a NO-OP for NaN (every
            // comparison against NaN is false), and `EchoelDelayLine.read` says in its own
            // body that the next step after the clamp is an `Int(d)` that TRAPS on NaN —
            // a crash on the audio thread, not a degradation. CLAUDE.md records this as a
            // shipped permanent-silence class. The line clamps again internally; this one
            // exists so the value handed over is already sane.
            let d = grains[i].delay.clamped(to: 1.0...maxDelay)
            wetL += lineL.read(delaySamples: d) * g * grains[i].gainL
            wetR += lineR.read(delaySamples: d) * g * grains[i].gainR
            grains[i].position += 1
            grains[i].delay += grains[i].delayStep
            if grains[i].position >= grains[i].length { grains[i].active = false }
        }

        // The windows of `overlap` simultaneous grains sum to about overlap/2, so
        // dividing by that keeps a dense cloud at roughly dry level instead of
        // letting density double as a volume control.
        //
        // ⭐ This is the COLA condition, not a heuristic, and the reason is worth keeping:
        // spawning is driven by an accumulator incremented by a CONSTANT, so the grain hop is
        // uniform (`length/overlap` samples) — and Hann windows at a uniform hop sum to
        // exactly overlap/2. The randomness in this stage is in the start POINT and the pan,
        // never in the spawn timing. Make spawning stochastic and this normalisation stops
        // being exact.
        let norm = 1.0 / Swift.max(1.0, overlap * 0.5)
        let outL = dryL * (1 - m) + wetL * norm * m
        let outR = dryR * (1 - m) + wetR * norm * m
        return (outL.isFinite ? outL : dryL, outR.isFinite ? outR : dryR)
    }

    /// Silence every grain and rewind the buffers. Returns the stage to exactly the
    /// state a freshly constructed one is in, seed included — so a reset instance
    /// and a new instance render the same thing.
    public func reset() {
        for i in 0..<grains.count { grains[i] = Grain() }
        spawnAccumulator = 0
        rngState = seed
        lineL.reset()
        lineR.reset()
    }

    // MARK: - Private

    private func spawn(lengthSamples: Float) {
        guard let slot = grains.firstIndex(where: { !$0.active }) else { return }
        let spray = Swift.min(Swift.max(spraySeconds.isFinite ? spraySeconds : 0.05, 0), 0.5) * sr
        let semis = Swift.min(Swift.max(pitchSemitones.isFinite ? pitchSemitones : 0, -24), 24)
        let ratio = powf(2.0, semis / 12.0)
        // The write head advances one sample per output sample; a grain reading at
        // `ratio` therefore needs its distance behind that head to change by
        // (1 - ratio) each sample. Up-shifts walk toward the head, down-shifts away.
        let step = 1.0 - ratio
        // ⛔ THE COMMENT HERE NAMED THE WRONG DIRECTION AND THE WRONG BOUNDARY. It said
        // "a DOWN-shifting grain cannot walk past the END of the line". `step = 1 - ratio`,
        // so `-step > 0` means `ratio > 1`, an UP-shift — and an up-shifting grain's delay
        // SHRINKS, so it walks toward the write head (the `delay == 1` floor), the opposite
        // boundary. The arithmetic was right; the sentence a later session would reason from
        // was wrong on both nouns.
        //
        // Start far enough back that an up-shifting grain cannot reach the write head before
        // its window closes. Down-shifts need no headroom: they walk the other way, and the
        // 1 s line absorbs their swing.
        //
        // ⚠️ AND THE WALK IS BUDGETED, not just offset. Clamping only the START let a long
        // up-shifting grain run out of line mid-window: at 500 ms and +24 st the wanted start
        // is 74 401 samples against a 65 532-sample line, so `delay` bottomed out at 1 and the
        // grain SILENTLY STOPPED PITCH-SHIFTING for its tail, reading live input at unity
        // instead. No trap and no click — the window stayed intact — which is exactly why it
        // would never have surfaced as a bug report. Both trigger points sit inside the public
        // parameter ranges (>438 ms at default spray, >288 ms at maximum spray), so this is
        // reachable, not theoretical. Shortening the grain keeps the ratio true for its whole
        // life, which is the property that matters.
        let walk = Swift.max(0, -step)
        let budget = Swift.max(1, maxDelay - 1 - spray)
        let len = walk > 0 ? Swift.min(lengthSamples, budget / walk) : lengthSamples
        let headroom = walk * len
        let start = 1 + next01() * spray + headroom
        let spread = Swift.min(Swift.max(stereoSpread.isFinite ? stereoSpread : 0.5, 0), 1)
        let pan = (next01() * 2 - 1) * spread            // -1 … +1
        grains[slot] = Grain(active: true,
                             delay: Swift.min(start, maxDelay),
                             delayStep: step,
                             position: 0,
                             length: Swift.max(len, 1),
                             gainL: sqrtf(Swift.max(0, 0.5 * (1 - pan))),
                             gainR: sqrtf(Swift.max(0, 0.5 * (1 + pan))))
    }

    /// Six-line LCG (Numerical Recipes constants). Local by the layering rule in
    /// this file's header — NOT a duplicate to be folded into `SeededRNG`.
    @inline(__always)
    private func next01() -> Float {
        rngState = rngState &* 1_664_525 &+ 1_013_904_223
        return Float(rngState >> 40) / Float(1 << 24)
    }
}
