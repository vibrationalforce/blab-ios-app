//
//  EntrainmentEngine.swift
//  Echoelmusic — Bio
//
//  The evidence-based, SAFETY-FIRST core of the bio-paced Session (warm-restart
//  foundation, 2026-07-05). Turns a personal target rhythm — measured from the
//  body's CARDIAC/RESPIRATORY signal (heart rate, HRV, breath), the only rhythms
//  camera rPPG / HRV / BLE-HRS can actually measure — into a stimulation schedule:
//  an isochronic audio pulse plus a flash-SAFE visual pulse, phase-locked.
//
//  What the science does and does NOT support (deep research 2026-07-05, 22/25
//  claims adversarially confirmed):
//   • SUPPORTED: closed-loop pacing of an audio/visual/haptic target from real-time
//     heart/breath produces measurable SHORT-TERM parasympathetic (calming) effects;
//     personal resonance breathing (~4.5–7 breaths/min, 0.075–0.117 Hz) is the
//     defensible target. This is Echoel's honest lane.
//   • NOT SUPPORTED (do NOT claim): that isochronic/audiovisual "brainwave
//     entrainment" reliably drives cortical oscillations, that multi-sensory beats
//     single-sensory, or that we measure brainwaves. rPPG/HRV CANNOT read cortical
//     alpha — we personalize to cardiac/respiratory rhythm only. "Multidimensional"
//     is an AESTHETIC/experiential choice, never an efficacy claim.
//
//  HARD SAFETY ENVELOPE for the VISUAL layer (WCAG 2.x + photosensitive-epilepsy
//  research — these are invariants, not preferences):
//   • ≤ 3 flashes per second (`maxVisualFlashHz`).
//   • NEVER emit visual flicker inside the 4–70 Hz hazardous band — fold to a safe
//     sub-harmonic (≤ 3 Hz) or go steady.
//   • Cap luminance-modulation depth (proxy for the < 20 cd/m² per-flash limit).
//   • Saturated red is disproportionately provocative → never flicker on red.
//  The AUDIO pulse carries the true (possibly faster) rate; only the light is clamped.
//
//  Pure value types + pure functions: no allocation on the hot path, fully unit-
//  tested, safe to read from the audio render thread (phase math only). Self-
//  observation, not therapy or diagnosis.
//

import Foundation

/// A flash-safe stimulation schedule derived from a personal target rhythm.
/// Everything here has already passed the safety envelope — a renderer may use it
/// verbatim without re-checking limits.
public struct EntrainmentPlan: Equatable, Sendable {
    /// Isochronic audio gate rate (Hz). May exceed the visual flash limit; audio is
    /// not photosensitive-hazardous. 0 → no audio pulse (steady tone / silence).
    public var audioPulseHz: Double
    /// Visual pulse rate (Hz), GUARANTEED ≤ `EntrainmentEngine.maxVisualFlashHz` and
    /// never inside the hazardous band. 0 → steady glow, no flicker.
    public var visualPulseHz: Double
    /// True when the visual layer must NOT flicker (target unsafe/absent) — the light
    /// breathes as a slow steady swell instead. A renderer honors this over any rate.
    public var visualIsSteady: Bool
    /// Luminance-modulation depth for the visual pulse, 0…`maxBrightnessDelta`.
    public var brightnessDelta: Double
    /// Always false while flickering — saturated red flicker is banned outright.
    public var allowSaturatedRedFlicker: Bool

    public init(audioPulseHz: Double, visualPulseHz: Double, visualIsSteady: Bool,
                brightnessDelta: Double, allowSaturatedRedFlicker: Bool) {
        self.audioPulseHz = audioPulseHz
        self.visualPulseHz = visualPulseHz
        self.visualIsSteady = visualIsSteady
        self.brightnessDelta = brightnessDelta
        self.allowSaturatedRedFlicker = allowSaturatedRedFlicker
    }

    /// The safe "do nothing" plan: steady light, no pulse. Used for degenerate input.
    public static let steady = EntrainmentPlan(
        audioPulseHz: 0, visualPulseHz: 0, visualIsSteady: true,
        brightnessDelta: 0, allowSaturatedRedFlicker: false)
}

public enum EntrainmentEngine {

    // MARK: - Safety constants (invariants — do NOT relax without bio-safety review)

    /// WCAG 2.x general flash threshold + photosensitive research: no more than three
    /// flashes in any one-second period.
    ///
    /// ⚠️ THE CANONICAL DECLARATION IS `FlashGuard.maxFlashHz`, and this is a SECOND COPY of
    /// it. A third lives at `BioEntrainmentDirector.maxVisualHz`. `FlashGuard`'s own header
    /// argues against exactly this shape — *"two symbols for one number is the drift surface
    /// this whole hoist exists to remove"* — and it was right; the ceiling itself had escaped
    /// the hoist that removed the 2.5 Hz literals.
    ///
    /// It is NOT folded into one symbol here, and the reason is layering, not oversight:
    /// `FlashGuard` lives in `Studio/`, and `Bio/` references no `Studio/` type today
    /// (`git grep -ln FlashGuard -- Sources` lists Core · Studio · Sync · Views, no Bio).
    /// `BioEntrainmentDirector` is worse off — `DSP/` is kept Foundation-only by hygiene
    /// (`project.yml`), so it may not reach `Studio/` at all. Moving `FlashGuard` to a layer
    /// all three can see is a real decision about where visual-safety law lives, not a tidy-up,
    /// and it is not this slice.
    ///
    /// What IS this slice: the drift is now RED. `Tests/CISmoke/TheFlashCeilingIsOneNumberTests`
    /// asserts all three are equal, so relaxing one alone fails the blocking bundle. Change all
    /// three together, or change none — and a bio-safety review comes first either way.
    public static let maxVisualFlashHz: Double = 3.0
    /// Flicker anywhere in this band can provoke photosensitive seizures — the visual
    /// layer must never operate here (audio is exempt; it is not a flash hazard).
    public static let hazardBandLowerHz: Double = 4.0
    public static let hazardBandUpperHz: Double = 70.0
    /// Cap on visual luminance-modulation depth (0…1), a conservative proxy for the
    /// "< 20 cd/m² change between flashes" rule on a bright mobile display.
    public static let maxBrightnessDelta: Double = 0.5

    // MARK: - Personal target (cardiac/respiratory — never cortical)

    /// Resonance-breathing window, breaths per minute. ~4.5–7/min is the evidence-based
    /// calming target (Lehrer/Vaschillo resonance range), and that is where these two come
    /// from — not from another file.
    ///
    /// ⛔ THE SENTENCE THAT STOOD HERE WAS FALSE, and it was a claim of PARITY, which is the
    /// expensive kind: *"Matches BreathPacer/ResonanceFinder so the whole loop shares one safe
    /// range."* It does not. `BreathPacer.minRate` is **5.0** and `ResonanceFinder.minRate`
    /// chains to it, so the floors differ by 0.5/min. Only the ceiling coincides
    /// (`ResonanceFinder.maxRate` is also 7.0) — and it coincides, it is not chained.
    ///
    /// The number is NOT changed to 5.0, because the number is not the defect: 4.5 has a stated
    /// evidence basis right here, and `BreathPacer`'s 5.0 answers a different question (it is
    /// the RESONANCE-SEARCH sweep floor and nothing more — that file retracted its own safety
    /// framing in #435, and `ResonanceFinder` still carries the retracted wording). Two ranges
    /// that legitimately differ need a sentence saying so, not a silent merge.
    ///
    /// ⚠️ The one-way risk if a later slice "unifies" these: `breathTargetHz` CLAMPS to this
    /// window, so raising the floor to 5.0 makes a genuinely-4.6/min breather read as 5.0 —
    /// an invented rate, the class #424/#426 has already paid for twice on the measurement side.
    public static let minBreathsPerMinute: Double = 4.5
    public static let maxBreathsPerMinute: Double = 7.0

    /// The personal calming target, in Hz, from a measured breathing rate. Respiratory
    /// pacing (~0.1 Hz) is the defensible, evidence-supported target — NOT cortical alpha
    /// (which rPPG/HRV cannot measure). Degenerate input → the canonical 6/min (0.1 Hz).
    public static func breathTargetHz(breathsPerMinute bpm: Double) -> Double {
        guard bpm.isFinite, bpm > 0 else { return 6.0 / 60.0 }
        let clamped = Swift.min(maxBreathsPerMinute, Swift.max(minBreathsPerMinute, bpm))
        return clamped / 60.0
    }

    // MARK: - Plan (the safety-enforcing transform)

    /// Build a flash-SAFE plan from a target frequency and an intensity (0…1).
    ///
    /// The audio pulse carries the target rate directly. The VISUAL pulse is forced
    /// into the safe envelope: if the target is at or below `maxVisualFlashHz` it is
    /// used as-is; if it is faster (e.g. an 8 Hz "alpha" ambition), it is folded down
    /// by whole octaves until it sits at or below 3 Hz AND outside the hazardous band,
    /// so the light stays phase-related to the audio yet never flickers dangerously.
    /// If no safe sub-harmonic exists, the light goes steady.
    public static func plan(targetHz: Double, intensity: Double) -> EntrainmentPlan {
        guard targetHz.isFinite, targetHz > 0 else { return .steady }
        let clampedIntensity = Swift.min(1, Swift.max(0, intensity.isFinite ? intensity : 0))
        let brightness = clampedIntensity * maxBrightnessDelta

        let audioHz = targetHz
        let safeVisual = safeVisualHz(for: targetHz)

        guard let visualHz = safeVisual else {
            // No flash-safe sub-harmonic → audio still pulses, light stays steady.
            return EntrainmentPlan(audioPulseHz: audioHz, visualPulseHz: 0,
                                   visualIsSteady: true, brightnessDelta: brightness,
                                   allowSaturatedRedFlicker: false)
        }
        return EntrainmentPlan(audioPulseHz: audioHz, visualPulseHz: visualHz,
                               visualIsSteady: false, brightnessDelta: brightness,
                               allowSaturatedRedFlicker: false)
    }

    /// The fastest flash-safe visual rate at or octave-below `targetHz`, or nil if none
    /// exists at/under `maxVisualFlashHz`. A rate is safe iff it is ≤ 3 Hz and NOT in
    /// the 4–70 Hz hazardous band (≤ 3 Hz already satisfies the second, but we check
    /// both so the invariant is explicit and future-proof if the flash cap ever moves).
    public static func safeVisualHz(for targetHz: Double) -> Double? {
        guard targetHz.isFinite, targetHz > 0 else { return nil }
        var hz = targetHz
        // Fold down by octaves until at/under the flash cap. Bounded iteration: even
        // from a huge input this terminates quickly (halving), and we guard the count.
        var guardCount = 0
        while hz > maxVisualFlashHz && guardCount < 64 {
            hz /= 2
            guardCount += 1
        }
        guard hz <= maxVisualFlashHz, !isInHazardBand(hz), hz > 0 else { return nil }
        return hz
    }

    /// Whether a frequency lies within the photosensitive hazardous band.
    public static func isInHazardBand(_ hz: Double) -> Bool {
        hz >= hazardBandLowerHz && hz <= hazardBandUpperHz
    }

    // MARK: - Phase (sample-accurate gating; pure, render-thread safe)

    /// Normalized phase in [0, 1) of a pulse of `hz` at absolute time `t` seconds, with
    /// an optional phase offset (also normalized). Returns 0 for a non-positive/NaN rate
    /// (steady). Pure arithmetic — safe to call from the audio render block.
    public static func phase(atSeconds t: Double, hz: Double, phaseOffset: Double = 0) -> Double {
        guard hz.isFinite, hz > 0, t.isFinite else { return 0 }
        let raw = t * hz + phaseOffset
        let frac = raw - raw.rounded(.down)
        return frac < 0 ? frac + 1 : frac
    }

    /// A raised-cosine (0…1) gate envelope for the pulse at time `t` — smooth, click-free
    /// isochronic gating (a hard square gate clicks and is harsher than the evidence base
    /// warrants). Peaks once per cycle. Pure; render-thread safe.
    public static func gate(atSeconds t: Double, hz: Double, phaseOffset: Double = 0) -> Double {
        let p = phase(atSeconds: t, hz: hz, phaseOffset: phaseOffset)
        // 0.5·(1 − cos(2πp)) → 0 at p=0, 1 at p=0.5, 0 at p=1: one smooth swell per cycle.
        return 0.5 * (1 - cos(2 * Double.pi * p))
    }
}
