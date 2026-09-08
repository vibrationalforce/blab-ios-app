//
//  FlashGuard.swift
//  Echoelmusic — Studio (visual safety)
//
//  WCAG 2.3.1 epilepsy safety as a pure, reusable primitive. Bio-reactive
//  visuals must never strobe: nothing may flash more than 3 times per second,
//  and a "general flash" is a luminance swing ≥10% of max where the darker
//  state is below 0.80 relative luminance (W3C). This type encodes those rules
//  so every visual clamps the same way, and honors Reduce Motion by stopping
//  oscillation entirely.
//
//  Pure value type — no platform import, trivially unit-testable.
//

import Foundation

public enum FlashGuard {

    /// WCAG 2.3.1 hard limit: at most three flashes per second.
    ///
    /// ⭐ THIS IS THE CANONICAL DECLARATION, and it is canonical by DESIGNATION rather than by
    /// being the only one — there are two more, and `maxPulseRateHz` below argues against
    /// exactly that shape ("two symbols for one number is the drift surface this whole hoist
    /// exists to remove"). That argument was written about the 2.5 Hz pulse ceiling and it
    /// was right; the 3 Hz ceiling it sits next to had escaped the same hoist.
    ///
    /// The other two are `EntrainmentEngine.maxVisualFlashHz` (`Bio/`) and
    /// `BioEntrainmentDirector.maxVisualHz` (`DSP/`). Neither can chain to this symbol today:
    /// `Bio/` references no `Studio/` type, and `DSP/` is kept Foundation-only by hygiene
    /// (`project.yml`). Folding them means MOVING this type to a layer all three can see —
    /// a decision about where visual-safety law lives, deliberately not taken in passing.
    /// Until then `Tests/CISmoke/TheFlashCeilingIsOneNumberTests` makes any divergence red.
    ///
    /// ⛔ THIS DOC SAID "TWO MORE" AND THERE WAS A THIRD (#864, 2026-08-29).
    /// `BioColorGradeParams.flashLimited(… maxHz: Float = 3)` declared the same ceiling as a
    /// default ARGUMENT. Four homes agreed on "three" — this paragraph, both copies' own
    /// docs, and the guard's header table — because each census looked for a `static let`
    /// with `Flash` or `Visual` in the name, and that is the one shape the fourth did not
    /// have. It now reads `Float(FlashGuard.maxFlashHz)`: chained, not counted, because it
    /// sits in `Studio/` and layering permits there what it forbids for the other two.
    /// LESSON, and it is an ENUMERATION lesson rather than a value one: a census of a
    /// constant searches the VALUE and the default arguments, never the naming convention
    /// the already-known copies happen to share. Nothing was wrong for a user — that file
    /// has no caller — so this is a forward guard, not a fix.
    public static let maxFlashHz: Double = 3.0

    /// The app's OWN, stricter ceiling on the rate at which the bio pulse phase advances.
    ///
    /// This is not belt-and-braces caution, it is the number the look budgets are computed
    /// FROM. `FlashGuardTests.testEveryReachableLookObeysTheThreeHzLaw` derives each look's
    /// flash rate as (phase rate × its own multiplier, doubled if the field folds), and
    /// Aurora lands on **exactly 3.00 Hz** — zero margin against `maxFlashHz`. So raising
    /// this to WCAG's 3.0 would put Aurora at 3.6 Hz: a real epilepsy-law violation, not a
    /// rounding question.
    ///
    /// It lives here, and every consumer reads it, because the value used to be a bare
    /// `2.5` literal in `MetalBioView`, in `HeaderMonitors` AND in the tests that prove the
    /// law — so those tests validated a COPY and would have stayed green while the renderer
    /// flashed faster. That is the same failure mode `ringsPhaseDampingLiteral` below was
    /// written to end; the ceiling itself had escaped it.
    ///
    /// The one deliberate NON-consumer this note used to name — `ClipLaunchGlyph.blinkPeriod`
    /// — is gone with the file (#132 Slice 5a). The REASON it was excluded is kept, because
    /// it is the general trap and the next blink/pulse constant will walk into it: a
    /// half-cycle DURATION is not a full-cycle RATE. `1 / maxPulseRateHz` happened to equal
    /// that 0.4 s exactly, so substituting it would have been bit-identical and read correct
    /// while asserting a relationship off by a factor of two — the trap springs on the
    /// maintainer who then aligns code to comment and writes `0.5 / maxPulseRateHz` = 0.2 s
    /// → 5 transitions/s, i.e. a WCAG breach introduced by a tidy-up.
    ///
    /// It is a `Double`. `MetalBioView` works in `Float`, so it casts at the call site
    /// (`Float(FlashGuard.maxPulseRateHz)`) rather than this type carrying a `Float` twin:
    /// two symbols for one number is the drift surface this whole hoist exists to remove,
    /// and the rounding it would buy is ~1e-7 Hz — three orders of magnitude below anything
    /// WCAG can express, and below the smoothing already applied to `pulseHz` upstream.
    public static let maxPulseRateHz: Double = 2.5

    /// A general flash needs a relative-luminance change of at least this
    /// fraction of the maximum (W3C: 10%).
    public static let luminanceDeltaThreshold: Double = 0.10

    /// …and only when the darker of the two states is below this relative
    /// luminance (W3C: 0.80). Two bright states swinging do not count.
    public static let darkStateThreshold: Double = 0.80

    /// Clamps an oscillation frequency (Hz) to the WCAG-safe range. Returns 0
    /// when Reduce Motion is on, so the caller renders a still frame.
    public static func safeFrequency(_ hz: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0 }
        guard hz.isFinite else { return 0 }
        return Swift.max(0, Swift.min(hz, maxFlashHz))
    }

    /// Phase damping the Rings look applies before squaring its field. Interpolated
    /// INTO the Metal shader source (`MetalBioView.shaderSource`) rather than
    /// duplicated there, so this constant and the shader cannot drift apart — the
    /// first version of this fix mirrored the number in a comment and a test, which
    /// is a guard that passes while the shader says something else.
    /// 0.5 × 2 (the fold) = 1.0, i.e. the squared field lands exactly on the cap.
    public static let ringsPhaseDamping: Double = 0.5

    /// The SAME value as a string, because it is interpolated into Metal source that
    /// is compiled at RUNTIME. Interpolating the `Double` directly would emit
    /// whatever Swift's description produces; a hand-written literal is exact and
    /// cannot become locale-dependent, and a bad literal here would fail as a shader
    /// COMPILE error on device (a black visual), not at build time — so
    /// `FlashGuardTests` asserts the two agree.
    public static let ringsPhaseDampingLiteral = "0.5"

    /// How much the heartbeat may swing the central bloom's BRIGHTNESS
    /// (`MetalBioView`'s `beatGain = base + swing·beat`). Founder-approved 2026-07-25.
    ///
    /// Why it is bounded at all: the bloom runs at the FULL phase rate while the field
    /// runs at its own damped rate, and the two are ADDED. At radii where their peaks
    /// do not coincide a pixel sees two maxima per cycle — the union of both flash
    /// counts, up to ~5/s. Rather than slow the heartbeat (which would read as a pulse
    /// every second beat) the bloom's own swing is held BELOW the WCAG general-flash
    /// threshold, so its transitions do not qualify as flashes and only the field's
    /// rate counts. The bloom's RADIUS pulse is deliberately untouched: the beat still
    /// visibly expands, which is the part that reads as "your heartbeat drives it".
    ///
    /// The number: worst-case luminance delta =
    /// `swing × restGlowMax(0.21) × (1 − ambient)(0.94) × filmicMaxSlope(1.06)`.
    /// At 0.42 → 0.088, i.e. 12 % under the 0.10 gate. NOTE the curve factor — the
    /// first attempt used 0.50 and landed at 0.105, still OVER, because the filmic
    /// contrast lift at the end of the shader was not counted. Any change here must
    /// re-run that product; `FlashGuardTests` asserts it.
    ///
    /// ⚠️ THAT FOURTH FACTOR IS A MAXIMUM, NOT A UNIFORM GAIN, since #1059. It used to be
    /// both — the old closing line multiplied every channel by 1.06 everywhere — so the
    /// wording "sCurveGain(1.06)" was true in a way it no longer is. Today the curve reaches
    /// 1.06 only at mid grey and amplifies less elsewhere, which makes this product a strict
    /// upper bound rather than an equality. The number did not move; what it MEANS did, and
    /// a bound that quietly became an average is how a WCAG argument rots.
    public static let bloomBeatGainSwing: Double = 0.42

    /// The same value as an exact Metal token (see `ringsPhaseDampingLiteral`).
    public static let bloomBeatGainSwingLiteral = "0.42"

    /// Strength of the shader's closing filmic contrast curve — and it lives HERE, not in
    /// the shader, because the bloom's flash budget one constant up is computed FROM it.
    ///
    /// The curve is `L + strength · (smoothstep(0,1,L) − L)` applied to LUMINANCE, with the
    /// colour scaled by the resulting ratio. Its slope is `1 + strength · (6L − 6L² − 1)`,
    /// which peaks at `L = 0.5` — so `filmicMaxSlope` below is exactly `1 + strength/2`, and
    /// that is the number the flash product must use. Changing `filmicStrength` therefore
    /// changes the WCAG headroom of a constant in a different file; the derivation below is
    /// what makes that impossible to do by accident.
    ///
    /// ⛔ IT USED TO BE A PER-CHANNEL AFFINE, `(c − 0.5) · 1.06 + 0.5` clamped per channel,
    /// and that form was wrong twice over (#1059). It was not a curve at all — a straight
    /// line has no shoulder and no toe, so the comment calling it an "S-contrast" described
    /// a function the code did not implement. And applying it per CHANNEL rotated hue: a
    /// (0.10, 0, 0.50) pixel came out (0.076, 0, 0.50), i.e. its R:B ratio moved 0.20 → 0.15,
    /// on a surface whose whole claim is that a pitch has a physically derived colour. Below
    /// 0.028 every channel clamped to zero, which also undid part of the ambient wash two
    /// lines above it whose stated job is that the frame is NEVER a dead black.
    ///
    /// The replacement was chosen so this flash argument did not have to be re-litigated:
    /// at strength 0.12 the maximum slope is 1.06, identical to the old uniform gain, and
    /// every other point on the curve amplifies LESS. The worst-case product is unchanged
    /// to twelve decimals.
    public static let filmicStrength: Double = 0.12

    /// The same value as an exact Metal token (see `ringsPhaseDampingLiteral`).
    public static let filmicStrengthLiteral = "0.12"

    /// The steepest the filmic curve gets — `1 + filmicStrength/2`, at mid grey. Derived,
    /// never typed twice: the flash product above multiplies by it, and a hand-copied 1.06
    /// is exactly the kind of number that survives a change to the curve it describes.
    public static let filmicMaxSlope: Double = 1.0 + filmicStrength / 2.0

    // MARK: - The COLOUR path (note clouds) — #1091

    /// Time constants of the colour path, hoisted from `MetalBioView`'s cloud update so the
    /// 3 Hz argument can READ them instead of trusting a comment. Until #1091 they were bare
    /// literals at seven call sites — the same shape `maxPulseRateHz` above was rescued from,
    /// and the same blind spot the look table in `FlashGuardTests` admits to: that table
    /// bounds the scalar FIELD, and colour travels a separate path it never sees.
    ///
    /// What they ARE: each sounding note owns one of five clouds. A cloud's WEIGHT eases in
    /// (fast for a finger, slower for the generative bed — its 16th-note retriggers at ~8/s
    /// bloomed half-frame clouds in ~90 ms) and out; a slot stolen by a new note CHASES the
    /// new colour and place per channel instead of cutting, which is what keeps a visible
    /// cloud from ever jumping (the 2026-07-08 "Bildfehler"). The Prism look keeps a discrete
    /// A→B crossfade whose retarget is GATED on the running fade.
    ///
    /// ⚠️ WHAT THEY DO NOT PROVE, stated here because a hoist reads like a proof: none of
    /// these constants rate-limits the colour path BELOW the WCAG threshold. A first-order
    /// lowpass driven on/off at 3 Hz still passes `squareWaveSurvival(hz: 3, tau: 0.09)` ≈
    /// 73 % of a finger cloud's swing and ≈ 27 % of a generative cloud's. Whether that is a
    /// WCAG 2.3.1 flash depends on the photometric half — how much RELATIVE LUMINANCE a
    /// cloud moves over what FRACTION of the field (the shader's cloud radius is
    /// `0.42 · spread`, spread up to 1.92) — and that half is measured on a device clip, not
    /// asserted here. `TheColourPathHasAFlashBudgetTests` pins exactly this status so it
    /// cannot be read as "colour is covered".
    public static let cloudRiseTauTouch: Double = 0.09
    /// See `cloudRiseTauTouch`.
    public static let cloudRiseTauGenerative: Double = 0.30
    /// See `cloudRiseTauTouch`.
    public static let cloudFallTau: Double = 0.35
    /// See `cloudRiseTauTouch` — per-channel RGB chase of a stolen slot toward its new note.
    public static let cloudColourChaseTau: Double = 0.18
    /// See `cloudRiseTauTouch` — the stolen slot's place chases the new note's cell.
    public static let cloudPositionChaseTau: Double = 0.25
    /// The Prism look's discrete A→B colour crossfade. See `cloudRiseTauTouch`.
    public static let prismFadeTau: Double = 0.18
    /// A Prism retarget is accepted only once the running fade has passed this fraction, so
    /// a fast retrigger can no longer flash the stale A end. With `prismFadeTau` this bounds
    /// the switch rate at `1 / (prismFadeTau · ln(1 / (1 − gate)))` ≈ 6.1 switches/s — i.e.
    /// ≈ 3.0 opposing pairs/s, ON the ceiling with no margin, like Aurora in the look table.
    public static let prismRetriggerGate: Double = 0.6

    /// The fraction of a symmetric on/off square wave's swing that SURVIVES a first-order
    /// lowpass of time constant `tau` when the wave alternates at `hz`: `tanh(1 / (4·hz·tau))`.
    ///
    /// Use it to ask whether an easing constant rate-limits a channel below the general-flash
    /// threshold (`luminanceDeltaThreshold`): if the survival at `maxFlashHz` times the
    /// channel's full luminance swing is still ≥ 0.10, the easing is NOT the safety argument
    /// and something else (spatial extent, a gate) has to be. Non-finite or non-positive input
    /// returns 1 — the whole swing survives — so a caller asserting "attenuated enough" FAILS
    /// CLOSED, the same direction `effectiveFieldHz` chooses with `.infinity`.
    public static func squareWaveSurvival(hz: Double, tau: Double) -> Double {
        guard hz.isFinite, tau.isFinite, hz > 0, tau > 0 else { return 1 }
        return Foundation.tanh(1.0 / (4.0 * hz * tau))
    }

    /// The rate a visual FIELD actually flashes at — which is NOT always the rate
    /// its phase is integrated at, and that gap shipped a WCAG violation.
    ///
    /// THE LAW, stated precisely (the loose version cost a re-review): only a
    /// **non-monotone** operation on a phase-bearing quantity adds flashes, because
    /// only a non-monotone map can create new extrema. Those are:
    ///   • squaring a BIPOLAR signal — `sin²x = ½(1 − cos 2x)`, rate ×2
    ///   • `abs()` of a bipolar signal — folds identically, rate ×2
    ///   • a PRODUCT of two phase-bearing factors — adds a sum sideband at f₁+f₂
    /// Monotone maps do NOT add flashes, however nonlinear they look: `pow` on a
    /// non-negative field, `clamp`, `smoothstep`, an S-curve. They change the SHAPE
    /// of each flash (and can make it harsher), never the count per second.
    ///
    /// This is what `MetalBioView`'s Rings look got wrong: it fed the full 2.5 Hz
    /// capped phase into a squared bipolar field and so reached 5 Hz, while every
    /// frequency clamp in the codebase correctly read "2.5 ≤ 3, safe". Clamping the
    /// input is necessary and not sufficient once a fold follows it.
    ///
    /// - Parameters:
    ///   - phaseRateHz: the rate the phase is advanced at (already clamped).
    ///   - phaseMultiplier: the multiplier on the shared phase of the style's
    ///     FASTEST term — for a product of two phase-bearing factors that is the
    ///     SUM of their multipliers, not either one alone.
    ///   - folds: true when a non-monotone map (bipolar square, `abs`) is applied.
    /// - Returns: an UPPER BOUND on the field's flash rate in Hz — the fastest
    ///   component, not the highest-energy one. Non-finite input returns
    ///   `.infinity` so a caller asserting `<= maxFlashHz` FAILS CLOSED; this is a
    ///   value to check, not a frequency to use (contrast `safeFrequency`, which
    ///   returns 0 because its result is rendered).
    ///
    /// Use it when adding or retuning a style: the result must be `<= maxFlashHz`.
    ///
    /// KNOWN LIMIT — do not mistake this for a complete model: it describes ONE
    /// oscillator. It cannot express two ADDITIVE oscillators at different phases
    /// (e.g. a field plus a separate heartbeat bloom), where a pixel sees the UNION
    /// of both flash counts. Check those by hand.
    public static func effectiveFieldHz(phaseRateHz: Double,
                                       phaseMultiplier: Double,
                                       folds: Bool) -> Double {
        guard phaseRateHz.isFinite, phaseMultiplier.isFinite else { return .infinity }
        let base = Swift.abs(phaseRateHz) * Swift.abs(phaseMultiplier)
        return folds ? base * 2 : base
    }

    // MARK: - The per-look flash budget (#1123)

    /// What one selectable look costs in flashes per second.
    ///
    /// ⛔ THIS TABLE LIVED IN `Tests/EchoelmusicTests/FlashGuardTests.swift` UNTIL #1123, AND
    /// THAT IS THE NON-BLOCKING SUITE — no gate compiles it (#208). So the numbers that
    /// decide a WCAG safety property were, structurally, documentation. #1114 pulled the
    /// ARITHMETIC into the blocking bundle by parsing the file as TEXT; this moves the DATA
    /// itself into the law, where the shader's own caller can read it and a parser is no
    /// longer needed for anything.
    ///
    /// `phaseMultiplier` is the FASTEST phase-bearing term of that look's shader function,
    /// and `folds` doubles it when an `abs()`, a square, or a non-monotone map creates new
    /// extrema. The derivation per row is written at the row — re-derive it when you touch
    /// the function, never copy the number forward.
    public struct FieldFlashBudget: Sendable, Equatable {
        public let styleIndex: Int
        public let name: String
        public let phaseMultiplier: Double
        public let folds: Bool

        /// Flashes per second at the app's own phase ceiling.
        public var effectiveHz: Double {
            FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                        phaseMultiplier: phaseMultiplier, folds: folds)
        }
    }

    /// One row per look a user can select (`LookBlendMap.library`). Style indices are the
    /// shader's, not positions in this array.
    public static let fieldBudgets: [FieldFlashBudget] = [
        // fieldRings: p = 0.5·phase, then interference INTENSITY (a bipolar square) folds it.
        .init(styleIndex: 0, name: "Rings", phaseMultiplier: ringsPhaseDamping, folds: true),
        // fieldDish (#1101/#1102, the former Plasma slot): the ONLY phase-bearing term is
        // `breathe = 0.85 + 0.15·sin(0.4·phase)`; it enters the lens strength `c` linearly and
        // (1 − c)/(1 − c·h) is monotone in c at every fixed h — no product of two phase-bearing
        // factors, no abs(), no square. `dishStrength` is the eased music level, not a phase.
        .init(styleIndex: 2, name: "Dish", phaseMultiplier: 0.40, folds: false),
        // fieldWater: sin(x·s + t)·cos(y·(0.818·s) − 0.7t), t = 0.4·phase. PRODUCT of two
        // phase-bearing factors ⇒ sum sideband 0.4 + 0.28 = 0.68. #1078 gave `s` the capillary
        // law and moved breath onto the sum's AMPLITUDE; neither touches a phase-bearing term
        // (`s` multiplies the SPATIAL coordinate), so this row is unchanged BY STRUCTURE.
        .init(styleIndex: 3, name: "Water", phaseMultiplier: 0.68, folds: false),
        // fieldAurora: abs(p.y − wave) FOLDS a wave whose fastest term is 1.0·t = 0.35·phase
        // ⇒ 0.70. The curtain is then MULTIPLIED by `breathe` (0.5·phase), adding a
        // 0.70 + 0.50 = 1.20 sideband ⇒ 3.00 Hz. ⚠️ AURORA SITS EXACTLY ON THE LIMIT WITH ZERO
        // MARGIN — the worst-case row in the app, and it is in `LookBlendMap.defaultSequence`.
        // Do not add any further phase term to it.
        .init(styleIndex: 5, name: "Aurora", phaseMultiplier: 1.20, folds: false),
        // fieldDepthCaustics (#1117 rebuilt it as a real ray map): the only phase-bearing term
        // is `breathe = 0.85 + 0.15·sin(0.30·phase)`, entering the focus number φ. Unlike the
        // dish's lens law, 1/|det J| is NOT monotone in φ — it peaks AT the caustic — so a
        // pixel near a fold can cross it twice per cycle. That fold is declared, not argued
        // away. ⛔ The row it replaces read (0.72, folds: false) → 1.80 Hz and described a
        // sine product that no longer exists.
        .init(styleIndex: 7, name: "Depth", phaseMultiplier: 0.30, folds: true),
    ]

    /// The budget for a style index, or `nil` for one that has none.
    ///
    /// ⚠️ `nil` MEANS "UNKNOWN", NOT "FREE". A caller that cannot find a row must assume the
    /// worst (`maxFlashHz`), never zero — the retired styles still compiled in the shader
    /// (1 Cymatics, 4 Prism, 6 Lissajous, 8 Scope, 9 Fractal) have no rows precisely because
    /// nobody re-derived them, not because they are calm.
    public static func fieldBudget(forStyle index: Int) -> FieldFlashBudget? {
        fieldBudgets.first { $0.styleIndex == index }
    }

    /// Whether a transition between two relative luminances [0,1] counts as a
    /// WCAG "general flash" (such a pair repeating >3×/s is the seizure risk).
    public static func isFlash(from a: Double, to b: Double) -> Bool {
        let lo = Swift.min(a, b)
        let hi = Swift.max(a, b)
        return (hi - lo) >= luminanceDeltaThreshold && lo < darkStateThreshold
    }

    /// Slew-limits a luminance step so a value stream can never strobe: the move
    /// from `previous` toward `target` is capped to `maxDelta` per step.
    public static func limitedLuminance(from previous: Double, to target: Double,
                                        maxDelta: Double = luminanceDeltaThreshold) -> Double {
        let delta = target - previous
        if delta > maxDelta { return previous + maxDelta }
        if delta < -maxDelta { return previous - maxDelta }
        return target
    }

    /// The next dimmer value a lighting sender emits, given its slew anchor.
    /// The ONE flash-safe decision shared by ArtNet and sACN (so both fixture
    /// protocols get an identical, testable guarantee):
    ///   • blackout        → 0 (an instant cut is a single edge, not a strobe)
    ///   • no history (lastDimmer < 0) → the target (nothing to ramp from)
    ///   • otherwise       → the target, slew-limited to `maxDelta`/tick.
    /// `lastDimmer` is the anchor to update with the return value.
    ///
    /// ⚠️ The 0.08 DEFAULT is no longer what the app uses. Both senders pass
    /// `senderTickDelta` explicitly (#372) — the rate resolved at their own interval,
    /// which happens to equal 0.08 today. The default survives for the existing test
    /// call sites and for any caller with a genuinely fixed tick; a new production
    /// caller should pass a step derived from ITS interval, not inherit this one.
    public static func slewedDimmer(from lastDimmer: Float, to mastered: Float,
                                    blackout: Bool, maxDelta: Double = 0.08) -> Float {
        if blackout { return 0 }
        if lastDimmer < 0 { return mastered }
        return Float(limitedLuminance(from: Double(lastDimmer), to: Double(mastered),
                                      maxDelta: maxDelta))
    }

    // MARK: - The flash bound as a RATE, not a step (#370 primitive, #372 wiring)

    /// ⚠️ THE DEFECT THIS EXISTS TO CLOSE, stated plainly because it is a safety bound:
    /// `slewedDimmer`'s `maxDelta` is a step PER CALL. Nothing in this file knows how often
    /// it is called. The senders that call it USED TO set their own tick interval in two
    /// OTHER files — `Sync/ArtNetSender.swift` and `Sync/SACNSender.swift` — with nothing
    /// binding the two together: speed a loop up and the flash rate rose with it, silently,
    /// with no test anywhere going red. `BioPhaser` already learned this and says so at
    /// `Sync/BioPhaser.swift:35-41`: a per-TICK cap lets a fast poll sneak extra flashes
    /// through, so the guarantee has to live as a per-SECOND velocity.
    ///
    /// #372 closed it: both senders now start their loop from `senderTickMilliseconds` and
    /// cap with `senderTickDelta`, which is that rate resolved at that same interval. Change
    /// the interval and the step follows in the same expression — the two cannot drift apart
    /// because they are no longer two facts.
    ///
    /// ⚠️ WHAT IS STILL NOT GUARANTEED, so nobody reads more into this than it says: the
    /// binding is to the NOMINAL interval, not to a measured one. A timer that fires late
    /// still gets the nominal step, so a stalled loop that catches up takes slightly larger
    /// effective steps per real second. That residual is bounded by how far the loop can
    /// drift and is much smaller than the file-split this replaced — but it is real, and
    /// closing it means measuring dt at the sender (`maxDelta(perSecond:dt:)` already takes
    /// one), which is a behaviour change with a device look, not a cleanup.
    ///
    /// ⛔ NOT NAMED `maxLuminancePerSecond`. `BioPhaser` already owns that name with the
    /// value 0.5/s — nearly FIVE TIMES stricter than what the senders actually do. Two
    /// constants with one name and a 4.8× gap is the kind of collision that gets "unified"
    /// by a later reader who assumes they meant the same thing; unifying them would slow
    /// every fixture fade to a fifth of its shipped speed, which is a visible product
    /// change nobody asked for. If the two ever SHOULD agree, that is a founder decision
    /// with a device look, not a tidy-up.
    ///
    /// The value is written as its derivation on purpose. Writing "2.42" by hand would
    /// have made the wiring slice change behaviour by 0.17 % while its commit message
    /// claimed bit-identity — a small lie of exactly the kind this file's history is full
    /// of. Derived, the wiring slice is genuinely a no-op at the shipped tick rate.
    public static let shippedTickDelta: Double = 0.08
    /// ⛔ THE CALIBRATION INTERVAL, AND IT MUST NOT BE `senderTickSeconds`. This is a frozen
    /// historical fact: the interval the 0.08 above was measured against. My first draft of
    /// #372 derived the rate from the LIVE interval instead, and that quietly cancelled the
    /// entire slice — with `rate = 0.08 / live` the step comes back out as
    /// `rate × live = 0.08` for EVERY interval, so halving the loop would have doubled the
    /// flash rate exactly as before, now with a rate-shaped constant sitting on top of it
    /// claiming otherwise. The two arithmetic tests written alongside it both passed,
    /// because they varied `dt` while holding the rate fixed — they could not see it.
    /// The rate is only rate-invariant if its denominator is frozen. Hence two constants
    /// that hold the same number today and mean entirely different things.
    public static let calibrationTickSeconds: Double = 0.033
    /// The interval BOTH sender loops start at — and since #372 the SOURCE of it, not a
    /// record of one: `ArtNetSender` and `SACNSender` build their `.milliseconds(…)` from
    /// this. Changing it changes the loop rate AND, through `senderTickDelta` below, the
    /// step size in the same breath.
    public static let senderTickMilliseconds: Int = 33
    /// The live interval in seconds, for the rate arithmetic.
    public static let senderTickSeconds: Double = Double(senderTickMilliseconds) / 1000.0
    /// ≈ 2.4242 luminance units per second — the per-tick step expressed as the
    /// rate-invariant quantity, so a faster loop takes smaller steps instead of flashing
    /// faster. Derived from the CALIBRATION pair (see the ⛔ above for why that word is
    /// load-bearing) rather than hand-written, so the wiring came out bit-identical at the
    /// shipped interval.
    public static let senderLuminancePerSecond: Double = shippedTickDelta / calibrationTickSeconds
    /// The step BOTH senders actually pass to `slewedDimmer` — the rate above, resolved at
    /// the LIVE interval. Equals `shippedTickDelta` today only because the live interval
    /// still equals the calibration interval; set `senderTickMilliseconds` to 16 and this
    /// becomes ≈0.039, which is the entire point of routing through the rate.
    public static let senderTickDelta: Double = maxDelta(perSecond: senderLuminancePerSecond,
                                                        dt: senderTickSeconds)

    /// The per-call step that realises a per-SECOND luminance velocity at the caller's
    /// actual tick spacing.
    ///
    /// `dt` is sanitised the same way `BioPhaser.step` does it (`Sync/BioPhaser.swift:67`):
    /// a non-finite or non-positive `dt` falls back to 0.1 s rather than to zero, and a
    /// `dt` above one second is capped at one. The cap is the part that matters for safety
    /// — after a stall or a clock jump, an uncapped `dt` would authorise an arbitrarily
    /// large single luminance leap, which is precisely one flash edge.
    public static func maxDelta(perSecond: Double, dt: Double) -> Double {
        let safeDt = (dt.isFinite && dt > 0) ? Swift.min(dt, 1.0) : 0.1
        let rate = perSecond.isFinite ? Swift.max(0, perSecond) : 0
        return rate * safeDt
    }
}
