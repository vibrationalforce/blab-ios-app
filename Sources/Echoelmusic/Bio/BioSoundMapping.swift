//
//  BioSoundMapping.swift
//  Echoelmusic — Bio
//
//  REIHENFOLGE item 2 ("Bio-Modulation live sichtbar"): the legible answer to
//  "which sound parameters does my biofeedback move?" — shown in the reachable
//  bio guide (BioMetricsGuideView), so the founder principle
//  ("die Musik verändert sich mit dem Biofeedback") is not just audible but
//  READABLE.
//
//  This is a STABLE DESIGN FACT — which body signal drives which sound target,
//  and in which direction — NOT the live coefficients (those live in
//  EchoelDDSP.applyBioReactive and may be tuned without changing this routing).
//  Because it is static, the guide renders it with ZERO live observation: the
//  10 Hz menu-freeze law never applies here. Pure Foundation value type, unit-
//  tested off-device. Keep this in sync with the ROUTING (not the numbers) of
//  applyBioReactive if a mapping's source→target ever changes.
//

import Foundation

/// One body-signal → sound-character routing, for the "how your body shapes the
/// sound" section of the bio guide.
public struct BioSoundMapping: Sendable, Equatable, Identifiable {
    /// Stable id — matches the corresponding bio-strip metric key.
    public let id: String
    /// The body signal (e.g. "Coherence").
    public let source: String
    /// The sound character it moves (e.g. "Filter brightness & harmonics").
    public let target: String
    /// A plain-language phrase for the direction of the effect.
    public let direction: String

    public init(id: String, source: String, target: String, direction: String) {
        self.id = id
        self.source = source
        self.target = target
        self.direction = direction
    }

    /// The canonical map, in the SAME order as the bio strip (HR · HRV · Coh · Breath),
    /// so the guide reads consistently with the numbers above it.
    ///
    /// ⭐ SINCE #638 THE TARGETS ARE THE SAME FOUR SETS `AlwaysOnBioChannel.shapedParameters`
    /// DECLARES, and that is the point of this rewrite. That switch is the app's audited,
    /// in-app truth table for exactly this question — `coherence → filterCutoff · brightness ·
    /// harmonicity · noiseLevel` · `hrv → brightness` · `heartRate → vibrato · brightness` ·
    /// `breathPhase → amplitude` — and before #638 this list disagreed with it on THREE of its
    /// four rows while both were rendered to the same user, in two sheets one chip apart. Two
    /// spellings of one decision (#416), and they had drifted.
    ///
    /// ⛔ HRV DID NOT "OPEN THE REVERB", AND THAT WAS ONLY THE FIRST OF THREE. The row said
    /// `"Reverb & sense of space"`. The write is real — `applyBioReactive` sets `reverbMix`
    /// from `hrvVariability` — and the READ is gated: `reverbMix` is consumed only inside
    /// `if Self.useConvolutionReverb, …`, a flag that is `false` with no assignment anywhere in
    /// `Sources/`. A correct write into a stage switched off at runtime. CLAUDE.md struck the
    /// mapping at #546; the sweep corrected the DDSP table and the always-on row and never
    /// looked here, so this file went on being the app's most explicit statement of it — a
    /// whole sentence, in the sheet whose only job is to explain what the body moves.
    ///
    /// ⛔ HEART RATE DID NOT "QUICKEN THE FILTER SWEEP" EITHER, and this one was worse, because
    /// nothing was ever gated: the sweep it described is the heart-rate LFO **deleted at #331**,
    /// whose tombstone sits in `applyBioReactive` ("AN LFO STOOD HERE AND IS DELETED").
    /// `filterLFORate` has no bio writer at all. This list was the last surface in the app still
    /// selling it.
    ///
    /// ⛔ AND BREATH DID NOT "WIDEN THE FILTER'S MOVEMENT" — the half-true row, and the one the
    /// engine itself forbids in so many words. The swell half is real (`breathPhase` →
    /// `amplitude`, every profile). The filter-motion half rides `breathDepth`, which has NO
    /// PRODUCER: both `BioParams` construction sites pass the literal `0.5`, so the factor is
    /// exactly 1.0 on every frame the shipped app can produce. `applyBioReactive` says at that
    /// line: *"the MODULATION half is dormant … must not be claimed as live in any user-facing
    /// copy."* The word this row used was literally "deeper" breathing — the one breath channel
    /// nothing measures.
    ///
    /// ⚠️ SO THE SYNC RULE IN THIS FILE'S HEADER IS SHARPENED, not merely obeyed. It says to
    /// track the ROUTING and not the numbers, and the routing IS there in all three cases — a
    /// real assignment, in `applyBioReactive`, with the right driver on the right side. What
    /// failed is one step further on: **a mapping is real when the WRITE reaches an UNGATED
    /// READ, from a channel that has a PRODUCER.** Following a value one hop looks like
    /// diligence and stops one hop early; all three of these were verified that way once.
    ///
    /// ⚠️ THE HONEST STATEMENT ABOUT REVERB IS NARROWER THAN "NO PATH EXISTS", which is what the
    /// first draft of this block wrote and a reviewer refuted with the code. `FXBioModulator` is
    /// constructed and started at app launch, writes `c.reverb.mix` for an `FXModTarget
    /// .reverbMix` route and even force-enables the stage, `.hrv` passes `hasProducer`, and
    /// `EchoelFXView`'s "Add bio modulation…" menu builds such a route behind a reachable door.
    /// So a player CAN make HRV move the algorithmic `EchoelReverb` — by choosing to. What does
    /// not exist is an AUTOMATIC HRV → reverb mapping, and an automatic mapping is the only
    /// thing this table describes. (`ADMOSCSender` also sends `hrvNormalized` to an immersive
    /// object's elevation — a real HRV → space mapping, in a different subsystem, gated on the
    /// `adm.out` sink and not part of the sound the player hears from the device.)
    public static let all: [BioSoundMapping] = [
        BioSoundMapping(
            // ⚠️ "on patches that have one" is not hedging. On the anchored path
            // `vibratoDepth = bioBaseVibratoDepth * factor`, so for the many shipped patches
            // whose own `vibratoDepth` is 0 the factor multiplies zero and a faster pulse adds
            // no vibrato at all. The brightness term is the half that always applies — and it
            // was MISSING from this row before #638, which is an under-claim sitting inside an
            // over-claim.
            id: "heartRate",
            source: "Heart rate",
            target: "Vibrato & tone brightness",
            direction: "a faster pulse lifts the tone a little, and deepens the vibrato on patches that have one"),
        BioSoundMapping(
            // ⚠️ The target that IS live: `hrvDev` is one of three terms summed into
            // `targetBrightness`, and `brightness` is the SPECTRAL-SHAPE exponent —
            // `computeShapeAmplitudes` divides each partial by `n^(1.5 − brightness)`, so a
            // higher value lifts the upper harmonics. It is NOT the filter: `targetCutoff` is a
            // function of coherence alone in BOTH branches. The first draft of this row said
            // "opens the filter" and would have re-introduced, one surface over, exactly the
            // kind of claim #546 removed. ⚠️ And it said the mapping holds "on the anchored-
            // patch path — the shipping one", which UNDER-states it: the legacy sentinel branch
            // carries the identical 0.20 coefficient, so this is true of the patched voice and
            // the raw bio voice alike, with no "which path?" caveat. The coefficient equals
            // heart rate's and is two thirds of coherence's — "a little" is right against
            // coherence and exact against heart rate.
            // (`harmonicity = 0.40 + hrv * 0.50` also exists, but only under the
            // `.harmonicSeries` map profile, and a player cannot see which profile is active —
            // naming a mapping he cannot attribute would mislead more than omitting it.)
            id: "hrv",
            source: "Heart-rate variability",
            target: "Overtone brightness",
            direction: "more beat-to-beat variation lifts the upper harmonics a little, so the tone opens up"),
        BioSoundMapping(
            // The only row that was already true, and the widest: coherence is the one channel
            // that moves the FILTER (`targetCutoff`), and it also moves brightness, harmonicity
            // and noise. "cleaner" is the noise term, which the old copy left out.
            id: "coherence",
            source: "Coherence",
            target: "Filter brightness & harmonics",
            direction: "higher coherence opens the filter and makes the tone brighter, more harmonic and cleaner"),
        BioSoundMapping(
            // Amplitude only — one clean swell per breath, from `breathPhase`, on every profile.
            // The filter-motion half of the old copy is struck; see the ⛔ block above.
            id: "breath",
            source: "Breath",
            target: "Swell",
            direction: "the sound swells and settles once with each breath you take"),
    ]
}
