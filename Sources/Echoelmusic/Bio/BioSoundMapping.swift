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
    /// so the guide reads consistently with the numbers above it. Targets mirror the
    /// audited applyBioReactive routing: coherence opens the filter + harmonics,
    /// heart rate drives vibrato + filter-sweep speed, HRV opens the reverb, breath
    /// widens filter motion and can swell the sound.
    public static let all: [BioSoundMapping] = [
        BioSoundMapping(
            id: "heartRate",
            source: "Heart rate",
            target: "Vibrato & filter movement",
            direction: "a faster pulse adds a gentle vibrato and quickens the filter sweep"),
        BioSoundMapping(
            id: "hrv",
            source: "Heart-rate variability",
            target: "Reverb & sense of space",
            direction: "more variability opens the reverb, so the sound settles into a larger space"),
        BioSoundMapping(
            id: "coherence",
            source: "Coherence",
            target: "Filter brightness & harmonics",
            direction: "higher coherence opens the filter and makes the tone brighter and more harmonic"),
        BioSoundMapping(
            id: "breath",
            source: "Breath",
            target: "Filter motion & swell",
            direction: "deeper breathing widens the filter's movement and can swell the sound with each breath"),
    ]
}
