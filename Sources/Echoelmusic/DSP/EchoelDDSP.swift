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
/// Thread-safety invariant (corrected 2026-07-18, audit AU3 — the old note claimed
/// "exclusively MainActor / do NOT call from background threads", the OPPOSITE of
/// how the render path uses it, and cited storage `EchoelCreativeWorkspace.bioSynth`
/// that no longer exists). `@unchecked Sendable` because each instance is reached by
/// exactly ONE owner and the read/write threads are kept disjoint per-frame:
///
/// • `renderStereo()` / `render()` ALWAYS run on the audio render thread (the
///   `AVAudioSourceNode` render block). Audio-thread-safe by construction —
///   pre-allocated buffers, vDSP only, zero runtime allocation, no lock/malloc/
///   ObjC/GCD.
/// • `applyBioReactive()` runs on the audio RENDER thread in BOTH owners
///   (corrected 2026-07-24 — the old note here still described a control-thread
///   caller and an open "KNOWN SMELL"; both were closed by tasks #83/#90/#94):
///     - `BioReactiveSynthVoice` — enqueues on the control poll to an SPSC
///       command queue, drains + applies inside its render block.
///     - `PolySynthVoice` — same discipline: the poll enqueues to `bioCommands`
///       (SPSC), the render block drains to the latest frame and applies it there,
///       AFTER the patch drain (see PolySynthVoice.swift). ⚠️ It has a SECOND
///       caller that is not a bio frame at all: `spawnVoice` applies the cached
///       bio values to the voice it just allocated, so a voice's smoothers also
///       advance once per NOTE-ON. That is what makes the τ figures in
///       `applyBioReactive` ceilings rather than facts (#332).
///   ⛔ A THIRD BULLET STOOD HERE — AUv3 `EchoelmusicAudioUnit`, "the 10 Hz KVO
///   poll writes atomic-width Float mirrors (`BioMirror`)". That target was removed
///   by #121 Slice 1; `git ls-files | grep -i auv3` returns one orphaned test and
///   three scratchpads, no source. It mattered because this list is what a reader
///   auditing "who calls this on the audio thread" works from — a phantom owner
///   sends them hunting a render path that does not exist, and it inflated the
///   apparent risk of every edit to this function.
///   ⛔ AND THE "10 Hz" IN THE SURVIVING BULLETS WAS THE #315 UNIT ERROR ITSELF:
///   the poll fires at 10 Hz but drops every frame whose timestamp is unchanged,
///   and every wired publisher emits ~1 Hz. Said plainly here because the same
///   stale rate belief is what cost #331 and #332 two separate slices.
/// • Note / patch / master-gain updates use the same lock-free handoff (SPSC queue
///   / `nonisolated(unsafe)` mirror).
///
/// Consequence: `updateSpectralEnvelope()`'s in-place rewrite of `harmonicAmplitudes`
/// (once per `applyBioReactive`, via `brightness`'s `didSet`) happens on the ONE render
/// thread that also reads it, so there is no longer a cross-thread array race / COW hazard
/// on any path.
///
/// ⛔ THIS LINE SAID "every 6th `applyBioReactive`" UNTIL #331, AND IT WAS ALREADY WRONG
/// BEFORE #331 DELETED THAT COUNTER. `brightness` carries `didSet { updateSpectralEnvelope() }`
/// and is assigned on every call, so the rebuild was never throttled; the counter only fired a
/// duplicate. Corrected here rather than left as "harmlessly stale" because this is the FILE
/// HEADER — the first thing a session reads about this class — and it is the one place a
/// reader would learn the rebuild rate without reading `applyBioReactive` itself.
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
    /// Instrument"). Set by `SynthPatch.apply` off (or ON) the audio thread — `apply(to:)`
    /// is drained inside `PolySynthVoice`'s render block (`SynthPatch.swift`, which heads
    /// `ResolvedPatch.apply` "AUDIO-THREAD SAFE"), so the old "off the audio thread" here was
    /// simply wrong, and wrong in the doc that a `didSet` was later hung under. Aligned
    /// Float, atomic-width, same discipline as `warmthDrive`; read per-sample and folded into
    /// the master-gain smoother so a patch switch GLIDES instead of clicking. 1.0 =
    /// bit-identical to before. (The sanitiser below makes the store no longer a single
    /// atomic-width write — store, load, compare, maybe store — so a concurrent render can
    /// read the raw value for that window. Harmless only BECAUSE the accumulator clamp now
    /// recovers; worth naming rather than leaving the atomic-width claim standing unqualified.)
    ///
    /// ⚠️ SANITISED AT THE DOOR (#295). It is one of TWO inputs to the master-gain smoother,
    /// not the only one — `amplitude` above is equally raw, and the reason it gets no door is
    /// that both its writers are audited finite (`applyBioReactive` clamps to 0…1; the poly
    /// path is `pow(v, expo) * unisonGain` with both factors ≤ 1). The honest consequence,
    /// since the accumulator clamp alone cannot heal a non-finite TARGET: a non-finite
    /// `amplitude` would leave `smoothedGain` bounded-but-stuck at 0 — silent, not poisoned.
    /// `patchOutputLevel` is the input with no such audit: `SynthPatch.outputLevel` comes from `decodeIfPresent` on
    /// a file the user could have edited or a save that was truncated, and `apply(to:)`
    /// writes it here without a clamp. The smoother downstream has NO clamp of its own that
    /// could rescue it — unlike the filter cutoff, whose render clamp caught the same class
    /// of poison on every sample — so a non-finite value here multiplied every sample of
    /// every voice for the lifetime of the app. The factory range is 0.45…1.4
    /// (`loudnessNormalized`), so this substitution can only ever fire on data that was
    /// already broken; a healthy patch is bit-identical.
    public var patchOutputLevel: Float = 1.0 {
        didSet {
            if !patchOutputLevel.isFinite { patchOutputLevel = 1.0 }
        }
    }

    /// Analog-warmth drive (0 = clean, bit-identical). A gentle pre-filter soft-
    /// saturation that gives the pure additive SINE stack some harmonic body, so it
    /// stops reading as cold/"plastic" (founder 2026-07-11 sound north-star: warm ·
    /// organic · dubbig, "kein kaltes überladenes Plastik synthie gedudel"). Set by
    /// `SynthPatch.apply` off (or on) the audio thread — an aligned Float, atomic-
    /// width, same discipline as `patchOutputLevel`; read per-sample in `render` and
    /// fed to the pure `analogWarmth` shaper BEFORE the resonant filter (the filter
    /// then tames the added harmonics into warmth rather than harshness). 0 = the
    /// raw synth (all existing DSP golden tests unchanged).
    public var warmthDrive: Float = 0

    /// Velocity of the current note (0-1), used for touch dynamics (Anschlagdynamik).
    /// 0 = "no velocity context" (the mono/bio voice never sets it) → no attack
    /// scaling, behaviour unchanged. The poly engine sets the played velocity so a
    /// harder hit snaps the onset on percussive patches. Set on the trigger thread,
    /// read on the audio thread in the attack stage — an aligned Float, atomic-width.
    public var noteVelocity: Float = 0

    /// How much LOUDER OR QUIETER than a nominal note this one was played — the factor
    /// `applyBioReactive` multiplies its bio amplitude by, so the body SHAPES the note's level
    /// instead of erasing it. **Centred on 1.0, not on the raw velocity**: see below, because
    /// the difference between those two is a ~7 dB level regression.
    ///
    /// WHY THIS EXISTS (#174/#177). `spawnVoice` set `amplitude` from velocity and then let
    /// `applyBioToVoice` overwrite it outright. With bio modulation on — the instrument's whole
    /// purpose — velocity therefore did nothing, which made the Mix faders inaudible: a fader at
    /// 0 baked velocity 0 into the note (silent to the visual, which reads note amplitude out of
    /// `MusicalFrame`) while the sound played on unchanged. Mute that does not mute, and a grey
    /// visual over audible music.
    ///
    /// WHY IT IS A RATIO AGAINST `nominalVelocity`, NOT THE VELOCITY ITSELF. The generated take
    /// does not play near 1.0: `BioComposer` writes pads at 0.34–0.56 and bass at 0.48–0.70,
    /// then the genre mix glue trims further. Multiplying the bio amplitude by that raw value
    /// would drop the pad — the dominant texture — by ~7 dB, and ~11 dB on a percussive patch.
    /// `AutoMixChain` would claw some of it back, but it is clamped to ±6 dB and takes ~15–20 s,
    /// so the founder would hear "leiser geworden" long before it settled. Dividing by the
    /// velocity the material actually carries keeps a NOMINAL note at its previous level and
    /// spends the change on dynamics, which is the point.
    ///
    /// Capped at `maxBoost` so a hot note lifts the mix a little instead of slamming the poly
    /// tanh; 0 is deliberately reachable (velocity 0 ⇒ exactly 0 ⇒ a Mix fader at 0 truly mutes).
    ///
    /// 1.0 = "no velocity context" — the DEFAULT, and the mono/bio voice never leaves it. Its
    /// amplitude is then bit-identical to before, which is what keeps the bio-reactive synth
    /// from going quiet. Written in `spawnVoice` and read in the bio apply — on today's build
    /// both happen in the SAME render block (the poly note and bio commands are drained there),
    /// so there is no cross-thread hazard; it is an aligned Float, atomic-width, same discipline
    /// as `noteVelocity` above, so it stays safe if that ever changes.
    public var velocityGain: Float = 1.0

    /// The velocity a nominal generated note carries — the reference `velocityGain` is centred
    /// on. Taken from `BioComposer`'s own pad range (0.34–0.56), i.e. measured from the material
    /// rather than picked: a pad at this velocity keeps exactly the level it had before #174.
    public nonisolated static let nominalVelocity: Float = 0.5

    /// Ceiling on `velocityGain`. A hot note may lift the mix, but not without bound — the poly
    /// stage already has a safety tanh and this keeps notes off it. With `velocityCurve` applied
    /// only a near-maximum velocity reaches it, so it acts as a last-resort limiter rather than
    /// as the shape of the dynamics. (It was the shape, in the draft before this one, and that
    /// was wrong: bass and hot leads ALL landed on it, so the accents this change exists to
    /// restore were flattened back together at the top.)
    ///
    /// 1.7 is chosen so it NEVER binds for a legal velocity: the uncapped maximum is
    /// `2^(expo * velocityCurve)`, which tops out at ~1.68 for the steepest patch attack in the
    /// roster. A draft value of 1.4 still bound from velocity ~0.80 up — and downbeat lead
    /// accents on percussive genres reach ~0.90, so the flattening had merely MOVED into the
    /// loudest fifth of the range instead of going away. Headroom is not the constraint:
    /// 0.455 × 1.7 = 0.774, still under the 0...1 clamp, with the poly makeup and safety tanh
    /// downstream of that.
    public nonisolated static let maxVelocityBoost: Float = 1.7

    /// Gamma on the velocity exponent — how much of the played dynamic range reaches the level.
    /// 1.0 = the full curve, 0.5 = half the range in dB. MUST STAY > 0: at 0 this is `pow(x, 0)`,
    /// which is 1 for EVERY x including x = 0 in C, so a Mix fader at 0 would stop muting and
    /// #174 would silently re-arm itself. (An earlier version of this line offered "0 = velocity
    /// does nothing" as a supported setting. It is not; it is the defect.)
    ///
    /// WHY IT IS NOT 1.0. The exponent it modifies is `1 + percussiveness * 0.5`, and the roster
    /// that governs a GENERATED take — `MusicStyle.synthPatch`, not `SynthPatch.factory` — is
    /// mostly percussive: of its 26 genre patches, 19 have an attack under 0.15 s, so the exponent
    /// runs ~1.17–1.47. The other 7 sit at exactly 1.0, and they are precisely the ambient family
    /// (vaporwave · sciFi · stillMeditation · classical · selfObservation · drift ·
    /// contemplation) — so any retune of this constant must be checked against BOTH groups, not
    /// against "mostly percussive" alone. (The first version of this comment cited the wrong
    /// roster and the wrong counts. The conclusion held; the evidence did not.) At the full
    /// curve that turned the generated material's own velocity spread (pads 0.34–0.56, leads up
    /// to 0.9 — numbers nobody ever chose as a MIX decision) into a ~15 dB one-sided spread: the
    /// pad's pulse layer 12 dB down, everything hot pinned to the cap, and the lead about 4 dB
    /// FORWARD of the pad — reopening the exact complaint the genre mix glue exists to answer
    /// (`MusicStyle.mixLevels`, founder 2026-07-07: the melody sticking out unpleasantly).
    ///
    /// A floor would have been the wrong instrument: any floor above zero either breaks the mute
    /// this whole change is about, or needs a discontinuity right where the Mix fader travels —
    /// level holds, holds, then falls off a ledge into silence, which is a worse lying control
    /// than the one being fixed. A gamma keeps 0 → 0 exactly, keeps the unity fixpoint at
    /// `nominalVelocity`, keeps the DIRECTION of every dynamic, and halves the spread.
    public nonisolated static let velocityCurve: Float = 0.5

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

    /// The ONE audible domain of a filter cutoff in this engine, in Hz.
    ///
    /// ⛔ THE FIRST VERSION OF THIS PARAGRAPH ASSERTED THE OPPOSITE OF THE BUG THE CONSTANT WAS
    /// CREATED FOR, and it is the single most dangerous sentence I wrote in #294. It listed the
    /// four pre-existing copies as "the render clamp below, **the bio target in
    /// `applyBioReactive`**, `SoundPrompt`'s sanitiser and the Sound panel's knob range". The
    /// bio target had NO clamp — that absence IS #294. A session reading only this doc would
    /// conclude the bio path was already bounded and that this commit was pure de-duplication,
    /// and it contradicted both the comment at the assignment itself and the guard's header.
    ///
    /// The four REAL pre-existing copies, verified: the render clamp below · `SoundPrompt.swift`
    /// (`clamp(_:)`) · the Sound panel's knob range (`EchoelStudioView`) · and the one I missed
    /// entirely, `RoleRhythm.swift`'s `TimbreTrim.trimmed` — which matters most of the four
    /// because it is on the LIVE path (`applyTakeSound`, every Generate and every preset
    /// recall) and multiplies the cutoff by up to 1.12 BEFORE the value ever becomes
    /// `bioBaseFilterCutoff`. The render clamp now reads from here, and the bio assignment is
    /// the new fifth site.
    ///
    /// ⛔ AND THE NEXT SENTENCE HERE — "`SoundPrompt` and the knob keep their literals — folding a
    /// UI range and a prompt sanitiser into a DSP constant is a separate errand" — WAS TRUE UNTIL
    /// #441 AND SURVIVED IT. That errand is done: both now read `SynthPatch.Bounds.filterCutoff`,
    /// which is defined as this constant, so the only remaining spellings are the render clamp
    /// below and the bio assignment. ⚠️ `RoleRhythm.swift`'s `TimbreTrim.trimmed` is STILL a
    /// separate copy on the LIVE path, and it is still guarded by nothing but this paragraph —
    /// that half of the note has not aged, and it is the one that matters.
    ///
    /// The doc on `filterCutoff` said "[20-20000 Hz]" while every clamp in the codebase used
    /// 18000. Nothing depended on the wrong upper bound, which is exactly why it survived.
    public nonisolated static let cutoffRange: ClosedRange<Float> = 20...18000

    /// Domain of the harmonic/noise character smoothers in `render` (#296). 0…1 because that
    /// is the domain `SoundPrompt`'s `c01` enforces on BOTH fields, and because
    /// `applyBioReactive`'s harmonicity line already sits inside it (0.05…0.98, unconditional
    /// — not an anchored branch; the anchored/sentinel split applies to vibrato and LFO
    /// depth). Every shipped patch is inside it, so the clamp is a boundary, not a tuning
    /// knob. Named rather than written as a literal twice for the same reason `cutoffRange` is.
    ///
    /// ⛔ DELIBERATELY NOT JUSTIFIED BY `applyBioReactive`'s noiseLevel line — that is
    /// `Swift.max(0, …)`, a floor with NO ceiling, and that missing ceiling IS the bug. The
    /// first version of this comment cited it anyway, in the same commit whose render-site
    /// comment spells out why the citation is circular. Two comments, one the guard against
    /// the other, and the weaker one sat on the constant. (Footnote so it is not cited wrong
    /// later: `c01` is `min(max(x, 0), 1)`, which passes NaN through by argument order — it
    /// bounds the DOMAIN, it is not a NaN sanitiser.)
    public nonisolated static let characterRange: ClosedRange<Float> = 0...1

    /// Domain of the per-voice master-gain smoother (#295).
    ///
    /// ⚠️ THE CEILING IS MEASURED, NOT GUESSED — the ledger records a dead-end where a
    /// sentinel was chosen without measuring the palette first. `amplitude` is ≤ 1 on both
    /// of its two writers (`applyBioReactive` clamps to 0…1; the poly path is
    /// `pow(v, expo) * unisonGain` with `v` clamped to 0…1 and `unisonGain` ≤ 1), and
    /// `patchOutputLevel` has THREE doors, not one: `SynthPatch.loudnessNormalized` (0.45…1.4,
    /// and the only one that can exceed unity in a COMPILED-IN patch — ⛔ this used to add "no
    /// genre or library patch sets `outputLevel` at all", and the LIBRARY half is false: the
    /// library is `SynthPatch.factory` plus user patches, and `loudnessNormalized` is exactly
    /// what stamps every factory entry. Only the GENRE roster leaves the field nil), the Sound
    /// panel's "Output" row (0.3…1.5 — REACHABLE
    /// since #286 put it under the "Level" header; it was `PatchEditorView`'s doorless row when
    /// this note was written, and that file is now deleted, so the Sound panel is the only
    /// hand-editable door left — which holds ONLY because the third door below has no editor
    /// at all: the automation row that once drew this lane was unmounted from #121 Slice 4/4d
    /// and its view was DELETED in #473, and `AutomationPlayer` has no production
    /// writer, so that lane can write this field but nothing lets a user aim it. That is now a
    /// stronger premise than when this note was written, not a weaker one — the earlier version
    /// said "`TimelineAutomationRow` has zero instantiation sites", which a re-mount would have
    /// silently falsified; a deleted file cannot be re-mounted by accident. Build a new
    /// automation editor and this sentence needs re-checking), and the `ddsp.amp.level`
    /// automation lane (0…1,
    /// registry-clamped). So: **1.4 is the largest product anything SHIPS**, 1.5 the largest a
    /// user can save. The ceiling sits well above both, so the `outputLevel` row cannot
    /// silently hit it and become a lying control, while +inf still cannot escape. The FLOOR is
    /// what matters for the bug:
    /// `clamped(to:)` maps NaN to the lower bound, so a poisoned accumulator lands on 0 for
    /// one sample and then glides back up instead of latching there forever.
    ///
    /// ⚠️ "Glides back up" ASSUMES THE TARGET BECAME FINITE AGAIN. While the source is still
    /// non-finite the accumulator is BOUNDED, not healed: it sits on the lower bound every
    /// sample, which for the gain is silence and for the character smoothers is a voice
    /// stripped of its harmonic bank. #294's comment drew that distinction for itself; these
    /// two did not, and a guard that only asserts `isFinite` green-lights exactly that state.
    public nonisolated static let masterGainRange: ClosedRange<Float> = 0...4

    /// Base filter cutoff (before modulation), in Hz — kept inside `cutoffRange`.
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

    /// Vibrato rate in Hz. Set by the patch; the heart rate then moves it AROUND that value
    /// (`bioBaseVibratoRate`, #279). The old note here said only "bio: linked to heart rate",
    /// which was accurate about the code and hid that the link OVERWROTE the patch.
    public var vibratoRate: Float = 0

    /// Vibrato depth in semitones. Same anchored relationship as `vibratoRate`.
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
    /// When set, harmonicAmplitudes are interpolated toward this profile.
    ///
    /// Backed by a PREALLOCATED buffer that is never resized and never released,
    /// because the patch drain that writes it runs on the AUDIO THREAD
    /// (`PolySynthVoice.renderOnAudioThread` → `ResolvedPatch.apply(to:)`): the old
    /// `[Float]?` store meant a heap allocation on every character change and a
    /// `free()` on every clear, both forbidden there. The optional façade is kept
    /// for control-thread callers; `applyTimbre(_:blend:)` is the render-safe path.
    ///
    /// The getter hands back a fresh copy on purpose — returning the buffer itself
    /// would leave a second reference alive and turn the next in-place write into a
    /// COW heap copy ON the audio thread (the exact `RenderScratch` bug class).
    ///
    /// ⚠ That mitigation is narrower than it looks: the copy stops a caller RETAINING
    /// the buffer, but the getter still holds a transient +1 while it runs. Reading
    /// `timbreProfile` from the control thread WHILE the render thread is inside
    /// `applyTimbre` would make the uniqueness check see 2 and malloc anyway. No code
    /// in `Sources/` reads this property today (it is test-only), so this is a trap
    /// for a future UI, not a live bug — but if a view ever wants to show the profile,
    /// give it a render-free snapshot instead of reaching in here.
    public var timbreProfile: [Float]? {
        get { hasTimbreProfile ? timbreBuffer.map { $0 } : nil }
        set {
            guard let v = newValue, v.count >= harmonicCount else {
                hasTimbreProfile = false
                return
            }
            for i in 0..<harmonicCount { timbreBuffer[i] = v[i] }
            hasTimbreProfile = true
        }
    }

    /// The preallocated backing store for `timbreProfile` — always `harmonicCount` long.
    private var timbreBuffer: [Float]

    /// Whether `timbreBuffer` currently holds a profile that should be blended in.
    /// (Replaces the old `timbreProfile != nil` test, which needed an optional box.)
    public private(set) var hasTimbreProfile = false

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

    /// Per-sample-smoothed base frequency. -1 = seed on first use.
    ///
    /// ⛔ THE THIRD COPY OF A CLAIM THAT WAS BACKWARDS, and the one most likely to be read
    /// — it sits on the property itself, above both use sites. The #404 commit corrected
    /// the two USE-site comments and said so in its message; this one survived, still
    /// asserting "reused voices slide to the new pitch; a fresh idle voice re-seeds this
    /// in `prepareForNote(hardReset:)` so it snaps instead". Both halves are false.
    /// `prepareForNote` writes `smoothedFreq = -1` ABOVE its `guard hardReset`, so it runs
    /// for a reused ringing voice too, and `render` re-seeds to the new pitch on the next
    /// sample: NOTHING slides on a note-on, idle or reused. The one caller that glides is
    /// `slideNote`, which moves `frequency` and never calls `prepareForNote` — that is the
    /// portamento, and it is what this one-pole is for.
    ///
    /// The lesson is the reason this paragraph is this long: correcting the comments you
    /// happened to be reading is not correcting the claim. `git grep` the CLAIM — here,
    /// "snaps"/"slides"/`smoothedFreq` — before writing "corrected" into a commit message.
    ///
    /// The instant pitch change on a reused voice is real and is not free; it is a
    /// discontinuity in the waveform's SLOPE (see `prepareForNote`). Calling it a "phase
    /// jump", as this comment used to, names a mechanism that does not occur — the partial
    /// phases are exactly what a reuse KEEPS.
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
    /// ⛔ THE STATED REASON BELOW IS HISTORICAL, THE DECISION IS NOT. Note triggering no
    /// longer runs on a timer thread: `prepareForNote`'s one caller is `spawnVoice` ←
    /// `noteOn` ← `PolySynthVoice.drainNoteCommands`, which runs INSIDE the render block
    /// (#404 review, 2026-08-05). So the cross-thread race described here cannot occur as
    /// written — but nothing has re-validated the convolution against a same-thread
    /// `reset()` either, and re-enabling it is not a comment edit. Left OFF; the paragraph
    /// is kept because it records what was actually observed on device.
    ///
    /// DISABLED by default: note triggering ran on the pattern's TIMER thread
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

        // All buffer sizing below reads the CLAMPED self.* params (self.harmonicCount /
        // self.noiseBandCount / self.frameSize, each `max(1, …)` above) — never the raw
        // init parameters. A negative raw param would make a `count:`/range negative and
        // fatally trap [Float](repeating:count:) before init finishes. Byte-identical for
        // every valid input (self.x == x when x >= 1).
        self.harmonicAmplitudes = [Float](repeating: 0, count: self.harmonicCount)
        self.timbreBuffer = [Float](repeating: 0, count: self.harmonicCount)
        self.partialStretch = [Float](repeating: 1, count: self.harmonicCount)   // filled by rebuildPartialStretch() below
        self.noiseMagnitudes = [Float](repeating: 0, count: self.noiseBandCount)
        self.phases = [Float](repeating: 0, count: self.harmonicCount)
        self.smoothedAmplitudes = [Float](repeating: 0, count: self.harmonicCount)
        // Shimmer phases start spread by the golden angle (deterministic, maximally
        // incommensurate) so the partial wobbles never line up into a tremolo.
        self.shimmerPhases = (0..<self.harmonicCount).map { Float($0) * 2.399963 }
        self.shimmerWeights = [Float](repeating: 1, count: self.harmonicCount)
        self.aaWeights = [Float](repeating: 0, count: self.harmonicCount)

        // vDSP scratch buffers
        self.vdspPhaseIncrements = [Float](repeating: 0, count: self.harmonicCount)
        self.vdspSinBuffer = [Float](repeating: 0, count: self.harmonicCount)
        self.vdspCosBuffer = [Float](repeating: 0, count: self.harmonicCount)

        // Multi-band noise buffers
        let fftSize = self.noiseBandCount * 2
        self.noiseFFTBuffer = [Float](repeating: 0, count: fftSize)
        self.noiseOutputBuffer = [Float](repeating: 0, count: self.frameSize + fftSize)
        self.noiseOverlapBuffer = [Float](repeating: 0, count: fftSize)
        self.noiseFilterState = [Float](repeating: 0, count: self.noiseBandCount)

        // Pre-compute noise filter coefficients (avoids exp() on audio thread)
        let spacing = 1.0 / Float(self.noiseBandCount)
        self.noiseFilterAlphas = (0..<self.noiseBandCount).map { band in
            let centerFreq = Float(band + 1) * spacing
            return exp(-2.0 * Float.pi * centerFreq * 0.5)
        }

        // Spectral morph buffers
        self.morphSourceAmplitudes = [Float](repeating: 0, count: self.harmonicCount)
        self.morphTargetAmplitudes = [Float](repeating: 0, count: self.harmonicCount)

        // Reverb IR buffers — pre-allocate for the max render block the poly engine
        // can deliver (4096). Sized at 2048 before, so blocks 2049–4096 silently
        // skipped the reverb → audible wet-tail dropouts as host block size varied.
        let reverbCap = max(self.frameSize, 4096)
        self.reverbFrameBuffer = [Float](repeating: 0, count: reverbCap)
        self.reverbWetBuffer = [Float](repeating: 0, count: reverbCap)

        // Initialize convolution reverb with a synthetic IR. maxInputLength must
        // match the buffer cap or the convolution truncates large blocks.
        // Clamped self.sampleRate (not the raw param): a negative sampleRate makes
        // generateReverbIR's `Int(0.02 * sampleRate)` negative → a `0..<negative`
        // invalid-range trap. self.sampleRate == sampleRate for every valid input.
        self.reverbConvolution = EchoelConvolution(kernel: EchoelDDSP.generateReverbIR(
            decay: 1.5, sampleRate: self.sampleRate, length: 4096
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
        // Reads the backing buffer directly — going through the `timbreProfile`
        // façade here would build a throwaway copy on every envelope update.
        if hasTimbreProfile, timbreBlend > 0 {
            for i in 0..<harmonicCount {
                harmonicAmplitudes[i] = harmonicAmplitudes[i] * (1.0 - timbreBlend)
                    + timbreBuffer[i] * timbreBlend
            }
        }

        normalizeAmplitudes(&harmonicAmplitudes)
    }

    /// Fixed formant band centres/amplitudes/bandwidths for the `.formant` spectral
    /// shape (a vowel-like /a/ triple). Hoisted to a static constant so the `.formant`
    /// branch below allocates NOTHING per call — `computeShapeAmplitudes` runs on the
    /// audio render thread for a bio-reactive voice (the bio-spectral path was moved
    /// onto that thread in v337), where the former per-call array literal would have
    /// been a heap allocation. Read-only; iterating a stored array is alloc-free.
    private static let formantBands: [(freq: Float, amp: Float, bw: Float)] = [
        (730, 1.0, 90), (1090, 0.5, 110), (2440, 0.3, 170)
    ]

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
            for i in 0..<harmonicCount {
                let freq = frequency * Float(i + 1)
                var amp: Float = 0.01
                for formant in Self.formantBands {
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

    /// Where this voice's ENVELOPE currently stands (0…1).
    ///
    /// ⚠️ THIS IS NOT THE VOICE'S LOUDNESS, and the first version of this doc said it was
    /// ("how LOUD this voice is right now"). The render line is
    /// `sample = mixed * smoothedGain * envelopeValue`, and `smoothedGain` follows
    /// `amplitude * patchOutputLevel` — so two tails at envelope 0.5 struck at velocity 0.3
    /// and 1.0 are ~10 dB apart while this property reports them identical. Worse, since
    /// #174 a Mix fader at zero bakes velocity 0 into the note, so a slot can sit at
    /// envelope 0.9 and emit exact silence. A caller ranking tails by this alone would
    /// have preferred the audible one and spared the silent one — backwards.
    ///
    /// `isActive` answers "is anything still coming out of this slot"; this answers "how
    /// far through its envelope is it". The poly engine multiplies it by `amplitude`
    /// before comparing (`allocateVoice`) — that product is the per-voice level factor;
    /// `patchOutputLevel` is common to all voices of a patch and so cannot change a
    /// RANKING.
    ///
    /// Read-only on purpose: the envelope stays owned by this voice. Plain Float read
    /// on the same audio thread that already drives `render` and `noteOn`, so it adds
    /// no synchronisation of its own.
    public var envelopeLevel: Float { envelopeValue }

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
        // note whenever polyphony exceeds maxVoices. Only the amplitude smoothers /
        // phases must NOT be zeroed mid-tail — those stay below the guard.
        //
        // ⚠️ "PITCH SNAPPING DOESN'T CLICK" is what this comment used to assert, and it is
        // half true in a way that hid #404. Partial phases ARE kept, so the harmonic sum's
        // VALUE is continuous across the snap — no step from the phases. Its SLOPE is not:
        // every partial's phase increment changes in one sample. That kink is a real,
        // broadband discontinuity whose loudness scales with how loud the tail still was,
        // and on a sustained pad several of them can land in the SAME render block at a bar
        // line and sum (the note drain runs once per block, so simultaneity is per-block —
        // the Humanizer can still scatter onsets across blocks). Writing it off as "doesn't
        // click" is what let the line sit unexamined while the founder reported crackling.
        //
        // TWO THINGS THE "value is continuous" HALF STILL DOES NOT COVER (#404 review) —
        // both make the artefact bigger, so they argue for the fix rather than against it:
        // · The anti-alias taper is derived from each partial's frequency, which snaps in
        //   the same sample. On a DOWNWARD reuse a partial can go from tapered-or-excluded
        //   to full weight instantly — that is a genuine value step, not just a kink.
        //   Upward snaps are safe; fading them out is what that band was built for.
        // · `noteOn` sets `onsetNoiseEnv` from `percussiveness`, added straight into the
        //   mix on the first new sample. Zero for a slow-attack pad (so not the reported
        //   case), non-zero for anything plucked.
        //
        // The snap STAYS — the sliding-note artefact it prevents is worse and more constant
        // than the kink it costs. What changed is that the cost is now named here, and
        // `quietestFreeSlot` (#404) makes the poly engine pay it on the quietest available
        // tail instead of whichever slot happened to have the lowest index.
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
        // note-trigger (timer) thread — ⛔ that thread claim is stale, see the
        // `reverbConvolution` property doc: this runs on the AUDIO thread today, so the
        // race named here is not the current reason. The removal stands; only its
        // justification has expired. Mutating the convolution's arrays here
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

            // Glide the base frequency per-sample toward `frequency`. Coefficient default
            // 0.01 (~2 ms, the legacy micro-glide); `glideCoeff` is fanned from the poly
            // engine's portamento setting so slid notes SING between pitches.
            //
            // ⛔ WHOM THIS GLIDE ACTUALLY SERVES — the previous version of this comment named
            // the wrong half and it mattered. It said "fresh idle voices seed smoothedFreq in
            // prepareForNote so they snap; only reused voices glide", i.e. exactly backwards.
            // `prepareForNote` writes `smoothedFreq = -1` ABOVE its `guard hardReset`, so it
            // runs for a reused/stolen ringing voice too, and the seed line below then snaps
            // that voice to the new pitch on its very first sample. NO note-on glides — idle
            // or reused. The one caller that glides is `slideNote`, which moves `frequency`
            // and never calls `prepareForNote` at all, so `smoothedFreq` survives and this
            // one-pole walks it: that is the portamento, and it is the whole reason the line
            // exists.
            //
            // The distinction is not cosmetic. As written, the old comment promised that a
            // still-loud reused voice was protected from an instant pitch jump — the exact
            // protection #404 needs and does not have. A session reading it would look for
            // the crackle everywhere except here. The snap is a deliberate trade (see
            // `prepareForNote`); what it is not, is free.
            if smoothedFreq < 0 { smoothedFreq = frequency }
            smoothedFreq += glideCoeff * (frequency - smoothedFreq)

            // Apply pitch modulation (vibrato + analog drift) — accumulate both as
            // semitone offsets and apply with ONE pow so a note that has neither is
            // bit-identical to before (offset stays 0 → pow(2,0)=1).
            var currentFreq = smoothedFreq
            var pitchModSemitones: Float = 0
            // Vibrato (bio: heart rate → vibrato rate) — periodic.
            // ⚠️ THE GATE SCREENS NaN BUT NOT +inf (#297) — `NaN > 0` is false, `inf > 0` is
            // true. With an infinite rate the phase becomes inf, the wrap test `> 2π` is true
            // but `inf - 2π` is still inf, so the subtraction cannot bring it back, and
            // `sin(inf)` is NaN → `pitchModSemitones` NaN → `currentFreq` NaN for every
            // remaining sample of the voice. `vibratoPhase` is cleared only by `reset()`,
            // never by `prepareForNote`, so a new note inherits it. Both halves fixed: the
            // gate now requires finite inputs (`ResolvedPatch.apply` writes both raw, and
            // #279's 0…12 / 0…1 clamps only apply while bio runs AND the anchor is ≥ 0), and
            // the wrap re-seeds the phase instead of leaving a value it cannot reduce.
            if vibratoRate > 0 && vibratoDepth > 0 && vibratoRate.isFinite && vibratoDepth.isFinite {
                vibratoPhase += vibratoRate / sampleRate * 2.0 * .pi
                if !vibratoPhase.isFinite {
                    vibratoPhase = 0
                } else if vibratoPhase > 2.0 * .pi {
                    vibratoPhase -= 2.0 * .pi
                }
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
            // ⚠️ THE CLAMP ON THE ASSIGNMENT IS THE RE-SEED THAT WORKS (#296). The `< 0`
            // sentinel check below CANNOT recover a poisoned accumulator, because `NaN < 0`
            // is false — the guard that exists to re-seed is precisely the one that never
            // fires when it is needed. Clamping the result is what makes these one-poles
            // self-healing: a non-finite lands on the lower bound and the next sample glides
            // back toward the (finite) target. Same shape and same reason as the filter
            // cutoff's `.clamped(to: Self.cutoffRange)` (#294).
            // Two entry points, both real: `harmonicity` is written RAW by
            // `ResolvedPatch.apply` (the pure patch path, no bio running), and `noiseLevel`'s
            // bio line is `Swift.max(0, …)` — a floor with no ceiling, so +inf walks straight
            // through it. Bounds are 0…1 because that is the domain `SoundPrompt`'s own
            // sanitiser enforces on both fields (`c01`), and `applyBioReactive`'s harmonicity
            // line sits inside it at 0.05…0.98. It is deliberately NOT justified by
            // `applyBioReactive`'s noise line, which has no ceiling at all — that missing
            // ceiling IS the bug, and citing it as the precedent would be circular.
            // `GainLatchRecoveryTests` asserts every shipped patch is inside these bounds, so
            // this is hardening, not a tuning change.
            if smoothedHarmonicity < 0 { smoothedHarmonicity = harmonicity }
            if smoothedNoiseLevel < 0 { smoothedNoiseLevel = noiseLevel }
            smoothedHarmonicity = (smoothedHarmonicity + 0.01 * (harmonicity - smoothedHarmonicity))
                .clamped(to: Self.characterRange)
            smoothedNoiseLevel = (smoothedNoiseLevel + 0.01 * (noiseLevel - smoothedNoiseLevel) + antiDenormal)
                .clamped(to: Self.characterRange)
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
            // ⭐ ONE OF THREE EQUALLY SEVERE MEMBERS (#295), and the first version of this
            // comment called it "THE severest, unlike every other member" — both halves wrong.
            // `sample = mixed * smoothedGain * envelopeValue`, so once this accumulator went
            // non-finite EVERY sample did and the block's end-of-render guard zeroed the whole
            // buffer. But `smoothedHarmonicity` and `smoothedNoiseLevel` poison `mixed` on the
            // two lines above (`0 * NaN` is NaN, so even a silent noise bed carries it), reach
            // the same guard, and survive the same events. Nothing downstream catches any of
            // the three. What IS true: all three survive note-off, note-on, `prepareForNote`,
            // `reset()` and a fresh patch apply alike — only `vibratoPhase` (cleared by
            // `reset()`) and `smoothedFreq` (cleared by `prepareForNote`, POLY path only) are
            // recoverable by any existing call. Permanent silence with no way back except an
            // app restart.
            // Both halves are needed: the `< 0` re-seed never fires on NaN, and the clamp on
            // the assignment is what lets a poisoned accumulator glide back. The target is
            // sanitised at its own door (`patchOutputLevel`'s `didSet`) so the recovery has a
            // finite value to converge ON — clamping only here would land at 0 and stay there
            // while a corrupt patch level kept the target non-finite. `amplitude`, the target's
            // other factor, gets no door because both its writers are audited finite; if that
            // ever changes, a non-finite `amplitude` lands this accumulator on 0 and HOLDS it —
            // bounded, silent, and reading perfectly healthy from every control.
            let gainTarget = amplitude * patchOutputLevel
            if smoothedGain < 0 { smoothedGain = gainTarget }
            smoothedGain = (smoothedGain + 0.01 * (gainTarget - smoothedGain) + antiDenormal)
                .clamped(to: Self.masterGainRange)
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

            // --- Analog warmth (pre-filter soft-saturation) ---
            // Add harmonic body BEFORE the SVF so the filter tames the new harmonics
            // into warmth, not harshness — the anti-"plastic" lever. warmthDrive 0
            // (the raw synth default) returns `sample` bit-identically.
            if warmthDrive > 0 {
                sample = Self.analogWarmth(sample, drive: warmthDrive)
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
            // `clamped(to:)` here is NOT a behaviour change: the previous
            // `max(20, min(x, 18000))` was already NaN-safe by ARGUMENT ORDER (min returns NaN,
            // then `NaN >= 20` is false so max returns 20), and the NaN-safe overload maps NaN to
            // the same lower bound. Identical for every finite input too. What it buys is the
            // shared `cutoffRange`. (The first version called this "a fourth copy of the two
            // literals" — it was the FIRST copy; see the constant's own ⛔ block.)
            let modulatedCutoff = (filterCutoff * renderCutoffScale
                                   * (1.0 + lfoMod * lfoToFilterDepth)
                                   * brightBoost).clamped(to: Self.cutoffRange)
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

    // MARK: - Analog warmth (pure, unit-testable)

    /// Gentle analog-style saturation that gives the pure additive sine stack some
    /// harmonic BODY, so it stops reading as cold/"plastic" (founder 2026-07-11 sound
    /// north-star). An algebraic soft-clip `x / (1 + a|x|)` — odd, monotonic, bounded
    /// by `1/a`, with UNITY slope at zero so quiet passages pass through untouched
    /// while peaks compress and gain odd harmonics — blended with the dry signal by
    /// `drive`. `drive` ≤ 0 returns the input BIT-IDENTICALLY. The curve is monotonic
    /// and bounded, so it is safe ahead of the resonant filter. Pure arithmetic (no
    /// allocation, no calls) — audio-thread safe and Linux-testable.
    @inline(__always)
    nonisolated static func analogWarmth(_ x: Float, drive: Float) -> Float {
        guard drive > 0 else { return x }
        let a: Float = 1.6                      // saturation amount
        let shaped = x / (1 + a * abs(x))       // odd · monotonic · |shaped| < 1/a
        return x + drive * (shaped - x)         // dry/wet blend; slope 1 at x→0
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
    // ⛔ `_spectralUpdateCounter` and `_lfoPhase` STOOD HERE AND ARE DELETED (#331). Both existed
    // only to serve a 60 Hz caller that has never existed — see the tombstones in
    // `applyBioReactive`, which carry the evidence. The counter fired a DUPLICATE spectral
    // rebuild every 6th call (the envelope was already rebuilt on every call by `brightness`'s
    // own `didSet`, so deleting it changes no sample); the phase drove an LFO that needed
    // 24–120 s per cycle and cannot be rescued by any divisor, because 0.5–2.5 Hz is above
    // Nyquist for a ~1 Hz control stream.
    // coherenceTrend→morph change-gate (audio-thread review): remember the last morph
    // shape/position we actually applied so the 10 Hz mapping only calls setMorphPosition
    // (which rewrites the shared pre-allocated spectral buffer) on a REAL change — never
    // every frame on a slow trend. -1 = "nothing applied yet".
    private var _lastMorphPos: Float = -1
    private var _lastMorphShape: SpectralShape? = nil

    /// Patch-baseline timbre values, captured in `SynthPatch.apply(to:)`. Biofeedback
    /// modulates SUBTLY AROUND these (founder: "Biofeedback ändert dann nur subtil die Filter
    /// etc.") instead of overwriting them — so the character of the patch you chose survives,
    /// and the body only gently colours it (filter first, character a touch). Default to the
    /// synth's own defaults so a bio frame before any patch still behaves.
    public var bioBaseHarmonicity: Float = 0.88
    public var bioBaseNoiseLevel: Float = 0.01
    public var bioBaseReverbMix: Float = 0.25
    /// Patch-baseline FILTER CUTOFF (Hz) for bio modulation. 0 = "no patch anchor set" →
    /// the raw bio voice keeps the legacy absolute coherence sweep (byte-identical).
    /// When > 0 (set by `SynthPatch.apply(to:)` alongside `filterCutoff`), coherence opens
    /// the filter as a CLAMPED DEVIATION AROUND this value — neutral coherence 0.5 settles at
    /// exactly the patch cutoff (and `apply` seeds the smoother there) — so genres keep their
    /// distinct cutoffs instead of all
    /// collapsing toward one shared timbre when the body calms (task #81, the A8 law).
    public var bioBaseFilterCutoff: Float = 0
    /// Patch-baseline BRIGHTNESS (spectral-shape exponent, read by computeShapeAmplitudes) for
    /// bio modulation. **−1 = "no patch anchor set"** → the raw bio voice keeps the legacy
    /// absolute brightness path (byte-identical). When >= 0 (set by `SynthPatch.apply(to:)`
    /// alongside `brightness`), the body modulates as a CLAMPED DEVIATION AROUND this value —
    /// neutral readings (coherence/HR/HRV 0.5) settle at ~the patch brightness — so genres keep
    /// their distinct spectral character instead of all collapsing to one brightness when the
    /// body calms. This is the second dynamic convergence vector after the cutoff (task #81).
    ///
    /// ⛔ THE SENTINEL WAS 0 AND `> 0` UNTIL #564, AND IT SAT INSIDE ITS OWN PARAMETER'S RANGE.
    /// `SynthPatch.Bounds.brightness` is `0...1` and the registry descriptor `ddsp.osc.brightness`
    /// has min 0, so **zero is a value a player can set** — the Brightness field in `soundPanel`
    /// reaches it by dragging to the bottom. `apply(to:)` then wrote 0 into this anchor and
    /// `applyBioReactive` read it as "no patch", switching to the LEGACY absolute path, which
    /// computes ~0.2…0.7 brightness from coherence/HR alone. The darkest setting in the app
    /// produced a mid-bright sound, but ONLY while a bio source was running — a mode change
    /// disguised as a parameter value, and one a listener would blame on the patch.
    ///
    /// ⭐ SO IT NOW MATCHES THE VIBRATO TRIO BELOW, and the paragraph under them states the rule
    /// this is an instance of: 0 may not mean "unset" for a parameter whose range contains 0.
    /// A filter cutoff of 0 Hz is not a musical value (`bioBaseFilterCutoff` keeps its 0-sentinel,
    /// unreachable from a range starting at 20 Hz); a brightness of 0 is. Every patch that ships
    /// or was ever saved is byte-identical under this change — the factory floor is 0.1 — and the
    /// only behaviour that moves is the one case that was wrong.
    ///
    /// ⚠️ AND THIS IS WHAT UNBLOCKED AUTOMATING BRIGHTNESS. `TheAutomatableSetHasOneWriterTests`
    /// claim 5 held `ddsp.osc.brightness` out of `PolySynthVoice.automatableBases` for exactly
    /// this reason and said in its own failure message that removing the sentinel is the
    /// GO-AHEAD, not a defect. The bind landed in the same commit; that case is retired.
    public var bioBaseBrightness: Float = -1
    /// Patch-baseline VIBRATO RATE (Hz) / VIBRATO DEPTH (semitones) / FILTER-LFO DEPTH for bio
    /// modulation. **−1 = "no patch anchor set"** → the legacy absolute path below, byte-identical.
    ///
    /// ⚠️ THE SENTINEL IS −1 HERE AND 0 FOR CUTOFF/BRIGHTNESS, AND THAT DIFFERENCE IS THE POINT.
    /// A patch may legitimately ask for NO vibrato — the MAJORITY of shipped patches do — so 0
    /// cannot mean "unset" for these three without silently routing exactly those patches back
    /// into the absolute path that gives them a vibrato they asked not to have. A filter cutoff
    /// of 0 Hz is not a musical value; a vibrato depth of 0 is. Copying the 0-sentinel here would
    /// have been the plausible move and the wrong one.
    ///
    /// ⛔ WHAT THIS FIXES (#279) — AND THE FIRST VERSION OF THIS PARAGRAPH GOT THE PALETTE
    /// BACKWARDS, which matters because it is the paragraph that states the size of the bug.
    /// It said "every preset ships a musical `vibratoRate` of 4.5–5.5 Hz". Measured instead of
    /// assumed:
    ///   · `SynthPatch.rawFactory` — 20 presets, 12 name `vibratoRate` (three of them 0, the rest
    ///     4.5…5.5) and 8 never mention it and inherit the `= 0` default → **11 of 20 ship no
    ///     vibrato**.
    ///   · `MusicStyle.offered` — 16 genres, and **only `classical` (5.0 Hz) has any vibrato at
    ///     all**; the other 15 ship `vibRate: 0, vibDepth: 0`. (`GenrePatches.swift` holds 33
    ///     entries across ALL styles, 8 of them non-zero — do not read that 8 as "8 offered".)
    /// So roughly 26 of ~36 shipped patches carry NO vibrato, and the true defect had two halves,
    /// pulling in opposite directions:
    ///   1. For the ~10 patches that DO ask for vibrato, the absolute mapping wrote 0.05–0.2 Hz
    ///      over their 4.5–6.2 Hz — a factor of 25–100. It did not modulate their vibrato, it
    ///      deleted it.
    ///   2. For the ~26 that ask for none, it ADDED an unrequested 0.4–2.4 cent periodic drift at
    ///      0.05–0.2 Hz. Anchoring REMOVES that from nearly the whole palette. `pitchDriftCents`
    ///      still supplies an aperiodic wander, so those patches are not newly static — but this
    ///      is a real change to how almost everything sounds and it needs an ear, not a test.
    /// Both halves follow the one law (the patch you chose survives). Meanwhile the Sound panel
    /// kept offering "Vibrato rate", "Vibrato depth" and "LFO→filter" as editable rows — three
    /// lying controls in the panel that IS the patch editor (ship-gate item 2).
    /// Recount before quoting any of this:
    /// `grep -c 'vibRate: 0' Sources/Echoelmusic/Sequencer/GenrePatches.swift` and the
    /// `rawFactory` block in `SynthPatch.swift`.
    ///
    /// ⚠️ FOR WHOEVER BINDS AN AUTOMATION ROUTE HERE. `EchoelParameterRegistry` already declares
    /// `ddsp.mod.vibratoRate` / `ddsp.mod.vibratoDepth`, and today NOTHING binds an apply-closure
    /// to them (`git grep` returns only the descriptor and one vocabulary entry). When one is
    /// written it must set the ANCHOR, not the live parameter — a route that writes
    /// `vibratoRate` directly is overwritten by the next bio frame and becomes exactly the lying
    /// control this task removed.
    public var bioBaseVibratoRate: Float = -1
    public var bioBaseVibratoDepth: Float = -1
    public var bioBaseLFOToFilterDepth: Float = -1

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
        // BIO-REACTIVE MAPPINGS — AUDIBLE DEVIATION AROUND THE CHOSEN PATCH (ONE LAW)
        // Each bio input is an audible-sized, CLAMPED deviation around the patch's own
        // value, CENTERED on the neutral reading (HRV 0.5, trend 0, breath a ≤1.0
        // factor) so a resting body = exactly the patch's sound. Audible enough to hear
        // the body (fixes #77 "genres sound the same"), bounded so the chosen character
        // survives (honours the A8 audit: never an absolute overwrite that plasters
        // every patch to one timbre). Physiology is a MODULATION SOURCE + self-observation
        // only — no health claim, no valence on any timbre direction.
        // NOTE: for BioReactiveSynthVoice this function runs ON the audio render thread
        // (SPSC-drained inside render(), see header L54-60). Every line here is
        // allocation-free EVEN ON the audio thread: scalar/C-math into pre-allocated
        // buffers only — never add an Array/String/dictionary/lock/Task here.
        // =====================================================================

        // DEFENSE-IN-DEPTH (audio thread): sanitize the bio inputs at the boundary. The
        // one-pole accumulators below (_smoothedBrightness and _smoothedAmplitude, both via
        // smoothCoeff — the `_lfoPhase via lfoSpeed, _smoothedAmplitude via lfoValue` named
        // here until #331 deleted that LFO outright)
        // and the unclamped SENTINEL-path vibrato writes (vibratoDepth/Rate — the anchored path
        // added by #279 clamps its product, this one still does not) ingest these BEFORE any clamp, so
        // a single non-finite reading (a bad rPPG frame, a divide-by-zero coherence) would
        // permanently poison that state → NaN vibrato samples and an amplitude one-pole that
        // sticks at NaN and clamps to 0 forever (the #22/#29 "alles ist still" permanent-silence
        // class). `isFinite` rejects NaN AND ±inf; the neutral fallbacks are the resting-body
        // reading, so a dropout fails to "resting" — never to silence. Only NON-finite values are
        // rewritten, so every finite (real) reading is byte-identical to before. Scalar-only,
        // allocation-free, no lock/ObjC/GCD — audio-thread safe. (`lfHfRatio` is not read in this
        // body, so it is deliberately not shadowed — an unused shadow would fail -Werror.)
        let coherence = coherence.isFinite ? coherence : 0.5
        let hrvVariability = hrvVariability.isFinite ? hrvVariability : 0.5
        let heartRate = heartRate.isFinite ? heartRate : 0.5
        let breathPhase = breathPhase.isFinite ? breathPhase : 0.5
        let breathDepth = breathDepth.isFinite ? breathDepth : 0.5
        let coherenceTrend = coherenceTrend.isFinite ? coherenceTrend : 0

        // ⭐ THE SMOOTHING POLE, ON THE CLOCK THIS FUNCTION ACTUALLY RUNS AT (#331).
        //
        // It was `0.92  // Slightly faster response than 0.95` — a number chosen for a 60 Hz
        // caller (τ = 0.200 s) that has NEVER existed. This function runs once per NEW bio
        // frame, and every WIRED publisher emits ~1 Hz: `CameraRPPGBioPublisher` gates
        // on `tick % 10` inside a 100 ms loop, `PolarH10BioPublisher` and `BioSimulator` both
        // sleep a full second, HealthKit is slower still. The poll that feeds the audio thread
        // (`PolySynthVoice.applyLatestIfFresh`) drops every frame whose timestamp is unchanged,
        // so the enqueue rate IS the new-frame rate — its own comment saying "bio updates at
        // ~10 Hz" is the same stale assumption, one order of magnitude out.
        //
        // "WIRED", not "in the repo", and the word is load-bearing: `FaceExpressionBioPublisher`
        // sleeps 100 ms and publishes a frame every tick — 10 Hz. It has ZERO instantiations in
        // `Sources/`, so it cannot drive the audio thread today and the reasoning below holds.
        // But wiring it later would change this block's premise, and the first version of this
        // sentence said "every publisher in the repo", which would have made that change look
        // like it needed no thought here.
        //
        // At 1 Hz, α = 0.92 means τ = −1/ln(0.92) = 11.99 s. Step response, re-derived:
        //
        //            after 1 s   2 s    3 s    5 s    10 s
        //   was 0.92     8 %    15 %   22 %   34 %    57 %
        //   now 0.6065  39 %    63 %   78 %   92 %    99 %
        //
        // A change in the player's body was 8 % delivered after one second and barely half
        // after ten. That is this instrument's premise — your body plays it — failing quietly,
        // and it is a plausible contributor to "the genres all sound the same": every genre's
        // bio-driven brightness and level converge over a twelve-second horizon no matter which
        // genre it is. exp(−1/2) = 0.6065 gives τ = 2 s at the real rate.
        //
        // ZIPPER RISK IS NOT INTRODUCED: both consumers are smoothed AGAIN per sample
        // downstream — the spectral amplitudes with α = 0.995 (≈ 4.2 ms) and `smoothedGain`
        // with 0.01 (≈ 2.1 ms) — so a faster CONTROL rate cannot step the audio.
        //
        // If a device listen finds the body too twitchy, 0.75 (τ = 3.5 s) is the one-token
        // revert. Do NOT go back to 0.92 without re-reading this block: that value is not
        // "slower", it is a 60× unit error.
        let smoothCoeff: Float = 0.6065

        // 1. Heart rate → filter/brightness range.
        //
        // ⛔ AN LFO STOOD HERE AND IS DELETED, AND "FIX THE DIVISOR" IS NOT AN OPTION.
        // It read `_lfoPhase += lfoSpeed / 60.0  // 60 Hz update rate`, sweeping 0.5–2.5 Hz.
        // At the real ~1 Hz that is 24–120 SECONDS per cycle. Advancing by real elapsed time
        // instead does not rescue it: 0.5…2.5 cycles per sample of a 1 Hz grid is above
        // Nyquist, and 40 / 120 / 200 bpm map to exactly 0.5 cycles/sample, where sin(πk) = 0
        // for every k — i.e. FROZEN at the very rates a heart most often sits at. A heart-rate
        // tremolo belongs on the SAMPLE clock (`filterLFO`, ticked per sample), not here.
        //
        // Deleted rather than moved: nobody asked for a tremolo, and what this one actually
        // produced was not one. Both its consumers were live — brightness (±0.075 around its
        // centre) and amplitude (±0.06) — but each traced that swing over 24–120 SECONDS. That
        // is a slow drift, not a wobble, and it is what disappears here: both consumers below
        // now take the LFO's exact MEAN (0.5), so each centre is unchanged. If the take now
        // feels too steady, that is a deliberate tremolo to design on the sample clock, not
        // this constant to restore.
        //
        // ⛔ THE FIRST VERSION OF THIS TOMBSTONE CALLED THE LFO "half dead already — its
        // brightness contribution reached the ear only through `updateSpectralEnvelope()`,
        // which the counter below throttled to once per six seconds". That is false, and the
        // proof is four lines below the brightness maths: `brightness` carries
        // `didSet { updateSpectralEnvelope() }`, so the assignment `brightness =
        // _smoothedBrightness` rebuilds the envelope on EVERY call. The brightness half was
        // fully live. Writing it off as half-dead made the deletion sound cheaper than it is —
        // this removes a real (if very slow) modulation, and that is the honest framing.

        // Brightness (spectral-shape exponent — read by computeShapeAmplitudes, so it DOES
        // carry patch character; the old "no patch character (A8)" note here was wrong). Like
        // the filter cutoff, the body must modulate AROUND the chosen patch, not overwrite it —
        // otherwise every genre's brightness collapses toward one absolute value when the body
        // calms (the second dynamic convergence vector, task #81). Coherence/HR/HRV stay
        // audible as CENTERED deviations (0 at the neutral reading), so a resting body settles
        // at ~the patch brightness and calm/arousal open/darken it around that. (This list read
        // "Coherence/HR/HRV/LFO" until #331; the LFO term was `(lfoValue - 0.5) * 0.15`, already
        // centered on 0 — dropping it leaves the anchor exactly where it was.)
        let targetBrightness: Float
        // `>= 0`, not `> 0`, since #564: the sentinel is −1 and zero is a brightness a player
        // can set. See the anchor's declaration for the mode-change bug that comparison caused.
        if bioBaseBrightness >= 0 {
            let cohDev: Float = (coherence - 0.5) * 0.30       // calm opens, aroused darkens
            let hrDev: Float  = (heartRate - 0.5) * 0.20       // faster HR = a touch brighter
            let hrvDev: Float = (hrvVariability - 0.5) * 0.20  // more beat-to-beat variation = more open
            targetBrightness = (bioBaseBrightness + cohDev + hrDev + hrvDev).clamped(to: 0.05...0.95)
        } else {
            // Legacy raw-bio voice (no patch anchor): unchanged absolute brightness path.
            let baseFilter: Float = 0.08 + coherence * 0.35  // 0.08-0.43 base
            let hrShift: Float = heartRate * 0.2               // +0.0-0.2 from HR
            // Was `lfoValue * 0.15`; this is that term's exact MEAN (0.5 × 0.15), so the
            // legacy path's brightness CENTRE is byte-unchanged and only the 24–120 s
            // drift around it disappears (#331).
            let lfoSweep: Float = 0.075
            let hrvBright: Float = (hrvVariability - 0.5) * 0.20
            targetBrightness = (baseFilter + hrShift + lfoSweep + hrvBright).clamped(to: 0.05...0.8)
        }
        _smoothedBrightness = _smoothedBrightness * smoothCoeff + targetBrightness * (1.0 - smoothCoeff)
        brightness = _smoothedBrightness

        // Coherence opens the filter. Higher coherence = more open (instrument-control
        // mapping, no wellness valence). Smoothed by the SHARED `smoothCoeff` above — this
        // line read "Very slow smoothing (α=0.97) for silky transitions" until #332, and
        // both halves of that were wrong at the rate this function runs at (see the ⛔ block
        // on the assignment itself).
        // Anchored path (bioBaseFilterCutoff > 0, i.e. a patch was applied): the target is a
        // CLAMPED DEVIATION AROUND the patch's own cutoff (the bioBase* law) — neutral
        // coherence 0.5 → exactly the patch cutoff, calm opens (+), aroused darkens (−). This
        // keeps each genre's distinct cutoff instead of collapsing every patch toward one
        // shared value when the body calms ("erst individuell → dann alles gleich", task #81).
        // Sentinel path (== 0, the raw patch-less bio voice): the legacy absolute sweep,
        // byte-identical (200 Hz dark → 1800 Hz open).
        let targetCutoff: Float
        if bioBaseFilterCutoff > 0 {
            let cutoffFactor: Float = (1.0 + (coherence - 0.5) * 0.5).clamped(to: 0.7...1.3)
            targetCutoff = bioBaseFilterCutoff * cutoffFactor
        } else {
            targetCutoff = 200 + coherence * 1600
        }
        // ⛔ THE CLAMP IS THE POINT OF #294, AND IT BELONGS ON THE ASSIGNMENT, NOT ON
        // `targetCutoff`. Once `filterCutoff` is non-finite it stays non-finite forever
        // (`inf * 0.97 + anything = inf`, `NaN * 0.97 = NaN`), with no recovery short of
        // re-applying a patch. Clamping the TARGET would not have fixed it: the
        // poison can arrive in the accumulator itself, because `ResolvedPatch.apply(to:)`
        // writes the raw patch cutoff straight into `filterCutoff` one line before it sets the
        // anchor. Clamping the ASSIGNMENT makes the accumulator SELF-HEALING for THAT door —
        // one frame after a bad value it is back in range. ⚠️ Not for the other one: a `+inf`
        // ANCHOR passes `> 0`, so `targetCutoff` is `inf` on EVERY frame and the accumulator
        // pins at exactly 18000 forever. Finite and in range, but stuck at maximum brightness
        // with no recovery — "bounded", not "healed", and the guard only asserts `isFinite`,
        // so it green-lights that state. `clamped(to:)` maps NaN to the lower bound (20 Hz:
        // a dark filter, audible, recoverable) rather than letting it through, which is the
        // documented "fail quiet, never stuck-silent" rule of `FloatingPointClamp`.
        //
        // ⛔ WHAT THE FIRST VERSION OF THIS COMMENT CLAIMED, AND WHY IT WAS WRONG — the third
        // "mechanism right, justification wrong" in this file in one day. It called the
        // unclamped accumulator "the #22/#29 permanent-silence class … NaN samples poisoning
        // filter/oscillator state". The accumulator half is true; the CONSEQUENCE half is not,
        // because the render clamp intercepted the value on every single sample. Pre-fix:
        // `filterCutoff = NaN` → `max(20, min(NaN, 18000))` = 20 → the SVF sat at a 20 Hz
        // lowpass (inaudible, yes — but by a pinned-dark filter, recoverable by re-applying a
        // patch, NOT by NaN samples spreading). `filterCutoff = +inf` → 18000 → the filter
        // simply opened fully: audible and benign, i.e. the case the old text named explicitly
        // as permanent silence was never silent at all. The fix is still right — the
        // accumulator now recovers on its own, and the value the UI reads stops being a stuck
        // non-finite — but it prevents a MILDER failure than advertised. Do not re-inflate it.
        //
        // ⛔ IT WAS ONE INSTANCE OF A FIVE-INSTANCE CLASS, NOT THE CLASS — and the other four
        // are closed as of #295/#296/#297, in `render`. The shape is `if x < 0 { x = seed }`
        // as a re-seed guard that never re-fires on NaN, because `NaN < 0` is false. Members:
        // `smoothedGain` (#295, the severe one — no downstream clamp rescued it, and it
        // survived note-off and patch re-apply), `smoothedHarmonicity` + `smoothedNoiseLevel`
        // (#296, the latter's `Swift.max(0, …)` being a floor with no ceiling two lines from
        // the trio that got clamped), `vibratoPhase` (#297, whose `> 0` gate screens NaN but
        // admits +inf). This one was the mildest of the five. The fix is the same everywhere:
        // clamp the ASSIGNMENT so the accumulator can heal, and sanitise whichever raw input
        // feeds it so there is a finite value to heal toward.
        //
        // ⚠️ NOT A MEMBER, checked rather than assumed: `expressVibrato`/`expressChorus` look
        // identical (a `> 0.0005` gate over a persistent phase) but their single writer
        // already does `isFinite ? … : 0` and clamps to 0…1, so no non-finite can reach them.
        // `smoothedFreq` also has the `< 0` shape — and here the first version of this note
        // excluded it on a mechanism that only holds for HALF the app. `prepareForNote` sets it
        // back to −1 on every note, but `prepareForNote`'s one production caller is
        // `spawnVoice`, the POLY path. On the MONO/bio path `BioReactiveSynthVoice.playNote`
        // calls only `noteOn(frequency:)`, which never touches it, and `reset()` does not clear
        // it either — so there it outlives every note exactly as `smoothedGain` did. It is a
        // real FIFTH member, DEFERRED rather than excluded. (Note also that the standard
        // differs between these two entries: `expressVibrato` is excluded on a writer audit
        // while `smoothedGain`'s accumulator was hardened despite an equally clean one. That
        // asymmetry is deliberate — the gain's failure mode is total silence — but it should
        // be stated, not left for the next reader to notice.)
        //
        // ⚠️ AND IT IS A NO-OP FOR EVERYTHING THAT SHIPS — measured, not assumed. The highest
        // cutoff in any shipped patch is 6500 Hz (`SynthPatch.rawFactory`; `GenrePatches` tops
        // out at 3600), and the largest bio factor is 1.3, so the target peaks at 8450 Hz —
        // less than half the ceiling. Only a hand-edited/saved patch above ~13.8 kHz, or a
        // non-finite one, can reach this clamp at all. This is hardening with a precedent
        // (#92 sanitised the bio INPUTS of this same function with no demonstrated producer
        // either), not a tuning change, and it must not be reported as one.
        // ⭐ THE SECOND MEMBER OF THE 60 Hz UNIT-ERROR CLASS, CLOSED (#332). #331 fixed the
        // brightness/amplitude pole and named this one in a ⚠️ block 35 lines below; it stayed
        // for one slice so the device listen could attribute what it heard. This is that slice.
        //
        // It read `filterCutoff * 0.97 + targetCutoff * 0.03`. At ~1 Hz, α = 0.97 is
        // τ = −1/ln(0.97) = 32.83 s. Step response, both poles, PER CALL:
        //
        //          after 1 call  2    5     10    30
        //   was 0.97        3 %  6 %  14 %  26 %  60 %
        //   now 0.6065     39 % 63 %  92 %  99 % 100 %
        //
        // ⛔ THE AXIS IS CALLS, NOT SECONDS, AND THE FIRST VERSION OF THIS BLOCK WROTE
        // SECONDS — the same "mechanism right, justification wrong" this repo keeps paying
        // for, committed inside the slice that fixes an instance of it. Calls equal seconds
        // only where a bio frame is the sole trigger: the mono/bio voice, and any poly voice
        // holding a sustained note. There is a SECOND production caller. `spawnVoice` runs
        // `if bioModulationEnabled { applyBioToVoice(voiceIdx) }` on EVERY note-on, so a
        // voice's poles also advance once per note it receives. Consequences, both ways:
        //  · the "32.8 s" indictment is an upper bound. On a busy poly part — say 4 note-ons
        //    per second into one voice — the old α = 0.97 already behaved like τ ≈ 6.6 s.
        //    Still far too slow, but "3 % after one second" was only ever true for sustained
        //    material and for the mono voice.
        //  · τ = 2 s is likewise a CEILING now, not a fact. Extra ticks converge toward the
        //    same `targetCutoff`, so there is no overshoot and no oscillation — but two
        //    voices on the same chord can sit at different cutoffs depending on how recently
        //    each was retriggered, and that per-voice spread is ~39 % per note-on instead of
        //    3 %. Converges, but it is a real transient the old constant hid. Listen to a
        //    DENSE poly part on device, not only to a held pad.
        //
        // The mapping the comments around here repeatedly call the MAIN bio expression —
        // "coherence opens the filter" — was, on sustained material, delivering 3 % of a
        // change in the player's body after a second and needing half a minute to get past
        // halfway. That is the instrument's premise failing quietly, in the one place a
        // listener would look for it first.
        //
        // ⭐ AND THE POINT IS THE SHARED CONSTANT, NOT THE NUMBER. Typing 0.6065 here a second
        // time would fix the symptom and leave the structure that produced it: two one-poles on
        // the same clock, each with its own literal, so a tuning change to one silently splits
        // them again — which is exactly how #331 could fix one and leave this one 32.8 s slow
        // in the same function. All THREE accumulators in `applyBioReactive` now read the one
        // `smoothCoeff` declared above, and a blocking-bundle guard
        // (`BioSmoothingSharesOnePoleTests`) fails if a fourth appears with its own literal.
        // The one-token revert that block offers (0.75 = τ 3.5 s) therefore still works, and now
        // moves all three together — which is what "one bio response time" has to mean.
        //
        // ZIPPER RISK: CHECKED, NOT ASSUMED. A faster block-rate pole steps `filterCutoff` in
        // bigger jumps, and stepping an SVF's cutoff injects energy into its integrators. It
        // cannot reach the filter as a step: `render` re-smooths PER SAMPLE toward this value
        // (`smoothedCutoff += 0.01 * (modulatedCutoff - smoothedCutoff)`, ≈ a few-ms glide),
        // and that smoother exists for precisely this reason — its own declaration names
        // "driven in block-size jumps by `applyBioReactive`" as the hazard it absorbs.
        //
        // ⚠️ THIS IS A TUNING CHANGE AND MUST BE REPORTED AS ONE — unlike the clamp above it,
        // which is a no-op for every shipped patch. It changes what the instrument sounds
        // like, and the two paths are not affected equally.
        //
        // ANCHORED path (a patch was applied) — this is what an ordinary session hears, and
        // it is the one that matters most. The factor is `(1 + (coherence − 0.5)·0.5)`
        // clamped to 0.7…1.3, but the CLAMP IS NOT THE SWING: `coherenceForSound` yields
        // (0, 1], so the factor only ever reaches **0.75…1.25 ×** the patch's own cutoff
        // (≈ 0.74 octaves) and the clamp is unreachable belt-and-braces. Quoting the guard
        // instead of the behaviour is its own small version of the error this slice fixes.
        //
        // SENTINEL path (no patch anchor) — an absolute 200…1800 Hz, 9× or ≈ 3.2 octaves,
        // now traversed in seconds. ⛔ AND THE FIRST VERSION CALLED THIS "the patch-less bio
        // voice", which points at the global `bioVoice` — a voice that CANNOT BE HEARD:
        // `BioReactiveSynthVoice.playNote` is the only thing that flips `hasEverSounded`,
        // and `bioVoice.playNote` has no caller in `Sources/` (attach/start/onPollTick/
        // setTuning only), so its render block returns zeros.
        //
        // ⛔ AND THAT CORRECTION WAS ITSELF WRONG IN ITS SECOND HALF (#338). "No caller in
        // `Sources/`" is a claim about TEXTUAL `bioVoice.playNote(` call sites and it holds;
        // "CANNOT BE HEARD" does not follow from it, because the caller is INSIDE the type:
        // `apply(controller:)` calls `playNote(frequency:)` on an external MIDI `.noteOn`,
        // and `bioVoice.start(subscribing: bus)` (run at launch in `EchoelmusicApp`) is what
        // installs the drain that reaches it. Plug a keyboard in and the global bio voice
        // sounds. `isArmed` does not stop it either — that latch gates only the BREATH
        // trigger. So the global instance takes the SENTINEL branch too, for the same reason
        // as the rack ones: nothing routes a patch to it. This is the most expensive shape of
        // stale note in this repo — one that declares a live mechanism dead — and it earned
        // its keep by being the stated reason the #338 tuning fan skipped this voice.
        //
        // The sentinel voice that ALSO sounds, and the louder one, is a different object:
        // `LaneVoiceRack.bios`, one per rack, reached when a
        // user assigns a track `TrackInstrument.bioVoice` under `FeatureFlags.multiRoll`.
        // It never receives a patch (`applyPatch` routes to the poly slot, never to `bios`),
        // so it takes the sentinel branch. The sentence was materially true and its
        // reasoning was wrong — and the correction changes the RISK ORDER: the big sweep is
        // behind a flag plus a deliberate user choice, while the modest 0.75…1.25 × change
        // is what every session hears. Do not read the sentinel as the headline.
        //
        // If a device listen finds either too twitchy, the fix is the shared constant above,
        // not a private literal back here.
        filterCutoff = (filterCutoff * smoothCoeff
                        + targetCutoff * (1.0 - smoothCoeff)).clamped(to: Self.cutoffRange)

        // ⛔ A THROTTLE STOOD HERE AND IS DELETED (#331) — AND IT WAS REDUNDANT, NOT A GATE.
        // It read `_spectralUpdateCounter += 1 / if … >= 6 { updateSpectralEnvelope() }` under
        // the comment "Recalculate spectral envelope 10x/sec for snappier bio response" (10 Hz
        // is what every 6th call means at 60 Hz — the caller that has never existed; the real
        // rate is ~1 Hz, so it fired once per six SECONDS).
        //
        // But the envelope was never stale, because it was never waiting on this counter:
        // `brightness` carries `didSet { updateSpectralEnvelope() }`, and the assignment
        // `brightness = _smoothedBrightness` above runs on EVERY call. Between that assignment
        // and THIS POINT the only write is `filterCutoff`, which the envelope does not read —
        // so every 6th call rebuilt the identical spectrum a SECOND time. Deleting it removes
        // one duplicated rebuild per six calls on the audio thread and one comment that
        // misstated the rate by 60×; it does not change a single sample.
        //
        // ⛔ THE FIRST VERSION OF THAT PROOF WAS WRONG, AND THE TRUE ONE IS STRONGER. It said
        // "`spectralShape`, `morphTarget`, `morphPosition`, `timbreBlend` are all untouched
        // inside this function". `morphTarget`/`morphPosition` are very much written inside
        // this function — in the coherence-trend morph block further down, whose own comment
        // calls itself "INTENTIONALLY THE LAST spectral write: it must win over the earlier
        // brightness.didSet rebuild". That block sits BELOW where the counter stood, so a call
        // here could never have observed those writes. The right scope is "between the
        // assignment and this point", not "inside this function". (The full read set is larger
        // than the four names too: `updateSpectralEnvelope` also reads `brightness`,
        // `hasTimbreProfile`, `timbreBuffer`, and — on the `.formant` branch only —
        // `frequency`. None is written in `applyBioReactive`; checked, not assumed.)
        //
        // ⛔ THE FIRST VERSION OF THIS TOMBSTONE CLAIMED THE OPPOSITE — "it rebuilt the spectrum
        // once per SIX SECONDS, which is why `brightness` felt dead no matter how fast the pole
        // above was made". That is the "mechanism right, justification wrong" failure this repo
        // keeps paying for: the deletion is correct, the reason was invented, and it would have
        // sent the next session hunting a staleness bug that the `didSet` had already closed.
        // The unit error never lived in this counter.
        //
        // ⚠️ THIS PARAGRAPH SAID "DO NOT READ THAT AS 'THE 60 Hz CLASS IS CLOSED' — #331 fixed
        // ONE member of it", and named the `filterCutoff` one-pole above (α = 0.97, τ = 32.8 s
        // at the real rate) as the other. **That one is closed as of #332**: it now reads the
        // same `smoothCoeff`, and a blocking-bundle guard fails if a fourth accumulator appears
        // with its own literal. The tombstone stays because the WARNING outlived its instance —
        // "one slice, one measurable change, so the device listen can attribute what it hears"
        // is why the two shipped separately, and a future reader deciding whether to batch two
        // audible tuning changes should see that this repo deliberately did not.
        //
        // ⚠️ WHAT IS STILL OPEN in the same class, so this does not read as an all-clear either:
        // the 60 Hz assumption was never confined to this function. Any per-call one-pole or
        // per-call counter fed by a bio frame carries it. The two closed instances were both in
        // `applyBioReactive`; nothing here proves there is no third elsewhere, and "I did not
        // look" is the honest state of that claim.

        // 2. Bio → amplitude (coherence sets the level; the "audible pump synced to pulse"
        //    this comment used to promise was the deleted LFO's ±0.06 over 24–120 s — never a
        //    pulse, and never synced to one. A real per-beat pump belongs on the sample clock.)
        let ampBase: Float = 0.35 + coherence * 0.15     // Calm = fuller
        // `+ 0.06` is the deleted `lfoValue * 0.12` term's exact MEAN, so the level CENTRE at any
        // given coherence is unchanged. The RANGE is not, and saying otherwise would be the exact
        // error this commit is fixing: the old line's "0.35-0.62" spanned coherence AND the LFO
        // together, and coherence alone spans 0.41–0.56. What narrows is only the ±0.06 drift the
        // LFO took 24–120 s to trace — coherence's own 0.15 span is untouched (#331).
        let ampPulse: Float = ampBase + 0.06
        _smoothedAmplitude = _smoothedAmplitude * smoothCoeff + ampPulse * (1.0 - smoothCoeff)
        // Breath phase → amplitude swell (ALL profiles — the sound rises and falls with the
        // breath). Raised cosine: 0 at the exhale trough AND the phase wrap, 1 mid-breath — its
        // merit is that TROUGH PLACEMENT (loudest mid-cycle, quiet at both ends), giving one
        // clean swell per breath. Downward-only factor (≤ 1.0) so it can never push past the
        // −1 dBFS master trim. Written into `amplitude`, NOT `_smoothedAmplitude`, so the swell
        // never accumulates in the one-pole state.
        let breathSwell: Float = 0.5 - 0.5 * cosf(breathPhase * 2 * .pi)
        let swellDepth: Float = (profile == .harmonicSeries) ? 0.18 : 0.10
        // × `velocityGain` (#174/#177): the bio pulse SHAPES the note's level, it does not
        // replace it. This line used to be an absolute write, so with bio modulation on — i.e.
        // always, in a bio-reactive instrument — the played velocity had no effect on loudness
        // and the Mix faders were inaudible while still baking themselves into the note data
        // the visual reads. `velocityGain` defaults to 1.0 ("no velocity context"), which the
        // mono/bio voice never leaves, so ITS amplitude is bit-identical to before.
        amplitude = (_smoothedAmplitude * (1.0 - swellDepth + swellDepth * breathSwell)
                     * velocityGain).clamped(to: 0...1)

        // 3. Heart rate → VIBRATO — a deviation AROUND the patch's own vibrato, not a rewrite
        //    (#279; the bioBase* law, same as the cutoff/brightness/character lines around it).
        //    ANCHORED path (a patch was applied): one MULTIPLICATIVE factor centred on 1.0 at
        //    heartRate 0.5, and arousal makes the vibrato a touch faster AND a touch deeper
        //    together — which is how vibrato intensifies on a real instrument.
        //    ⛔ heartRate 0.5 IS NOT "REST", AND THE FIRST VERSION OF THIS COMMENT SAID IT WAS —
        //    in the sentence a future session would copy when it anchors the next parameter.
        //    Both producers normalise `clampUnit((frame.heartRateBPM - 40) / 160)`
        //    (`PolySynthVoice.swift:667`, `BioReactiveSynthVoice.swift:387`), so 0.5 is **120
        //    BPM**. A genuinely resting 60 BPM gives 0.125 → factor 0.8125, i.e. the palette
        //    plays ~81 % of its designed vibrato at rest and only reaches 1.0× at 120 BPM. That
        //    is inside the deliberate ±25 % band and consistent with EVERY other bioBase* mapping
        //    here (they all centre on 0.5), so it is not this task's bug to fix — but whether the
        //    family's centre should be a resting heart rate rather than the middle of the
        //    mappable range is a real open question affecting five mappings at once, and it must
        //    be decided for all of them or none. Do not "fix" vibrato alone.
        //    Multiplicative, not additive like the character
        //    lines below, for the same reason the cutoff is: these are a RATE and a DEPTH, and —
        //    decisively — a patch that asks for NO vibrato must GET no vibrato. An additive
        //    deviation would push `vibratoDepth` off 0 at any HR above rest and switch the
        //    vibrato oscillator ON (render gate: `vibratoRate > 0 && vibratoDepth > 0`) in a
        //    preset that deliberately has none. The products are clamped to the same domains
        //    `SoundPrompt` enforces (depth 0…1, rate 0…12 Hz), which also makes a non-finite
        //    baseline out of a corrupted patch decode harmless. ⛔ BUT NOT BY THE MECHANISM THE
        //    FIRST VERSION OF THIS SENTENCE NAMED: it credited the NaN-safe `clamped(to:)`, and a
        //    NaN anchor never REACHES the clamp — `NaN >= 0` is false, so the guard below sends it
        //    to the legacy branch. The clamp handles ±inf (`inf * 1.0` → 1.0 / 12). Two different
        //    mechanisms for two different non-finite values; the guard is the one doing the NaN
        //    work. (The boundary sanitisation at the top of this function covers only the bio
        //    INPUTS, never the anchor, which is why either mechanism is needed at all.)
        //    ⚠️ The cutoff branch above used to be the exception — it multiplied its anchor
        //    UNCLAMPED into a persistent one-pole, so a non-finite anchor poisoned it forever.
        //    #294 closed that (the clamp sits on the ASSIGNMENT there, because that accumulator
        //    can be poisoned by `apply(to:)` directly, not only through the anchor).
        //    ⛔ "The family is symmetric again" stood here and was a completion claim this same
        //    file refutes twice: the SENTINEL vibrato writes a few lines below are still
        //    unclamped (the boundary-sanitisation comment at the top of this function says so),
        //    and `noiseLevel`'s `Swift.max(0, …)` is a floor with no ceiling. Symmetric for the
        //    ANCHORED branches only. Do not re-open those by "simplifying" a clamp away, and do
        //    not read this as "the class is closed" — see the five-instance note above.
        //    ⚠️ The rate clamp also pins the upward half of the deviation for any patch at or
        //    above 9.6 Hz. No shipped patch exceeds 5.5 Hz, so this is dormant too.
        //    SENTINEL path (−1, the raw patch-less bio voice): the legacy absolute GENTLE drift,
        //    byte-identical — 0.4 cent at heartRate 0 → 2.4 cent at 1, 0.05 → 0.2 Hz. (The
        //    inherited wording said "at rest → active" for those endpoints while the paragraph
        //    above called 0.5 the neutral reading: two different "rests" in one comment block.
        //    These are the RAW endpoints of the normalised input, i.e. 40 BPM and 200 BPM.)
        if bioBaseVibratoDepth >= 0 && bioBaseVibratoRate >= 0 {
            let vibratoFactor: Float = (1.0 + (heartRate - 0.5) * 0.5).clamped(to: 0.75...1.25)
            vibratoDepth = (bioBaseVibratoDepth * vibratoFactor).clamped(to: 0...1)
            vibratoRate = (bioBaseVibratoRate * vibratoFactor).clamped(to: 0...12)
        } else {
            vibratoDepth = 0.004 + heartRate * 0.02
            vibratoRate = 0.05 + heartRate * 0.15   // Very slow → moderate
        }

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

        // 7. Filter LFO depth — the same anchored/sentinel split as the vibrato above (#279):
        //    with a patch applied the value is a factor centred on 1.0 at neutral breath (0.5),
        //    so a patch that asks for a still filter (0) keeps a still filter and one that asks
        //    for movement keeps its designed amount. Without a patch, the legacy absolute
        //    mapping, byte-identical.
        //
        //    ⛔ AND `breathDepth` HAS NO PRODUCER, so read the paragraph above as a shape, not a
        //    behaviour. The first version of this comment said "the breath moves the patch's own
        //    lfoToFilterDepth" — that is false today and the audio-thread reviewer caught it in
        //    the same hour it was written. `BioSampleFrame` carries `breathRate` and
        //    `breathPhase` and NO depth field; both call sites pass the literal `0.5`
        //    (the `bioCommands.tryEnqueue(PolyBioParams(` block in `PolySynthVoice` and the
        //    `bioCommands.tryEnqueue(BioParams(` block in `BioReactiveSynthVoice` — cited by
        //    PHRASE, because this comment carried `:680` and `:399` for weeks while the real
        //    lines drifted to 732 and 524; a quoted phrase survives an insertion, a line number
        //    does not), so `breathFactor`
        //    is exactly 1.0 on every frame the shipped app can produce and this line reduces to
        //    a constant restore of the patch value. That restore is STILL the fix worth having —
        //    without it the legacy branch pinned every patch to `0.05 + 0.5*0.3 = 0.20`,
        //    overwriting whatever the Sound panel's "LFO→filter" row was set to. But the
        //    MODULATION half is dormant, tracked separately, and must not be claimed as live in
        //    any user-facing copy. (`breathPhase` IS measured and does drive the amplitude swell
        //    above; it is `breathDepth` specifically that nothing measures — same class as the
        //    `motionEnergy: 0` absence CLAUDE.md documents.)
        if bioBaseLFOToFilterDepth >= 0 {
            let breathFactor: Float = (1.0 + (breathDepth - 0.5) * 0.6).clamped(to: 0.7...1.3)
            lfoToFilterDepth = (bioBaseLFOToFilterDepth * breathFactor).clamped(to: 0...1)
        } else {
            lfoToFilterDepth = 0.05 + breathDepth * 0.3  // Deeper breath = more filter movement
        }

        // HARMONIC-SERIES profile (opt-in; §1.2). Body drives the harmonic structure:
        // HRV opens the overtone richness (variability → harmonic spread). `.natural`
        // skips this (identical sound). The breath-amplitude swell now lives in the shared
        // path above (a deeper swellDepth for .harmonicSeries), so it is NOT re-applied here.
        // 10 Hz control-plane writes; the render loop re-smooths harmonicity/gain.
        if profile == .harmonicSeries {
            harmonicity = (0.40 + hrvVariability * 0.50).clamped(to: 0.05...0.98) // HRV → overtone spread
        }

        // 8. Coherence TREND → slow spectral morph (INTENTIONALLY THE LAST spectral write:
        //    it must win over the earlier brightness.didSet rebuild). A slope (not an instant
        //    value) leans the spectrum around the patch's OWN shape — morphPosition 0 == the
        //    patch's spectralShape, so this is a deviation-from-baseline that RELEASES to the
        //    pure base at neutral trend (re-enabling spectralShape.didSet, guarded by
        //    `morphTarget == nil`). rising→.natural / falling→.metallic is an ARBITRARY
        //    engineering mapping with NO wellbeing valence — user-facing copy must NEVER call a
        //    rising-coherence sound "purer/calmer/better/healthier". Assign morphTarget DIRECTLY
        //    (never startMorph — it re-zeros morphPosition every call). CHANGE-GATED so the
        //    shared spectral-buffer rebuild fires only on a real change, not every 10 Hz frame.
        //
        //    ⭐ `coherenceTrend` HAS A PRODUCER SINCE #813, and this branch is reachable for the
        //    first time since it was written. ⛔ The note here said it had none: both
        //    `…BioParams(` sites passed the literal 0 (#496 measured it), so `trendMag` was
        //    exactly 0 on every frame the shipped app could produce and the deadband always won.
        //    The note also said what to do about it — "deriving one from the coherence history
        //    is a real slice — this branch is what it will drive" — and that is what #813 did:
        //    `Core/CoherenceTrend`, a pure struct each voice owns, fed on the MAIN ACTOR from
        //    the RAW `frame.coherence` (never `coherenceForSound`, whose neutral substitution
        //    would read as movement to a derivative), with ONE RUN PER SOURCE so an interleaved
        //    feed cannot deafen the measured one, and reset or held across an unmeasured
        //    stretch, a non-finite reading, a long gap and a non-positive interval so no
        //    transition mints a full-scale trend.
        //    ⛔ THIS WAS THE THIRD HOME OF A SAFETY LIST THAT NAMED AN ABSENT SAFEGUARD. It said
        //    "reset across an unmeasured stretch, a SOURCE SWITCH or a long gap" — the switch was
        //    not built (#920 built it, #920c replaced it with per-source state), and the `dt <= 0`
        //    hold that WAS built went unmentioned. #920's own retraction named two homes, this
        //    file and `CLAUDE.md`, and missed this one: the #766 pattern verbatim — when every
        //    home you checked is the same KIND (always-loaded prose), the ENUMERATION is what is
        //    incomplete, not the care per entry.
        //    ⚠️ ITS TWO NEIGHBOURS ARE STILL DEAD: `breathDepth` and `lfHfRatio` remain pinned
        //    literals, and the FX panel's always-on note still deliberately names FOUR channels.
        //    Naming the trend in panel copy is now ALLOWED and not required — a copy decision,
        //    not a side effect of wiring one. And the valence rule is unchanged and binds the
        //    new producer too: rising coherence is an ENGINEERING mapping, never "purer" or
        //    "calmer".
        let trendMag = abs(coherenceTrend)
        if trendMag < 0.10 {                                   // deadband → release to the patch shape
            if morphTarget != nil {
                morphTarget = nil                              // clear FIRST so the crossfade is skipped …
                setMorphPosition(0)                            // … and the PURE base envelope is rebuilt this frame
                _lastMorphShape = nil; _lastMorphPos = 0
            }
        } else {
            let newShape: SpectralShape = coherenceTrend > 0 ? .natural : .metallic
            let pos = Swift.min((trendMag - 0.10) / 0.90 * 0.30, 0.30)   // 0 at deadband edge → 0.30 cap
            if newShape != _lastMorphShape || abs(pos - _lastMorphPos) > 0.005 {
                morphTarget = newShape
                setMorphPosition(pos)                          // clamps 0...1 AND rebuilds the crossfade this frame
                _lastMorphShape = newShape; _lastMorphPos = pos
            }
        }
    }

    // MARK: - Timbre Transfer

    /// Load a timbre profile from recorded harmonic analysis of a target instrument
    /// The profile is a [Float] of harmonicCount amplitudes representing the instrument's
    /// characteristic spectral envelope at a reference pitch.
    public func loadTimbreProfile(_ profile: [Float], blend: Float = 1.0) {
        guard profile.count >= harmonicCount else { return }
        for i in 0..<harmonicCount { timbreBuffer[i] = profile[i] }
        hasTimbreProfile = true
        timbreBlend = blend
        updateSpectralEnvelope()
    }

    /// Clear timbre profile (return to pure spectral shape). Flag-only — the buffer
    /// is kept so this costs no `free()` on the audio-thread patch drain.
    public func clearTimbreProfile() {
        hasTimbreProfile = false
        timbreBlend = 0
        updateSpectralEnvelope()
    }

    /// RENDER-SAFE timbre recall: writes the built-in instrument's spectral profile
    /// straight into the preallocated buffer, so no array is created or destroyed.
    /// `nil` — or a non-positive blend — clears back to the pure spectral shape.
    ///
    /// This is the entry point the audio-thread patch drain uses. The allocating
    /// pair (`instrumentProfile(_:)` + `loadTimbreProfile(_:blend:)`) stays for
    /// control-thread callers and for custom, non-built-in profiles.
    public func applyTimbre(_ instrument: InstrumentTimbre?, blend: Float) {
        guard let instrument, blend > 0 else {
            clearTimbreProfile()
            return
        }
        timbreBuffer.withUnsafeMutableBufferPointer {
            EchoelDDSP.writeInstrumentProfile(instrument, into: $0)
        }
        hasTimbreProfile = true
        timbreBlend = blend
        updateSpectralEnvelope()
    }

    /// RENDER-SAFE custom timbre (EchoelVoice #591): copies caller-owned taps into the
    /// preallocated buffer — the `applyTimbre` discipline with a MEASURED source instead
    /// of a built-in instrument. Scalar stores + `updateSpectralEnvelope()` only; no
    /// allocation, no ARC, no ObjC. Short input or a non-positive blend clears, matching
    /// `applyTimbre`'s contract.
    public func applyCustomTimbre(_ taps: UnsafeBufferPointer<Float>, blend: Float) {
        guard taps.count >= harmonicCount, blend > 0 else {
            clearTimbreProfile()
            return
        }
        for i in 0..<harmonicCount { timbreBuffer[i] = taps[i] }
        hasTimbreProfile = true
        timbreBlend = blend
        updateSpectralEnvelope()
    }

    /// Generate a simple timbre profile from a known instrument type
    /// These are pre-computed spectral envelopes based on acoustic analysis
    public static func instrumentProfile(_ instrument: InstrumentTimbre, harmonics: Int = 64) -> [Float] {
        var profile = [Float](repeating: 0, count: harmonics)
        profile.withUnsafeMutableBufferPointer { writeInstrumentProfile(instrument, into: $0) }
        return profile
    }

    /// The same spectral profiles, written into a buffer the CALLER owns.
    ///
    /// Split out of `instrumentProfile(_:harmonics:)` because the patch drain runs on
    /// the audio thread: allocating a fresh 64-tap `[Float]` per voice per character
    /// change was a heap allocation in the render block. Everything here is scalar
    /// arithmetic, C math (`exp`/`pow`, both audio-thread-safe) and two vDSP calls
    /// over the caller's memory — no allocation, no ARC, no ObjC.
    public static func writeInstrumentProfile(_ instrument: InstrumentTimbre,
                                              into out: UnsafeMutableBufferPointer<Float>) {
        guard let profile = out.baseAddress, !out.isEmpty else { return }
        let harmonics = out.count
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
            vDSP_vsdiv(profile, 1, &div, profile, 1, vDSP_Length(harmonics))
        }
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
        // Back to "no velocity context". Harmless today (the poly loops gate on
        // `voiceNotes[i] >= 0`, which reset clears), but a reset voice must not carry a
        // stale gain into whatever plays next — and since #174 a stale gain of 0 would
        // read as a muted fader that nobody set.
        velocityGain = 1
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
    /// Harmonic tap count every pooled voice was built with — the size contract for
    /// `setCustomTimbre` (mirrors each voice's own `harmonicCount`).
    public let harmonicCount: Int

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

    // MARK: - Custom voice timbre (EchoelVoice #591)

    /// Staged MEASURED timbre profile (the voice-as-patch plan): `harmonicCount` fixed
    /// slots behind a RAW pointer allocated once in init and freed in deinit — no CoW,
    /// no ARC, so the audio-thread fan below can read it across the whole voice loop
    /// without a retain (a plain `[Float]` here would keep a formal access open long
    /// enough that a concurrent control-thread write could trigger a CoW reseat and put
    /// the last release — a `free()` — on the audio thread; review #591a). Control
    /// thread writes the taps, THEN bumps `customTimbreVersion` (aligned Int word
    /// write); the render drain compares versions. HONEST TORN-READ BOUND: the stores
    /// are plain (no release/acquire pairing), so a drain that observes the version
    /// before every tap store is visible fans a mixed envelope AND marks the version
    /// applied — that state STAYS until the next version bump or patch reassert, not
    /// "one block". Bounded staleness, healed by any recall; never heap corruption.
    ///
    /// WHY THIS EXISTS (trap 1 of `scratchpads/PLAN_ECHOEL_VOICE.md`): every patch recall
    /// ends in `ResolvedPatch.apply(to:)` on the audio thread, which calls `applyTimbre`
    /// UNCONDITIONALLY — for a patch without a built-in instrument that means
    /// `clearTimbreProfile()`, wiping a custom profile. `ResolvedPatch` is deliberately
    /// POD (no Array), so the profile cannot ride inside it. It is staged HERE instead,
    /// and re-fanned AFTER each patch drain (`drainCustomTimbre(reassert: true)`), so the
    /// measured voice survives patch recalls until explicitly cleared.
    private let customTimbre: UnsafeMutablePointer<Float>
    private var customTimbreBlend: Float = 0
    /// Control-written, audio-read. `false` means the PATCH pathway owns timbre state
    /// and the drain must not touch it.
    private var customTimbreActive: Bool = false
    private var customTimbreVersion: Int = 0
    /// Audio-thread only.
    private var appliedCustomTimbreVersion: Int = 0

    /// CONTROL THREAD. Stage a measured profile (≥ `harmonicCount` taps; shorter input is
    /// refused, matching `loadTimbreProfile`). Non-finite taps are read as 0 and negatives
    /// clamped (the engineering.md boundary rule); a non-positive or non-finite blend
    /// deactivates instead of arming a silent profile.
    public func setCustomTimbre(_ taps: [Float], blend: Float) {
        guard taps.count >= harmonicCount else { return }
        for i in 0..<harmonicCount {
            let t = taps[i]
            customTimbre[i] = t.isFinite ? Swift.max(0, t) : 0
        }
        let b = blend.clamped(to: 0...1)
        customTimbreBlend = b
        customTimbreActive = b > 0
        customTimbreVersion &+= 1
    }

    /// CONTROL THREAD. Hand timbre ownership back to the patch pathway. The caller that
    /// wants the last patch's own instrument spectrum back re-applies that patch (the
    /// normal recall path); with no re-apply, the next drain clears to the pure shape.
    public func clearCustomTimbre() {
        customTimbreActive = false
        customTimbreVersion &+= 1
    }

    /// AUDIO THREAD, called from the render drain AFTER the patch drain. `reassert` is
    /// true when a patch was applied this block — the patch's unconditional
    /// `applyTimbre` just ran, so an active custom profile must be re-fanned on top.
    /// While inactive the drain leaves timbre state to the patch pathway, EXCEPT on the
    /// deactivation edge itself (version changed, nothing reasserting): then it clears —
    /// gated on `!reassert` so a same-block "clear custom + re-apply patch" cannot wipe
    /// the patch's own just-restored instrument timbre.
    public func drainCustomTimbre(reassert: Bool) {
        let v = customTimbreVersion
        let versionChanged = v != appliedCustomTimbreVersion
        appliedCustomTimbreVersion = v
        guard customTimbreActive else {
            if versionChanged && !reassert {
                for voice in voices { voice.clearTimbreProfile() }
            }
            return
        }
        guard versionChanged || reassert else { return }
        let blend = customTimbreBlend
        let taps = UnsafeBufferPointer(start: customTimbre, count: harmonicCount)
        for voice in voices { voice.applyCustomTimbre(taps, blend: blend) }
    }

    deinit {
        customTimbre.deinitialize(count: harmonicCount)
        customTimbre.deallocate()
    }

    // MARK: - Voices

    private var voices: [EchoelDDSP]
    private var voiceNotes: [Int]      // MIDI note per voice (-1 = free)
    /// PER-NOTE filter expression (founder 2026-07-27: "mehr MPE vibes … der Sound auf
    /// den Kacheln soll je nach Position ein bisschen anders klingen"). The global
    /// `cutoffScale` is automation and applies to the WHOLE instrument; this is the one
    /// finger's own position, held for as long as that note sounds. They MULTIPLY in the
    /// render fan, so automation still works and expression rides on top of it.
    ///
    /// Why this had to be per-voice: `cutoffScale` alone is a single Float fanned to every
    /// voice, so three fingers at three heights all got the LAST finger's filter — the
    /// opposite of MPE, and inaudible only because one finger is the common case.
    private var voiceCutoffScale: [Float]
    /// PER-VOICE loudness trim for the expression above (#230). Recomputed at every writer of
    /// this voice's pitch or cutoff — `spawnVoice`, `slideNote`, `setNoteCutoffScale` — and
    /// then only READ in the per-sample loop, which therefore stays free of `pow`/`log2`.
    ///
    /// ⚠️ SAY WHAT THAT DOES AND DOES NOT BUY, because the first version of this comment let a
    /// reader infer the stronger claim: all three of those writers run ON THE AUDIO THREAD
    /// (they are called from the note-command drain inside the render block). The
    /// transcendentals did not stay off the audio thread — they moved onto it, once per note
    /// event, from the UIKit touch handler where the velocity-side version ran. That is
    /// permitted (`sin`/`cos`/`pow`/`logf` are on the SAFE list in `swift-audio.md`, and
    /// `spawnVoice` already calls `pow` two lines from here) and it is bounded by the event
    /// rate, not the sample rate. What the precompute genuinely buys is that the cost does not
    /// multiply by frames × voices every block.
    ///
    /// Why per-voice and not on the velocity, where it started: velocity is not addressable on
    /// a sounding note, so a velocity-side trim evened the STRIKE and left the DRAG — the
    /// gesture the surface exists for — exactly as uneven as before. See `ExpressionLevelTrim`.
    ///
    /// A voice keeps its trim through its release tail (nothing rewrites it after noteOff),
    /// which is correct: a level jump at key-up would be a new defect, not a fix.
    private var voiceLevelTrim: [Float]

    /// What the render actually multiplies — `voiceLevelTrim` eased toward, per block.
    ///
    /// ⛔ THE FIRST VERSION MULTIPLIED THE TARGET DIRECTLY, AND THAT WAS A CLICK. Review found
    /// it: this is the first per-voice level scalar in this render that MOVES while a voice
    /// sustains, and every other such value in this file is one-poled — `smoothedCutoff`,
    /// `smoothedGain`, and `polyMakeupGain`, whose own comment records that the unsmoothed
    /// version was "audible pumping on chord/arp changes". The drag was harmless (the view
    /// gates cutoff events at 1 % and the filter term is 1.0 dB/oct, so ~0.007 dB a step), but
    /// the GLIDE was not: `slideNote` re-derives the trim from the new pitch, and the pitch
    /// term is 1.5 dB per octave applied at one block boundary — ~16 % of amplitude, stepped,
    /// on a sustaining pad. A diagonal drag crossing two bands doubles it.
    ///
    /// SNAPPED, NOT EASED, ON SPAWN (`spawnVoice` writes both arrays): a fresh note must start
    /// at its own trim, never fade in from whatever the recycled slot last held.
    private var voiceLevelTrimSmoothed: [Float]
    private var voiceAges: [Int]       // Age counter for voice stealing
    private var ageCounter: Int = 0

    /// Scratch for `allocateVoice`: each slot's current envelope level, refreshed on the
    /// audio thread immediately before the reuse decision (#404). Pre-allocated at init and
    /// never resized, so reading "how loud is each tail right now" costs no allocation.
    /// Holds no meaning between calls — do not read it as state.
    private var voiceLevels: [Float]

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
        let hc = max(1, harmonicCount)   // ONE spelling of the clamp for both members
        self.harmonicCount = hc
        let ct = UnsafeMutablePointer<Float>.allocate(capacity: hc)
        ct.initialize(repeating: 0, count: hc)
        self.customTimbre = ct

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
        self.voiceCutoffScale = [Float](repeating: 1, count: maxVoices)
        self.voiceLevelTrim = [Float](repeating: 1, count: maxVoices)
        self.voiceLevelTrimSmoothed = [Float](repeating: 1, count: maxVoices)
        self.voiceAges = [Int](repeating: 0, count: maxVoices)
        self.voicePans = [Float](repeating: 0, count: maxVoices)
        self.voiceLevels = [Float](repeating: 0, count: maxVoices)

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
    /// Per-voice TRANSPOSE in semitones (founder 2026-07-14, per-instrument Transpose:
    /// "einzelne Instrumenten Elemente im synth nen transpose Button"). Folded into the
    /// ONE MIDI→Hz exponent in `noteOn`, so it shifts the SOUNDING pitch while note-on/
    /// off voice bookkeeping keeps keying on the untransposed note number (no hung
    /// notes). `slideNote`'s glide ratio is transpose-invariant (the offset cancels in
    /// newBase/oldBase) and its voices already carry the transposed frequency from their
    /// noteOn, so it needs no change. Takes effect on the next note; 0 = bit-identical.
    /// Same atomic-Float discipline as `a4Hz` (aligned word read on the audio thread).
    public var transposeSemitones: Float = 0
    /// Per-voice DETUNE in cents (founder 2026-07-14, per-instrument "transpose detune"):
    /// a FINE continuous pitch offset folded into the SAME MIDI→Hz exponent as
    /// `transposeSemitones` and the microtonal `cents`, so it shifts the sounding pitch
    /// by a fraction of a semitone (e.g. +7¢ sharp) without touching note bookkeeping.
    /// `slideNote`'s glide ratio is offset-invariant (cancels in newBase/oldBase). Takes
    /// effect on the next note; 0 = bit-identical. Atomic-Float discipline, like `a4Hz`.
    public var detuneCents: Float = 0

    /// Set unison live (clamped). count 1 = off; detune is the full spread in cents.
    public func setUnison(count: Int, detuneCents: Float) {
        unisonCount = min(max(count, 1), Self.maxUnison)
        unisonDetuneCents = min(max(detuneCents, 0), 50)
    }

    // MARK: - Oktaver

    /// Octave-double direction (founder 2026-07-14 "transpose detune und Oktaver"):
    /// −1 = add a sub-octave voice, +1 = an upper-octave voice, 0 = off (default,
    /// bit-identical). Control-path only — `noteOn` spawns ONE extra voice at 2×/0.5×
    /// the base frequency, keyed on the SAME note number, so `noteOff`/`slideNote`
    /// handle it with zero extra bookkeeping (the glide ratio is octave-invariant).
    /// Same atomic-Int discipline as `unisonCount` (aligned word, next-note effect).
    public var octaveDouble: Int = 0
    /// The ONE octave-voice mix default (code-review: callers that only steer the
    /// direction reference this instead of re-stating a magic 0.5 that could drift).
    public static let defaultOctaveMix: Float = 0.5
    /// Level of the octave voice relative to the main stack (0…1, default 0.5).
    /// 0 skips the spawn entirely (a silent voice must not burn a slot). Same
    /// atomic-Float discipline as `a4Hz`.
    public var octaveMix: Float = EchoelPolyDDSP.defaultOctaveMix

    /// Set the octaver live (clamped; non-finite mix falls back to the 0.5 default —
    /// the repo NaN law: fail quiet/neutral, never propagate).
    public func setOctaver(direction: Int, mix: Float) {
        octaveDouble = min(max(direction, -1), 1)
        octaveMix = min(max(mix.isFinite ? mix : Self.defaultOctaveMix, 0), 1)
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
    public func slideNote(from oldNote: Int, to newNote: Int, velocity: Float = 1.0,
                          cutoffScale: Float = 1) {
        guard oldNote != newNote else { return }
        let newCents = tuningCents[((newNote % 12) + 12) % 12]
        let newBase = a4Hz * pow(2.0, (Float(newNote - 69) + newCents / 100.0) / 12.0)
        let oldCents = tuningCents[((oldNote % 12) + 12) % 12]
        let oldBase = a4Hz * pow(2.0, (Float(oldNote - 69) + oldCents / 100.0) / 12.0)
        let ratio = newBase / max(oldBase, 1e-3)
        var moved = false
        // `velocityGain` is deliberately NOT re-derived here: a slide is legato, so the note
        // keeps the level it was struck at (same reasoning that already left `amplitude`
        // alone). This path is the touch surface, not the generated take, so no Mix fader is
        // waiting on it.
        let slideScale = Self.clampExpressionScale(cutoffScale)
        // A glide keeps its struck level (see above) — but the trim is not level, it is the
        // correction for WHERE the note now sits. The pitch moves, so the trim must move with
        // it, or a glide up an octave arrives 1.5 dB louder than the same note struck.
        let slideTrim = Self.expressionTrim(pitch: newNote, cutoffScale: slideScale,
                                            reference: Int(expressionTrimReferencePitch))
        for i in 0..<maxVoices where voiceNotes[i] == oldNote {
            voices[i].frequency *= ratio        // smoothedFreq glides there per-sample
            voiceNotes[i] = newNote
            voiceCutoffScale[i] = slideScale
            voiceLevelTrim[i] = slideTrim
            ageCounter += 1
            voiceAges[i] = ageCounter
            moved = true
        }
        if !moved { noteOn(note: newNote, velocity: velocity, cutoffScale: cutoffScale) }
    }

    // MARK: - Note Control

    /// MIDI note on
    public func noteOn(note: Int, velocity: Float = 1.0, cutoffScale: Float = 1) {
        // Per-pitch-class microtonal retune (cents → semitone fraction). Zero table
        // = standard 12-TET, bit-identical to before.
        let cents = tuningCents[((note % 12) + 12) % 12]
        // Per-instrument transpose (whole semitones) + detune (cents) fold into the
        // SAME exponent as the microtonal cents — snapshot reads (atomic Float), both
        // 0 ⇒ bit-identical.
        let baseFreq = a4Hz * pow(2.0, (Float(note - 69) + transposeSemitones + (cents + detuneCents) / 100.0) / 12.0)
        let v = min(1, max(0, velocity))
        // Snapshot ONCE for this whole note-on — see `expressionTrim`. Every voice this call
        // spawns (unison stack + Oktaver) must share one reference, or the same note ends up
        // with mismatched trims when the surface changes key mid-strike.
        let trimRef = Int(expressionTrimReferencePitch)

        let u = min(max(unisonCount, 1), Self.maxUnison)
        if u == 1 {
            // OFF: spawn one voice with the original pan/amplitude behaviour (unchanged).
            spawnVoice(note: note, soundingPitch: note, frequency: baseFreq, velocity: v,
                       unisonPan: nil, unisonGain: 1,
                       cutoffScale: cutoffScale, trimReference: trimRef)
        } else {
            // ON: stack `u` detuned voices, symmetric about the played pitch, panned
            // across the stereo field. Per-voice gain 1/√u keeps the summed loudness sane.
            let gain = 1 / sqrt(Float(u))
            let panSpread: Float = 0.6
            let spread = unisonDetuneCents  // snapshot once (atomic read) for this note
            for k in 0..<u {
                let t = Float(k) / Float(u - 1) * 2 - 1      // -1 … +1
                let detune = pow(2.0, (t * spread * 0.5) / 1200.0)
                spawnVoice(note: note, soundingPitch: note, frequency: baseFreq * detune,
                           velocity: v, unisonPan: t * panSpread, unisonGain: gain,
                           cutoffScale: cutoffScale, trimReference: trimRef)
            }
        }

        // Oktaver: ONE extra voice an octave up/down, keyed on the SAME note number —
        // noteOff releases it and slideNote glides it (the ratio is octave-invariant)
        // with zero extra bookkeeping. Snapshot reads (atomic); 0/0 skips entirely,
        // so the default path stays bit-identical. Gain rides the unison per-voice
        // gain scaled by the mix, panned where its SOUNDING pitch sits (key-follow).
        let oct = min(max(octaveDouble, -1), 1)
        let mix = octaveMix
        if oct != 0, mix.isFinite, mix > 0 {
            spawnVoice(note: note, soundingPitch: note + 12 * oct,
                       frequency: baseFreq * (oct > 0 ? 2 : 0.5), velocity: v,
                       unisonPan: Self.keyFollowPan(forNote: note + 12 * oct),
                       unisonGain: (u == 1 ? 1 : 1 / sqrt(Float(u))) * min(mix, 1),
                       cutoffScale: cutoffScale, trimReference: trimRef)
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
    ///
    /// `cutoffScale` is the note's PER-NOTE filter expression and MUST be a parameter, not
    /// read from the property of the same name. It was omitted here when per-note
    /// expression landed: the write below then silently bound `self.cutoffScale` — the
    /// GLOBAL automation scale — so (a) every note-on dropped its finger's position and
    /// (b) the render's `cutoffScale * voiceCutoffScale[i]` SQUARED the automation value.
    /// Neither is a compiler warning, because an unused function parameter is legal Swift.
    ///
    /// `soundingPitch` is what the voice will actually be HEARD at, which is not always `note`:
    /// the Oktaver spawns a voice an octave away while deliberately keeping the original note
    /// number so `noteOff`/`slideNote` still find it. The trim must follow the sounding pitch —
    /// ⛔ the first version passed `note` and therefore under-trimmed an octave-up doubling by
    /// 1.5 dB (and over-trimmed an octave-down one by the same). The correct idiom was already
    /// three lines away at the call site: `keyFollowPan(forNote: note + 12 * oct)` pans by the
    /// sounding pitch for exactly this reason.
    private func spawnVoice(note: Int, soundingPitch: Int, frequency freq: Float, velocity v: Float,
                            unisonPan: Float?, unisonGain: Float, cutoffScale: Float,
                            trimReference: Int) {
        let voiceIdx = allocateVoice()

        voiceNotes[voiceIdx] = note
        let spawnScale = Self.clampExpressionScale(cutoffScale)
        voiceCutoffScale[voiceIdx] = spawnScale
        let spawnTrim = Self.expressionTrim(pitch: soundingPitch, cutoffScale: spawnScale,
                                            reference: trimReference)
        voiceLevelTrim[voiceIdx] = spawnTrim
        // SNAP, not ease: this slot may have just been stolen from a note with a very different
        // trim, and a fresh note must start at its own level rather than sliding into it.
        voiceLevelTrimSmoothed[voiceIdx] = spawnTrim
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
        let expo = 1 + percussiveness * 0.5
        voices[voiceIdx].amplitude = pow(v, expo) * unisonGain
        // The factor the bio apply SCALES its amplitude by, instead of overwriting it
        // (#174/#177). Referenced against the velocity the generated material actually
        // carries, so a nominal note keeps its old level and only the DIFFERENCES move —
        // the raw velocity here would have cost the pad ~7 dB. `unisonGain` is folded in
        // because bio used to erase it, which made a unison stack louder than one voice
        // instead of the 1/√u the stack was built for.
        // `velocityCurve` halves the dB spread — see its doc comment; the full curve put the
        // pad's pulse layer 12 dB down and the lead 4 dB in front of it, on velocities nobody
        // ever chose as a mix. The gamma sits on the EXPONENT, not on the result, so 0 stays
        // exactly 0 (the mute) and `nominalVelocity` stays exactly 1 (the level).
        // NaN belt: defensive only — `v` is clamped to 0...1 and every `unisonGain` producer is
        // finite, so this cannot fire today. It falls back to 1, not 0, because this file's law
        // is "fail to resting, never to silence", and 0 would be indistinguishable from the
        // muted-fader case the change exists to make honest.
        // NOT `Self.` — required, not stylistic: this line lives in EchoelPolyDDSP, which has no
        // such member; the constants belong to the VOICE class whose property they bound.
        let scale = pow(v / EchoelDDSP.nominalVelocity, expo * EchoelDDSP.velocityCurve) * unisonGain
        voices[voiceIdx].velocityGain = scale.isFinite
            ? Swift.min(scale, EchoelDDSP.maxVelocityBoost) : 1
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

    /// Continuous PER-NOTE filter expression for a sounding note — the finger that is
    /// still down moving to a new position. Same pitch→voice lookup `noteOff` uses. A note
    /// that is no longer held simply matches nothing, so a stale update is a no-op rather
    /// than a wrong-voice write. Pure arithmetic on the audio thread: no allocation, no lock.
    public func setNoteCutoffScale(note: Int, scale: Float) {
        let s = Self.clampExpressionScale(scale)
        // THE HALF #230 EXISTS FOR: this is the drag, and until now it wrote only the filter.
        // The trim is recomputed from the CLAMPED scale — the filter the voice actually gets —
        // so a corrected preset and the sounding timbre can never disagree.
        let trim = Self.expressionTrim(pitch: note, cutoffScale: s,
                                       reference: Int(expressionTrimReferencePitch))
        for i in 0..<maxVoices where voiceNotes[i] == note {
            voiceCutoffScale[i] = s
            voiceLevelTrim[i] = trim
        }
    }

    /// The pitch that gets NO expression level trim, or a negative value (the default) to
    /// switch the trim off entirely — in which case every voice keeps `voiceLevelTrim == 1`
    /// and the render is bit-identical to before #230.
    ///
    /// OFF BY DEFAULT ON PURPOSE. The generated take passes `cutoffScale: 1`, so only the
    /// PITCH term would bite there — and it would quietly re-balance every generated note
    /// against a reference nobody chose. The trim belongs to the play surface, which knows
    /// its own middle band; `TouchInstrumentView` sets this and nothing else does.
    ///
    /// Written from the UI, read on the audio thread: `Int32`, atomic width, same discipline
    /// as `portamentoCoeff` / `transposeSemitones`. A torn read is not possible, and a read
    /// one block late only delays the trim by one buffer.
    public var expressionTrimReferencePitch: Int32 = -1

    /// The trim for one voice, or 1 when `reference` is negative (the feature off). Called only
    /// from the note path (spawn/slide/expression), never from the per-sample loop.
    ///
    /// `reference` is a PARAMETER rather than a property read, so every caller must snapshot
    /// `expressionTrimReferencePitch` once. ⛔ That is not style: the first version read the
    /// property inside this function, and `noteOn` calls `spawnVoice` up to four times for ONE
    /// note (three unison + the Oktaver). A `@MainActor` write landing between two of them gave
    /// voices of the same note different trims — an unison imbalance that nothing would heal
    /// until the next slide. `slideNote` and `setNoteCutoffScale` already hoisted their
    /// computation above their loops; this makes the discipline impossible to forget.
    @inline(__always)
    private static func expressionTrim(pitch: Int, cutoffScale: Float, reference: Int) -> Float {
        guard reference >= 0 else { return 1 }
        return ExpressionLevelTrim.gain(cutoffScale: cutoffScale, pitch: pitch,
                                        referencePitch: reference)
    }

    /// One clamp for every writer of a per-note expression scale. NaN → 1 (resting), never
    /// 0 — this file's law is "fail to resting, never to silence", and a NaN reaching the
    /// filter cutoff is the permanent-silence class (#29/#92). Bounds match `setCutoffScale`.
    @inline(__always)
    private static func clampExpressionScale(_ x: Float) -> Float {
        Swift.min(Swift.max(x.isFinite ? x : 1, 0.1), 8)
    }

    /// All notes off
    public func allNotesOff() {
        for i in 0..<maxVoices {
            voices[i].noteOff()
            voiceNotes[i] = -1
        }
    }

    // MARK: - Voice Allocation

    /// Of the slots whose note has been released (`voiceNotes[i] < 0`), the one whose tail
    /// is QUIETEST — not the one with the lowest index.
    ///
    /// WHY THIS EXISTS (#404, founder "teilweise extremes Knacken"). Reusing a slot whose
    /// release tail is still ringing is not free: `spawnVoice` calls
    /// `prepareForNote(hardReset: false)`, which nevertheless clears `smoothedFreq`, so the
    /// render re-seeds it to the NEW pitch on the very next sample. The waveform's VALUE
    /// stays continuous (the partial phases are kept) but its SLOPE does not — a kink whose
    /// audibility scales directly with how loud that tail still was. Picking the quietest
    /// candidate puts that unavoidable kink on the least audible voice available.
    ///
    /// ⚠️ HOW FAR THIS CLAIM GOES, so the next reader does not over-read it: choosing the
    /// quietest tail REDUCES the energy of a confirmed discontinuity. It does not remove it,
    /// and it is NOT established that this discontinuity is the whole of what the founder
    /// hears. Treat it as a floor-lowering, not as a fix, until a device listen says
    /// otherwise. The stronger move — fade the reused tail to zero over ~3 ms and then hard
    /// reset — is deliberately NOT taken here: it changes what a stolen voice sounds like,
    /// and this slice is meant to be safe under every competing theory of the artefact.
    ///
    /// TIES GO TO THE LOWEST INDEX, which makes this a strict refinement: when every free
    /// slot carries the same level, the answer is identical to the old lowest-free-index
    /// rule. (That rule's exact call is deliberately NOT quoted anywhere in this file's
    /// prose — `ReusedTailIsTheQuietestOneTests` scans the source for its absence, so a
    /// doc-comment mention would redden the blocking gate over a sentence.)
    /// A slot whose level is non-finite can never WIN (it would be a meaningless comparison)
    /// but stays eligible as the fallback, so a poisoned envelope can never make a voice
    /// unallocatable — it would only be chosen when it is the sole free slot, exactly as
    /// before.
    ///
    /// Pure and total: no allocation, no state, defined for mismatched array lengths (a
    /// slot past the end of `levels` is treated as having no usable level).
    ///
    /// Audio-thread safe by construction. `polyMakeupTarget`/`smoothedMakeup` are the
    /// precedent for "pure `nonisolated static` helper called from the render", but they
    /// take SCALARS — citing them as cover for passing arrays, as the first version did,
    /// over-claimed. The precedent for that is the line this replaced: the old rule was
    /// itself an Array method call on the same stored property, and branch 1 above already
    /// subscripts `voices` up to `maxVoices` times. Read-only arguments take no copy, so
    /// the cost is the same category and roughly twice the count of something already
    /// negligible — not a new class of risk.
    nonisolated static func quietestFreeSlot(voiceNotes: [Int], levels: [Float]) -> Int? {
        var firstFree: Int?
        var bestIdx: Int?
        var bestLevel = Float.infinity
        for i in 0..<voiceNotes.count where voiceNotes[i] < 0 {
            if firstFree == nil { firstFree = i }
            guard i < levels.count else { continue }
            let level = levels[i]
            guard level.isFinite else { continue }
            if level < bestLevel {
                bestLevel = level
                bestIdx = i
            }
        }
        return bestIdx ?? firstFree
    }

    private func allocateVoice() -> Int {
        // Prefer a truly silent voice (free slot AND envelope idle) so we never
        // cut off a still-audible release tail.
        for i in 0..<maxVoices where voiceNotes[i] < 0 && !voices[i].isActive {
            return i
        }
        // Next, a free slot — the note is released but its tail may still be ringing.
        // Among those take the QUIETEST, not the lowest index (#404): every candidate here
        // costs a re-pitch kink on a sounding voice, so the choice is which voice pays it.
        // Filling `voiceLevels` is `maxVoices` plain Float reads into a pre-allocated array
        // — no allocation on the audio thread.
        //
        // ENVELOPE × AMPLITUDE, not the envelope alone. The first version compared
        // `envelopeLevel` by itself and its doc called that "how loud" — it is not. The
        // render is `mixed * smoothedGain * envelopeValue` with `smoothedGain` tracking
        // `amplitude * patchOutputLevel`, so the envelope is only one of two per-voice
        // factors. Comparing it alone inverts on the case this repo actually ships: a
        // role muted by a Mix fader bakes velocity 0 into its notes (#174), leaving a
        // slot at envelope 0.9 that emits exact silence — which the old comparison
        // ranked as the LOUDEST tail and therefore protected, while reusing an audible
        // one instead. `patchOutputLevel` is deliberately left out: it is common to
        // every voice of a patch and cannot change a ranking.
        for i in 0..<maxVoices {
            voiceLevels[i] = voices[i].envelopeLevel * voices[i].amplitude
        }
        if let freeIdx = Self.quietestFreeSlot(voiceNotes: voiceNotes, levels: voiceLevels) {
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
    /// voices stack, the gain follows an RMS 1/√N law. Clamped to [`floorGain`,
    /// `fullGain`]. Pure — no state, no allocation, unit-testable.
    ///
    /// ⛔ THE SENTENCE THAT USED TO END THAT PARAGRAPH — "so their COHERENT sum is backed
    /// off before the safety tanh instead of slamming it" — WAS WRONG, and it is worth
    /// spelling out why, because #195 was filed on the same wrong intuition ("1/√N applies
    /// to incoherent sums; a chord sums coherently") and the obvious 'fix' would have been
    /// a regression. Measured, additive 8-harmonic voices at real intervals, 40 random
    /// phase sets each (exponent p in growth = N^p, relative to one voice):
    ///
    ///     chord            N   p(RMS) zero-phase   p(RMS) random      p(PEAK) random
    ///     octave           2        0.776           0.205 … 0.719      0.274 … 1.342
    ///     fifth            2        0.492           0.489 … 0.511      0.766 … 1.341
    ///     major triad      3        0.496           0.495 … 0.505      0.902 … 1.143
    ///     major 7th        4        0.499           0.496 … 0.504      0.883 … 1.088
    ///     five notes       5        0.499           0.497 … 0.504      0.864 … 1.014
    ///
    /// So it is EXACTLY INVERTED from the way it was written. What a chord sums coherently
    /// is its PEAK (p ≈ 1, phase notwithstanding — the partials of musically-related pitches
    /// realign every common period). Its RMS sums INCOHERENTLY at p = 0.50, to three
    /// decimals, for every chord with distinct pitches and for every phase set tried. This
    /// function controls LOUDNESS, so 1/√N is not an approximation here — it is the measured
    /// law, and raising the exponent toward 1 "because chords are coherent" would make every
    /// chord quieter than a single note by exactly the amount the founder has repeatedly
    /// reported as too thin.
    ///
    /// The octave is the one real exception (its partials coincide rather than interleave,
    /// so p(RMS) swings 0.21…0.72 with phase) and it is deliberately NOT special-cased: the
    /// octaver is an opt-in effect carrying its own mix, and a voice-count law that branched
    /// on interval content would be unpredictable to play.
    ///
    /// WHAT THIS FUNCTION THEREFORE DOES NOT DO: it does not protect the tanh. After 1/√N
    /// the peak still grows as N^0.5 — a five-note chord peaks ~2.2× a single note. That is
    /// the safety tanh's job, and the limiter's behind it. Do not extend this law to try to
    /// cover it; a makeup that flattened peak growth would flatten the dynamics of playing
    /// more notes, which is the musical gesture itself.
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
        // Per-block ease for the expression level trim (#230). Same shape as the makeup
        // gain's, block-size-independent, and hoisted out of the voice loop because it does
        // not depend on the voice. τ = 40 ms: long enough that a 1.5 dB glide step is a ramp
        // rather than a click, short enough that it still reads as the finger's own movement.
        let trimCoeff = 1 - exp(-Float(frameCount) / sampleRate / 0.04)

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
            // Count only voices that CARRY LEVEL. Since #174 a Mix fader at 0 bakes velocity 0
            // into the note, so a slot can be occupied by a note that renders exact zeros. Before
            // that fix such a note was audible WITH BIO ON, so counting it was honest in the mode
            // the product actually runs in — with bio off it was always silent and counting it was
            // always wrong, which is the half this gate fixes retroactively. Counting it now would
            // make muting one role quieter the others — 6 slots at 0.85/√6 = 0.347 instead of
            // 4 at 0.425, i.e. the pad loses ~1.8 dB because you muted the lead.
            //
            // It still RENDERS (deliberately — the guard is on the counter, not the loop): the
            // envelope has to keep advancing or a silent voice never finishes its release,
            // `isActive` stays true, and the slot leaks for the rest of the session.
            //
            // Gated on `amplitude`, NOT on `velocityGain`, even though both are zero for a muted
            // note today: `amplitude` is the value actually multiplied into the render gain in
            // BOTH modes, so if a future level path ever writes it without touching
            // `velocityGain`, this counter stays in step with what is audible instead of
            // silently desyncing.
            if voices[i].amplitude > 1e-5 { soundingVoices += 1 }

            // Fan the cutoff to the voice before it renders (all on the one audio thread):
            // the GLOBAL scale (automation, whole instrument) MULTIPLIED by this voice's own
            // PER-NOTE expression (where its finger is). Product clamped to the same bounds
            // either factor obeys, so two legal values can never compound past the range the
            // filter is designed for. Both default to 1 ⇒ bit-identical to before.
            voices[i].renderCutoffScale = Self.clampExpressionScale(cutoffScale * voiceCutoffScale[i])
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

            // Mix into stereo buffers (vDSP accelerated, zero allocation).
            // The expression level trim (#230) folds into the pan gains rather than into the
            // voice's `amplitude`: `amplitude` is owned by velocity and by the bio apply
            // (#174/#177), and a second writer there would re-open exactly the overwrite bug
            // those two closed. TWO multiplies per voice per block — one per channel — plus the
            // one-pole step below, and no branch. (The first version of this line said "one
            // multiply … no arithmetic", which contradicted itself inside one sentence; a
            // multiply is arithmetic, and there are two of them.)
            //
            // The ease uses the SAME per-block coefficient the poly makeup gain does, derived
            // from `frameCount`/`sampleRate` so the time constant is real seconds and not a
            // buffer-size accident. τ is shorter than the makeup's 0.25 s because this must
            // track a finger, not a chord: ~40 ms removes the step without smearing a glide.
            // Both arrays hold 1 when the trim is off ⇒ still bit-identical.
            voiceLevelTrimSmoothed[i] += trimCoeff * (voiceLevelTrim[i] - voiceLevelTrimSmoothed[i])
            let trim = voiceLevelTrimSmoothed[i]
            var lg = leftGain * trim
            var rg = rightGain * trim

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
            voiceLevelTrim[i] = 1
            voiceLevelTrimSmoothed[i] = 1
        }
        ageCounter = 0
        polyMakeupGain = 0.85   // back to single-voice full gain; render eases from here
    }
}
#endif // canImport(Accelerate)
