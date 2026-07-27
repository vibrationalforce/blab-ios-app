//
//  LoudnessTarget.swift
//  Echoelmusic
//
//  Delivery loudness targets (EBU R128 / streaming) and the pure compliance check
//  the Master + Broadcast readouts use to colour the integrated LUFS and true-peak.
//  Pure value type — no UI, no audio — so the compliance logic is unit-tested.
//

import Foundation

public enum LoudnessTarget: String, CaseIterable, Identifiable, Sendable {
    case off
    case streaming      // YouTube / Spotify / Apple Music ≈ −14 LUFS
    case podcast        // Apple Podcasts ≈ −16 LUFS
    case broadcastEBU   // EBU R128 broadcast −23 LUFS
    case cinema         // theatrical −24 LUFS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:          return "No target"
        case .streaming:    return "Streaming (−14)"
        case .podcast:      return "Podcast (−16)"
        case .broadcastEBU: return "Broadcast (−23)"
        case .cinema:       return "Cinema (−24)"
        }
    }

    /// Target integrated loudness in LUFS (nil = no target selected).
    public var integratedLUFS: Float? {
        switch self {
        case .off:          return nil
        case .streaming:    return -14
        case .podcast:      return -16
        case .broadcastEBU: return -23
        case .cinema:       return -24
        }
    }

    /// Maximum allowed true peak (dBTP) for the delivery spec.
    public var maxTruePeakDb: Float {
        switch self {
        case .off:          return 0          // unused when off
        case .streaming, .podcast: return -1
        case .broadcastEBU: return -1
        case .cinema:       return -2
        }
    }

    /// ± tolerance (LU) counted as "on target".
    public static let tolerance: Float = 1.0

    /// The loudness an export should normalise to for a persisted raw setting —
    /// `nil` meaning DO NOT NORMALISE.
    ///
    /// This exists to keep two different nils apart, which is the bug it fixes. The
    /// old call site was `LoudnessTarget(rawValue: raw)?.integratedLUFS ?? -14`, and
    /// optional-chaining flattened both of them onto −14:
    ///   · the user deliberately choosing "No target" (`.off` → `integratedLUFS` nil), and
    ///   · an unreadable/absent raw value (the enum init returning nil).
    /// So picking "No target" normalised the export to −14 LUFS — byte-identical to
    /// picking "Streaming (−14)". A control that reads "off" and is not off.
    ///
    /// The two cases genuinely differ and are now handled separately: a corrupted
    /// setting must fall back to the registered DEFAULT (`.streaming`, see
    /// `StudioDefaultKeys`), never silently disable normalisation; only an explicit
    /// `.off` returns nil.
    ///
    /// Named `resolvedLUFS`, not `exportTargetLUFS` (2026-07-27): it is no longer the
    /// export stage's private resolver. `AutoMixChain` reads it too, because the export
    /// switch alone was only half the control — that stage had its own hardcoded −14 with
    /// no writer, and `RetroCapture` taps DOWNSTREAM of it, so the level was already baked
    /// into the captured file before the export path was ever consulted. Both stages now
    /// resolve the one setting through this one function.
    public static func resolvedLUFS(rawValue: String) -> Float? {
        (LoudnessTarget(rawValue: rawValue) ?? .streaming).integratedLUFS
    }
}

public enum LoudnessCompliance: Sendable {
    case unknown    // no target, or still silent
    case onTarget
    case tooLoud
    case tooQuiet
}

extension LoudnessTarget {

    /// Compliance of a measured integrated loudness against this target. `floor` is
    /// the meter's silence floor — readings at/near it are "unknown" (nothing playing).
    public func compliance(integratedLUFS v: Float, floor: Float) -> LoudnessCompliance {
        guard let t = integratedLUFS else { return .unknown }
        if v <= floor + 1 { return .unknown }
        if v > t + Self.tolerance { return .tooLoud }
        if v < t - Self.tolerance { return .tooQuiet }
        return .onTarget
    }

    /// True if a measured true peak exceeds the delivery ceiling (only when a target
    /// is set and the reading is real, i.e. above `floor`).
    public func truePeakExceeds(_ db: Float, floor: Float) -> Bool {
        guard integratedLUFS != nil, db > floor + 1 else { return false }
        return db > maxTruePeakDb + 0.01
    }
}
