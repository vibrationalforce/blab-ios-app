// GenreFX.swift
// Echoel — the *space* behind each genre. GenrePatches gives a take the right
// timbre; this gives it the right effects: the long tempo-synced dub delay, the
// vaporwave chorus wash, the psytrance ping-pong roll, the sci-fi phaser sweep.
// Applied to the melody voice's EchoelFXChain on Generate so a take sounds like
// its reference out of the box, then stays fully editable in the FX tool.
//
// LOCATION: Sequencer/ (not DSP/) on purpose — it depends on MusicStyle, which
// the AUv3 target does not glob. See GenrePatches.swift for the same constraint.
//
// Pure value type: delay time is a musical NoteDivision (via TempoSyncOption), so
// the echo locks to the take's BPM. `apply(to:bpm:)` is the only side-effecting
// call and it just writes already-clamped scalars onto the (audio-thread-safe)
// chain — no allocation, no locks.

import Foundation

/// The effect colour for one genre: a tempo-synced delay plus optional chorus and
/// phaser. Resolved against a BPM at apply time.
public struct GenreFXPreset: Sendable, Equatable {

    // Filter — tone colour (underwater low-pass, telephone band-pass, lo-fi).
    public var filterEnabled: Bool
    public var filterMode: EchoelSVFilter.Mode
    public var filterCutoff: Float
    public var filterResonance: Float

    // Delay — the defining space (dub, psy, Berlin-school sequencer echo).
    public var delayEnabled: Bool
    public var delayMode: EchoelDelay.Mode
    /// Echo time as a note division, resolved to seconds at the take's BPM.
    public var delaySync: TempoSyncOption
    public var delayMix: Float
    public var delayFeedback: Float
    public var delayTone: Float        // 0 dark … 1 bright
    public var delaySpread: Float      // stereo width on the right tap
    public var delayWow: Float         // tape pitch wobble (only audible in .tape)
    public var delayDrive: Float       // tape feedback saturation (.tape)

    // Chorus — width / shimmer (80s, vaporwave, synthwave).
    public var chorusEnabled: Bool
    public var chorusRate: Float
    public var chorusDepth: Float
    public var chorusMix: Float

    // Phaser — sweep / motion (sci-fi).
    public var phaserEnabled: Bool
    public var phaserRate: Float
    public var phaserDepth: Float
    public var phaserMix: Float

    // Saturation — analog warmth. The additive synth is a clean sine stack; a
    // little drive gives it harmonic body so a take sounds professional, not
    // thin and digital. 0 disables (a truly dry "Clean").
    public var saturation: Float

    // Harmonizer — pitch-shifted harmony voices. Off in every genre preset; the
    // `.harmonizer` character turns it on. Carried here so every preset apply
    // explicitly settles the harmonizer state (no sticky-on when switching).
    public var harmonizerEnabled: Bool
    public var harmonizerInterval1: Float
    public var harmonizerInterval2: Float
    public var harmonizerVoice2: Bool
    public var harmonizerMix: Float

    // Reverb — real algorithmic room/hall space. The additive source has no
    // reverb of its own, so this is where a take gets its "produced" depth.
    public var reverbEnabled: Bool
    public var reverbMix: Float
    public var reverbRoom: Float
    public var reverbDamping: Float

    public init(
        filterEnabled: Bool = false,
        filterMode: EchoelSVFilter.Mode = .lowpass,
        filterCutoff: Float = 20_000,
        filterResonance: Float = 0.2,
        delayEnabled: Bool = false,
        delayMode: EchoelDelay.Mode = .digital,
        delaySync: TempoSyncOption = TempoSyncOption(.quarter),
        delayMix: Float = 0.25,
        delayFeedback: Float = 0.30,
        delayTone: Float = 0.5,
        delaySpread: Float = 0.0,
        delayWow: Float = 0.0,
        delayDrive: Float = 0.0,
        chorusEnabled: Bool = false,
        chorusRate: Float = 0.4,
        chorusDepth: Float = 0.5,
        chorusMix: Float = 0.4,
        phaserEnabled: Bool = false,
        phaserRate: Float = 0.2,
        phaserDepth: Float = 0.6,
        phaserMix: Float = 0.4,
        saturation: Float = 0.30,
        harmonizerEnabled: Bool = false,
        harmonizerInterval1: Float = 4,
        harmonizerInterval2: Float = 7,
        harmonizerVoice2: Bool = true,
        harmonizerMix: Float = 0.5,
        reverbEnabled: Bool = false,
        reverbMix: Float = 0.0,
        reverbRoom: Float = 0.72,
        reverbDamping: Float = 0.5
    ) {
        self.filterEnabled = filterEnabled
        self.filterMode = filterMode
        self.filterCutoff = filterCutoff
        self.filterResonance = filterResonance
        self.delayEnabled = delayEnabled
        self.delayMode = delayMode
        self.delaySync = delaySync
        self.delayMix = delayMix
        self.delayFeedback = delayFeedback
        self.delayTone = delayTone
        self.delaySpread = delaySpread
        self.delayWow = delayWow
        self.delayDrive = delayDrive
        self.chorusEnabled = chorusEnabled
        self.chorusRate = chorusRate
        self.chorusDepth = chorusDepth
        self.chorusMix = chorusMix
        self.phaserEnabled = phaserEnabled
        self.phaserRate = phaserRate
        self.phaserDepth = phaserDepth
        self.phaserMix = phaserMix
        self.saturation = saturation
        self.harmonizerEnabled = harmonizerEnabled
        self.harmonizerInterval1 = harmonizerInterval1
        self.harmonizerInterval2 = harmonizerInterval2
        self.harmonizerVoice2 = harmonizerVoice2
        self.harmonizerMix = harmonizerMix
        self.reverbEnabled = reverbEnabled
        self.reverbMix = reverbMix
        self.reverbRoom = reverbRoom
        self.reverbDamping = reverbDamping
    }

    /// Delay-line capacity in the chain (EchoelDelay default). The synced time is
    /// clamped to this so a whole note at a slow tempo never overruns the buffer.
    ///
    /// ⛔ RAISING THIS DOES NOT DO WHAT THE FIRST VERSION OF THIS DOC CLAIMED, and getting the
    /// attribution right matters more than the recommendation. That version gave two reasons not
    /// to raise it and BOTH were attached to the wrong constant. There are FOUR `2.0` literals
    /// on this path (the first version said three) and they are not linked:
    ///
    ///  · THIS one — a pure clamp inside `apply`. It allocates nothing.
    ///  · `EchoelDelay.init(maxDelaySeconds: Float = 2.0)` (`EchoelDelay.swift`) — the one that
    ///    SIZES the buffer, and the one `EchoelFXChain` uses (it constructs
    ///    `EchoelDelay(sampleRate:)`, i.e. the default). `EchoelDelayLine` rounds up to a power
    ///    of two: 2.0 s at 48 kHz wants 96 004 samples → 131 072 → 512 KB/channel; 6.0 s wants
    ///    288 004 → 524 288 → 2 MB/channel, ×2 channels × every chain that exists. ⚠️ The chain
    ///    inventory named here was wrong: `EchoelFXChain` is CONSTRUCTED at exactly four sites —
    ///    `BioReactiveSynthVoice`, `PolySynthVoice` (so once per `LaneVoiceRack` voice too, behind
    ///    `FeatureFlags.multiRoll`) and twice in `FXCuratedLibrary`. `EchoelFXView` builds NONE:
    ///    it is INJECTED one (`synth.fxChain`).
    ///  · `EchoelDelayLine.init(maxDelaySeconds: Float = 2.0)` — inert for this path, because
    ///    `EchoelDelay` always passes explicitly. Listed anyway: the point of this paragraph is
    ///    to stop the next reader mis-attributing a literal, and this is the one they will hit.
    ///  · `EchoelStudioView.applyDelaySync(bpm:)`, which hardcodes `0.001...2.0` for the USER's
    ///    delay-division picker — and per the note below that is the ceiling a listener actually
    ///    meets.
    ///
    /// TWO CONSEQUENCES the first version hid:
    ///  1. Raising THIS constant costs no memory at all. `maxDelaySamples = capacity - 2` =
    ///     131 070 = **2.7306 s** of usable line at 48 kHz, so anything up to ~2.73 s is already
    ///     paid for. Past that, `EchoelDelayLine.read`'s own clamp catches it — a longer
    ///     authored value would silently truncate one layer down instead of here.
    ///     ⚠️ AND 2.7306 s IS THE LEFT TAP ONLY. `EchoelDelay.processStereo` offsets the right
    ///     tap by `spread * 0.025 * sr` (up to 25 ms) and, in `.tape`, by up to ±4.6 ms of
    ///     wow — both BEFORE the line's clamp. Every shipped genre sets a non-zero
    ///     `delaySpread`, so the right channel's un-clamped ceiling is ≈2.706 s (less in tape
    ///     mode). Raising to "~2.73" would truncate the right channel only: the delay collapses
    ///     toward MONO at the top of its range, which is a miserable thing to diagnose.
    ///  2. `PolySynthVoice.idleFrameThreshold` (2.5 s) derives from `EchoelDelay`'s ceiling, not
    ///     from this one — the render may only sleep after a window longer than the longest
    ///     possible echo gap, or a sparse repeat freezes mid-train and pops out on the next
    ///     note-on. That coupling is real but UNENFORCED and already violated: `FXPreset`
    ///     decodes `delayTime` with no bound (`FXPreset.swift`) and writes it straight to
    ///     `chain.delay.timeSeconds`, so a hand-edited or community `.echoelfx` can produce a
    ///     2.73 s gap today. Do not read the 2.5 s as a guaranteed invariant.
    ///
    /// The recommendation survives all of that: the honest fix for a truncated echo is to author
    /// a division that RESOLVES inside the genre's own tempo window, because that keeps the echo
    /// on the musical grid instead of flat — guarded by
    /// `Tests/CISmoke/GenreDelaySyncResolvabilityTests`. (That test reads the ceiling back through
    /// `apply` precisely because this is `private`; it does not need to be widened.) But if you
    /// DO want a longer one, this constant up to ~2.73 s is the cheap move, and moving the other
    /// two is a separate, bigger decision.
    private static let maxDelaySeconds: Float = 2.0

    /// Write this preset onto a live chain, resolving the synced delay time at
    /// `bpm`. Safe to call from the main actor; the chain reads are audio-thread
    /// atomic-width scalars.
    ///
    /// ⛔ ONE LINE BELOW HAS NO AUDIBLE EFFECT IN THE APP TODAY: `chain.delay.timeSeconds`, the
    /// one `delaySync` resolves to. ⚠️ SCOPED DELIBERATELY — the first version of this paragraph
    /// said "the `delaySync` LINE … and every comment about what a genre's echo sounds like",
    /// which swept the whole delay block into the same framing and invited the conclusion that
    /// all of it is inert. It is not: `delayMode`, `delayMix`, `delayFeedback`, `delayTone`,
    /// `delaySpread`, `delayWow` and `delayDrive` — seven of the eight delay fields, and most of
    /// what "the genre's echo sounds like" (tape-with-wow versus ping-pong, feedback depth,
    /// darkness, width) — all reach the audio today. Only the TIME does not.
    ///
    /// Three sites stamp a genre/character preset — `EchoelStudioView.applyFX()`, the re-seed
    /// path and the open-take path — and each calls `applyDelaySync(bpm:)` IMMEDIATELY
    /// afterwards, over the SAME chain inventory, writing the view's `@State delaySync` (the
    /// user's delay-division picker, default dotted 1/8) over `chain.delay.timeSeconds`.
    ///
    /// ⚠️ "So the picker is the last writer, ALWAYS" was the first version's wording and it is
    /// FALSE. `EchoelFXView.applyCharacter` is a FOURTH stamp site, reachable from the FX
    /// panel's character menu, and NO `applyDelaySync` follows it — so after tapping Cassette or
    /// Dream the CHARACTER's division is the last writer and the Studio picker displays a time
    /// the chain does not hold. It also writes only the injected chain (`synth.fxChain`), never
    /// `touchSynth?.fxChain` — #240's other half, on a surface #240 did not reach. A genre
    /// preset is not involved (`.auto` is filtered out of that menu), so the claim below about
    /// GENRE divisions still stands; the absolute did not. Whoever implements the routing fix
    /// must cover four sites, not three.
    ///
    /// That is DELIBERATE, not a bug to undo here: it is the resolution of #240, guarded by
    /// `Tests/CISmoke/DelayReachesEveryChainTests` — a visible control must not display one
    /// division while the chain plays another, and `delaySync` is not part of the saved
    /// `Project`, so restoring a genre's division would be a schema change.
    ///
    /// The consequence is nonetheless a real, unfixed defect: **29 authored per-genre delay
    /// divisions never reach the audio, and every genre shares whatever one division the picker
    /// holds.** That is a far bigger delay-axis collapse than any preset-level tuning, and it is
    /// tracked separately as a founder decision (the honest fix is for a genre change to SET
    /// `delaySync` so the picker shows the genre's own division and then stamps it — making both
    /// true instead of picking a winner).
    ///
    /// So the per-genre `delaySync` values are today a SOURCE-level contract: they must be
    /// resolvable and they must be distinct, so that they are correct on the day the routing is
    /// fixed. `GenreDelaySyncResolvabilityTests` guards exactly that and nothing more.
    public func apply(to chain: EchoelFXChain, bpm: Double) {
        chain.filterEnabled = filterEnabled
        chain.setFilter(mode: filterMode, cutoff: filterCutoff, resonance: filterResonance)

        chain.delayEnabled = delayEnabled
        chain.delay.mode = delayMode
        chain.delay.timeSeconds = delaySync.clampedSeconds(bpm: bpm, in: 0.001...Self.maxDelaySeconds)
        chain.delay.mix = delayMix
        chain.delay.feedback = delayFeedback
        chain.delay.tone = delayTone
        chain.delay.spread = delaySpread
        chain.delay.wow = delayWow
        chain.delay.drive = delayDrive

        chain.chorusEnabled = chorusEnabled
        chain.chorus.rate = chorusRate
        chain.chorus.depth = chorusDepth
        chain.chorus.mix = chorusMix

        chain.phaserEnabled = phaserEnabled
        chain.phaser.rate = phaserRate
        chain.phaser.depth = phaserDepth
        chain.phaser.mix = phaserMix

        chain.saturationEnabled = saturation > 0
        chain.saturationDrive = saturation

        chain.harmonizerEnabled = harmonizerEnabled
        chain.harmonizer.interval1 = harmonizerInterval1
        chain.harmonizer.interval2 = harmonizerInterval2
        chain.harmonizer.voice2Enabled = harmonizerVoice2
        chain.harmonizer.mix = harmonizerMix

        chain.reverbEnabled = reverbEnabled
        chain.reverb.mix = reverbMix
        chain.reverb.roomSize = reverbRoom
        chain.reverb.damping = reverbDamping
    }
}

public extension MusicStyle {

    /// The effect space this genre is generated through. Applied to the melody
    /// voice on Generate, then editable in the FX tool.
    ///
    /// ROOM FLOOR (audit A3 — "instrument is bone dry, in a box"): every REAL production
    /// happens in SOME space; 12 of the genre presets specified no reverb at all, which
    /// left jazz/klezmer/rock playing in a vacuum — the "buzzy/flat" additive fingerprint.
    /// Genres that DESIGN their reverb keep it exactly; the dry ones get a subtle room
    /// (mix 0.10 — felt as depth, not heard as hall). Character presets (telephone,
    /// cassette …) are a different path and stay intentionally dry.
    var fxPreset: GenreFXPreset {
        var p = rawFXPreset
        if !p.reverbEnabled {
            p.reverbEnabled = true
            p.reverbMix = 0.10
            p.reverbRoom = 0.48
            p.reverbDamping = 0.55
        }
        return p
    }

    private var rawFXPreset: GenreFXPreset {
        switch self {
        case .dubTechno:
            // The signature: a long, dark, swung dub delay with high feedback,
            // plus a slow chorus wobble on the chord.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.42, delayFeedback: 0.58, delayTone: 0.22, delaySpread: 0.45,
                chorusEnabled: true, chorusRate: 0.35, chorusDepth: 0.5, chorusMix: 0.4,
                reverbEnabled: true, reverbMix: 0.22, reverbRoom: 0.82, reverbDamping: 0.60)
        case .acidTechno:
            // #254 — THE RESONANT FILTER IS THE POINT, and it is the reason this preset does not
            // look like psytrance's. First draft gave acid a ping-pong SIXTEENTH delay, which is
            // character-for-character `psytrance`'s preset below — a new genre that copies a
            // hidden one is the "more options that sound the same" defect (#81/#125), even though
            // no test would have caught it (psytrance is not `offered`, so the distinctness sweep
            // never compares them).
            // acidTechno is now the ONLY genre that enables the chain FILTER at all: a resonant
            // lowpass ON TOP of the patch's own resonance is the 303 squelch, and nothing else in
            // the roster sounds like it. Resonance 0.62 sits well inside `EchoelSVFilter`'s
            // 0.01…0.95 clamp (it is also NaN-guarded there), so it bites without ringing.
            // The delay is a short straight-EIGHTH digital slap — deliberately NOT psytrance's
            // rolling 16th ping-pong — plus real saturation (the 303's drive is half its sound)
            // and a tiny room. No chorus: width would soften exactly what should bite.
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass,
                filterCutoff: 1300, filterResonance: 0.62,
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.14, delayFeedback: 0.24, delayTone: 0.50, delaySpread: 0.20,
                saturation: 0.48,
                reverbEnabled: true, reverbMix: 0.10, reverbRoom: 0.34, reverbDamping: 0.64)
        case .deepHouse:
            // #254 — the warm counterpart: a dotted-eighth digital echo that answers the
            // offbeat chord, a gentle chorus for the 7th's shimmer, and a big soft room. Low
            // saturation, because the character here is space, not drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.26, delayFeedback: 0.32, delayTone: 0.52, delaySpread: 0.38,
                chorusEnabled: true, chorusRate: 0.30, chorusDepth: 0.42, chorusMix: 0.30,
                saturation: 0.22,
                reverbEnabled: true, reverbMix: 0.30, reverbRoom: 0.78, reverbDamping: 0.44)
        case .upliftingTrance:
            // #254 batch 3 — THE BIG BRIGHT SPACE, the opposite pole to techHouse below on every
            // axis they could share. A dotted-8th digital ping (0.326 s at 138 BPM, resolving
            // un-clamped across the whole 136…144 window — the division is shared with deepHouse,
            // the space around it is not), wide, and the LEAST-DAMPED reverb of any offered genre:
            // 0.30, just under drift's 0.35. The sus pad needs air above it or the suspension
            // reads as mud. Chorus ON for supersaw-ish width. Saturation stays moderate (0.30):
            // the lift comes from the space, not from drive.
            //
            // ⚠️ DO NOT reason about how this echo SOUNDS today — see `apply(to:bpm:)`: the delay
            // TIME never reaches the audio (a picker value overwrites it). The other seven delay
            // fields, the reverb and the chorus DO.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.26, delayFeedback: 0.38, delayTone: 0.62, delaySpread: 0.55,
                chorusEnabled: true, chorusRate: 0.35, chorusDepth: 0.40, chorusMix: 0.30,
                saturation: 0.30,
                reverbEnabled: true, reverbMix: 0.32, reverbRoom: 0.90, reverbDamping: 0.30)
        case .techHouse:
            // #254 batch 3 — DRY AND TIGHT, which is the whole contrast to `deepHouse`'s wash and
            // to trance above. The shortest delay DIVISION of any offered genre (dotted 16th =
            // 0.375 quarters, 0.177 s at 127 BPM) at a LOW mix, so it reads as slap rather than
            // space — with the same ⚠️ as trance above: per `apply(to:bpm:)` the delay TIME never
            // reaches the audio, so that is a source-level contract, not a sound.
            // The room is the SECOND smallest and second-most damped of the offered roster
            // (0.42 / 0.58) — only `acidTechno` is tighter and deader (0.34 / 0.64); every other
            // offered genre sits at 0.78 room and up. No chorus at all, because width would blur
            // the groove. Saturation 0.42 is where the punch comes from: above dubTechno (none)
            // and deepHouse (0.22), still below acidTechno's 0.48.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth, .dotted),
                delayMix: 0.16, delayFeedback: 0.28, delayTone: 0.55, delaySpread: 0.30,
                saturation: 0.42,
                reverbEnabled: true, reverbMix: 0.12, reverbRoom: 0.42, reverbDamping: 0.58)
        case .deepDrone:
            // #254 batch 2 — the DARKEST space in the product.
            //
            // ⚠️ TWO CLAIMS STOOD HERE FOR ONE COMMIT AND BOTH WERE WRONG. They were "THE
            // LONGEST ECHO IN THE PRODUCT" and "it played a flat 2.0 s that the founder hears as
            // 'die Genres klingen gleich'". Corrected, because this is the comment a session
            // reads before differentiating a calm preset on delay time:
            //  · NOT the longest. Its floor value IS 2.0 s (`.half, .triplet` at 40 BPM) — but
            //    2.0 s is the CEILING, and three other genres reach it at their own slow ends:
            //    selfObservation (half @46 = 2.61), esotericMeditation (half @50 = 2.40) and doom
            //    (half @50 = 2.40) — partial slow-end truncation, which this slice deliberately
            //    does NOT condemn (see the banner further down). Plus
            //    `FXCharacter.dream` (dotted quarter) at 40 BPM. At DEFAULT tempos this genre is
            //    not even in front: selfObservation 2.000, esotericMeditation 2.000, doom 1.935,
            //    deepDrone 1.667. "Equal to the ceiling, shared with three genres" is the truth,
            //    and it is not a differentiation axis to build on.
            //  · NOT what anyone heard. See `apply(to:bpm:)`: `applyDelaySync` overwrites the
            //    genre's delay TIME on all three stamp paths, so no genre's division reaches the
            //    audio today. The old `.whole` never played 2.0 s and the new value will not play
            //    1.667 s until that routing is fixed.
            //
            // What IS true and is why the value changed: `.whole` at 40…58 BPM is 6.0…4.14 s,
            // past the 2.0 s `maxDelaySeconds` clamp at EVERY tempo in its own window. A notated
            // division that cannot resolve anywhere is a lie in the source regardless of whether
            // anything currently listens to it.
            //
            // `.half, .triplet` (1⅓ quarters) is the LONGEST division on the `TempoSyncOption`
            // grid that resolves un-clamped across the WHOLE window: 2.0 s at 40 BPM, 1.379 s at
            // 58, 1.667 s at the 48 default. Derived from the ceiling, not chosen by ear — the
            // next grid value up (dotted quarter, 1.5) is 2.25 s at 40 and would clamp again.
            // Now the echo also TRACKS tempo, so a body that slows genuinely lengthens the space.
            //
            // ⛔ WHICH CEILING TO RAISE, IF ANY, IS NOT OBVIOUS — read `maxDelaySeconds`' own doc
            // before touching one: there are THREE unlinked `2.0` literals, only ONE of them
            // sizes the buffer, and the usable line is 2.7306 s either way. The invariant that
            // keeps this class of defect out lives in
            // `Tests/CISmoke/GenreDelaySyncResolvabilityTests`: a division that cannot resolve at
            // any tempo the genre allows is a lie in the source.
            //
            // ⚠️ 2.0 s at the 40 BPM floor lands EXACTLY on the ceiling — `min(2.0, 2.0)` does
            // not clamp, so the "un-clamped across its whole window" guarantee holds with ZERO
            // margin by construction. "The longest division that fits" means "fits exactly".
            //
            // ⚠️ A LISTENING ITEM — AND READ THE QUALIFIER, because the first version of this
            // banner dropped it and said "`selfObservation` is now the ONLY offered genre whose
            // delay is clamped". That is true only AT THE DEFAULT TEMPO, which is the bar test 3
            // sets. Per WINDOW it is false, and the same comment block says so 30 lines up:
            // `esotericMeditation`'s window is 50…70 and a half note exceeds 2.0 for every bpm
            // below 60, so HALF its window clamps too; `doom` (50…80) likewise. What is special
            // about selfObservation is only that its DEFAULT (58) is inside the clamped part.
            // At exactly 60 BPM a half note is 2.000 s and no clamp fires, so the two coincide
            // at 2.0 s there by AUTHORSHIP (same division, near-identical default tempo), not by
            // truncation — which is why this slice did not touch them. Partial slow-end
            // truncation is explicitly NOT what this slice condemns (test 1 condemns a division
            // that resolves NOWHERE; the header declines to sweep windows for untouched
            // presets), so do not tighten test 3 into a per-window sweep on the strength of this
            // note. Retuning a preset that already resolves as authored is
            // a founder decision.
            //
            // Beyond time, this preset separates on: mode (tape, with wow), the
            // darkest tone in the roster (0.14 < contemplation's 0.24), and the most DAMPED hall
            // in the roster (0.68; next is acidTechno 0.64). ⚠️ NOT the biggest — that claim stood
            // for one commit and is false: contemplation is 0.96 and drift 0.95 against this
            // preset's 0.94. Damping is what makes it dark; size is shared with its siblings. Feedback stays below 0.5 like the whole family so the
            // tail washes and never builds. No chorus: the quartal voicing already spans an
            // octave, and width on top of that smears the one thing the genre has — a still,
            // clear, low stack.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half, .triplet),
                delayMix: 0.30, delayFeedback: 0.42, delayTone: 0.14, delaySpread: 0.35,
                delayWow: 0.28, delayDrive: 0.10,
                saturation: 0.10,
                reverbEnabled: true, reverbMix: 0.44, reverbRoom: 0.94, reverbDamping: 0.68)
        case .ambientPulse:
            // #254 batch 2 — the SHORTEST echo of the calm family and the only straight quarter:
            // 0.706 s at 85 BPM. ⚠️ "The repeats interleave BETWEEN the notes" is what this line
            // first claimed, and it is backwards: `arpStep` is 4 sixteenths when calm (0.706 s)
            // and 2 when busy (0.353 s), so the echo lands exactly ON the next note, or on every
            // second one — in phase, never between. That is still the intended effect (each step
            // is reinforced by the previous one's tail, which is what thickens a sparse sequence)
            // but it is doubling, not syncopation. Say what it does. 0.706 s at 85 BPM is well
            // under the 2.0 s clamp, so this echo time is real and does change with tempo across
            // the whole 78…92 window. ⚠️ It was NOT "unlike its darker siblings" for long — that
            // clause shipped one commit and is now false: `deepDrone` and `contemplation` were
            // re-authored to divisions that also resolve un-clamped, so only `selfObservation`
            // still truncates. Brightest tone of the family
            // (0.58 > drift's 0.42) so the steps stay individually audible, a very slow chorus
            // for width, and a big but only lightly damped hall.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.34, delayFeedback: 0.44, delayTone: 0.58, delaySpread: 0.50,
                chorusEnabled: true, chorusRate: 0.12, chorusDepth: 0.48, chorusMix: 0.28,
                saturation: 0.12,
                reverbEnabled: true, reverbMix: 0.34, reverbRoom: 0.86, reverbDamping: 0.44)
        case .trap:
            // Mostly dry; just a short triplet slap for depth.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .triplet),
                delayMix: 0.16, delayFeedback: 0.20, delayTone: 0.70, delaySpread: 0.2)
        case .vaporwave:
            // Tape echo + lush slow chorus — washed-out and nostalgic.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.36, delayFeedback: 0.42, delayTone: 0.34, delaySpread: 0.4,
                delayWow: 0.5, delayDrive: 0.2,
                chorusEnabled: true, chorusRate: 0.28, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.28, reverbRoom: 0.80, reverbDamping: 0.50)
        case .eighties:
            // Big chorus, bright dotted-eighth delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.24, delayFeedback: 0.28, delayTone: 0.62, delaySpread: 0.35,
                chorusEnabled: true, chorusRate: 0.6, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.16, reverbRoom: 0.70, reverbDamping: 0.45)
        case .disco:
            // Light chorus, short tight delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.15, delayFeedback: 0.16, delayTone: 0.6, delaySpread: 0.25,
                chorusEnabled: true, chorusRate: 0.5, chorusDepth: 0.4, chorusMix: 0.3,
                reverbEnabled: true, reverbMix: 0.12, reverbRoom: 0.65, reverbDamping: 0.45)
        case .synthwave:
            // Wide ping-pong dotted-eighth + chorus — neon-night drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.30, delayFeedback: 0.38, delayTone: 0.62, delaySpread: 0.55,
                chorusEnabled: true, chorusRate: 0.4, chorusDepth: 0.6, chorusMix: 0.4,
                reverbEnabled: true, reverbMix: 0.18, reverbRoom: 0.74, reverbDamping: 0.40)
        case .earlySynth:
            // Berlin-school sequencer echo: ping-pong straight eighths.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.30, delayFeedback: 0.46, delayTone: 0.5, delaySpread: 0.6)
        case .futuristic:
            // Bright shimmering long delay + subtle chorus.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.40, delayFeedback: 0.42, delayTone: 0.82, delaySpread: 0.5,
                chorusEnabled: true, chorusRate: 0.25, chorusDepth: 0.5, chorusMix: 0.3,
                reverbEnabled: true, reverbMix: 0.26, reverbRoom: 0.82, reverbDamping: 0.35)
        case .sciFi:
            // Slow phaser sweep over a long, dark tape delay — deep space.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.45, delayFeedback: 0.50, delayTone: 0.4, delaySpread: 0.5,
                delayWow: 0.4, delayDrive: 0.15,
                phaserEnabled: true, phaserRate: 0.12, phaserDepth: 0.7, phaserMix: 0.5,
                reverbEnabled: true, reverbMix: 0.30, reverbRoom: 0.86, reverbDamping: 0.50)
        case .psytrance:
            // The psy roll: fast ping-pong sixteenth echo.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.30, delayFeedback: 0.46, delayTone: 0.6, delaySpread: 0.5)
        case .esotericMeditation:
            // Long, dark, spacious half-note delay + very slow chorus.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.40, delayFeedback: 0.45, delayTone: 0.30, delaySpread: 0.4,
                chorusEnabled: true, chorusRate: 0.15, chorusDepth: 0.5, chorusMix: 0.35,
                reverbEnabled: true, reverbMix: 0.34, reverbRoom: 0.88, reverbDamping: 0.60)
        case .classical:
            // Pristine — almost no drive, so the chamber tone stays clean.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.20, delayFeedback: 0.25, delayTone: 0.45, delaySpread: 0.30,
                saturation: 0.10,
                reverbEnabled: true, reverbMix: 0.26, reverbRoom: 0.82, reverbDamping: 0.45)
        case .jazz:
            // Warm but clean — a touch of tube glue on the Rhodes.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.16, delayFeedback: 0.20, delayTone: 0.55, delaySpread: 0.25,
                chorusEnabled: true, chorusRate: 0.30, chorusDepth: 0.3, chorusMix: 0.20,
                saturation: 0.20)
        case .klezmer:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.18, delayFeedback: 0.22, delayTone: 0.60, delaySpread: 0.30)
        case .oriental:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.30, delayFeedback: 0.40, delayTone: 0.40, delaySpread: 0.40,
                delayWow: 0.40, delayDrive: 0.15,
                reverbEnabled: true, reverbMix: 0.20, reverbRoom: 0.76, reverbDamping: 0.50)
        case .punk:
            // Raw and driven — heavy saturation for buzzsaw bite.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.10, delayFeedback: 0.12, delayTone: 0.60, delaySpread: 0.15,
                saturation: 0.45)   // trimmed from 0.60 (warmth pass) — driven, not harsh
        case .rocknroll:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.18, delayFeedback: 0.20, delayTone: 0.55, delaySpread: 0.20,
                delayWow: 0.30, delayDrive: 0.20,
                saturation: 0.45)
        case .rock:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.eighth, .dotted),
                delayMix: 0.20, delayFeedback: 0.26, delayTone: 0.55, delaySpread: 0.35,
                saturation: 0.50)
        case .ska:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.12, delayFeedback: 0.14, delayTone: 0.60, delaySpread: 0.20,
                saturation: 0.32)
        case .rocksteady:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.20, delayFeedback: 0.28, delayTone: 0.45, delaySpread: 0.25,
                delayWow: 0.35, delayDrive: 0.10)
        case .heavyMetal:
            // High-gain rig — the most driven preset.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.12, delayFeedback: 0.18, delayTone: 0.50, delaySpread: 0.20,
                saturation: 0.50)   // trimmed from 0.68 (warmth pass) — still driven, less brittle
        case .doom:
            // Thick, slow wall of drive.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.40, delayFeedback: 0.50, delayTone: 0.30, delaySpread: 0.40,
                delayWow: 0.40, delayDrive: 0.30,
                saturation: 0.55,
                reverbEnabled: true, reverbMix: 0.24, reverbRoom: 0.86, reverbDamping: 0.62)
        case .selfObservation:
            // THE Fläche (founder 2026-07-07: "Mehr atmosphärische Stimmung durch
            // Hall und Tape Delay, langsamere Vibes"): a slow, wide TAPE echo —
            // half note at ~58 BPM ≈ 2 s, gentle wow so the repeats breathe like
            // tape, a touch of drive for warmth — blooming into a big, dark hall.
            // Feedback stays < 0.5 so the tail washes without ever building up;
            // the slow chorus keeps the pad's stereo width alive between echoes.
            //
            // ⚠️ THE ONE GENRE CLAMPED AT ITS OWN DEFAULT TEMPO, deliberately left alone. A half
            // note is 2.069 s at 58 BPM — 3.5% over the 2.0 s clamp — so the time reads flat at
            // 2.0 for bpm < 60, i.e. 41% of the 46…78 window (⚠️ the first version wrote
            // "bpm ≤ 60 / 44%": at exactly 60 a half note is 2.000 s and the clamp does NOT fire,
            // the same arithmetic deepDrone's floor relies on). It coincides there with
            // `esotericMeditation` (half @60 = exactly 2.0, no clamp). Unlike the two genres
            // fixed in this slice the division DOES resolve over most of this window (56% of it),
            // so re-authoring it would change a preset that already resolves as authored — a
            // founder listening call, not a derivable one. `GenreDelaySyncResolvabilityTests`
            // allows exactly one genre clamped AT ITS DEFAULT, so a second one cannot appear
            // unnoticed; it deliberately does not bound partial slow-end truncation.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.half),
                delayMix: 0.34, delayFeedback: 0.45, delayTone: 0.28, delaySpread: 0.45,
                delayWow: 0.25, delayDrive: 0.15,
                chorusEnabled: true, chorusRate: 0.12, chorusDepth: 0.35, chorusMix: 0.25,
                reverbEnabled: true, reverbMix: 0.44, reverbRoom: 0.94, reverbDamping: 0.42)
        case .drift:
            // G2 airy Fläche: distinct from the two darker ambient presets — a WIDE
            // dotted-quarter digital shimmer (not the darker two's straight half),
            // brighter tone (0.42) + the widest spread, a very slow lush chorus, and
            // the brightest, least-damped big hall so the space reads weightless
            // rather than dark. Feedback stays < 0.5 so the tail washes, never builds.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.36, delayFeedback: 0.42, delayTone: 0.42, delaySpread: 0.55,
                chorusEnabled: true, chorusRate: 0.10, chorusDepth: 0.45, chorusMix: 0.30,
                reverbEnabled: true, reverbMix: 0.46, reverbRoom: 0.95, reverbDamping: 0.35)
        case .contemplation:
            // G2 grounded Fläche: warm and grounded rather than airy — a dark TAPE echo with
            // gentle wow into the BIGGEST hall in the roster (0.96) but far more DAMPED than
            // drift (0.55 vs 0.35). Feedback < 0.5 so the tail washes, never builds.
            //
            // ⚠️ IT IS NO LONGER "THE LONGEST SPACE OF THE FAMILY". It shipped as `.half, .dotted`
            // (3 quarters) = 4.09…2.73 s across its own 44…66 window — over the 2.0 s
            // `maxDelaySeconds` clamp at EVERY tempo it can reach, so the notated dotted-half
            // could not resolve anywhere and clamped to a flat 2.0 s, the same number two
            // siblings clamp to. A preset cannot be "the longest" by authoring a number the
            // chain refuses. (⚠️ "IDENTICAL to two siblings" was the first wording and it
            // over-claimed: identical in what `apply` WRITES, yes — but `applyDelaySync`
            // overwrites the delay time downstream on all three stamp paths, so no listener has
            // ever heard any genre's division. See `apply(to:bpm:)`.)
            //
            // `.quarter` resolves un-clamped across the whole window (1.364 s at 44, 0.909 at 66,
            // 1.154 at the 52 default) and is chosen over the longest-fitting `.half, .triplet`
            // (1.818/1.212, the value `deepDrone` takes) on ONE derived ground: 1.538 s at the
            // default would sit 2.5% from `drift`'s 1.5 s — trading a collision with the clamped
            // pair for a collision with drift. At 1.154 s the nearest sibling is 30% away. The
            // grounded reading now comes from the big damped hall, not from echo length.
            // ⚠️ THE SENTENCE THAT FOLLOWED HERE — "the longest echo in the family is
            // `deepDrone`'s" — IS DELETED, not softened. It was the same superlative retracted
            // 290 lines up in this very file, left standing in the block a session lands on
            // FIRST when tuning a calm preset: it would have invited "give the new one more than
            // deepDrone's 1.667" straight into the clamp. There is no longest echo to build on;
            // 2.0 s is the clamp and four genres sit on it.
            //
            // The word "distinct sync" is also gone: this division is shared with THREE other
            // offered genres — `ambientPulse`, `classical` AND `vaporwave` (the first version of
            // this line named only the first two; `vaporwave` is `.quarter` too and is offered,
            // it is just not drum-free, which is how it was missed). Sharing a DIVISION is not
            // sharing an echo — the resolved seconds differ because the tempo windows do
            // (vaporwave @70 = 0.857 s, 35% from this preset's 1.154 s). Pinned in
            // `Tests/CISmoke/GenreDelaySyncResolvabilityTests`.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.32, delayFeedback: 0.40, delayTone: 0.24, delaySpread: 0.40,
                delayWow: 0.20, delayDrive: 0.12,
                chorusEnabled: true, chorusRate: 0.08, chorusDepth: 0.40, chorusMix: 0.28,
                reverbEnabled: true, reverbMix: 0.48, reverbRoom: 0.96, reverbDamping: 0.55)
        }
    }
}

/// A hand-built production effect *character* the producer can stamp on a take
/// while making loops/samples/tracks — independent of genre. `.auto` defers to
/// the genre's own `fxPreset`; the others impose a strong, recognisable colour
/// (the muffled "Underwater", a "Telephone" band-pass, tape "Cassette", dusty
/// "Vinyl", wide "Dream", barking "Megaphone").
public enum FXCharacter: String, CaseIterable, Sendable, Identifiable {
    case auto
    case clean
    case underwater
    case telephone
    case cassette
    case vinyl
    case dream
    case megaphone
    case blurry
    case harmonizer
    case room
    case hall

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto:       return "Auto (genre)"
        case .clean:      return "Clean (dry)"
        case .underwater: return "Underwater"
        case .telephone:  return "Telephone"
        case .cassette:   return "Cassette"
        case .vinyl:      return "Vinyl"
        case .dream:      return "Dream"
        case .megaphone:  return "Megaphone"
        case .blurry:     return "Blurry"
        case .harmonizer: return "Harmonizer"
        case .room:       return "Room"
        case .hall:       return "Hall"
        }
    }

    /// One-line description for the picker.
    public var blurb: String {
        switch self {
        case .auto:       return "Use the genre's own effect space"
        case .clean:      return "No effects — reset to a dry signal"
        case .underwater: return "Submerged: deep low-pass + watery chorus + tape wobble"
        case .telephone:  return "Narrow band-pass — old-phone / lo-fi vocal"
        case .cassette:   return "Warm tape: gentle low-pass + wow & flutter"
        case .vinyl:      return "Dusty record: softened highs, subtle width"
        case .dream:      return "Wide and bright: lush chorus + long ping-pong"
        case .megaphone:  return "Barking band-pass + saturated slap"
        case .blurry:     return "Soft-focus wash: low-pass + deep chorus + smeared echo"
        case .harmonizer: return "Adds harmony voices: a third + fifth above the melody"
        case .room:       return "Tight, natural room — adds depth without washing out"
        case .hall:       return "Large, lush concert hall — long, bright reverb tail"
        }
    }

    /// The effect preset for this character. `nil` for `.auto` — the caller
    /// should fall back to the genre's `fxPreset`.
    public var preset: GenreFXPreset? {
        switch self {
        case .auto:
            return nil
        case .clean:
            // Everything off — a dry reset, including saturation. The safety
            // limiter (not touched by a preset) stays on.
            return GenreFXPreset(filterEnabled: false, delayEnabled: false,
                                 chorusEnabled: false, phaserEnabled: false,
                                 saturation: 0)
        case .underwater:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 650, filterResonance: 0.35,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.35, delayFeedback: 0.45, delayTone: 0.20, delaySpread: 0.45,
                delayWow: 0.6, delayDrive: 0.2,
                chorusEnabled: true, chorusRate: 0.22, chorusDepth: 0.8, chorusMix: 0.5)
        case .telephone:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .bandpass, filterCutoff: 1500, filterResonance: 0.45,
                delayEnabled: false)
        case .cassette:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 7000, filterResonance: 0.18,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.16, delayFeedback: 0.30, delayTone: 0.45, delaySpread: 0.25,
                delayWow: 0.45, delayDrive: 0.25)
        case .vinyl:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 5500, filterResonance: 0.15,
                delayEnabled: false,
                chorusEnabled: true, chorusRate: 0.2, chorusDepth: 0.3, chorusMix: 0.22)
        case .dream:
            return GenreFXPreset(
                delayEnabled: true, delayMode: .pingPong,
                delaySync: TempoSyncOption(.quarter, .dotted),
                delayMix: 0.40, delayFeedback: 0.45, delayTone: 0.82, delaySpread: 0.6,
                chorusEnabled: true, chorusRate: 0.30, chorusDepth: 0.7, chorusMix: 0.5,
                reverbEnabled: true, reverbMix: 0.32, reverbRoom: 0.86, reverbDamping: 0.40)
        case .megaphone:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .bandpass, filterCutoff: 1800, filterResonance: 0.55,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.sixteenth),
                delayMix: 0.14, delayFeedback: 0.22, delayTone: 0.6, delaySpread: 0.15,
                delayDrive: 0.5,
                saturation: 0.55)
        case .blurry:
            return GenreFXPreset(
                filterEnabled: true, filterMode: .lowpass, filterCutoff: 2200, filterResonance: 0.20,
                delayEnabled: true, delayMode: .tape,
                delaySync: TempoSyncOption(.eighth),
                delayMix: 0.30, delayFeedback: 0.50, delayTone: 0.35, delaySpread: 0.55,
                delayWow: 0.55, delayDrive: 0.15,
                chorusEnabled: true, chorusRate: 0.45, chorusDepth: 0.9, chorusMix: 0.6)
        case .harmonizer:
            // Stacked third + fifth over a lightly-driven dry tone, with a touch
            // of chorus to glue the harmony voices into an ensemble.
            return GenreFXPreset(
                chorusEnabled: true, chorusRate: 0.3, chorusDepth: 0.4, chorusMix: 0.25,
                saturation: 0.25,
                harmonizerEnabled: true,
                harmonizerInterval1: 4, harmonizerInterval2: 7,
                harmonizerVoice2: true, harmonizerMix: 0.55)
        case .room:
            // A tight, natural space — short tail, gentle warmth, no delay wash.
            return GenreFXPreset(
                saturation: 0.22,
                reverbEnabled: true, reverbMix: 0.24, reverbRoom: 0.45, reverbDamping: 0.55)
        case .hall:
            // A large, bright concert hall — long tail over a soft quarter delay.
            return GenreFXPreset(
                delayEnabled: true, delayMode: .digital,
                delaySync: TempoSyncOption(.quarter),
                delayMix: 0.18, delayFeedback: 0.30, delayTone: 0.6, delaySpread: 0.5,
                saturation: 0.20,
                reverbEnabled: true, reverbMix: 0.38, reverbRoom: 0.90, reverbDamping: 0.30)
        }
    }

    /// Apply this character to a live chain at `bpm`. For `.auto`, applies the
    /// supplied `genre`'s preset instead.
    public func apply(to chain: EchoelFXChain, bpm: Double, genre: MusicStyle) {
        (preset ?? genre.fxPreset).apply(to: chain, bpm: bpm)
    }
}
