import Foundation

/// Ordered, audio-thread-safe composition of the EchoelFX processors — the unit
/// the render block, UI, and (later) AUv3 wrapper drive. Signal flow:
///
///   in → filter → saturation → tape → bitcrush → harmonizer → chorus → flanger → phaser → tremolo → granular → delay → reverb → widener → compressor → limiter → out
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
    /// Granular texture. Sits AFTER harmony and modulation and BEFORE the time
    /// effects on purpose: grains inherit the pitch and movement above them, and
    /// the delay/reverb below then place those grains in a room. Put it last and
    /// it would only smear a finished mix.
    public let granular: EchoelGranular
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
    /// Granular texture. Off by default, and its own `mix` also defaults to 0, so
    /// the stage is inert twice over until something deliberately opens both.
    public var granularEnabled: Bool = false {
        willSet { if newValue && !granularEnabled { granular.reset() } }
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
    /// `filterL/filterR.cutoff` becomes an internal audio mirror written ONLY by
    /// `advanceFilterGlide` and `snapFilterToTarget` in this file. Same shape
    /// `EchoelDelay` already uses for its read tap. (`filterL.mode` is the exception and
    /// is still written from outside — it is discrete, so there is nothing to glide.)
    ///
    /// Writers: the UI fader and the 30 Hz driver GLIDE; `setFilter`, `reset()`,
    /// `filterEnabled`'s rising edge and a render resume after `noteRenderSkipped()` SNAP.
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
    /// Set by `noteRenderSkipped()`, consumed by the next `advanceFilterGlide`. Written
    /// and read on the AUDIO THREAD only (all FIVE call sites are inside a render block),
    /// so it needs no isolation and no atomics — it never crosses a thread. That argument
    /// is the reason `noteRenderSkipped` is internal rather than public.
    private var renderSkipped = false

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.sampleRateHz = sampleRate > 0 && sampleRate.isFinite ? sampleRate : 48000
        self.filterL = EchoelSVFilter(sampleRate: sampleRate)
        self.filterR = EchoelSVFilter(sampleRate: sampleRate)
        self.tape = EchoelTape(sampleRate: sampleRate)
        self.bitcrush = EchoelBitcrush(sampleRate: sampleRate)
        self.harmonizer = EchoelHarmonizer(sampleRate: sampleRate)
        self.granular = EchoelGranular(sampleRate: sampleRate)
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
    /// The single place the three control-plane snap edges go through (`filterEnabled`'s
    /// rising edge, `setFilter`, `reset()`). It exists in this form because each edge used
    /// to write the RAW TARGET into the SVF right after snapping the glide, so
    /// `ParamGlide.snap`'s non-finite guard was decorative on those paths. What reaches
    /// `filterL/filterR` here is always `ParamGlide.value` — the last FINITE value.
    ///
    /// ⚠️ Be precise about the stake, because the first version of this comment was not:
    /// a raw NaN in `filterL.cutoff` is NOT permanent silence. `EchoelSVFilter.process`
    /// never reads `cutoff`; it reads the derived `g`/`k`, and `updateCoefficients()`
    /// already substitutes 1 kHz / 0.3 for a non-finite input. The real cost is a filter
    /// silently parked at a substitute frequency plus a field that reads back NaN. Worth
    /// closing — one guard, one choke point — but do not repeat the silence claim.
    ///
    /// CONTROL PLANE ONLY (main thread). The audio thread performs the identical two-line
    /// snap inline in `advanceFilterGlide`'s resume branch — it must not come through
    /// here, because two threads snapping the same `ParamGlide` structs is a race with no
    /// guard on it. A new caller that is not one of the three edges above needs to think
    /// about that first.
    ///
    /// The render-side freeze paths are deliberately NOT served from here. Every way a
    /// block can skip this chain (`hasEverSounded`, the 2.5 s `renderIdle` skip, the
    /// `fxEnabled` gate — five call sites across the two voices) is decided ON the audio
    /// thread, where there is no control-plane edge to hook. Those use
    /// `noteRenderSkipped()` instead — and, at the moment the idle skip decides to SLEEP,
    /// `noteRenderSleeping()`, which for this same reason drains stages directly and does
    /// not route through here either (#389).
    func snapFilterToTarget() {
        cutoffGlide.snap(to: filterCutoff)
        resonanceGlide.snap(to: filterResonance)
        let c = cutoffGlide.value, q = resonanceGlide.value
        filterL.cutoff = c;    filterR.cutoff = c
        filterL.resonance = q; filterR.resonance = q
    }

    /// Tell the chain that the caller's render block ran but SKIPPED this chain.
    ///
    /// The tone-filter glide only advances when a block reaches it, so any path that
    /// returns before `processBuffer`/`processBufferMono` freezes the glide while the
    /// control-plane target keeps moving under the UI fader and the 30 Hz bio driver. On
    /// resume, the first audible thing would be a 50 ms resonant sweep out of a value the
    /// user last heard seconds — or minutes — ago.
    ///
    /// **FIVE such call sites exist today** — `PolySynthVoice`'s `hasEverSounded` guard,
    /// its 2.5 s `renderIdle` skip and its `fxEnabled` gate; `BioReactiveSynthVoice`'s
    /// `hasEverSounded` guard and its `fxEnabled` gate. (An earlier draft of this comment
    /// said four, having counted the `fxEnabled` gate once for both voices — the same
    /// blind spot that made the previous two rounds of this fix incomplete. Count the
    /// call sites, not the kinds.) Only the `fxEnabled` kind has a control-plane setter
    /// that could snap instead; `hasEverSounded` and `renderIdle` are decided on the
    /// AUDIO thread, so there is nothing on the main thread to hook. Hence one flag, set
    /// wherever the skip is decided, consumed by the next block that reaches the filter.
    ///
    /// SCOPE, so this does not read as more than it is: it restores the tone-filter
    /// GLIDE only. The time-based stages (delay, reverb, tape) also freeze across a skip
    /// and can burst stale audio on resume — this file's own switch-crackle rule at the
    /// top — and that is deliberately left alone HERE, because this hook runs on every
    /// skipped block and a buffer clear per block is the wrong bill. #389 shipped that
    /// slice as `noteRenderSleeping()` just below, for the 2.5 s idle sleep only; the
    /// `fxEnabled` gate is still untreated and is named there.
    ///
    /// Audio-thread safe: a single Bool store, no allocation, no locks, no isolation
    /// crossing. Internal, not public, for the same reason `processStereo` was narrowed:
    /// `renderSkipped`'s whole correctness argument is "audio thread only", and a
    /// main-thread caller would break it with no symptom louder than one extra snap.
    /// A chain whose caller never calls this behaves exactly as before.
    @inline(__always)
    func noteRenderSkipped() {
        renderSkipped = true
    }

    /// Tell the chain that its caller is going to SLEEP — not that one more block was skipped.
    ///
    /// #389, and it is the SWITCH-CRACKLE RULE at the top of this file applied one level up.
    /// That rule already says a skipped stage freezes holding old audio and must be reset on the
    /// edge, or re-enabling it bursts stale audio into the mix. `PolySynthVoice`'s 2.5 s idle
    /// skip does exactly that to the WHOLE chain, and nothing reset anything — the gap
    /// `noteRenderSkipped`'s SCOPE paragraph above names and leaves for its own slice. This is
    /// that slice.
    ///
    /// ⭐ THE HOLE IS THE TANK AT LOW MIX, not the tail. The idle skip measures the chain's
    /// OUTPUT, so with `reverb.mix` (or `delay.mix`) near zero the output can sit under the
    /// floor while the stage still holds energy. Sleep then freezes it while the 30 Hz bio
    /// driver keeps writing parameters, and the next thing that raises the mix walks
    /// seconds-old audio out. #386 made that reachable in ordinary play by giving every
    /// sounding chain a bio path to those mixes; before it, nothing moved them mid-take.
    /// The tails themselves were never at risk — they decay monotonically, so while audible
    /// they hold the output above the floor and the sleep counter never fills.
    ///
    /// ⛔ NOT `reset()` — AND THE FIRST VERSION OF THIS METHOD CALLED IT. That version was a
    /// ship blocker, and this paragraph exists so the "obvious" one-liner is not written a
    /// second time. `reset()` is documented CONTROL PLANE ONLY ninety lines above
    /// (`snapFilterToTarget`: "two threads snapping the same `ParamGlide` structs is a race with
    /// no guard on it"), and it resets ALL FOURTEEN stages UNCONDITIONALLY (thirteen
    /// until #687 added granular; `filterL`/`filterR` count as one). The second half is
    /// the worse one: the SWITCH-CRACKLE RULE at the top of this file is safe only because the
    /// control thread resets a stage exclusively while its flag is still FALSE — i.e. exactly
    /// when the audio thread is not touching it. An unconditional reset from the audio thread
    /// clears DISABLED stages too, so both threads can be inside `EchoelReverb.combBufL`'s
    /// zero-fill at the same instant: a Swift exclusivity trap on concurrent `modify`, and —
    /// worse than a crash — an index cleared against a half-cleared buffer, which is a
    /// stale-audio burst produced by the fix for stale-audio bursts.
    ///
    /// DRAINING ONLY THE ENABLED STAGES keeps the two threads' reset sets DISJOINT and needs no
    /// new invariant: the control thread resets a stage only while its flag is false, the audio
    /// thread only while it is true. It is not a compromise, either — a disabled stage's frozen
    /// content is already cleared on its own rising edge by that same rule, which is the whole
    /// point of it. If a stage is added later it arrives with its own enable flag and its own
    /// rising-edge reset; add its line here in the same commit.
    ///
    /// NO `snapFilterToTarget()`: `renderSkipped = true` alone already makes
    /// `advanceFilterGlide`'s resume branch perform the identical two-line snap INLINE, on the
    /// audio thread — the sanctioned path, and the one the prohibition points at. The old
    /// sequence cleared that flag inside `reset()` and immediately re-armed it here; the churn
    /// only existed because the entry point was wrong.
    ///
    /// ⚠️ SCOPE — read this before assuming the chain-level gap is closed. This covers the 2.5 s
    /// idle sleep ONLY. `PolySynthVoice.setFXEnabled(false)` bypasses the WHOLE chain and freezes
    /// it in exactly the same way — the canonical switch-crackle case one level up, and the one
    /// whole-chain bypass switch still untreated. It is the EASY one (it HAS a control-plane
    /// setter, so it drains before raising the flag and is race-free by the rule above) and it is
    /// its own slice, not this one. The two `hasEverSounded` sites need nothing at all: one-way
    /// latches, and the chain has never been fed when they fire.
    ///
    /// Audio-thread safe, and the arithmetic belongs here because this is the most expensive
    /// thing on the path. Every stage `reset()` is a zero-fill of pre-allocated storage plus
    /// scalar stores — no allocation, no locks, no isolation crossing. Counted at 48 kHz:
    /// `EchoelDelay` DOMINATES at 262,144 floats (two `EchoelDelayLine`s, each rounding
    /// ceil(2.0 s × 48 k) + 4 up to the next power of two = 131,072), which is 9.5× the reverb's
    /// 27,688 (8 combs + 4 all-passes × 2 channels, Freeverb tunings scaled from 44.1 k).
    /// **Granular 131,072** (two lines × 65,536, one second per side — the SECOND largest
    /// entry, 4.7× the reverb and half the delay; an enabled granular takes the everyday
    /// bill from ~36 k stores to ~167 k) · harmonizer 32,768 · tape 8,192 · chorus 8,192 ·
    /// flanger 2,048. Granular was added to the drain by #687 and to THIS TABLE only by
    /// #688 — adding a stage to the drain without adding its line here is exactly the
    /// failure the ⛔ below was written to prevent.
    ///
    /// ⛔ THE FIRST VERSION OF THAT COUNT READ "the dominant cost is `EchoelReverb`, ≈40 k float
    /// stores, tens of microseconds against a ~5 ms deadline". Three numbers, three wrong: 40 k
    /// is neither the reverb (27,688) nor the whole drain; the dominant stage is the DELAY by an
    /// order of magnitude; and the default deadline is 512 frames = 10.67 ms, not 5 ms (5.33 ms
    /// is `LatencyMode.low`). The wrong dominant stage was the dangerous one — a later session
    /// optimising "the reverb" would have left most of the cost untouched.
    ///
    /// The everyday bill is far below even the corrected total, because `delayEnabled` defaults
    /// to false: a typical sounding chain drains reverb + chorus, ~36 k stores, tens of
    /// microseconds — paid ONCE per sleep (at most every 2.5 s), not per block. That is why the
    /// drain lives here and not in `noteRenderSkipped`, which runs on every skipped block.
    func noteRenderSleeping() {
        if filterEnabled     { filterL.reset(); filterR.reset() }
        if tapeEnabled       { tape.reset() }
        if bitcrushEnabled   { bitcrush.reset() }
        if harmonizerEnabled { harmonizer.reset() }
        if chorusEnabled     { chorus.reset() }
        if flangerEnabled    { flanger.reset() }
        if phaserEnabled     { phaser.reset() }
        if tremoloEnabled    { tremolo.reset() }
        // ⚠️ THE SITE A CARELESS WIRING MISSES. This stage holds a one-second ring buffer,
        // the SECOND largest in the chain — 131,072 floats against the delay's 262,144.
        //
        // ⛔ The first version called it "the longest in the chain" and said the drain
        // "matters here more than anywhere else". Both false, neither measured: `EchoelDelay`
        // defaults to `maxDelaySeconds: 2.0` and the chain takes that default. Worse on the
        // AUDIBLE reading, which is the one that matters — what a woken stage sprays is how
        // far BACK it reads, and granular's grains sit `1 + rand·spray` behind the head with
        // spray defaulting to 0.05 s, so it wakes with ~50 ms of stale audio while a typical
        // delay wakes with hundreds. The ⛔ block in the doc above is a retraction of an
        // EARLIER wrong version of this same arithmetic, whose stated lesson was that naming
        // the wrong dominant stage is the dangerous half. Written directly beneath it, and
        // then repeated in three files. The drain line is right; only the superlative was
        // invented, and inventing one is easier than checking two constructor defaults.
        if granularEnabled   { granular.reset() }
        if delayEnabled      { delay.reset() }
        if reverbEnabled     { reverb.reset() }
        if widenerEnabled    { widener.reset() }
        if compressorEnabled { compressor.reset() }
        if limiterEnabled    { limiter.reset() }
        renderSkipped = true
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
        if renderSkipped {
            // The caller skipped this chain for an unknown span of wall time, so the
            // glide's stored value is stale by an unknown amount. Gliding from it would
            // sweep; the honest resume is to land. Same reasoning as `reset()` — there is
            // nothing to glide FROM.
            renderSkipped = false
            cutoffGlide.snap(to: filterCutoff)
            resonanceGlide.snap(to: filterResonance)
        } else {
            if frameCount != glideCoefficientFrames {
                glideCoefficient = ParamGlide.coefficient(
                    tauSeconds: ParamGlide.bioTau,
                    stepRateHz: sampleRateHz / Float(frameCount))
                glideCoefficientFrames = frameCount
            }
            cutoffGlide.advance(toward: filterCutoff, coefficient: glideCoefficient)
            resonanceGlide.advance(toward: filterResonance, coefficient: glideCoefficient)
        }
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
        if granularEnabled   { (l, r) = granular.processStereo(l, r) }
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

    /// Process raw L/R pointers in place — the entry point the V1a monitor insert's
    /// `internalRenderBlock` needs (#822, mechanism decided at #669). An `AUAudioUnit` render
    /// block receives an `AudioBufferList`, not Swift `Array`s, so `processBuffer(left:right:)`
    /// cannot be called from it without a copy on the audio thread. This is the SAME law as
    /// `processBuffer`, one definition (#416): glide once per block, then `processStereo` per
    /// sample. No allocation, no lock, no copy.
    ///
    /// ⚠️ CALLER CONTRACT, stated because a pointer cannot state it: both pointers must be
    /// valid for at least `frameCount` floats. `processBuffer` clamps to `min(count)` because
    /// an `Array` knows its length; a pointer does not, so the render block that calls this
    /// owns the bound (it gets the true frame count from the render call itself).
    public func processInPlace(left: UnsafeMutablePointer<Float>,
                               right: UnsafeMutablePointer<Float>,
                               frameCount: Int) {
        guard frameCount > 0 else { return }
        advanceFilterGlide(frameCount: frameCount)
        for i in 0..<frameCount {
            let (l, r) = processStereo(left[i], right[i])
            left[i] = l
            right[i] = r
        }
    }

    // MARK: - Reset

    public func reset() {
        // SNAP, second of the three edges. `reset()` means "the signal path is empty" —
        // there is nothing to glide FROM, so gliding here would sweep the first audio
        // after the reset up from a stale value. The targets themselves are untouched:
        // reset clears state, it does not change what the user set.
        snapFilterToTarget()
        // …and a pending skip is state too. Leaving it set would make the first block
        // after a reset snap a second time — bounded and harmless, but `reset()` is the
        // one method that claims to return the chain to a defined state.
        renderSkipped = false
        filterL.reset()
        filterR.reset()
        tape.reset()
        bitcrush.reset()
        harmonizer.reset()
        chorus.reset()
        flanger.reset()
        phaser.reset()
        tremolo.reset()
        granular.reset()
        delay.reset()
        reverb.reset()
        widener.reset()
        compressor.reset()
        limiter.reset()
    }
}
