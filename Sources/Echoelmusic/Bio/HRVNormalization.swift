// HRVNormalization.swift
// ONE documented source of truth for mapping a time-domain HRV magnitude (in ms) onto
// the shared [0,1] `hrvNormalized` vagal-tone knob.
//
// WHY THIS EXISTS (consistency fix, 3-team audit 2026-07-23): the three live bio sources
// each carried their OWN divisor for the SAME field — the camera divided RMSSD by 200,
// the BLE strap divided RMSSD by 100, and HealthKit divided SDNN by 100 (through a
// constant misleadingly named `rmssdNormalizationMax`). Identical physiology (e.g.
// RMSSD = 60 ms) therefore produced 0.30 from the camera but 0.60 from the strap into a
// field EVERY downstream consumer treats as one uniform 0…1 scale (OSC /bio/heart/hrv,
// ADM-OSC object elevation, synth brightness, BioComposer.hrvHumanize). That is
// copy-drift, not deliberate per-source calibration (no divisor carried a justification).
//
// This collapses all sources onto the house "excellent ≈ 100 ms" ceiling — the value BLE
// and HealthKit already used — so the camera (the outlier at 200) now agrees with the
// strap and the Watch. SDNN and RMSSD are distinct HRV metrics, but at rest they share
// the same order of magnitude; one common display/modulation ceiling is the honest,
// consistent choice for a single 0…1 knob (this normalizes for display, it does not
// claim the two metrics are equal).
//
// Pure Foundation — deterministic, unit-tested, no actor isolation.

import Foundation

/// Maps a time-domain HRV magnitude in milliseconds (RMSSD from a beat-to-beat source, or
/// SDNN from HealthKit) onto the shared [0,1] `hrvNormalized` display/modulation knob.
public enum HRVNormalization {

    /// The HRV ceiling in ms that maps to 1.0. ~100 ms is "excellent", ~20 ms is "low".
    /// Shared by ALL bio sources so identical physiology reads identically regardless of
    /// whether it came from the camera, a BLE strap, or HealthKit/Apple Watch.
    public static let ceilingMs: Double = 100.0

    /// Normalize an HRV magnitude (ms) into [0,1]. Non-finite, zero, or negative input → 0
    /// (an honest "no usable HRV"), never a NaN or an out-of-range value.
    public static func normalize(_ milliseconds: Double) -> Double {
        guard milliseconds.isFinite, milliseconds > 0 else { return 0 }
        return Swift.min(milliseconds / ceilingMs, 1.0)
    }
}
