//
//  BioModulationMap.swift
//  Echoelmusic — Core (pure, cross-platform)
//
//  REIHENFOLGE item 2 ("Bio-Modulation live sichtbar"): the LIVE half of the
//  "how your body shapes the sound" readout. It answers, right now, HOW MUCH each
//  body signal is contributing — the moving bar next to each static routing row.
//
//  Single source of truth: the static routing (which signal → which sound target,
//  and the plain-language direction) is `BioSoundMapping.all` — that list is the
//  ONLY place the mappings are declared, so the display never drifts. This type
//  adds ONLY the live [0..1] amount, keyed by the SAME `BioSoundMapping.id`
//  strings, read straight from the live `BioSampleFrame`. It deliberately does NOT
//  re-derive the DSP target values (brightness Hz, vibrato cents…) — duplicating
//  `EchoelDDSP.applyBioReactive`'s coefficients would silently drift from the DSP.
//  The driver amount is exactly what the user needs to see ("your coherence is
//  high → this row is near full").
//
//  Pure value types + Foundation only, so it is Linux-CI testable and a readout
//  leaf can compute the amount cheaply in its OWN body — never in a root/ancestor
//  (the 10 Hz `@Observable` menu-freeze law).
//

import Foundation

/// Live [0..1] contribution of each bio driver behind a `BioSoundMapping` row.
public enum BioModulationMap {

    /// The heart-rate normalization used across Echoel (appex `pullSharedVitals`,
    /// the AUv3 heartRate param): BPM in `[minBPM, maxBPM]` → `[0..1]`.
    public static let minBPM: Float = 40
    public static let maxBPM: Float = 200

    /// The physiological signal behind a `BioSoundMapping`. Raw values MATCH
    /// `BioSoundMapping.id` (heartRate / hrv / coherence / breath), so a row's
    /// live amount is looked up by its own stable id.
    public enum Driver: String, Sendable, CaseIterable {
        case coherence
        case heartRate
        case hrv
        case breath
    }

    /// The live [0..1] amount for a driver, read straight from the frame.
    /// Heart rate is normalized on `[minBPM, maxBPM]`; the others are already
    /// normalized channels. Always finite and clamped to `[0..1]`.
    public static func amount(_ driver: Driver, in frame: BioSampleFrame) -> Float {
        let raw: Float
        switch driver {
        case .coherence: raw = frame.coherence
        case .heartRate:
            let span = maxBPM - minBPM
            raw = span > 0 ? (frame.heartRateBPM - minBPM) / span : 0
        case .hrv:       raw = frame.hrvNormalized
        case .breath:    raw = frame.breathPhase
        }
        guard raw.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, raw))
    }

    /// The live [0..1] amount for a `BioSoundMapping` row, by its stable id.
    /// An unknown id yields `0` (no crash), so the display degrades safely if a
    /// routing row is ever added without a matching driver.
    public static func amount(forMappingID id: String, in frame: BioSampleFrame) -> Float {
        guard let driver = Driver(rawValue: id) else { return 0 }
        return amount(driver, in: frame)
    }
}
