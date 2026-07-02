import Foundation

// TempoMatch.swift
// Echoel — pure tempo-matching math for "Vorhören im Mastertempo": compute a loop's
// native tempo and the pitch-preserving time-stretch RATE needed to fit it to the
// master (transport) tempo. Value type, no audio graph, fully unit-testable — the
// safe foundation the shared tempo-preview voice (AVAudioUnitTimePitch) will use so
// every tool (Browser · sampler · breakbeat slicer · drum machine) auditions in time.
// See scratchpads/PLAN_TEMPO_PREVIEW.md.

public enum TempoMatch {

    /// Musical clamp for the stretch rate. `AVAudioUnitTimePitch.rate` accepts 1/32…32,
    /// but a mis-set bar count shouldn't ever produce absurd speed — keep it musical.
    public static let rateRange: ClosedRange<Double> = 0.25...4.0

    /// The native tempo (BPM) of a loop that is `bars` bars long and lasts
    /// `durationSeconds`. `nil` for non-positive inputs (e.g. a one-shot with bars 0).
    /// 4/4 by default (`beatsPerBar`).
    public static func nativeBPM(durationSeconds: Double,
                                 bars: Int,
                                 beatsPerBar: Int = 4) -> Double? {
        guard durationSeconds > 0, bars > 0, beatsPerBar > 0 else { return nil }
        let beats = Double(bars * beatsPerBar)
        return beats * 60.0 / durationSeconds
    }

    /// The time-stretch rate to play a loop of `nativeBPM` at `masterBPM`, clamped to
    /// `range`. Returns 1.0 (no stretch) for non-positive inputs.
    public static func stretchRate(nativeBPM: Double,
                                   masterBPM: Double,
                                   range: ClosedRange<Double> = rateRange) -> Double {
        guard nativeBPM > 0, masterBPM > 0 else { return 1.0 }
        let r = masterBPM / nativeBPM
        return Swift.min(Swift.max(r, range.lowerBound), range.upperBound)
    }

    /// Convenience: the stretch rate straight from a loop's duration + bar length and the
    /// master tempo. A one-shot (`bars <= 0`) returns 1.0 — never stretched.
    public static func stretchRate(durationSeconds: Double,
                                   bars: Int,
                                   masterBPM: Double,
                                   beatsPerBar: Int = 4,
                                   range: ClosedRange<Double> = rateRange) -> Double {
        guard let native = nativeBPM(durationSeconds: durationSeconds,
                                     bars: bars,
                                     beatsPerBar: beatsPerBar) else { return 1.0 }
        return stretchRate(nativeBPM: native, masterBPM: masterBPM, range: range)
    }

    /// Best-guess bar length for a loop of `durationSeconds` at `masterBPM`, snapped to a
    /// power of two in `candidates` — so a well-cut loop auditions correctly with no manual
    /// entry. Picks the candidate whose implied native BPM is closest (log-ratio) to the
    /// master, i.e. the least stretching. `nil` for non-positive inputs.
    public static func guessBars(durationSeconds: Double,
                                 masterBPM: Double,
                                 beatsPerBar: Int = 4,
                                 candidates: [Int] = [1, 2, 4, 8]) -> Int? {
        guard durationSeconds > 0, masterBPM > 0, beatsPerBar > 0 else { return nil }
        var best: (bars: Int, cost: Double)?
        for bars in candidates where bars > 0 {
            guard let native = nativeBPM(durationSeconds: durationSeconds,
                                         bars: bars, beatsPerBar: beatsPerBar) else { continue }
            let cost = Swift.abs(Foundation.log(native / masterBPM))   // 0 == perfect fit
            if best == nil || cost < best!.cost { best = (bars, cost) }
        }
        return best?.bars
    }
}
