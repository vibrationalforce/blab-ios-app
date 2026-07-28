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
        willSet {
            if newValue && !filterEnabled {
                filterL.reset(); filterR.reset()
                // #138 SLICE 2 — THE THIRD SNAP EDGE, and the one that is easy to miss.
                // `FXBioModulator.enableStage` flips this the first time a bio route
                // contributes. Without the snap, the first audible thing after a body
                // route engages would be a sweep up from whatever the glide happened to
                // hold — the stale-value artefact `snap` exists to prevent, arriving
                // exactly at the moment the user is listening for the body to take hold.
                snapFilterToTarget()
            }
        }
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

    // MARK: - Tone filter: TARGET (control plane) vs. GLIDE (audio) — #138 Slice 2

    /// THE DEFECT THIS SPLIT EXISTS FOR. Nothing in this chain smoothed its own
    /// parameters. `FXBioModulator` writes at 30 Hz off a bio carrier that itself only
    /// updates at ~10 Hz, so a body-driven filter sweep was a staircase with ten steps a
    /// second — and on a resonant filter every step is an audible edge, not a sweep.
    ///
    /// WHY A FACADE RATHER THAN GLIDING `filterL.cutoff` IN PLACE, which is the obvious
    /// and wrong fix: five places outside this file READ that field — `FXBioModulator`
    /// captures its modulation BASE from it, `FXPreset` saves from it, `EchoelFXView`
    /// seeds its view model from it. Glide it directly and the driver would capture a
    /// value caught mid-glide and then modulate around a random intermediate, the saved
    /// preset would store wherever the sweep happened to be, and the UI would show a
    /// number the user never set. So: THIS is the authoritative control-plane number
    /// (what the user set, what gets saved, what the driver modulates around), and
    /// `filterL/filterR.cutoff` becomes an internal audio mirror that only the block
    /// entry points below write. Same shape `EchoelDelay` already uses for its read tap.
    ///
    /// Writers: the UI fader and the 30 Hz driver GLIDE; `setFilter`, `reset()` and
    /// `filterEnabled`'s rising edge SNAP.
    public var filterCutoff: Float = 2000.0
    /// Companion target for resonance — same contract as `filterCutoff`.
    public var filterResonance: Float = 0.3

    /// Audio-side mirrors. Stepped once per block in `processBuffer`/`processBufferMono`,
    /// never per sample: `EchoelSVFilter.cutoff`'s `didSet` runs `tanf`, and the filter's
    /// integrators cannot resolve cutoff motion inside one block anyway — ~10 coefficient
    /// updates per glide instead of ~3000, for no audible difference.
    private var cutoffGlide = ParamGlide(2000.0)
    private var resonanceGlide = ParamGlide(0.3)
    /// `expf` is not free, and the coefficient only changes when the host hands us a
    /// different buffer size. Cached against the LAST SEEN `frameCount` — never against
    /// an assumed 256, which would make the glide's wall-clock duration scale with the
    /// host's buffer, reintroducing exactly the rate-dependence `ParamGlide.coefficient`
    /// is formulated to remove.
    private var glideCoefficient: Float = 1
    private var glideCoefficientFrames: Int = 0
    private let sampleRateHz: Float

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.sampleRateHz = sampleRate > 0 && sampleRate.isFinite ? sampleRate : 48000
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
    ///
    /// SNAPS rather than glides, and that is the point of having both. Its callers are
    /// `FXPreset.apply`, `GenreFX` and `FXCuratedLibrary` — a preset load, a genre change,
    /// a character switch. Gliding there would be WRONG, not merely fast: the new sound
    /// would arrive as a 50 ms sweep from the old one, which is an artefact of the switch
    /// rather than part of either sound. The UI fader and the 30 Hz bio driver glide; the
    /// document-level changes land.
    public func setFilter(mode: EchoelSVFilter.Mode, cutoff: Float, resonance: Float) {
        filterCutoff = cutoff
        filterResonance = resonance
        filterL.mode = mode; filterR.mode = mode   // discrete — nothing to glide
        snapFilterToTarget()
    }

    /// Land the tone-filter mirror on the current targets, skipping the glide.
    ///
    /// The single place every snap edge goes through, and it exists in this form for a
    /// reason worth stating: each edge used to write the RAW TARGET into the SVF right
    /// after snapping the glide, which quietly bypassed `ParamGlide.snap`'s non-finite
    /// guard. A NaN `filterCutoff` — one bad frame away, since the 30 Hz bio driver writes
    /// this field — would then reach a recursive filter, where one NaN is permanent
    /// silence. What reaches `filterL/filterR` here is always `ParamGlide.value`, i.e. the
    /// last FINITE value, never the target itself.
    ///
    /// PUBLIC because of the fourth edge, which is not in this file. `PolySynthVoice` and
    /// `BioReactiveSynthVoice` gate the whole chain behind `fxEnabled`; while that gate is
    /// off, `processBuffer` is never called, so the glide FREEZES — while `filterCutoff`
    /// keeps moving under the UI fader and the 30 Hz driver. Re-enabling insert FX would
    /// then open with a 50 ms resonant sweep out of a value the user last heard minutes
    /// ago: exactly the stale-value artefact the other three edges exist to prevent, on a
    /// path that had no edge. Those two voices call this on their false→true edge.
    ///
    /// Control-plane only (main thread). It can be clobbered by a block that lands
    /// between the snap and the caller's gate flip — the cost is bounded to one ≤50 ms
    /// glide instead of a jump, and the next block heals it, so this is documented rather
    /// than defended with a generation counter the audio thread would have to read.
    public func snapFilterToTarget() {
        cutoffGlide.snap(to: filterCutoff)
        resonanceGlide.snap(to: filterResonance)
        let c = cutoffGlide.value, q = resonanceGlide.value
        filterL.cutoff = c;    filterR.cutoff = c
        filterL.resonance = q; filterR.resonance = q
    }

    /// Advance the tone-filter glide by ONE block and publish it into the SVFs.
    ///
    /// Called from the two block entry points only. Kept separate rather than inlined so
    /// the one invariant is stated in one place: **the glide advances once per block, never
    /// per sample.** `EchoelSVFilter.cutoff`'s `didSet` runs `tanf`, and the filter's
    /// integrators cannot resolve cutoff motion inside a single block — per-sample gliding
    /// would cost ~3000 transcendental calls per glide instead of ~10 for no audible gain.
    ///
    /// Audio-thread safe: pure arithmetic plus `expf` (only when the host's buffer size
    /// changes) and `tanf` inside the SVF's own `didSet`, both on the permitted C-math
    /// list. No allocation, no locks, no shared mutable state beyond the chain itself.
    ///
    /// ⚠️ The SVF's equality guard is what keeps this cheap on a settled parameter: once
    /// the glide reaches its target, `ParamGlide` returns the exact target every block, the
    /// assignment is a no-op comparison, and `updateCoefficients()` stops being called.
    @inline(__always)
    private func advanceFilterGlide(frameCount: Int) {
        // `filterEnabled` is part of the guard, not an optimisation. A bypassed stage is
        // skipped entirely (the switch-crackle rule at the top of this file), and that is
        // precisely what makes the rising-edge snap in `filterEnabled`'s `willSet` safe:
        // it can only claim the audio thread is not touching the filter if the audio
        // thread really is not. Advancing the glide of a stage nobody hears would void
        // that argument and burn up to four `tanf` per block for silence.
        guard frameCount > 0, filterEnabled else { return }
        if frameCount != glideCoefficientFrames {
            glideCoefficient = ParamGlide.coefficient(
                tauSeconds: ParamGlide.bioTau,
                stepRateHz: sampleRateHz / Float(frameCount))
            glideCoefficientFrames = frameCount
        }
        cutoffGlide.advance(toward: filterCutoff, coefficient: glideCoefficient)
        resonanceGlide.advance(toward: filterResonance, coefficient: glideCoefficient)
        let c = cutoffGlide.value, q = resonanceGlide.value
        filterL.cutoff = c;    filterR.cutoff = c
        filterL.resonance = q; filterR.resonance = q
    }

    // MARK: - Process

    /// ONE SAMPLE. Deliberately `internal`, not `public`, since #138 Slice 2.
    ///
    /// It does NOT advance the tone-filter glide — `processBuffer`/`processBufferMono` do
    /// that once per block before entering their loop. A caller that drove this directly
    /// would therefore get a filter frozen at whatever cutoff the glide last held, which is
    /// a silent wrong-sound bug rather than a crash. There is no such caller today (grep:
    /// only the two block entry points below, in this file), and narrowing the access level
    /// is what keeps it that way without a comment nobody reads.
    @inline(__always)
    func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
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
        // Once per block, BEFORE the loop, and against the REAL block length — `n`, not the
        // requested `frameCount` and not an assumed 256. A coefficient derived from a
        // number of frames we did not actually process would make the glide's wall-clock
        // duration drift from the audio it is smoothing.
        advanceFilterGlide(frameCount: n)
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
        advanceFilterGlide(frameCount: n)   // once per block — see `processBuffer`
        for i in 0..<n {
            let x = buf[i]
            let (l, _) = processStereo(x, x)
            buf[i] = l
        }
    }

    // MARK: - Reset

    public func reset() {
        // SNAP, second of the three edges. `reset()` means "the signal path is empty" —
        // there is nothing to glide FROM, so gliding here would sweep the first audio
        // after the reset up from a stale value. The targets themselves are untouched:
        // reset clears state, it does not change what the user set.
        snapFilterToTarget()
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
