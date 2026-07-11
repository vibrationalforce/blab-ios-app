import Foundation
#if canImport(Accelerate)
import Accelerate

// MARK: - EchoelDDSP — Differentiable Digital Signal Processing Engine
// Pure-DSP harmonic-plus-noise model inspired by Google Magenta DDSP.
// No ML required — parameters driven by bio-reactive signals or manual control.
//
// Architecture:
//   1. Harmonic Synthesizer: Bank of N sinusoidal partials at integer multiples of f0
//      - Per-partial amplitude control (spectral envelope)
//      - Phase-coherent additive synthesis via vDSP (SIMD-vectorized)
//   2. Noise Synthesizer: Multi-band FIR-filtered noise with spectral shaping
//      - 65-band frequency-domain multiplication via vDSP_DFT
//      - Colored noise presets + custom spectral curves
//   3. Mix: Harmonic + Noise blend controlled by harmonicity parameter
//   4. Global amplitude envelope (exponential ADSR curves)
//   5. Spectral Morphing: Smooth interpolation between spectral shapes
//   6. Timbre Transfer: f0 + loudness → target instrument timbre mapping
//
// Bio-Reactive Integration (12 mappings):
//   - Coherence → Harmonicity (high = pure tone, low = noisy)
//   - HRV → Spectral brightness (calm = warm, stressed = bright)
//   - Heart rate → Vibrato rate + noise modulation
//   - Breathing → Amplitude envelope + noise filter sweep
//   - LF/HF ratio → Reverb wet/dry via EngineBus
//   - Coherence trend → Spectral shape morphing
//
// Performance:
//   - vDSP vectorized harmonic generation (SIMD bulk sin)
//   - Pre-allocated buffers, zero runtime allocation
//   - 48kHz, 64 harmonics, <1ms render per 256 samples on A15+
//
// References:
//   - Engel et al. (2020) "DDSP: Differentiable Digital Signal Processing" ICLR
//   - Rausch et al. (2008) "Parallel Genetic Algorithm" — adaptive parameter search
//   - Rausch et al. (2020) "Tracy" — signal deconvolution for bio input cleaning
//   - ICASSP 2024: Ultra-lightweight DDSP vocoder (15 MFLOPS)

/// EchoelDDSP — Harmonic+Noise Synthesizer with vDSP Vectorization
/// Pure DSP engine with per-partial amplitude control, multi-band FIR noise,
/// spectral morphing, extended bio-reactive mappings, and timbre transfer prep.
///
/// Thread-safety invariant: `@unchecked Sendable` because all access is serialized
/// through `@MainActor` (stored in `EchoelCreativeWorkspace.bioSynth`).
/// Both `applyBioReactive()` and `renderStereo()` are called exclusively from
/// MainActor context (Timer → `MainActor.assumeIsolated`). Do NOT call from
/// background threads without adding synchronization.
public final class EchoelDDSP: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of harmonic partials
    public let harmonicCount: Int

    /// Number of noise filter bands
    public let noiseBandCount: Int

    /// Sample rate
    public let sampleRate: Float

    /// Frame size for parameter updates (controls update rate)
    public let frameSize: Int

    // MARK: - Harmonic Parameters

    /// Fundamental frequency (Hz)
    public var frequency: Float = 110.0      // A2 — deep, warm base

    /// Per-partial amplitudes (normalized 0-1)
    /// Index 0 = fundamental, index 1 = 2nd harmonic, etc.
    public var harmonicAmplitudes: [Float]

    /// Per-partial frequency STRETCH table (index i multiplies the i-th partial's frequency).
    /// Encodes INHARMONICITY — real strings/piano partials drift slightly sharp of exact integer
    /// ratios, which makes the tone beat/breathe instead of sounding mathematically sterile.
    /// Fundamental (i=0) is always 1.0 → the played PITCH stays exact; only upper partials stretch.
    /// Rebuilt on the control thread when `inharmonicity` changes; render() only READS it.
    public private(set) var partialStretch: [Float]

    /// Global harmonic amplitude (0-1)
    public var harmonicLevel: Float = 0.8

    /// Harmonicity: blend between harmonic and noise (0 = noise, 1 = pure harmonic)
    public var harmonicity: Float = 0.88      // Clean pad — mostly harmonic

    // MARK: - Noise Parameters

    /// Per-band noise magnitudes (frequency-domain shaping)
    public var noiseMagnitudes: [Float]

    /// Global noise amplitude (0-1)
    public var noiseLevel: Float = 0.01      // Minimal noise — clean

    /// Noise color preset
    public var noiseColor: NoiseColor = .pink {
        didSet { updateNoiseProfile() }
    }

    // MARK: - Envelope

    /// Global amplitude (0-1)
    public var amplitude: Float = 0.5        // Moderate — room for modulation

    /// Per-PATCH output level (loudness trim), 1.0 = unity. DISTINCT from `amplitude`
    /// (which carries note velocity + the bio pulse): this normalises one instrument's
    /// overall loudness against the others so the Play-surface sounds match instead of
    /// some being "teils zu laut oder zu leise" (founder 2026-07-11: "Level pro
    /// Instrument"). Set by `SynthPatch.apply` off the audio thread (aligned Float,
    /// atomic-width, same discipline as `amplitude`); read per-sample and folded into
    /// the master-gain smoother so a patch switch GLIDES instead of clicking. 1.0 =
    /// bit-identical to before.
    public var patchOutputLevel: Float = 1.0

    /// Velocity of the current note (0-1), used for touch dynamics (Anschlagdynamik).
    /// 0 = "no velocity context" (the mono/bio voice never sets it) → no attack
    /// scaling, behaviour unchanged. The poly engine sets the played velocity so a
    /// harder hit snaps the onset on percussive patches. Set on the trigger thread,
    /// read on the audio thread in the attack stage — an aligned Float, atomic-width.
    public var noteVelocity: Float = 0

    /// Per-note attack-time multiplier derived from velocity × patch percussiveness,
    /// computed once at noteOn so the render loop just multiplies (no per-sample math).
    /// 1 = full patch attack (default / pads); <1 = snappier onset on a hard hit.
    private var velAttackScale: Float = 1

    /// Per-note BRIGHTNESS envelope value (1 at onset → decays to 0). Opens the filter
    /// cutoff at the attack and lets it settle darker as the note rings — the "bright
    /// attack → mellow body" fingerprint of a real plucked/struck instrument. Set to 1 in
    /// noteOn, decayed per-sample in render. Audio-thread: single Float, atomic-width.
    private var filterEnvValue: Float = 0
    /// How much the brightness envelope opens the cutoff at the onset (0 = static timbre,
    /// ~2 = strong pluck). Public so a patch/character can dial it later. Softened 2026-07-07
    /// (founder: sounds "stechen kalt aus dem mix raus") from 1.6 — keeps the "bright attack →
    /// mellow body" life but stops the top-end jab poking out of the mix.
    public var filterEnvAmount: Float = 1.0
    /// Per-sample one-pole decay of the brightness envelope (~0.9998 ≈ ~100 ms to 1/e at 48 k).
    public var filterEnvDecay: Float = 0.9998

    /// Per-note ONSET-noise envelope (1 at attack → fast decay). Adds a brief pick/bow/breath
    /// "chiff" transient at the note start — the 10–40 ms burst the ear relies on to identify a
    /// REAL instrument (absent in a pure additive tone). Re-armed in noteOn, decayed per-sample.
    /// Audio-thread: single Float, atomic-width (same convention as noteVelocity/filterEnvValue).
    private var onsetNoiseEnv: Float = 0
    /// Level of the onset chiff (0 = off). Trimmed 2026-07-07 (warmth pass) from 0.35 — a
    /// fainter attack noise so the transient tick doesn't poke out on the soft/pad genres.
    public var onsetNoiseAmount: Float = 0.20
    /// Per-sample decay of the onset-noise env (~0.9993 ≈ ~30 ms to 1/e at 48 k — a short chiff).
    public var onsetNoiseDecay: Float = 0.9993

    /// Attack time (seconds)
    public var attack: Float = 0.5            // Half second — audible but smooth

    /// Decay time (seconds)
    public var decay: Float = 0.5             // Moderate decay into sustain

    /// Sustain level (0-1)
    public var sustain: Float = 0.8

    /// Release time (seconds)
    public var release: Float = 2.0            // Ambient release tail

    /// Envelope curve type
    public var envelopeCurve: EnvelopeCurve = .exponential

    // MARK: - Resonant Filter + LFO + Entrainment

    /// State Variable Filter (lowpass/highpass/bandpass/notch)
    public let filter = EchoelSVFilter(sampleRate: 48000)

    /// Free-running LFO for filter modulation
    public let filterLFO = EchoelLFO(sampleRate: 48000)

    /// LFO modulation depth on filter cutoff [0-1]
    public var lfoToFilterDepth: Float = 0.15     // Gentle filter sweep

    /// Base filter cutoff (before modulation) [20-20000 Hz]
    public var filterCutoff: Float = 220.0     // Warm, dark start — opens with coherence

    /// External cutoff multiplier (1 = no change), e.g. driven by parameter
    /// automation. Applied on top of the base cutoff + LFO in the render. A plain
    /// Float written from the control side and read on the audio thread (aligned-word
    /// atomic, same discipline as other render params); off (1.0) is bit-identical.
    public var renderCutoffScale: Float = 1.0

    /// Isochronic brainwave entrainment
    public let entrainment = EchoelEntrainment(sampleRate: 48000)

    // MARK: - Convolution Reverb

    /// Reverb wet/dry mix (0 = dry, 1 = fully wet)
    public var reverbMix: Float = 0.25         // Moderate reverb

    /// Reverb decay time in seconds (controls IR length)
    public var reverbDecay: Float = 2.0        // Moderate reverb tail

    // MARK: - Spectral Control

    /// Spectral envelope shape
    public var spectralShape: SpectralShape = .dark {      // Dark = warm rolloff
        didSet {
            if morphTarget == nil {
                updateSpectralEnvelope()
            }
        }
    }

    /// Spectral brightness (0 = dark, 1 = bright)
    public var brightness: Float = 0.25 {     // Dark trance character
        didSet { updateSpectralEnvelope() }
    }

    /// Inharmonicity coefficient B (piano-style partial stretch: fₙ ≈ n·f0·√(1 + B·n²)).
    /// 0 = exact integer harmonics (sterile, "electronic"). Tiny values give the tone real-
    /// instrument life: upper partials drift slightly sharp and beat against the harmonic
    /// series. ~0.0001 = light string, ~0.0005 = piano, ~0.001 = very taut/metallic. The
    /// fundamental never shifts (pitch stays exact). didSet rebuilds the table on the CONTROL
    /// thread; the audio render only reads `partialStretch`. Small default so every voice
    /// benefits without detuning — patches can push it further.
    public var inharmonicity: Float = 0.0001 {
        didSet { rebuildPartialStretch() }
    }

    // MARK: - Spectral Morphing

    /// Morph target shape (nil = no morphing)
    public var morphTarget: SpectralShape? = nil

    /// Morph position (0 = current shape, 1 = target shape)
    public var morphPosition: Float = 0

    // MARK: - Vibrato (Bio-Driven)

    /// Vibrato rate in Hz (bio: linked to heart rate)
    public var vibratoRate: Float = 0

    /// Vibrato depth in semitones
    public var vibratoDepth: Float = 0

    /// Analog pitch drift — peak micro-detune in CENTS (100 cents = 1 semitone).
    /// A slow, band-limited random wander of the fundamental, re-centred per note.
    /// This is the "alive vs. dead" lever additive synthesis most lacks: real
    /// players/strings are never perfectly steady, so a few cents of slow drift
    /// makes CHORDS BEAT and sustained tones breathe instead of sounding sterile
    /// and mathematically pure. Distinct from `vibratoDepth` (periodic) — this is
    /// aperiodic (a smoothed random walk). Small default so every voice benefits
    /// (like `inharmonicity`); 0 = perfectly steady pitch (bit-identical to before).
    /// Audio-thread: read-only in render; the wander uses the per-voice xorshift PRNG.
    public var pitchDriftCents: Float = 3

    // MARK: - Slide Expression (touch-performance gesture)

    /// EXPRESSION vibrato depth 0…1 (founder 2026-07-08: "Auf dem Gitter hin und
    /// her sliden verändert den Sound: … ein bisschen Vibrato"). ADDS a fixed-rate
    /// (~5.2 Hz) vibrato of up to ~18 cents ON TOP of the patch's own vibrato, so
    /// the gesture composes with each instrument's character instead of replacing
    /// it. Fanned per render block from EchoelPolyDDSP (renderCutoffScale pattern);
    /// 0 (default) is bit-identical to before. Atomic-Float discipline.
    public var expressVibrato: Float = 0

    /// EXPRESSION ensemble/chorus amount 0…1: a slow (~0.5–0.8 Hz, per-voice
    /// de-phased via `expressSeed`) pitch wobble of up to ±10 cents. Voices of a
    /// chord/unison stack wobble independently → the sound visibly thickens under
    /// a travelling finger, like an ensemble leaning in. Independent of the FX
    /// chain, so no patch/genre chorus setting is ever stomped. 0 = bit-identical.
    public var expressChorus: Float = 0

    /// Per-voice de-phasing seed for the expression chorus (set once at pool init,
    /// golden-angle spacing). Not audio-thread-mutated.
    public var expressSeed: Float = 0

    /// Per-sample one-pole coefficient for the base-frequency glide (see
    /// `smoothedFreq` in render). Default 0.01 = the legacy ~2 ms micro-glide;
    /// fanned from EchoelPolyDDSP.portamentoCoeff so slid notes get a musical
    /// portamento. Atomic-Float discipline.
    public var glideCoeff: Float = 0.01

    private var expressVibPhase: Float = 0
    private var expressChorusPhase: Float = 0

    // MARK: - Timbre Transfer

    /// Timbre profile — per-harmonic amplitude template from target instrument
    /// When set, harmonicAmplitudes are interpolated toward this profile
    public var timbreProfile: [Float]? = nil

    /// Timbre blend (0 = original spectral shape, 1 = full timbre profile)
    public var timbreBlend: Float = 0

    // MARK: - Types

    /// Noise color presets
    public enum NoiseColor: String, CaseIterable, Sendable {
        case white = "White"
        case pink = "Pink"
        case brown = "Brown"
        case blue = "Blue"
        case violet = "Violet"
    }

    /// Spectral envelope shapes
    public enum SpectralShape: String, CaseIterable, Sendable {
        case natural = "Natural"       // 1/n rolloff
        case bright = "Bright"         // Boosted highs
        case dark = "Dark"             // Steep rolloff
        case formant = "Formant"       // Vowel-like formants
        case metallic = "Metallic"     // Enhanced odd harmonics
        case hollow = "Hollow"         // Missing even harmonics
        case bell = "Bell"             // Inharmonic partials (slightly detuned)
        case flat = "Flat"             // Equal amplitudes
    }

    /// Envelope curve types
    public enum EnvelopeCurve: String, CaseIterable, Sendable {
        case linear = "Linear"
        case exponential = "Exponential"   // -60dB decay curve
        case logarithmic = "Logarithmic"   // Fast initial, slow tail
    }

    // MARK: - Internal State

    /// Phase accumulators for each partial
    private var phases: [Float]

    /// Smoothed amplitudes (to avoid clicks)
    private var smoothedAmplitudes: [Float]

    /// Per-sample-smoothed filter cutoff. The base cutoff is driven in block-size
    /// jumps by `applyBioReactive` (coherence → cutoff) and the LFO; feeding those
    /// steps straight into the SVF injects energy into its integrators → audible
    /// zipper/buzz. We one-pole smooth toward the modulated target each sample.
    /// -1 = uninitialised (seed it to the first target so there's no startup sweep).
    private var smoothedCutoff: Float = -1

    /// Per-sample-smoothed harmonic/noise blend. `harmonicity` and `noiseLevel` are
    /// driven in block-size steps by bio frames (coherence→harmonicity) and slider
    /// drags; feeding the steps straight into the mix audibly zippers the timbre.
    /// One-pole smoothed each sample. -1 = seed on first use (no startup glide).
    private var smoothedHarmonicity: Float = -1
    private var smoothedNoiseLevel: Float = -1

    /// Per-sample-smoothed master gain. `amplitude` is driven in block-size steps —
    /// by a new note's velocity and (when bio modulation is on) the 10 Hz bio frame
    /// amplitude pulse — so reading it straight per-sample steps the output level and
    /// crackles. One-pole smoothed each sample (~10 ms glide). -1 = seed on first use.
    private var smoothedGain: Float = -1

    /// Per-sample-smoothed base frequency. When a still-ringing voice is reused
    /// (stolen, or a released tail), `frequency` is reassigned in a single step —
    /// an instant pitch change on a loud voice is the audible "phase jump"/click.
    /// One-pole glided each sample so reused voices slide to the new pitch; a fresh
    /// idle voice re-seeds this in `prepareForNote(hardReset:)` so it snaps instead.
    /// -1 = seed on first use.
    private var smoothedFreq: Float = -1

    /// Anti-alias weighting scratch — smoothedAmplitudes with a raised-cosine
    /// taper applied to partials approaching Nyquist (avoids the harsh "pop" of
    /// partials hard-cutting in/out as f0 or vibrato sweeps them past Nyquist).
    private var aaWeights: [Float]

    /// vDSP scratch buffers for vectorized harmonic generation
    private var vdspPhaseIncrements: [Float]
    private var vdspSinBuffer: [Float]
    private var vdspCosBuffer: [Float]

    /// Pre-computed noise filter coefficients (avoids exp() on audio thread)
    private var noiseFilterAlphas: [Float]

    /// Multi-band noise: FIR-filtered noise via overlap-add
    private var noiseFFTBuffer: [Float]
    private var noiseOutputBuffer: [Float]
    private var noiseOverlapBuffer: [Float]
    private var noiseFilterState: [Float]

    /// Lock-free PRNG for audio-thread noise generation
    /// xorshift32 — no locks, no syscalls, deterministic, fast
    private var prngState: UInt32 = 0x12345678

    /// Generate white noise sample in [-1, 1] without locking (audio-thread safe)
    private func nextNoiseSample() -> Float {
        // xorshift32 algorithm (Marsaglia 2003)
        prngState ^= prngState << 13
        prngState ^= prngState >> 17
        prngState ^= prngState << 5
        // Convert to float in [-1, 1]
        return Float(Int32(bitPattern: prngState)) / Float(Int32.max)
    }

    /// Vibrato phase accumulator
    private var vibratoPhase: Float = 0

    /// Analog pitch-drift state (see `pitchDriftCents`). A slow random walk: every
    /// ~80 ms a fresh target in [-1,1] is drawn from the PRNG; `pitchDriftValue`
    /// one-pole glides toward it (~a few-Hz wander). Re-centred to 0 at each noteOn
    /// so a note starts in tune and drifts from there. Audio-thread: index writes only.
    private var pitchDriftValue: Float = 0
    private var pitchDriftTarget: Float = 0
    private var pitchDriftCounter: Int = 0

    /// Analog LEVEL drift — the breath/bow-pressure twin of the pitch drift: no human
    /// holds a note at a perfectly constant level, so a slow ±few-% aperiodic wander on
    /// the gain makes sustains breathe like a played instrument instead of a test tone.
    /// 0 disables (bit-identical render). Deliberately a DIFFERENT cadence (~120 ms) and
    /// glide than the pitch drift so the two wanders stay uncorrelated, like a real hand.
    /// Fraction of level, e.g. 0.05 = ±5 % (≈ ±0.4 dB) — felt, not heard as tremolo.
    public var levelDriftAmount: Float = 0.05
    private var levelDriftValue: Float = 0
    private var levelDriftTarget: Float = 0
    private var levelDriftCounter: Int = 0

    /// Per-partial amplitude SHIMMER — each overtone's level wanders independently
    /// (incoherent slow sinusoids, upper partials more than the fundamental), the
    /// partial-level fluctuation every bowed/blown/sung sustain has. The pitch/level
    /// drifts above move ALL partials together; with a frozen RELATIVE spectrum a
    /// sustain still reads as "organ/cheap synth". Value = peak fractional wobble of
    /// the highest partials (0.10 ≈ ±10 %, ≈ ±0.8 dB — felt as life, not tremolo).
    /// 0 disables (bit-identical render). Updated at block rate (0.3–3 Hz motion
    /// needs no per-sample trig); the per-sample one-pole on `smoothedAmplitudes`
    /// glides over the block-rate steps, so there is no zipper.
    public var partialShimmer: Float = 0.10
    private var shimmerPhases: [Float]
    private var shimmerWeights: [Float]

    /// Current envelope value
    private var envelopeValue: Float = 0

    /// Envelope stage
    private var envelopeStage: EnvelopeStage = .idle

    /// Samples in current envelope stage
    private var envelopeSamples: Int = 0

    /// Envelope level at start of release (for smooth release from any stage)
    private var releaseStartLevel: Float = 0
    /// Envelope level at start of attack — a fast retrigger while a previous note
    /// is still in release would otherwise jump from a non-zero level to 0 and
    /// click. Ramping the attack FROM this level keeps the onset continuous.
    private var attackStartLevel: Float = 0

    private enum EnvelopeStage {
        case idle, attack, decay, sustain, release
    }

    /// Spectral morph scratch buffers
    private var morphSourceAmplitudes: [Float]
    private var morphTargetAmplitudes: [Float]

    /// Convolution reverb engine (vDSP_conv based).
    ///
    /// DISABLED by default: note triggering runs on the pattern's TIMER thread
    /// (`noteOn → prepareForNote`), which mutated this convolution's internal Swift
    /// arrays (`reset()`) while the AUDIO render thread was concurrently inside
    /// `process(...)` touching the same arrays → copy-on-write refcount race →
    /// heap corruption → EXC_BAD_ACCESS on the first note (device only). The
    /// convolution is not audio-thread/control-thread safe under this design, so
    /// it stays off until it is driven by a lock-free command queue. Spatial
    /// character is provided by the (Float-param-only, race-free) EchoelFXChain.
    nonisolated(unsafe) static var useConvolutionReverb = false
    private var reverbConvolution: EchoelConvolution?
    private var reverbFrameBuffer: [Float] = []
    private var reverbWetBuffer: [Float] = []   // pre-allocated wet output (no audio-thread alloc)

    // MARK: - Init

    /// Initialize EchoelDDSP
    /// - Parameters:
    ///   - harmonicCount: Number of harmonic partials (default 64)
    ///   - noiseBandCount: Number of noise filter bands (default 65)
    ///   - sampleRate: Audio sample rate (default 48000)
    ///   - frameSize: Parameter update frame size (default 192 = 250Hz at 48kHz)
    public init(
        harmonicCount: Int = 64,
        noiseBandCount: Int = 65,
        sampleRate: Float = 48000.0,
        frameSize: Int = 192,
        noiseSeed: UInt32 = 0x12345678
    ) {
        self.harmonicCount = max(1, harmonicCount)
        self.noiseBandCount = max(1, noiseBandCount)
        self.sampleRate = max(1, sampleRate)
        self.frameSize = max(1, frameSize)
        // Seed the per-voice noise PRNG. xorshift32 requires a non-zero state;
        // a distinct seed per voice decorrelates the noise across simultaneous
        // voices (identical seeds make poly noise add coherently / comb-filter).
        self.prngState = noiseSeed == 0 ? 0x12345678 : noiseSeed

        self.harmonicAmplitudes = [Float](repeating: 0, count: harmonicCount)
        self.partialStretch = [Float](repeating: 1, count: harmonicCount)   // filled by rebuildPartialStretch() below
        self.noiseMagnitudes = [Float](repeating: 0, count: noiseBandCount)
        self.phases = [Float](repeating: 0, count: harmonicCount)
        self.smoothedAmplitudes = [Float](repeating: 0, count: harmonicCount)
        // Shimmer phases start spread by the golden angle (deterministic, maximally
        // incommensurate) so the partial wobbles never line up into a tremolo.
        self.shimmerPhases = (0..<harmonicCount).map { Float($0) * 2.399963 }
        self.shimmerWeights = [Float](repeating: 1, count: harmonicCount)
        self.aaWeights = [Float](repeating: 0, count: harmonicCount)

        // vDSP scratch buffers
        self.vdspPhaseIncrements = [Float](repeating: 0, count: harmonicCount)
        self.vdspSinBuffer = [Float](repeating: 0, count: harmonicCount)
        self.vdspCosBuffer = [Float](repeating: 0, count: harmonicCount)

        // Multi-band noise buffers
        let fftSize = noiseBandCount * 2
        self.noiseFFTBuffer = [Float](repeating: 0, count: fftSize)
        self.noiseOutputBuffer = [Float](repeating: 0, count: frameSize + fftSize)
        self.noiseOverlapBuffer = [Float](repeating: 0, count: fftSize)
        self.noiseFilterState = [Float](repeating: 0, count: noiseBandCount)

        // Pre-compute noise filter coefficients (avoids exp() on audio thread)
        let spacing = 1.0 / Float(noiseBandCount)
        self.noiseFilterAlphas = (0..<noiseBandCount).map { band in
            let centerFreq = Float(band + 1) * spacing
            return exp(-2.0 * Float.pi * centerFreq * 0.5)
        }

        // Spectral morph buffers
        self.morphSourceAmplitudes = [Float](repeating: 0, count: harmonicCount)
        self.morphTargetAmplitudes = [Float](repeating: 0, count: harmonicCount)

        // Reverb IR buffers — pre-allocate for the max render block the poly engine
        // can deliver (4096). Sized at 2048 before, so blocks 2049–4096 silently
        // skipped the reverb → audible wet-tail dropouts as host block size varied.
        let reverbCap = max(frameSize, 4096)
        self.reverbFrameBuffer = [Float](repeating: 0, count: reverbCap)
        self.reverbWetBuffer = [Float](repeating: 0, count: reverbCap)

        // Initialize convolution reverb with a synthetic IR. maxInputLength must
        // match the buffer cap or the convolution truncates large blocks.
        self.reverbConvolution = EchoelConvolution(kernel: EchoelDDSP.generateReverbIR(
            decay: 1.5, sampleRate: sampleRate, length: 4096
        ), maxInputLength: reverbCap)

        // Initialize with natural spectral envelope
        updateSpectralEnvelope()
        updateNoiseProfile()
        rebuildPartialStretch()   // fill the inharmonicity table from the default coefficient
    }

    /// Rebuild the per-partial frequency STRETCH table from `inharmonicity` (control thread ONLY —
    /// never the audio thread; render just reads `partialStretch`). Uses n = 0-based partial index
    /// so the fundamental (n=0) stays exactly 1.0 (played pitch unchanged) while upper partials
    /// drift progressively sharp: stretchᵢ = √(1 + B·i²). Pure arithmetic, no allocation beyond the
    /// pre-sized table.
    private func rebuildPartialStretch() {
        let b = Swift.max(0, inharmonicity)
        for i in 0..<partialStretch.count {
            let n = Float(i)
            partialStretch[i] = (1 + b * n * n).squareRoot()
        }
    }

    /// Generate synthetic impulse response for convolution reverb
    /// Uses exponential decay with early reflections + diffuse tail
    private static func generateReverbIR(decay: Float, sampleRate: Float, length: Int) -> [Float] {
        var ir = [Float](repeating: 0, count: length)

        // Direct sound
        ir[0] = 1.0

        // Early reflections (first 20ms)
        let earlyEnd = min(length, Int(0.02 * sampleRate))
        let reflectionTimes = [0.003, 0.007, 0.011, 0.015, 0.019]
        for time in reflectionTimes {
            let idx = min(length - 1, Int(time * Double(sampleRate)))
            ir[idx] = Float.random(in: 0.2...0.5)
        }

        // Diffuse tail (exponential decay)
        let decayProduct = max(decay * sampleRate, 0.001)
        let decayRate = -6.9 / decayProduct  // -60dB decay
        for i in earlyEnd..<length {
            let envelope = exp(decayRate * Float(i))
            ir[i] = Float.random(in: -1...1) * envelope * 0.3
        }

        return ir
    }

    /// Update reverb IR when decay time changes.
    ///
    /// CRITICAL: this is called from the control plane (main thread) while the
    /// audio render thread may be dereferencing `reverbConvolution`. We MUST NOT
    /// reseat the object reference here — doing so raced the render thread's ARC
    /// retain/release and crashed on device (EXC_BAD_ACCESS) on the first
    /// Generate. Instead we update the existing convolution's kernel IN PLACE
    /// (length is always 4096, so `setKernel` never reallocates). The object the
    /// audio thread holds is never swapped.
    public func updateReverbDecay(_ newDecay: Float) {
        reverbDecay = newDecay
        let ir = EchoelDDSP.generateReverbIR(decay: newDecay, sampleRate: sampleRate, length: 4096)
        if let conv = reverbConvolution {
            conv.setKernel(ir)                 // in place — no reference reseat
        } else {
            // First-time allocation only (before audio is running): safe to create.
            reverbConvolution = EchoelConvolution(kernel: ir,
                                                  maxInputLength: max(reverbFrameBuffer.count, 4096))
        }
    }

    // MARK: - Spectral Envelope

    /// Update harmonic amplitudes based on spectral shape and brightness
    private func updateSpectralEnvelope() {
        computeShapeAmplitudes(shape: spectralShape, into: &harmonicAmplitudes)

        // Apply spectral morphing if target is set
        if let target = morphTarget, morphPosition > 0 {
            computeShapeAmplitudes(shape: target, into: &morphTargetAmplitudes)
            // Equal-power crossfade: cos/sin panning law preserves perceived loudness
            // Linear interpolation causes a -3dB dip at morph midpoint
            let theta = morphPosition * Float.pi * 0.5
            let gainA = cos(theta)
            let gainB = sin(theta)
            for i in 0..<harmonicCount {
                harmonicAmplitudes[i] = harmonicAmplitudes[i] * gainA
                    + morphTargetAmplitudes[i] * gainB
            }
        }

        // Apply timbre profile if set
        if let profile = timbreProfile, timbreBlend > 0, profile.count >= harmonicCount {
            for i in 0..<harmonicCount {
                harmonicAmplitudes[i] = harmonicAmplitudes[i] * (1.0 - timbreBlend)
                    + profile[i] * timbreBlend
            }
        }

        normalizeAmplitudes(&harmonicAmplitudes)
    }

    /// Compute spectral shape into target buffer
    private func computeShapeAmplitudes(shape: SpectralShape, into amps: inout [Float]) {
        let bright = brightness

        switch shape {
        case .natural:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                amps[i] = 1.0 / pow(n, 1.5 - bright)
            }
        case .bright:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                amps[i] = (1.0 / pow(n, 0.5)) * (0.5 + bright * 0.5)
            }
        case .dark:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                amps[i] = 1.0 / pow(n, 2.5 - bright)
            }
        case .formant:
            let formants: [(freq: Float, amp: Float, bw: Float)] = [
                (730, 1.0, 90), (1090, 0.5, 110), (2440, 0.3, 170)
            ]
            for i in 0..<harmonicCount {
                let freq = frequency * Float(i + 1)
                var amp: Float = 0.01
                for formant in formants {
                    let diff = (freq - formant.freq) / formant.bw
                    amp += formant.amp * exp(-diff * diff * 0.5)
                }
                amps[i] = amp
            }
        case .metallic:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                let isOdd = (i + 1) % 2 != 0
                let rolloff = 1.0 / pow(n, 1.0)
                amps[i] = isOdd ? rolloff : rolloff * 0.1
            }
        case .hollow:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                let isOdd = (i + 1) % 2 != 0
                amps[i] = isOdd ? 1.0 / pow(n, 1.2) : 0
            }
        case .bell:
            for i in 0..<harmonicCount {
                let n = Float(i + 1)
                let detune = 1.0 + 0.001 * n * n * bright
                amps[i] = (1.0 / pow(n, 0.8)) / detune
            }
        case .flat:
            let val = harmonicCount > 0 ? 1.0 / Float(harmonicCount) : 0
            for i in 0..<harmonicCount { amps[i] = val }
        }
    }

    /// Normalize amplitude array in-place
    /// Guards against NaN propagation: if any element is NaN, vDSP_maxv returns NaN
    /// which fails the > 0 check. Explicitly clamp NaN to 0 first.
    private func normalizeAmplitudes(_ amps: inout [Float]) {
        // Clamp NaN/Inf values to 0 before normalization (prevents NaN propagation to audio buffer)
        for i in 0..<amps.count where !amps[i].isFinite {
            amps[i] = 0
        }
        var maxAmp: Float = 0
        vDSP_maxv(amps, 1, &maxAmp, vDSP_Length(amps.count))
        if maxAmp > 0 {
            var divisor = maxAmp
            // Use withUnsafeMutableBufferPointer to avoid Swift exclusivity violation
            // vDSP supports in-place operation (same pointer for input and output)
            amps.withUnsafeMutableBufferPointer { buf in
                guard let ptr = buf.baseAddress else { return }
                vDSP_vsdiv(ptr, 1, &divisor, ptr, 1, vDSP_Length(buf.count))
            }
        }
    }

    /// Update noise profile based on color
    private func updateNoiseProfile() {
        for i in 0..<noiseBandCount {
            let freq = Float(i) / Float(noiseBandCount)
            switch noiseColor {
            case .white:  noiseMagnitudes[i] = 1.0
            case .pink:   noiseMagnitudes[i] = 1.0 / sqrt(max(0.01, freq))
            case .brown:  noiseMagnitudes[i] = 1.0 / max(0.01, freq)
            case .blue:   noiseMagnitudes[i] = sqrt(max(0.01, freq))
            case .violet: noiseMagnitudes[i] = freq
            }
        }
        normalizeAmplitudes(&noiseMagnitudes)
    }

    // MARK: - Note Control

    /// Trigger note on
    public func noteOn(frequency: Float? = nil) {
        if let f = frequency {
            self.frequency = f
        }
        attackStartLevel = envelopeValue   // ramp from current level → no retrigger click
        // Anschlagdynamik: a harder hit shortens the onset, but ONLY on percussive
        // (short-attack) patches — a pad's slow swell must stay intact. percussiveness
        // is read from the patch's own attack time (≤0.15 s = pluck/struck). With the
        // default noteVelocity 0 (mono/bio voice) the scale is 1 → no behaviour change.
        let percussiveness = max(0, 1 - attack / 0.15)
        let vel = min(1, max(0, noteVelocity))
        velAttackScale = 1 - percussiveness * 0.7 * vel
        filterEnvValue = 1                 // re-arm the per-note brightness envelope (attack = bright)
        // Onset chiff = a pick/bow/breath transient — a PERCUSSIVE onset. A slow-attack
        // pad/drone (attack ≥ 0.15 s) blooms in and physically has NO attack tick, so the
        // fixed full-level chiff read as a small digital "pff" at the start of every pad
        // note (audible on the new Drone). Arm it BY percussiveness: full on plucks/keys,
        // fading to zero as the attack lengthens — the transient matches the instrument.
        onsetNoiseEnv = percussiveness
        pitchDriftValue = 0                // start in tune; analog drift accrues from here
        pitchDriftTarget = 0
        pitchDriftCounter = 0              // draw a fresh drift target on the first render sample
        levelDriftValue = 0                // start at nominal level; pressure wander accrues
        levelDriftTarget = 0
        levelDriftCounter = 0
        envelopeStage = .attack
        envelopeSamples = 0
    }

    /// Trigger note off
    public func noteOff() {
        releaseStartLevel = envelopeValue
        envelopeStage = .release
        envelopeSamples = 0
    }

    /// Whether this voice is still producing sound (envelope not idle).
    /// Used by the poly engine to keep rendering release tails instead of
    /// cutting them off (which causes an abrupt click at every note end).
    public var isActive: Bool { envelopeStage != .idle }

    /// Prepare a freshly-allocated voice for a new note. Staggers oscillator
    /// phases (golden-ratio spread, so partials do NOT all start in-phase and
    /// produce an onset impulse) and clears filter + noise state left over from
    /// the previous note. Audio-thread safe: index writes only, no allocation.
    ///
    /// `hardReset` must be `false` when the voice is **still ringing** (a stolen
    /// note or a released-but-not-yet-silent tail being reused). Zeroing the
    /// amplitude smoothers / filter / phases mid-tail produces an audible click
    /// — instead we keep phases and let `noteOn`'s envelope ramp-from-current and
    /// the per-sample smoothers glide the old sound into the new one. Only a
    /// truly idle voice gets the clean staggered restart.
    public func prepareForNote(hardReset: Bool = true) {
        // Always snap pitch to the new note — including a STOLEN/ringing voice. The
        // smoothedFreq one-pole otherwise glides (~16 ms) from the stolen voice's old
        // pitch to the new one, an audible portamento that reads as a "weird" sliding
        // note whenever polyphony exceeds maxVoices. Pitch snapping doesn't click
        // (phase stays continuous and the attack envelope ramps amplitude from
        // current); only the amplitude smoothers / phases must NOT be zeroed mid-tail.
        smoothedFreq = -1
        guard hardReset else { return }
        let golden: Float = 0.61803398875
        let twoPi: Float = 2.0 * .pi
        for i in 0..<phases.count {
            phases[i] = (Float(i) * golden).truncatingRemainder(dividingBy: 1.0) * twoPi
            smoothedAmplitudes[i] = 0
        }
        for i in 0..<noiseFilterState.count { noiseFilterState[i] = 0 }
        filter.reset()
        // NOTE: reverbConvolution.reset() removed — prepareForNote runs on the
        // note-trigger (timer) thread; mutating the convolution's arrays here
        // raced the audio thread's process() → crash. Reverb is disabled
        // (see useConvolutionReverb) until it is fed by a lock-free queue.
    }

    // MARK: - Audio Generation (vDSP Vectorized)

    /// Generate audio samples — vDSP accelerated harmonic synthesis
    public func render(buffer: inout [Float], frameCount: Int, stereo: Bool = false) {
        let channelCount = stereo ? 2 : 1
        guard buffer.count >= frameCount * channelCount else { return }

        // Precompute phase increments for all harmonics (vDSP)
        let nyquist = sampleRate * 0.5
        let twoPiOverSR = 2.0 * Float.pi / sampleRate

        // --- Per-partial shimmer (block rate — see `partialShimmer`) ---
        // Each partial advances its own phase at a deterministic, incommensurate
        // rate (spread over ~0.3–3 Hz) so the wobbles never synchronise. The
        // fundamental stays anchored (depth ramps in across the first partials);
        // uppers breathe the most, like a real sustained note. Pure arithmetic +
        // one sinf per partial per BLOCK — negligible against the per-sample path.
        if partialShimmer > 0 {
            let blockDt = Float(frameCount) / sampleRate
            for i in shimmerPhases.indices {
                let rate: Float = 0.3 + 0.37 * Float(i % 7) + 0.11 * Float(i % 3)
                shimmerPhases[i] += 2.0 * .pi * rate * blockDt
                if shimmerPhases[i] > 2.0 * .pi { shimmerPhases[i] -= 2.0 * .pi }
                let depth = partialShimmer * min(1.0, Float(i) * 0.34)
                shimmerWeights[i] = 1.0 + depth * sinf(shimmerPhases[i])
            }
        } else if shimmerWeights.last != 1 {
            for i in shimmerWeights.indices { shimmerWeights[i] = 1 }   // off → bit-identical
        }

        for frame in 0..<frameCount {
            // Update envelope
            updateEnvelope()

            // Glide the base frequency per-sample so a stolen/reused voice doesn't
            // jump pitch instantly (the audible "phase jump"/click on a still-loud
            // voice). Fresh idle voices seed smoothedFreq in prepareForNote so they
            // snap to pitch; only reused voices glide. Coefficient default 0.01
            // (~2 ms, the legacy micro-glide); `glideCoeff` is fanned from the poly
            // engine's portamento setting so slid notes SING between pitches.
            if smoothedFreq < 0 { smoothedFreq = frequency }
            smoothedFreq += glideCoeff * (frequency - smoothedFreq)

            // Apply pitch modulation (vibrato + analog drift) — accumulate both as
            // semitone offsets and apply with ONE pow so a note that has neither is
            // bit-identical to before (offset stays 0 → pow(2,0)=1).
            var currentFreq = smoothedFreq
            var pitchModSemitones: Float = 0
            // Vibrato (bio: heart rate → vibrato rate) — periodic.
            if vibratoRate > 0 && vibratoDepth > 0 {
                vibratoPhase += vibratoRate / sampleRate * 2.0 * .pi
                if vibratoPhase > 2.0 * .pi { vibratoPhase -= 2.0 * .pi }
                pitchModSemitones += sin(vibratoPhase) * vibratoDepth
            }
            // Slide-expression vibrato (touch gesture) — fixed ~5.2 Hz, up to ~18
            // cents, ADDED to (never replacing) the patch vibrato. Pure sinf on the
            // voice's own phase; 0 depth skips entirely (bit-identical).
            if expressVibrato > 0.0005 {
                expressVibPhase += 5.2 / sampleRate * 2.0 * .pi
                if expressVibPhase > 2.0 * .pi { expressVibPhase -= 2.0 * .pi }
                pitchModSemitones += sin(expressVibPhase) * expressVibrato * 0.18
            }
            // Slide-expression ensemble/chorus — slow per-voice-de-phased wobble
            // (rate 0.5–0.8 Hz from the golden-angle seed) up to ±10 cents, so a
            // chord's voices thicken independently under a travelling finger.
            if expressChorus > 0.0005 {
                let rate = 0.5 + 0.3 * (expressSeed - floorf(expressSeed))
                expressChorusPhase += rate / sampleRate * 2.0 * .pi
                if expressChorusPhase > 2.0 * .pi { expressChorusPhase -= 2.0 * .pi }
                pitchModSemitones += sin(expressChorusPhase + expressSeed) * expressChorus * 0.10
            }
            // Analog pitch drift — aperiodic, a slow random walk (few-cent wander)
            // that makes chords beat and sustains breathe like a real instrument.
            if pitchDriftCents > 0 {
                pitchDriftCounter -= 1
                if pitchDriftCounter <= 0 {
                    pitchDriftTarget = nextNoiseSample()          // fresh target in [-1,1]
                    pitchDriftCounter = Int(0.08 * sampleRate)    // new target ~every 80 ms
                }
                // Slow one-pole glide toward the target → a ~few-Hz aperiodic wander.
                pitchDriftValue += 0.0006 * (pitchDriftTarget - pitchDriftValue)
                if pitchDriftValue < 1e-20 && pitchDriftValue > -1e-20 { pitchDriftValue = 0 }
                pitchModSemitones += pitchDriftValue * pitchDriftCents * 0.01   // cents → semitones
            }
            if pitchModSemitones != 0 {
                currentFreq = smoothedFreq * pow(2.0, pitchModSemitones / 12.0)
            }

            // Smooth amplitude transitions (exponential smoothing). The `+ antiDenormal`
            // term keeps a decaying partial (target→0 on note release) above the FP
            // denormal range so the per-sample one-pole never falls into the subnormal
            // zone that triggers idle CPU spikes (audit 2026-07-02 P2). 1e-25 is a normal
            // Float and its audible floor (~2e-23) is inaudible. Pure arithmetic, branch-free.
            let smoothCoeff: Float = 0.995
            let oneMinusSmooth: Float = 0.005
            let antiDenormal: Float = 1e-25
            for i in 0..<harmonicCount {
                // shimmerWeights = 1 when shimmer is off (bit-identical); otherwise the
                // per-partial block-rate wobble rides in here and the one-pole glides it.
                let target = harmonicAmplitudes[i] * harmonicLevel * shimmerWeights[i]
                smoothedAmplitudes[i] = smoothedAmplitudes[i] * smoothCoeff + target * oneMinusSmooth + antiDenormal
            }

            // --- vDSP Vectorized Harmonic Generation ---
            // Update phases and compute sin values in bulk
            var harmonicSample: Float = 0
            var activeCount = 0

            // Anti-alias band: partials between aaStart and Nyquist fade out via a
            // smoothstep instead of vanishing instantly — kills the spectral "edge"
            // click when pitch/vibrato sweeps a partial past Nyquist. Pure
            // arithmetic, audio-thread safe (no trig: smoothstep 3t²-2t³).
            let aaStart = nyquist * 0.85
            let aaRange = nyquist - aaStart   // > 0 (nyquist > 0)
            for i in 0..<harmonicCount {
                // Inharmonicity: multiply the exact integer partial by its precomputed stretch
                // (√(1+B·i²), fundamental = 1) so upper partials drift slightly sharp like a real
                // string/piano. partialStretch.count == harmonicCount → index always in bounds.
                let partialFreq = currentFreq * Float(i + 1) * partialStretch[i]
                if partialFreq >= nyquist { break }
                activeCount = i + 1

                let phaseInc = partialFreq * twoPiOverSR
                phases[i] += phaseInc
                if phases[i] > 2.0 * .pi { phases[i] -= 2.0 * .pi }
                vdspPhaseIncrements[i] = phases[i]

                var taper: Float = 1.0
                if partialFreq > aaStart {
                    let t = (partialFreq - aaStart) / aaRange      // 0..1 toward Nyquist
                    taper = 1.0 - (t * t * (3.0 - 2.0 * t))        // smoothstep 1→0
                }
                aaWeights[i] = smoothedAmplitudes[i] * taper
            }

            // Bulk sine computation via vForce (Accelerate)
            if activeCount > 0 {
                var count = Int32(activeCount)
                vvsinf(&vdspSinBuffer, &vdspPhaseIncrements, &count)

                // Weighted sum: harmonicSample = sum(sin[i] * aaWeights[i])
                vDSP_dotpr(vdspSinBuffer, 1, aaWeights, 1,
                           &harmonicSample, vDSP_Length(activeCount))
            }

            // --- Multi-Band Noise (FIR-filtered via noiseMagnitudes) ---
            // Audio-thread safe: xorshift32 PRNG, no locks/syscalls.
            // Only compute when noise audibly contributes — when noiseLevel is
            // effectively zero (the common case for tonal patches) the 65-band
            // bank would otherwise add a faint correlated hiss bed and burn CPU.
            var noiseSample: Float = 0
            onsetNoiseEnv *= onsetNoiseDecay   // fast per-sample decay of the attack chiff
            if onsetNoiseEnv < 1e-20 { onsetNoiseEnv = 0 }   // floor: no denormal churn on held notes
            // Compute the shaped noise when the steady bed OR the onset chiff needs it — so a
            // fully-tonal pluck (noiseLevel≈0) still gets its attack transient for the first ~30 ms.
            if noiseLevel > 0.0005 || onsetNoiseEnv > 0.001 {
                let whiteNoise = nextNoiseSample()
                // Multi-band spectral shaping via weighted filter bank: each band
                // tracks its own one-pole state, forming a spectral envelope.
                for band in 0..<noiseBandCount {
                    // Pre-computed alpha coefficients — no exp() on audio thread
                    let alpha = noiseFilterAlphas[band]
                    let filtered = whiteNoise * (1.0 - alpha) + noiseFilterState[band] * alpha
                    noiseFilterState[band] = filtered
                    noiseSample += filtered * noiseMagnitudes[band]
                }
                // Normalize by band count to prevent amplitude explosion
                noiseSample /= Float(noiseBandCount)
            }

            // One-pole smooth the harmonic/noise blend so bio/slider steps glide
            // instead of zippering. Seed on first sample to avoid a startup ramp.
            if smoothedHarmonicity < 0 { smoothedHarmonicity = harmonicity }
            if smoothedNoiseLevel < 0 { smoothedNoiseLevel = noiseLevel }
            smoothedHarmonicity += 0.01 * (harmonicity - smoothedHarmonicity)
            smoothedNoiseLevel  += 0.01 * (noiseLevel  - smoothedNoiseLevel) + antiDenormal
            // Mix harmonic + noise based on the smoothed harmonicity, PLUS a brief onset chiff
            // (pick/bow/breath transient) added on top — NOT gated by harmonicity, so even a
            // pure-tonal pluck gets the attack burst that makes it read as a real instrument.
            // Velocity-scaled (harder hit = louder chiff); env decays to 0 in ~30 ms → steady
            // state is bit-identical to before.
            let onsetVel: Float = 0.3 + 0.7 * min(1, max(0, noteVelocity))
            let mixed = harmonicSample * smoothedHarmonicity
                      + noiseSample * smoothedNoiseLevel * (1.0 - smoothedHarmonicity)
                      + noiseSample * onsetNoiseEnv * onsetNoiseAmount * onsetVel

            // Apply envelope and gain. Per-sample smooth the master gain so a new
            // note's velocity and the 10 Hz bio amplitude pulse glide in instead of
            // stepping the level (crackle). Seed on first sample to avoid a ramp-up.
            // Fold the per-patch loudness trim into the master-gain target so it glides
            // via the existing smoother (no click on a patch switch). 1.0 = unchanged.
            let gainTarget = amplitude * patchOutputLevel
            if smoothedGain < 0 { smoothedGain = gainTarget }
            smoothedGain += 0.01 * (gainTarget - smoothedGain) + antiDenormal
            var sample = mixed * smoothedGain * envelopeValue
            // Analog LEVEL drift (breath/bow-pressure instability) — same random-walk
            // pattern as the pitch drift above, but its own slower cadence/glide so the
            // two wanders stay uncorrelated. ±levelDriftAmount around nominal; 0 = off,
            // and the multiply-by-1 path is bit-identical. Pure arithmetic, no calls.
            if levelDriftAmount > 0 {
                levelDriftCounter -= 1
                if levelDriftCounter <= 0 {
                    levelDriftTarget = nextNoiseSample()          // fresh target in [-1,1]
                    levelDriftCounter = Int(0.12 * sampleRate)    // new target ~every 120 ms
                }
                levelDriftValue += 0.0004 * (levelDriftTarget - levelDriftValue)
                if levelDriftValue < 1e-20 && levelDriftValue > -1e-20 { levelDriftValue = 0 }
                sample *= 1.0 + levelDriftValue * levelDriftAmount
            }

            // --- Resonant Filter (SVF) ---
            // LFO modulates filter cutoff around the base cutoff
            let lfoMod = filterLFO.next()  // [-depth, +depth]
            // Per-note brightness envelope: open the cutoff at the onset and settle darker as
            // the note sustains — the "bright attack → mellow body" of a real plucked/struck
            // instrument, scaled by velocity (Anschlagdynamik: a harder hit is brighter, not just
            // louder). One-pole decay, pure arithmetic; env/amount/velocity 0 leaves timbre as-is.
            filterEnvValue *= filterEnvDecay
            if filterEnvValue < 1e-20 { filterEnvValue = 0 }   // floor: no denormal churn on held notes
            let brightBoost = 1.0 + filterEnvAmount * filterEnvValue * (0.4 + 0.6 * min(1, max(0, noteVelocity)))
            let modulatedCutoff = max(20, min(filterCutoff * renderCutoffScale * (1.0 + lfoMod * lfoToFilterDepth) * brightBoost, 18000))
            // One-pole smooth the target so bio/LFO cutoff steps don't zipper the SVF.
            // Seed on first sample to avoid a startup sweep. coeff ~0.01 ≈ a few-ms glide.
            if smoothedCutoff < 0 { smoothedCutoff = modulatedCutoff }
            smoothedCutoff += 0.01 * (modulatedCutoff - smoothedCutoff)
            filter.cutoff = smoothedCutoff
            sample = filter.process(sample)

            // --- Isochronic Brainwave Entrainment ---
            sample = entrainment.process(sample)

            if stereo {
                buffer[frame * 2] = sample
                buffer[frame * 2 + 1] = sample
            } else {
                buffer[frame] = sample
            }
        }

        // --- NaN/Inf guard (pre-reverb) ---
        let totalSamples = stereo ? frameCount * 2 : frameCount
        for i in 0..<totalSamples where !buffer[i].isFinite {
            buffer[i] = 0
        }

        // --- Convolution Reverb (post-render, block-based) ---
        // Gated OFF: not thread-safe vs. the timer-thread note path (see decl).
        if Self.useConvolutionReverb, reverbMix > 0, let conv = reverbConvolution {
            if stereo {
                // Extract mono mix for reverb input
                let monoCount = frameCount
                // Buffer pre-allocated in init — guard against unexpected sizes
                guard reverbFrameBuffer.count >= monoCount else { return }
                for i in 0..<monoCount {
                    reverbFrameBuffer[i] = (buffer[i * 2] + buffer[i * 2 + 1]) * 0.5
                }
                let wetN = conv.process(reverbFrameBuffer, into: &reverbWetBuffer)
                let dry = 1.0 - reverbMix
                let wetGain = reverbMix
                for i in 0..<monoCount {
                    let wetSample = i < wetN ? reverbWetBuffer[i] : 0
                    buffer[i * 2] = buffer[i * 2] * dry + wetSample * wetGain
                    buffer[i * 2 + 1] = buffer[i * 2 + 1] * dry + wetSample * wetGain
                }
            } else {
                // Mono path — reuse pre-allocated buffer (no audio-thread allocation)
                guard reverbFrameBuffer.count >= frameCount else { return }
                for i in 0..<frameCount {
                    reverbFrameBuffer[i] = buffer[i]
                }
                let wetN = conv.process(reverbFrameBuffer, into: &reverbWetBuffer)
                let dry = 1.0 - reverbMix
                let wetGain = reverbMix
                for i in 0..<frameCount {
                    let wetSample = i < wetN ? reverbWetBuffer[i] : 0
                    buffer[i] = buffer[i] * dry + wetSample * wetGain
                }
            }

            // --- NaN/Inf guard (post-reverb) ---
            let postCount = stereo ? frameCount * 2 : frameCount
            for i in 0..<postCount where !buffer[i].isFinite {
                buffer[i] = 0
            }
        }
    }

    // MARK: - Envelope (Exponential Curves)

    private func updateEnvelope() {
        envelopeSamples += 1

        switch envelopeStage {
        case .idle:
            envelopeValue = 0

        case .attack:
            // Click-safe onset: enforce a ~3 ms minimum attack ramp so even the
            // snappiest pluck / hardest velocity hit fades in over enough samples to
            // avoid a step discontinuity (knacksen). 3 ms reads as "instant" yet is a
            // continuous micro-fade, not a 1-sample jump.
            let minAttackSamples = Int(0.003 * sampleRate)
            let wanted = Int(attack * velAttackScale * sampleRate)
            let attackSamples = max(minAttackSamples, wanted)
            let progress = min(1.0, Float(envelopeSamples) / Float(attackSamples))
            // Click-free onset SHAPE: smoothstep (3p²−2p³). It has zero slope at BOTH
            // ends — continuous from `attackStartLevel` at p=0 and easing into full
            // level at p=1. The shared `applyCurve` exponential is the natural DECAY
            // shape (fast initial change, slow tail — right for decay/release); applied
            // to an ATTACK it would jump most of the way up in the first instants then
            // crawl to full level, which end-edge reads as a "knack" on snappier
            // characters. velocity/patch still sets the attack TIME (attackSamples);
            // smoothstep only fixes the shape.
            let eased = progress * progress * (3.0 - 2.0 * progress)
            envelopeValue = attackStartLevel + (1.0 - attackStartLevel) * eased
            if envelopeSamples >= attackSamples {
                envelopeStage = .decay
                envelopeSamples = 0
            }

        case .decay:
            let decaySamples = max(1, Int(decay * sampleRate))
            let progress = min(1.0, Float(envelopeSamples) / Float(decaySamples))
            envelopeValue = applyCurve(progress, from: 1.0, to: sustain)
            if envelopeSamples >= decaySamples {
                envelopeStage = .sustain
                envelopeSamples = 0
            }

        case .sustain:
            envelopeValue = sustain

        case .release:
            let releaseSamples = max(1, Int(release * sampleRate))
            let progress = min(1.0, Float(envelopeSamples) / Float(releaseSamples))
            envelopeValue = applyCurve(progress, from: releaseStartLevel, to: 0)
            if envelopeSamples >= releaseSamples {
                envelopeStage = .idle
                envelopeSamples = 0
                envelopeValue = 0
            }
        }
    }

    /// Apply envelope curve shape
    private func applyCurve(_ progress: Float, from start: Float, to end: Float) -> Float {
        let t: Float
        switch envelopeCurve {
        case .linear:
            t = progress
        case .exponential:
            // -60 dB exponential DECAY (industry standard), concave: fast initial drop,
            // long slow tail — how a real string/plucked/analog voice releases. `applyCurve`
            // is only used for decay + release (attack uses smoothstep), and `t` is PROGRESS
            // toward the target, so a natural tail needs t to rise FAST then flatten. The old
            // formula `(exp(6.9p)-1)/(exp(6.9)-1)` was CONVEX (accelerating) → the level hung
            // near the peak for most of the segment then plummeted at the end ("hang-then-cut",
            // the most audible un-natural fingerprint). This is the correct exp(-kt) shape:
            // t(0.5)≈0.97 (97 % gone by half-time), t(0)=0, t(1)=1.
            t = (1.0 - exp(-progress * 6.9)) / (1.0 - exp(-6.9))
        case .logarithmic:
            // Fast initial change, slow tail
            t = Foundation.log(1.0 + progress * 9.0) / Foundation.log(10.0)
        }
        return start + (end - start) * t
    }

    // MARK: - Bio-Reactive (Extended — 12 Mappings)

    /// Apply extended bio-reactive parameters from coherence, HRV, heart rate, breathing
    /// - Parameters:
    ///   - coherence: HRV coherence (0-1)
    ///   - hrvVariability: HRV variability RMSSD (normalized 0-1)
    ///   - heartRate: Heart rate in BPM (normalized 0-1, where 0=40bpm, 1=180bpm)
    ///   - breathPhase: Breathing phase (0-1, 0=exhale, 1=inhale)
    ///   - breathDepth: Breathing depth (0-1)
    ///   - lfHfRatio: LF/HF power ratio (normalized 0-1)
    ///   - coherenceTrend: Coherence derivative (-1=dropping, 0=stable, 1=rising)
    /// Smoothed bio parameters — prevent per-frame artifacts
    private var _smoothedBrightness: Float = 0.25
    private var _smoothedAmplitude: Float = 0.45
    private var _spectralUpdateCounter: Int = 0
    private var _lfoPhase: Float = 0  // Internal LFO for filter sweep

    /// Patch-baseline timbre values, captured in `SynthPatch.apply(to:)`. Biofeedback
    /// modulates SUBTLY AROUND these (founder: "Biofeedback ändert dann nur subtil die Filter
    /// etc.") instead of overwriting them — so the character of the patch you chose survives,
    /// and the body only gently colours it (filter first, character a touch). Default to the
    /// synth's own defaults so a bio frame before any patch still behaves.
    public var bioBaseHarmonicity: Float = 0.88
    public var bioBaseNoiseLevel: Float = 0.01
    public var bioBaseReverbMix: Float = 0.25

    public func applyBioReactive(
        coherence: Float,
        hrvVariability: Float = 0.5,
        heartRate: Float = 0.5,
        breathPhase: Float = 0.5,
        breathDepth: Float = 0.5,
        lfHfRatio: Float = 0.5,
        coherenceTrend: Float = 0,
        profile: BioMapProfile = .natural
    ) {
        // =====================================================================
        // BIO-REACTIVE MAPPINGS — DESIGNED TO BE AUDIBLE
        // Each mapping must produce a change the user can HEAR.
        // Previous ranges were too subtle (0.15-0.45 brightness = inaudible).
        // Now: dramatic but musical. The user must FEEL their body in the sound.
        // =====================================================================

        let smoothCoeff: Float = 0.92  // Slightly faster response than 0.95

        // 1. Heart rate → Filter LFO speed + filter cutoff range
        //    Resting (0.0) = slow sweep through warm range
        //    Active (1.0) = faster sweep through brighter range
        let lfoSpeed: Float = 0.5 + heartRate * 2.0  // 0.5 Hz → 2.5 Hz
        _lfoPhase += lfoSpeed / 60.0  // 60 Hz update rate
        if _lfoPhase > 1.0 { _lfoPhase -= 1.0 }
        let lfoValue = (1.0 + sinf(_lfoPhase * .pi * 2)) * 0.5 // 0-1 sine LFO

        // Filter brightness: 0.08 (very dark/warm) → 0.7 (bright/open)
        // Coherence opens the filter, heart rate shifts the range, LFO sweeps
        let baseFilter: Float = 0.08 + coherence * 0.35  // 0.08-0.43 base
        let hrShift: Float = heartRate * 0.2               // +0.0-0.2 from HR
        let lfoSweep: Float = lfoValue * 0.15              // ±0.15 LFO sweep
        let targetBrightness = (baseFilter + hrShift + lfoSweep).clamped(to: 0.05...0.8)
        _smoothedBrightness = _smoothedBrightness * smoothCoeff + targetBrightness * (1.0 - smoothCoeff)
        brightness = _smoothedBrightness

        // Filter opens with coherence — starts at 220 Hz (dark), blooms toward 1800 Hz (open)
        // Coherence drives the opening (body must relax to hear the filter open)
        // Very slow smoothing (α=0.97) for silky transitions
        let targetCutoff: Float = 200 + coherence * 1600
        filterCutoff = filterCutoff * 0.97 + targetCutoff * 0.03

        // Recalculate spectral envelope 10x/sec for snappier bio response
        _spectralUpdateCounter += 1
        if _spectralUpdateCounter >= 6 {
            _spectralUpdateCounter = 0
            updateSpectralEnvelope()
        }

        // 2. Heart rate → Amplitude pulse (audible pump synced to pulse)
        let ampBase: Float = 0.35 + coherence * 0.15     // Calm = fuller
        let ampPulse: Float = ampBase + lfoValue * 0.12   // 0.35-0.62 range — gentler
        _smoothedAmplitude = _smoothedAmplitude * smoothCoeff + ampPulse * (1.0 - smoothCoeff)
        amplitude = _smoothedAmplitude

        // 3. Heart rate → Vibrato depth — GENTLE drift, not a wobble (founder: bio should be
        //    subtle). ~0.4 cent at rest → ~2.4 cent when active, a fraction of the old range.
        vibratoDepth = 0.004 + heartRate * 0.02
        vibratoRate = 0.05 + heartRate * 0.15   // Very slow → moderate

        // 4-6. CHARACTER (harmonicity · reverb · noise) — modulate SUBTLY AROUND the patch's own
        //      values, never overwrite them (founder: "Biofeedback ändert dann nur subtil die
        //      Filter etc."; audit A8: the old absolute assignments plastered every patch toward
        //      one neutral timbre). The FILTER above stays the main bio expression; these only
        //      gently colour the sound so the character you chose survives. Small, clamped
        //      deviations centred on the captured baseline.
        harmonicity = (bioBaseHarmonicity + (coherence - 0.5) * 0.12).clamped(to: 0.05...0.98)
        reverbMix   = (bioBaseReverbMix + (hrvVariability - 0.5) * 0.12).clamped(to: 0...0.9)
        noiseLevel  = Swift.max(0, bioBaseNoiseLevel + (0.5 - coherence) * 0.06)
        // Note: reverb DECAY is intentionally NOT bio-modulated (rebuilding the convolution IR
        // allocates and would click the tail per frame); the spatial character comes from
        // reverbMix, decay is set once via updateReverbDecay().

        // 7. Breath phase → Filter LFO depth (breathing modulates filter movement)
        lfoToFilterDepth = 0.05 + breathDepth * 0.3  // Deeper breath = more filter movement

        // HARMONIC-SERIES profile (opt-in; §1.2). Body drives the harmonic structure:
        // HRV opens the overtone richness (variability → harmonic spread), and the
        // breath phase swells the amplitude (audible breath). Overrides two outputs on
        // top of the natural mappings; `.natural` skips this entirely (identical sound).
        // 10 Hz control-plane writes; the render loop re-smooths harmonicity/gain.
        if profile == .harmonicSeries {
            harmonicity = (0.40 + hrvVariability * 0.50).clamped(to: 0.05...0.98) // HRV → overtone spread
            let breathSwell = 0.5 + 0.5 * sinf(breathPhase * 2 * .pi)              // 0..1 over the breath
            amplitude = (amplitude * (0.82 + 0.18 * breathSwell)).clamped(to: 0...1)
        }
    }

    // MARK: - Timbre Transfer

    /// Load a timbre profile from recorded harmonic analysis of a target instrument
    /// The profile is a [Float] of harmonicCount amplitudes representing the instrument's
    /// characteristic spectral envelope at a reference pitch.
    public func loadTimbreProfile(_ profile: [Float], blend: Float = 1.0) {
        guard profile.count >= harmonicCount else { return }
        timbreProfile = Array(profile.prefix(harmonicCount))
        timbreBlend = blend
        updateSpectralEnvelope()
    }

    /// Clear timbre profile (return to pure spectral shape)
    public func clearTimbreProfile() {
        timbreProfile = nil
        timbreBlend = 0
        updateSpectralEnvelope()
    }

    /// Generate a simple timbre profile from a known instrument type
    /// These are pre-computed spectral envelopes based on acoustic analysis
    public static func instrumentProfile(_ instrument: InstrumentTimbre, harmonics: Int = 64) -> [Float] {
        var profile = [Float](repeating: 0, count: harmonics)
        switch instrument {
        case .violin:
            // Strong fundamental, peak at 3rd-5th harmonic, slow rolloff
            for i in 0..<harmonics {
                let n = Float(i + 1)
                let peak = exp(-pow((n - 4.0) / 3.0, 2) * 0.5)
                let rolloff = 1.0 / pow(n, 0.8)
                profile[i] = (peak * 0.6 + rolloff * 0.4)
            }
        case .flute:
            // Strong fundamental, weak upper harmonics, breathy
            for i in 0..<harmonics {
                let n = Float(i + 1)
                profile[i] = 1.0 / pow(n, 2.0)
            }
        case .trumpet:
            // Mid-range peak (harmonics 3-8), brass-like
            for i in 0..<harmonics {
                let n = Float(i + 1)
                let peak = exp(-pow((n - 5.5) / 4.0, 2) * 0.5)
                profile[i] = peak
            }
        case .cello:
            // Rich low harmonics, warm rolloff
            for i in 0..<harmonics {
                let n = Float(i + 1)
                let body = exp(-pow((n - 2.5) / 2.5, 2) * 0.5)
                let rolloff = 1.0 / pow(n, 1.0)
                profile[i] = (body * 0.5 + rolloff * 0.5)
            }
        case .clarinet:
            // Odd harmonics dominant (hollow bore)
            for i in 0..<harmonics {
                let n = Float(i + 1)
                let isOdd = (i + 1) % 2 != 0
                profile[i] = isOdd ? 1.0 / pow(n, 0.7) : 0.05 / n
            }
        case .oboe:
            // All harmonics present, mid-range emphasis
            for i in 0..<harmonics {
                let n = Float(i + 1)
                let peak = exp(-pow((n - 6.0) / 5.0, 2) * 0.5)
                profile[i] = peak * 0.7 + 0.3 / n
            }
        }

        // Normalize
        var maxVal: Float = 0
        vDSP_maxv(profile, 1, &maxVal, vDSP_Length(harmonics))
        if maxVal > 0 {
            var div = maxVal
            profile.withUnsafeMutableBufferPointer { buf in
                guard let ptr = buf.baseAddress else { return }
                vDSP_vsdiv(ptr, 1, &div, ptr, 1, vDSP_Length(harmonics))
            }
        }
        return profile
    }

    /// Known instrument timbre profiles for timbre transfer
    public enum InstrumentTimbre: String, CaseIterable, Sendable {
        case violin = "Violin"
        case flute = "Flute"
        case trumpet = "Trumpet"
        case cello = "Cello"
        case clarinet = "Clarinet"
        case oboe = "Oboe"
    }

    // MARK: - Spectral Morphing

    /// Set up spectral morph from current shape to target
    public func startMorph(to target: SpectralShape, duration: Float = 1.0) {
        morphTarget = target
        morphPosition = 0
        // Morphing is driven externally (e.g., bio-reactive coherence trend)
        // or by calling setMorphPosition() from the control loop
    }

    /// Set morph position (0-1), typically called from 60Hz control loop
    public func setMorphPosition(_ position: Float) {
        morphPosition = max(0, min(1, position))
        updateSpectralEnvelope()
    }

    // MARK: - State Access

    /// Get current spectral envelope for visualization
    public func getSpectralEnvelope() -> [Float] {
        return Array(smoothedAmplitudes.prefix(harmonicCount))
    }

    // MARK: - Reset

    /// Reset all state
    public func reset() {
        for i in 0..<harmonicCount {
            phases[i] = 0
            smoothedAmplitudes[i] = 0
        }
        for i in 0..<noiseBandCount {
            noiseFilterState[i] = 0
        }
        vibratoPhase = 0
        envelopeStage = .idle
        envelopeValue = 0
        envelopeSamples = 0
        releaseStartLevel = 0
        attackStartLevel = 0
        morphTarget = nil
        morphPosition = 0
    }
}

// MARK: - EchoelPolyDDSP — Polyphonic DDSP Engine

/// Polyphonic wrapper over EchoelDDSP.
/// Manages up to maxVoices independent DDSP voices with voice stealing.
///
/// Architecture:
///   - Round-robin voice allocation with oldest-voice stealing
///   - Shared bio-reactive parameters across all voices
///   - Per-voice frequency, envelope, and timbre
///   - Stereo output with per-voice pan
///
/// Performance: O(maxVoices * harmonicCount) per sample, SIMD-accelerated
///
/// Thread-safety: Same invariant as EchoelDDSP — all access serialized via @MainActor.
/// Bio→timbre mapping character (COLLAB_SYNC_TRIAGE §1.2). `.natural` is the
/// established mapping (unchanged). `.harmonicSeries` makes the BODY drive the
/// harmonic structure more directly — HRV opens the overtone richness and the
/// breath swells the amplitude — the "harmonic mapping of physiological rhythms"
/// character. Opt-in; uses only real signals (no fabricated depth/LF-HF).
public enum BioMapProfile: Int, Sendable, Codable {
    case natural
    case harmonicSeries
}

public final class EchoelPolyDDSP: @unchecked Sendable {

    // MARK: - Configuration

    public let maxVoices: Int
    public let sampleRate: Float

    /// Concert pitch (Kammerton) reference for MIDI→Hz, A4 in Hz. Default 440.
    /// Written from the main actor when the user changes tuning and read on the
    /// audio thread in `noteOn`; an aligned `Float` word write/read is atomic, so
    /// retuning a held loop is safe without a queue. Clamped by the setter caller.
    public var a4Hz: Float = 440

    /// Per-pitch-class (0=C…11=B) cent deviation from 12-TET, applied at noteOn so
    /// a take can play in just intonation, a maqām, etc. All zeros = 12-TET =
    /// identical playback (the default). Written from the main actor; read on the
    /// audio thread in `noteOn`. Kept as a fixed 12-element buffer and mutated
    /// **in place** (never reseated) so the audio-thread read never races an ARC
    /// retain/release on the backing storage — same discipline as `a4Hz`. A torn
    /// read at worst detunes a single note-on by one frame; no heap corruption.
    private var tuningCents: [Float] = Array(repeating: 0, count: 12)

    /// Install a 12-entry pitch-class retune table (no-op if not exactly 12).
    /// In-place element copy — does not swap the array reference, so it is safe to
    /// call while the audio thread is reading `tuningCents` in `noteOn`.
    public func setTuningCents(_ cents: [Float]) {
        guard cents.count == 12 else { return }
        for i in 0..<12 { tuningCents[i] = cents[i] }
    }

    // MARK: - Voices

    private var voices: [EchoelDDSP]
    private var voiceNotes: [Int]      // MIDI note per voice (-1 = free)
    private var voiceAges: [Int]       // Age counter for voice stealing
    private var ageCounter: Int = 0

    /// Smoothed poly makeup gain (audio-thread state) — eased toward the
    /// voice-count target each render block so a single note sounds FULL while a
    /// dense chord is backed off before the safety tanh (founder 2026-07-11:
    /// "EchoelSynth rudimentär bei den Levels · Einzelnote voll, Akkord zerrt
    /// nicht"). Starts at the single-voice full gain. Read/written only on the
    /// audio thread in `renderStereo`; reset in `reset()`.
    private var polyMakeupGain: Float = 0.85

    // MARK: - Per-Voice Pan

    /// Pan position per voice (-1.0 = left, 0 = center, 1.0 = right)
    private var voicePans: [Float]

    // MARK: - Shared Bio-Reactive State

    /// When false (default) bio never touches the voices at note-on, so each note
    /// keeps its patch timbre and its played velocity. Set true (mirrors
    /// PolySynthVoice.bioModulationEnabled) to let bio shape new notes immediately.
    public var bioModulationEnabled: Bool = false
    private var bioCoherence: Float = 0.5
    private var bioHRV: Float = 0.5
    private var bioHeartRate: Float = 0.5
    private var bioBreathPhase: Float = 0.5
    private var bioBreathDepth: Float = 0.5
    private var bioLfHfRatio: Float = 0.5
    private var bioCoherenceTrend: Float = 0
    /// Bio→timbre mapping character fanned to every voice (default `.natural`).
    private var bioProfile: BioMapProfile = .natural

    // MARK: - Scratch Buffers (pre-allocated, zero audio-thread allocation)

    private var voiceBuffer: [Float]
    private var mixBufferL: [Float]
    private var mixBufferR: [Float]
    private var scaledBufferL: [Float]
    private var scaledBufferR: [Float]

    /// Initialize polyphonic DDSP.
    ///
    /// - Parameter frameSize: parameter-update frame size forwarded to each
    ///   voice (default 192 = 250 Hz at 48 kHz). Does not cap the render block
    ///   length — scratch buffers are sized for the largest plausible block.
    public init(
        maxVoices: Int = 8,
        harmonicCount: Int = 64,
        sampleRate: Float = 48000.0,
        frameSize: Int = 192
    ) {
        self.maxVoices = maxVoices
        self.sampleRate = sampleRate

        self.voices = (0..<maxVoices).map { index in
            // Distinct noise seed per voice (golden-ratio step) so summed voices
            // don't share an identical noise sequence.
            let v = EchoelDDSP(harmonicCount: harmonicCount, sampleRate: sampleRate, frameSize: frameSize,
                               noiseSeed: 0x12345678 &+ UInt32(index) &* 0x9E3779B9)
            // De-phase the slide-expression chorus per voice (golden-angle spacing)
            // so a chord's voices wobble independently, never in lockstep.
            v.expressSeed = Float(index) * 2.399963
            return v
        }
        self.voiceNotes = [Int](repeating: -1, count: maxVoices)
        self.voiceAges = [Int](repeating: 0, count: maxVoices)
        self.voicePans = [Float](repeating: 0, count: maxVoices)

        let maxFrameSize = 4096
        self.voiceBuffer = [Float](repeating: 0, count: maxFrameSize)
        self.mixBufferL = [Float](repeating: 0, count: maxFrameSize)
        self.mixBufferR = [Float](repeating: 0, count: maxFrameSize)
        self.scaledBufferL = [Float](repeating: 0, count: maxFrameSize)
        self.scaledBufferR = [Float](repeating: 0, count: maxFrameSize)
    }

    // MARK: - Unison

    /// Maximum stacked detuned voices per played note. Bounds the polyphony cost.
    public static let maxUnison = 3

    /// Unison voice count per note (1 = off → bit-identical to before). Written from
    /// the main actor, read on the audio thread in `noteOn`; an aligned `Int` word is
    /// atomic, so it is safe to change live (takes effect on the next note). Clamped
    /// to 1…maxUnison on read.
    public var unisonCount: Int = 1
    /// Total detune spread across the unison stack, in cents (0 = no detune). Same
    /// atomic-Float discipline as `a4Hz`.
    public var unisonDetuneCents: Float = 0

    /// Set unison live (clamped). count 1 = off; detune is the full spread in cents.
    public func setUnison(count: Int, detuneCents: Float) {
        unisonCount = min(max(count, 1), Self.maxUnison)
        unisonDetuneCents = min(max(detuneCents, 0), 50)
    }

    /// Global filter-cutoff multiplier (1 = no change), fanned to every voice in the
    /// render. Driven by parameter automation; clamped to a musical range.
    public var cutoffScale: Float = 1.0
    public func setCutoffScale(_ scale: Float) {
        cutoffScale = min(max(scale.isFinite ? scale : 1, 0.1), 8)
    }

    /// Slide-expression amounts (touch gesture), fanned to every voice in the render
    /// exactly like `cutoffScale`. Written from the main actor (atomic Floats), read
    /// on the audio thread; 0/0 (default) is bit-identical to before.
    public var expressVibrato: Float = 0
    public var expressChorus: Float = 0
    public func setSlideExpression(vibrato: Float, chorus: Float) {
        expressVibrato = min(max(vibrato.isFinite ? vibrato : 0, 0), 1)
        expressChorus = min(max(chorus.isFinite ? chorus : 0, 0), 1)
    }

    /// Per-sample one-pole coefficient for each voice's base-frequency glide,
    /// fanned in the render like `cutoffScale`. Default 0.01 = the legacy ~2 ms
    /// micro-glide (bit-identical). `setPortamento` maps a musical glide time onto
    /// it; clamped so it can neither snap (audible step) nor stall forever.
    public var portamentoCoeff: Float = 0.01

    /// Portamento/glide time in seconds for slid notes. 0 (or < 5 ms) restores the
    /// legacy micro-glide; longer times make `slideNote` a true singing portamento.
    /// coeff ≈ 1/(τ·sampleRate) for the one-pole; atomic-Float discipline.
    public func setPortamento(seconds: Float) {
        let s = min(max(seconds.isFinite ? seconds : 0, 0), 0.6)
        portamentoCoeff = s < 0.005 ? 0.01 : min(0.01, max(1.0 / (s * sampleRate), 0.00004))
    }

    /// GLIDE every voice holding `oldNote` to `newNote` WITHOUT retriggering: the
    /// envelope keeps running and only the frequency target moves (each stacked
    /// unison voice keeps its detune ratio), so the note SLIDES at the portamento
    /// time instead of re-attacking — true legato for the touch surface. Runs on
    /// the AUDIO thread (called from the note-command drain, same discipline as
    /// noteOn/noteOff). If nothing holds `oldNote` any more, a normal noteOn fires.
    public func slideNote(from oldNote: Int, to newNote: Int, velocity: Float = 1.0) {
        guard oldNote != newNote else { return }
        let newCents = tuningCents[((newNote % 12) + 12) % 12]
        let newBase = a4Hz * pow(2.0, (Float(newNote - 69) + newCents / 100.0) / 12.0)
        let oldCents = tuningCents[((oldNote % 12) + 12) % 12]
        let oldBase = a4Hz * pow(2.0, (Float(oldNote - 69) + oldCents / 100.0) / 12.0)
        let ratio = newBase / max(oldBase, 1e-3)
        var moved = false
        for i in 0..<maxVoices where voiceNotes[i] == oldNote {
            voices[i].frequency *= ratio        // smoothedFreq glides there per-sample
            voiceNotes[i] = newNote
            ageCounter += 1
            voiceAges[i] = ageCounter
            moved = true
        }
        if !moved { noteOn(note: newNote, velocity: velocity) }
    }

    // MARK: - Note Control

    /// MIDI note on
    public func noteOn(note: Int, velocity: Float = 1.0) {
        // Per-pitch-class microtonal retune (cents → semitone fraction). Zero table
        // = standard 12-TET, bit-identical to before.
        let cents = tuningCents[((note % 12) + 12) % 12]
        let baseFreq = a4Hz * pow(2.0, (Float(note - 69) + cents / 100.0) / 12.0)
        let v = min(1, max(0, velocity))

        let u = min(max(unisonCount, 1), Self.maxUnison)
        if u == 1 {
            // OFF: spawn one voice with the original pan/amplitude behaviour (unchanged).
            spawnVoice(note: note, frequency: baseFreq, velocity: v, unisonPan: nil, unisonGain: 1)
            return
        }
        // ON: stack `u` detuned voices, symmetric about the played pitch, panned
        // across the stereo field. Per-voice gain 1/√u keeps the summed loudness sane.
        let gain = 1 / sqrt(Float(u))
        let panSpread: Float = 0.6
        let spread = unisonDetuneCents      // snapshot once (atomic read) for this note
        for k in 0..<u {
            let t = Float(k) / Float(u - 1) * 2 - 1          // -1 … +1
            let detune = pow(2.0, (t * spread * 0.5) / 1200.0)
            spawnVoice(note: note, frequency: baseFreq * detune, velocity: v,
                       unisonPan: t * panSpread, unisonGain: gain)
        }
    }

    /// Key-follow stereo pan for a polyphonic voice: low notes left, high notes
    /// right, stable per pitch (independent of which voice slot the note lands in).
    /// Pure arithmetic — bit-identical to the inline form, testable in isolation.
    /// `note` is a MIDI note number; the C2…C6 span maps to ±`spread`, clamped.
    static func keyFollowPan(forNote note: Int, spread: Float = 0.35) -> Float {
        let lo: Float = 36, hi: Float = 84            // C2…C6 musical span
        let norm = Swift.min(1, Swift.max(0, (Float(note) - lo) / (hi - lo)))
        return (norm * 2.0 - 1.0) * spread
    }

    /// Allocate one voice for `note` and start it. `unisonPan`/`unisonGain` override
    /// the default pan-spread / unity gain when stacking a unison voice.
    private func spawnVoice(note: Int, frequency freq: Float, velocity v: Float,
                            unisonPan: Float?, unisonGain: Float) {
        let voiceIdx = allocateVoice()

        voiceNotes[voiceIdx] = note
        ageCounter += 1
        voiceAges[voiceIdx] = ageCounter

        if let pan = unisonPan {
            voicePans[voiceIdx] = pan
        } else if maxVoices > 1 {
            // Stable stereo image: pan by PITCH, not the (reused) slot index. The old
            // index-keyed spread made a note's pan depend on which slot it landed in,
            // so fast/arp notes reusing a slot jumped across the field (audible stereo
            // wobble). Key-follow panning (low→left, high→right, like a hardware synth)
            // is stable per pitch; the dedicated mono SubBassVoice anchors the low end.
            voicePans[voiceIdx] = Self.keyFollowPan(forNote: note)
        } else {
            voicePans[voiceIdx] = 0
        }

        // Idle voice → clean staggered restart; reused/stolen ringing voice →
        // glide (no hard reset) so we never click mid-tail.
        voices[voiceIdx].prepareForNote(hardReset: !voices[voiceIdx].isActive)
        // Anschlagdynamik (touch response): velocity sets level AND, via noteOn,
        // the onset snap. The amplitude curve expands dynamics on percussive patches
        // (soft → softer, hard → present) while leaving pads linear, so the dialed-in
        // pad loudness is untouched. velocity stored for the per-note attack scale.
        let percussiveness = max(0, 1 - voices[voiceIdx].attack / 0.15)
        voices[voiceIdx].noteVelocity = v
        voices[voiceIdx].amplitude = pow(v, 1 + percussiveness * 0.5) * unisonGain
        voices[voiceIdx].noteOn(frequency: freq)
        // Only let bio overwrite the note's velocity/timbre when bio modulation is
        // actually on. Previously unconditional → every note collapsed to a neutral
        // ~0.45 amplitude and lost its patch character and velocity sensitivity.
        if bioModulationEnabled { applyBioToVoice(voiceIdx) }
    }

    /// MIDI note off
    public func noteOff(note: Int) {
        for i in 0..<maxVoices {
            if voiceNotes[i] == note {
                voices[i].noteOff()
                voiceNotes[i] = -1
            }
        }
    }

    /// All notes off
    public func allNotesOff() {
        for i in 0..<maxVoices {
            voices[i].noteOff()
            voiceNotes[i] = -1
        }
    }

    // MARK: - Voice Allocation

    private func allocateVoice() -> Int {
        // Prefer a truly silent voice (free slot AND envelope idle) so we never
        // cut off a still-audible release tail.
        for i in 0..<maxVoices where voiceNotes[i] < 0 && !voices[i].isActive {
            return i
        }
        // Next, any free slot (note released but tail may still be ringing).
        if let freeIdx = voiceNotes.firstIndex(of: -1) {
            return freeIdx
        }
        // Steal oldest voice
        var oldestAge = Int.max
        var oldestIdx = 0
        for i in 0..<maxVoices {
            if voiceAges[i] < oldestAge {
                oldestAge = voiceAges[i]
                oldestIdx = i
            }
        }
        voices[oldestIdx].noteOff()
        // Clear the stolen slot's note tag so a later noteOff(note:) for the OLD
        // pitch can't re-release this voice after it's been reassigned (would cut
        // a freshly-attacked note → click).
        voiceNotes[oldestIdx] = -1
        return oldestIdx
    }

    // MARK: - Bio-Reactive

    /// Apply bio-reactive parameters to all voices
    public func applyBioReactive(
        coherence: Float,
        hrvVariability: Float = 0.5,
        heartRate: Float = 0.5,
        breathPhase: Float = 0.5,
        breathDepth: Float = 0.5,
        lfHfRatio: Float = 0.5,
        coherenceTrend: Float = 0,
        profile: BioMapProfile = .natural
    ) {
        bioCoherence = coherence
        bioHRV = hrvVariability
        bioHeartRate = heartRate
        bioBreathPhase = breathPhase
        bioBreathDepth = breathDepth
        bioLfHfRatio = lfHfRatio
        bioCoherenceTrend = coherenceTrend
        bioProfile = profile

        for i in 0..<maxVoices where voiceNotes[i] >= 0 {
            applyBioToVoice(i)
        }
    }

    private func applyBioToVoice(_ idx: Int) {
        voices[idx].applyBioReactive(
            coherence: bioCoherence,
            hrvVariability: bioHRV,
            heartRate: bioHeartRate,
            breathPhase: bioBreathPhase,
            breathDepth: bioBreathDepth,
            lfHfRatio: bioLfHfRatio,
            coherenceTrend: bioCoherenceTrend,
            profile: bioProfile
        )
    }

    // MARK: - Bulk voice configuration

    /// Apply a configuration block to every voice — used to recall a SynthPatch
    /// across the whole pool. Voice frequency/amplitude (per-note) are left to
    /// the note path; the block should only touch shared timbre params.
    public func forEachVoice(_ body: (EchoelDDSP) -> Void) {
        for voice in voices { body(voice) }
    }

    // MARK: - Poly makeup gain (pure, unit-testable)

    /// Target makeup gain for `voiceCount` sounding voices. A single note plays at
    /// `fullGain` (near-full — the old fixed 0.40 made even one note thin); as more
    /// voices stack, the gain follows an RMS-style 1/√N law so their coherent sum is
    /// backed off before the safety tanh instead of slamming it. Clamped to
    /// [`floorGain`, `fullGain`]. Pure — no state, no allocation, unit-testable.
    nonisolated static func polyMakeupTarget(voiceCount: Int,
                                             fullGain: Float = 0.85,
                                             floorGain: Float = 0.22) -> Float {
        let n = Swift.max(voiceCount, 1)
        let g = fullGain / Foundation.sqrt(Float(n))
        return Swift.min(Swift.max(g, floorGain), fullGain)
    }

    /// One-pole smoothing step toward `target` (per render block). `coeff` ∈ 0…1 is
    /// the fraction of the remaining distance closed this block — SMALL = slow = no
    /// pumping when a note starts/stops (the raw, unsmoothed 1/√N was removed in the
    /// past precisely because it jumped audibly on every chord/arp change; smoothing
    /// is what makes the voice-count law usable). Pure — unit-testable.
    nonisolated static func smoothedMakeup(current: Float, target: Float, coeff: Float) -> Float {
        let c = Swift.min(Swift.max(coeff, 0), 1)
        return current + (target - current) * c
    }

    // MARK: - Audio Rendering

    /// Render stereo audio from all active voices
    public func renderStereo(left: inout [Float], right: inout [Float], frameCount: Int) {
        guard frameCount <= mixBufferL.count else { return }

        // Slide-expression settles HERE, on the audio clock (~0.45 s tau per
        // block): a resting finger fires no touch events, so without this the
        // vibrato/ensemble would stay engaged forever once pushed (review
        // 2026-07-08). Pushes from the main thread simply re-raise the values;
        // this also makes the lift-off fade a smooth ramp instead of a hard zero
        // (no cent-step tick on ringing release tails). Pure arithmetic, no
        // allocation; a lost update against a concurrent main-thread push is at
        // worst one block of slightly-stale depth (the accepted Float contract).
        let decay = exp(-Float(frameCount) / sampleRate / 0.45)
        expressVibrato *= decay
        expressChorus *= decay
        if expressVibrato < 0.0005 { expressVibrato = 0 }
        if expressChorus < 0.0005 { expressChorus = 0 }

        // Clear mix buffers
        memset(&mixBufferL, 0, frameCount * MemoryLayout<Float>.size)
        memset(&mixBufferR, 0, frameCount * MemoryLayout<Float>.size)

        var soundingVoices = 0
        for i in 0..<maxVoices {
            // Render any voice still producing sound — held notes AND release
            // tails of notes already noteOff'd (voiceNotes == -1 but still ringing).
            guard voiceNotes[i] >= 0 || voices[i].isActive else { continue }
            soundingVoices += 1

            // Fan the global cutoff scale (automation) + slide expression +
            // portamento to the voice before it renders (all on the one audio thread).
            voices[i].renderCutoffScale = cutoffScale
            voices[i].expressVibrato = expressVibrato
            voices[i].expressChorus = expressChorus
            voices[i].glideCoeff = portamentoCoeff

            // Render voice mono
            memset(&voiceBuffer, 0, frameCount * MemoryLayout<Float>.size)
            voices[i].render(buffer: &voiceBuffer, frameCount: frameCount, stereo: false)

            // Equal-power pan inline (avoid cross-file dependency)
            let theta = (voicePans[i] + 1.0) * 0.5 * Float.pi * 0.5
            let leftGain = cos(theta)
            let rightGain = sin(theta)

            // Mix into stereo buffers (vDSP accelerated, zero allocation)
            var lg = leftGain
            var rg = rightGain

            vDSP_vsmul(voiceBuffer, 1, &lg, &scaledBufferL, 1, vDSP_Length(frameCount))
            vDSP_vsmul(voiceBuffer, 1, &rg, &scaledBufferR, 1, vDSP_Length(frameCount))
            // Accumulate in-place. vDSP_vadd permits identical in/out pointers, so we
            // pass the mix buffer's own base address as both input A and output C via
            // withUnsafeMutableBufferPointer. This avoids the Swift exclusivity
            // violation WITHOUT the previous `let mixL = mixBufferL` copy, which forced
            // a copy-on-write heap allocation per voice per block on the audio thread.
            let n = vDSP_Length(frameCount)
            mixBufferL.withUnsafeMutableBufferPointer { mix in
                if let base = mix.baseAddress {
                    vDSP_vadd(base, 1, scaledBufferL, 1, base, 1, n)
                }
            }
            mixBufferR.withUnsafeMutableBufferPointer { mix in
                if let base = mix.baseAddress {
                    vDSP_vadd(base, 1, scaledBufferR, 1, base, 1, n)
                }
            }
        }

        // NaN/Inf guard on mix buffers before copy
        for i in 0..<frameCount {
            if !mixBufferL[i].isFinite { mixBufferL[i] = 0 }
            if !mixBufferR[i].isFinite { mixBufferR[i] = 0 }
        }

        // Poly makeup + soft-limiter safety. The makeup gain is now voice-count
        // aware BUT SMOOTHED (founder 2026-07-11 "Einzelnote voll, Akkord zerrt
        // nicht"): a single note plays near-full (0.85) instead of the old thin
        // fixed 0.40, while a dense chord follows a 1/√N law down toward the floor
        // so its coherent sum is backed off BEFORE the tanh — which returns the
        // tanh to a pure safety brick-wall (near-linear for typical content), not a
        // tone-colouring stage. The one-pole (τ ≈ 0.25 s) is the whole reason this
        // is safe where the raw per-block 1/√N was not: note-on/off no longer jumps
        // the level (the old "audible pumping on chord/arp changes"). Downstream the
        // master −1 dBFS trim + AutoMixChain limiter hold the final level.
        let makeupTau: Float = 0.25
        let makeupCoeff = 1 - exp(-Float(frameCount) / sampleRate / makeupTau)
        let makeupTarget = Self.polyMakeupTarget(voiceCount: soundingVoices)
        polyMakeupGain = Self.smoothedMakeup(current: polyMakeupGain,
                                             target: makeupTarget, coeff: makeupCoeff)
        let gainComp = polyMakeupGain
        for i in 0..<frameCount {
            let scaledL = mixBufferL[i] * gainComp
            let scaledR = mixBufferR[i] * gainComp
            // Fast tanh approximation: x * (27 + x²) / (27 + 9x²)
            // Accurate to <0.1% error, no branching, SIMD-friendly
            let xL2 = scaledL * scaledL
            let xR2 = scaledR * scaledR
            mixBufferL[i] = scaledL * (27.0 + xL2) / (27.0 + 9.0 * xL2)
            mixBufferR[i] = scaledR * (27.0 + xR2) / (27.0 + 9.0 * xR2)
        }

        // Copy to output
        left.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(base, mixBufferL, frameCount * MemoryLayout<Float>.size)
        }
        right.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(base, mixBufferR, frameCount * MemoryLayout<Float>.size)
        }
    }

    // MARK: - State

    /// Number of currently active voices
    public var activeVoiceCount: Int {
        voiceNotes.reduce(0) { $0 + ($1 >= 0 ? 1 : 0) }
    }

    /// Reset all voices
    public func reset() {
        for i in 0..<maxVoices {
            voices[i].reset()
            voiceNotes[i] = -1
            voiceAges[i] = 0
        }
        ageCounter = 0
        polyMakeupGain = 0.85   // back to single-voice full gain; render eases from here
    }
}
#endif // canImport(Accelerate)
