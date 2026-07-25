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

    /// Whether `driver`'s underlying field was actually MEASURED in this frame.
    ///
    /// `amount` cannot express this: it returns a clamped [0..1] number, and 0 is both
    /// "the bottom of the scale" and "no reading". For a display that distinguishes the
    /// two — which any display of a body signal must — this is the gate.
    ///
    /// Note `breath` is the one driver whose gate reads a DIFFERENT field than `amount`:
    /// the amount comes from `breathPhase`, but only `breathRate` can say whether any
    /// respiration was measured at all (0 is a meaningful phase, so `breathPhase` cannot
    /// answer for itself — and the HealthKit path leaves it at a 0.5 placeholder that
    /// would otherwise render as a confident half-scale reading). The other three encode
    /// "unavailable" as 0 directly — heart rate is non-zero only on a confident lock, and
    /// coherence is 0 on any source without beat-to-beat RR (HealthKit, which does
    /// provide a real HRV from SDNN — it is coherence alone that it cannot compute).
    public static func isMeasured(_ driver: Driver, in frame: BioSampleFrame) -> Bool {
        switch driver {
        case .breath:    return frame.hasMeasuredBreath
        case .coherence: return frame.coherence > 0
        case .hrv:       return frame.hrvNormalized > 0
        case .heartRate: return frame.heartRateBPM > 0
        }
    }

    /// `amount(forMappingID:in:)` for DISPLAY: `nil` where the field was not measured,
    /// so the row can render "—" instead of a specific "0.00" the body never produced.
    /// An unknown id is also nil (it has no driver, so nothing measured it).
    public static func measuredAmount(forMappingID id: String, in frame: BioSampleFrame) -> Float? {
        guard let driver = Driver(rawValue: id), isMeasured(driver, in: frame) else { return nil }
        return amount(driver, in: frame)
    }
}
