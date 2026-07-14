import Foundation

/// Ordered, audio-thread-safe composition of the EchoelFX processors — the unit
/// the render block, UI, and (later) AUv3 wrapper drive. Signal flow:
///
///   in → filter → saturation → tape → bitcrush → harmonizer → chorus → flanger → phaser → tremolo → delay → reverb → widener → compressor → limiter → out
///
/// The filter sits first so its colour (muffled "underwater" low-pass, telephone
/// band-pass) shapes the source before the echoes and modulation inherit it.
/// Saturation sits next — it gives the additive synth's mathematically-clean sine
/// stack the harmonic density and tube "glue" that makes a tone read as warm and
/// analog instead of thin and digital. On by default at a gentle setting so every
/// take has body; the `.clean` character and the sound editor can dial it out.
/// Each stage is individually bypassable; a bypassed stage is skipped entirely
/// (no work, no state advance). The limiter sits last as a safety brick-wall and
/// is enabled by default. No allocation or locks in the hot loop.
public final class EchoelFXChain: @unchecked Sendable {

    // MARK: - Stages

    /// Stereo tone-shaping filter (one SVF per channel). Drives the "underwater"
    /// / "telephone" / lo-fi characters.
    public let filterL: EchoelSVFilter
    public let filterR: EchoelSVFilter
    /// Analog tape / Bandmaschine / VHS character (wow&flutter + saturation + HF
    /// loss) on the dry through-signal. Sits right after saturation so the warble
    /// and dull colour the source before the echoes/modulation inherit it.
    public let tape: EchoelTape
    public let bitcrush: EchoelBitcrush
    public let harmonizer: EchoelHarmonizer
    public let chorus: EchoelChorus
    public let flanger: EchoelFlanger
    public let phaser: EchoelPhaser
    public let tremolo: EchoelTremolo
    public let delay: EchoelDelay
    public let reverb: EchoelReverb
    public let widener: EchoelStereoWidener
    public let compressor: EchoelCompressor
    public let limiter: EchoelLimiter

    // MARK: - Per-stage bypass (plain reads on the audio thread)
    //
    // SWITCH-CRACKLE RULE (founder: "knistert beim Umschalten von Dingen"): a
    // bypassed stage is skipped entirely, so its delay lines / filter states
    // FREEZE holding old audio. Re-enabling it later (preset/genre/character
    // switch, FX toggle) would burst that stale audio into the mix. Every
    // enable flag therefore resets its stage's state on the RISING edge —
    // in `willSet`, while the flag is still false: the audio thread is
    // skipping the stage at that moment, so the control-plane reset cannot
    // race the render loop.

    public var filterEnabled: Bool = false {
        willSet { if newValue && !filterEnabled { filterL.reset(); filterR.reset() } }
    }
    /// Analog warmth. On by default — the additive source is otherwise a sterile
    /// sum of sines; saturation adds the harmonic body that sounds professional.
    /// (Stateless waveshaper — nothing to reset on enable.)
    public var saturationEnabled: Bool = true
    /// Analog tape / Bandmaschine / VHS character (wow&flutter + saturation + HF
    /// loss). Off by default — a vintage character effect. Rising-edge reset
    /// clears the tape delay line so re-enabling never bursts stale audio.
    public var tapeEnabled: Bool = false {
        willSet { if newValue && !tapeEnabled { tape.reset() } }
    }
    /// Digital lo-fi (bit-depth + sample-rate crush). Off by default; a character
    /// effect for crushed/vintage textures.
    public var bitcrushEnabled: Bool = false {
        willSet { if newValue && !bitcrushEnabled { bitcrush.reset() } }
    }
    /// Pitch-shift harmony voices. Off by default — a character effect surfaced
    /// via the Effects picker (`.harmonizer`).
    public var harmonizerEnabled: Bool = false {
        willSet { if newValue && !harmonizerEnabled { harmonizer.reset() } }
    }
    /// Subtle ensemble chorus. On by default at a gentle setting (see init) so
    /// the additive pad/lead reads as lush and wide rather than thin and centred;
    /// the `.clean` character and the sound editor can switch it off.
    public var chorusEnabled: Bool = true {
        willSet { if newValue && !chorusEnabled { chorus.reset() } }
    }
    public var flangerEnabled: Bool = false {
        willSet { if newValue && !flangerEnabled { flanger.reset() } }
    }
    public var phaserEnabled: Bool = false {
        willSet { if newValue && !phaserEnabled { phaser.reset() } }
    }
    public var tremoloEnabled: Bool = false {
        willSet { if newValue && !tremoloEnabled { tremolo.reset() } }
    }
    public var delayEnabled: Bool = false {
        willSet { if newValue && !delayEnabled { delay.reset() } }
    }
    /// Algorithmic room/hall reverb. Off by default; genre presets enable it to
    /// give a take real space (the additive source has no reverb of its own).
    public var reverbEnabled: Bool = false {
        willSet { if newValue && !reverbEnabled { reverb.reset() } }
    }
    /// Stereo widener (M/S). Off by default; widens the modulation/reverb image.
    public var widenerEnabled: Bool = false {
        willSet { if newValue && !widenerEnabled { widener.reset() } }
    }
    public var compressorEnabled: Bool = false {
        willSet { if newValue && !compressorEnabled { compressor.reset() } }
    }
    public var limiterEnabled: Bool = true {
        willSet { if newValue && !limiterEnabled { limiter.reset() } }
    }

    // MARK: - Saturation params (plain reads on the audio thread)

    /// Pre-gain into the waveshaper [0…1]. 0 ≈ transparent, ~0.3 a warm sheen,
    /// 1 a thick, driven tone.
    public var saturationDrive: Float = 0.30
    /// Wet/dry blend [0…1]. 0.5 keeps the transient clarity of the dry signal
    /// while folding in the saturated harmonics (parallel-style warmth).
    public var saturationMix: Float = 0.5

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.filterL = EchoelSVFilter(sampleRate: sampleRate)
        self.filterR = EchoelSVFilter(sampleRate: sampleRate)
        self.tape = EchoelTape(sampleRate: sampleRate)
        self.bitcrush = EchoelBitcrush(sampleRate: sampleRate)
        self.harmonizer = EchoelHarmonizer(sampleRate: sampleRate)
        self.chorus = EchoelChorus(sampleRate: sampleRate)
        // Gentle default: low wet mix + modest depth + slow rate → ensemble
        // warmth and width without an obvious "seasick" wobble.
        self.chorus.mix = 0.22
        self.chorus.depth = 0.35
        self.chorus.rate = 0.45
        self.flanger = EchoelFlanger(sampleRate: sampleRate)
        self.phaser = EchoelPhaser(sampleRate: sampleRate)
        self.tremolo = EchoelTremolo(sampleRate: sampleRate)
        self.delay = EchoelDelay(sampleRate: sampleRate)
        self.reverb = EchoelReverb(sampleRate: sampleRate)
        self.widener = EchoelStereoWidener(sampleRate: sampleRate)
        self.compressor = EchoelCompressor(sampleRate: sampleRate)
        self.limiter = EchoelLimiter(sampleRate: sampleRate)
    }

    /// Configure both channels of the tone filter together (control plane).
    public func setFilter(mode: EchoelSVFilter.Mode, cutoff: Float, resonance: Float) {
        filterL.mode = mode; filterR.mode = mode
        filterL.cutoff = cutoff; filterR.cutoff = cutoff
        filterL.resonance = resonance; filterR.resonance = resonance
    }

    // MARK: - Process

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        var l = inL
        var r = inR
        if filterEnabled     { l = filterL.process(l); r = filterR.process(r) }
        if saturationEnabled { (l, r) = saturate(l, r) }
        if tapeEnabled       { (l, r) = tape.processStereo(l, r) }
        if bitcrushEnabled   { (l, r) = bitcrush.processStereo(l, r) }
        if harmonizerEnabled { (l, r) = harmonizer.processStereo(l, r) }
        if chorusEnabled     { (l, r) = chorus.processStereo(l, r) }
        if flangerEnabled    { (l, r) = flanger.processStereo(l, r) }
        if phaserEnabled     { (l, r) = phaser.processStereo(l, r) }
        if tremoloEnabled    { (l, r) = tremolo.processStereo(l, r) }
        if delayEnabled      { (l, r) = delay.processStereo(l, r) }
        if reverbEnabled     { (l, r) = reverb.processStereo(l, r) }
        if widenerEnabled    { (l, r) = widener.processStereo(l, r) }
        if compressorEnabled { (l, r) = compressor.processStereo(l, r) }
        if limiterEnabled    { (l, r) = limiter.processStereo(l, r) }
        return (l, r)
    }

    /// Tube-style soft saturation with a small DC bias for even-harmonic warmth.
    /// Pure C-math (`tanhf`) and arithmetic — no allocation, locks, or branches
    /// beyond the caller's enable check, so it is audio-thread safe.
    ///
    /// - A pre-gain `k` (1…4) drives the signal into the tanh knee, adding odd
    ///   harmonics and gentle compression ("glue").
    /// - A bias before the tanh, removed after, makes the curve asymmetric → the
    ///   even harmonics a tube/transformer adds, which read as "warm" not "fuzzy".
    /// - `comp` makeup keeps perceived level roughly constant as drive rises, and
    ///   `saturationMix` blends the saturated tone back against the clean signal
    ///   so transients stay crisp (parallel saturation).
    @inline(__always)
    private func saturate(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let drive = saturationDrive
        let k = 1.0 + drive * 3.0
        let bias = 0.12 * drive
        let dc = tanhf(bias)
        let comp = 1.0 / (1.0 + drive * 1.4)
        let mix = saturationMix
        let wetL = (tanhf(inL * k + bias) - dc) * comp
        let wetR = (tanhf(inR * k + bias) - dc) * comp
        return (inL * (1.0 - mix) + wetL * mix,
                inR * (1.0 - mix) + wetR * mix)
    }

    /// Process separate L/R buffers in place.
    public func processBuffer(left bufL: inout [Float], right bufR: inout [Float], frameCount: Int) {
        let n = Swift.min(frameCount, Swift.min(bufL.count, bufR.count))
        for i in 0..<n {
            let (l, r) = processStereo(bufL[i], bufR[i])
            bufL[i] = l
            bufR[i] = r
        }
    }

    /// Process a mono buffer in place — the chain runs with both channels fed
    /// the same sample and the left result is taken back. Used by mono source
    /// nodes (e.g. the bio synth voice). Audio-thread safe.
    public func processBufferMono(_ buf: inout [Float], frameCount: Int) {
        let n = Swift.min(frameCount, buf.count)
        for i in 0..<n {
            let x = buf[i]
            let (l, _) = processStereo(x, x)
            buf[i] = l
        }
    }

    // MARK: - Reset

    public func reset() {
        filterL.reset()
        filterR.reset()
        tape.reset()
        bitcrush.reset()
        harmonizer.reset()
        chorus.reset()
        flanger.reset()
        phaser.reset()
        tremolo.reset()
        delay.reset()
        reverb.reset()
        widener.reset()
        compressor.reset()
        limiter.reset()
    }
}
