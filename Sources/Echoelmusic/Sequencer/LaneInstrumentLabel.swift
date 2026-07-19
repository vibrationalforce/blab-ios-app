// LaneInstrumentLabel.swift
// REIHENFOLGE item 3 (externe AUv3 sichtbar/erlebbar): the pure, tested
// formatter for a track's instrument + FX "Belegung" — what a lane head shows
// so the external instrument/FX assignment is LEGIBLE per track. The doors to
// host third-party AUv3 exist (since 07810ba); this makes the resulting
// assignment visible without any UI-thread guesswork.
//
// Honest labels only (the "no lying label" rule, TrackInstrument.swift:34): a
// lane with NO instrument and NO effects returns nil — the caller decides how to
// render "empty" (dash, default voice name), the formatter never fabricates one.
//
// Foundation-only, Sequencer/ (uses TimelineLane / TrackInstrument / AUPluginRef,
// all same-module); NOT DSP/ (stays isolated for the AUv3 target).

import Foundation

public enum LaneInstrumentLabel {

    /// The instrument name shown on a track head: an external AU instrument wins
    /// (its plugin name), else the built-in voice's brand name, else nil (no
    /// instrument assigned — a bare/audio lane).
    public static func instrumentName(instrument: AUPluginRef?,
                                      builtin: TrackInstrument?) -> String? {
        if let instrument { return instrument.name }
        if let builtin { return builtin.displayName }
        return nil
    }

    /// A compact FX-chain summary: nil when empty, else the count as "N FX"
    /// (e.g. "1 FX", "3 FX"). Full names stay available via `effects` for a
    /// detail view.
    public static func effectsSummary(_ effects: [AUPluginRef]) -> String? {
        guard !effects.isEmpty else { return nil }
        return "\(effects.count) FX"
    }

    /// The whole one-line Belegung for a track head:
    ///   "Instrument"  ·  "Instrument · N FX"  ·  "N FX" (FX-only)  ·  nil (empty).
    public static func summary(instrument: AUPluginRef?, builtin: TrackInstrument?,
                               effects: [AUPluginRef]) -> String? {
        let inst = instrumentName(instrument: instrument, builtin: builtin)
        let fx = effectsSummary(effects)
        switch (inst, fx) {
        case let (i?, f?): return "\(i) · \(f)"
        case let (i?, nil): return i
        case let (nil, f?): return f
        case (nil, nil):   return nil
        }
    }

    /// Convenience over a whole lane.
    public static func summary(for lane: TimelineLane) -> String? {
        summary(instrument: lane.instrument, builtin: lane.builtinInstrument,
                effects: lane.effects)
    }
}
