//
//  BioModulationMap.swift
//  Echoelmusic — Core (pure, cross-platform)
//
//  REIHENFOLGE item 2 ("Bio-Modulation live sichtbar"): the data spine for a
//  legible readout of WHICH sound parameters the body is currently moving, and
//  by how much. It surfaces the ALWAYS-ON core bio→sound mapping that lives in
//  `EchoelDDSP.applyBioReactive` — the real, audible expression, not the
//  (default-empty) user `ModulationMatrix`.
//
//  Design law — single source of truth: this model surfaces each mapping's
//  DRIVER value (coherence / heart-rate / HRV / breath, all normalized [0..1]
//  straight from the live `BioSampleFrame`) plus an honest human description of
//  its target. It deliberately does NOT re-derive the target parameter's value
//  (brightness Hz, vibrato cents, …) — duplicating `applyBioReactive`'s
//  coefficients here would silently drift from the DSP. The driver amount is
//  exactly what the user needs to see ("your coherence is high → the filter is
//  open"), and it needs no DSP-internal read.
//
//  Pure value types + Foundation only, so it is Linux-CI testable and the leaf
//  view can compute `amounts(for:)` cheaply in its OWN body — never in a
//  root/ancestor (the 10 Hz `@Observable` menu-freeze law).
//

import Foundation

/// One canonical bio→sound relationship, mirroring `EchoelDDSP.applyBioReactive`
/// and the CLAUDE.md "DDSP Bio-Mappings" table.
public struct BioModulationLink: Identifiable, Sendable, Equatable {

    /// The physiological signal that drives the mapping. Each maps to a single
    /// normalized [0..1] channel of the live `BioSampleFrame`.
    public enum Driver: String, Sendable, CaseIterable {
        case coherence
        case heartRate
        case hrv
        case breath

        /// Short user-facing label (matches the bio strip's terse vocabulary).
        public var label: String {
            switch self {
            case .coherence: return "Coherence"
            case .heartRate: return "Heart"
            case .hrv:       return "HRV"
            case .breath:    return "Breath"
            }
        }
    }

    /// The physiological driver.
    public let driver: Driver
    /// The sound parameter it moves (concise audio term, as used in the studio UI).
    public let targetName: String
    /// One honest line on HOW it moves the sound (no health claim).
    public let detail: String

    public var id: String { driver.rawValue }

    public init(driver: Driver, targetName: String, detail: String) {
        self.driver = driver
        self.targetName = targetName
        self.detail = detail
    }
}

/// The canonical, always-on bio→sound map + live driver-amount extraction.
public enum BioModulationMap {

    /// The heart-rate normalization used across Echoel (appex `pullSharedVitals`,
    /// the AUv3 heartRate param): BPM in `[minBPM, maxBPM]` → `[0..1]`.
    public static let minBPM: Float = 40
    public static let maxBPM: Float = 200

    /// The canonical links, in a stable display order. Mirrors
    /// `EchoelDDSP.applyBioReactive` so the readout is truthful, not decorative.
    public static let links: [BioModulationLink] = [
        BioModulationLink(
            driver: .coherence,
            targetName: "Brightness / Filter",
            detail: "Higher coherence opens the filter and warms the harmonics."
        ),
        BioModulationLink(
            driver: .heartRate,
            targetName: "Vibrato / Pulse",
            detail: "A faster pulse deepens vibrato and speeds the filter sweep."
        ),
        BioModulationLink(
            driver: .hrv,
            targetName: "Space / Reverb",
            detail: "More heart-rate variability adds reverb space."
        ),
        BioModulationLink(
            driver: .breath,
            targetName: "Envelope",
            detail: "Breath phase shapes the amplitude envelope in and out."
        )
    ]

    /// The live [0..1] amount for a driver, read straight from the frame.
    /// Heart rate is normalized on `[minBPM, maxBPM]`; the others are already
    /// normalized channels. Always finite and clamped to `[0..1]`.
    public static func amount(_ driver: BioModulationLink.Driver,
                              in frame: BioSampleFrame) -> Float {
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

    /// Every link paired with its current live amount, in `links` order —
    /// the exact list a readout leaf view renders.
    public static func amounts(for frame: BioSampleFrame) -> [(link: BioModulationLink, amount: Float)] {
        links.map { (link: $0, amount: amount($0.driver, in: frame)) }
    }
}
