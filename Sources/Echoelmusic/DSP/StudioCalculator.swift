// StudioCalculator.swift
// Echoel — the production math behind tempo-synced effects, LFOs and loop/stem
// cutting. Converts a tempo (BPM, two-decimal precision) into note-division
// times in seconds / milliseconds / Hz / samples, with dotted and triplet
// variants, at a chosen sample rate. Pure value types (Foundation only, no audio,
// no SwiftUI) so the math is fully unit-tested and reusable from the AUv3 target.
//
// Reference (matches a 75.00 BPM / 44100 Hz / 4-4 session):
//   1/4 straight = 800 ms · dotted = 1200 ms · triplet ≈ 533 ms
//   1 bar (4 beats) = 3.2 s = 141 120 samples

import Foundation

/// A musical note division, as a multiple of a quarter note.
public enum NoteDivision: String, CaseIterable, Sendable, Identifiable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth

    public var id: String { rawValue }

    /// Length in quarter notes (1/4 == 1).
    public var quarters: Double {
        switch self {
        case .whole:        return 4
        case .half:         return 2
        case .quarter:      return 1
        case .eighth:       return 0.5
        case .sixteenth:    return 0.25
        case .thirtySecond: return 0.125
        case .sixtyFourth:  return 0.0625
        }
    }

    /// Common label ("1/4", "1/8", …).
    public var label: String {
        switch self {
        case .whole:        return "1/1"
        case .half:         return "1/2"
        case .quarter:      return "1/4"
        case .eighth:       return "1/8"
        case .sixteenth:    return "1/16"
        case .thirtySecond: return "1/32"
        case .sixtyFourth:  return "1/64"
        }
    }
}

/// Straight, dotted (×1.5) or triplet (×2/3) feel.
public enum NoteModifier: String, CaseIterable, Sendable, Identifiable {
    case straight, dotted, triplet
    public var id: String { rawValue }

    public var factor: Double {
        switch self {
        case .straight: return 1.0
        case .dotted:   return 1.5
        case .triplet:  return 2.0 / 3.0
        }
    }

    public var label: String {
        switch self {
        case .straight: return "Normal"
        case .dotted:   return "Dotted"
        case .triplet:  return "Triplet"
        }
    }
}

/// Tempo-aware production calculator. `bpm` carries two-decimal precision.
public struct StudioCalculator: Sendable, Equatable {
    public var bpm: Double
    public var sampleRate: Double
    public var beatsPerBar: Int

    public init(bpm: Double = 120.00, sampleRate: Double = 44_100, beatsPerBar: Int = 4) {
        self.bpm = bpm
        self.sampleRate = sampleRate
        self.beatsPerBar = beatsPerBar
    }

    /// Seconds per quarter note. Guards against a zero/negative tempo.
    public var quarterNoteSeconds: Double {
        guard bpm > 0 else { return 0 }
        return 60.0 / bpm
    }

    /// Duration of a division (with feel) in seconds.
    public func seconds(_ division: NoteDivision, _ modifier: NoteModifier = .straight) -> Double {
        quarterNoteSeconds * division.quarters * modifier.factor
    }

    /// Duration in milliseconds.
    public func milliseconds(_ division: NoteDivision, _ modifier: NoteModifier = .straight) -> Double {
        seconds(division, modifier) * 1000.0
    }

    /// LFO/repeat rate in Hz (cycles per second) for a division. Zero-safe.
    public func hertz(_ division: NoteDivision, _ modifier: NoteModifier = .straight) -> Double {
        let s = seconds(division, modifier)
        guard s > 0 else { return 0 }
        return 1.0 / s
    }

    /// Length in samples at the current sample rate.
    public func samples(_ division: NoteDivision, _ modifier: NoteModifier = .straight) -> Double {
        seconds(division, modifier) * sampleRate
    }

    /// Length of one bar in seconds.
    public var barSeconds: Double {
        quarterNoteSeconds * Double(beatsPerBar)
    }

    /// Length of `bars` bars in seconds — for cutting loops/stems (2, 4, 8, 16, 32…).
    public func loopSeconds(bars: Int) -> Double {
        barSeconds * Double(max(0, bars))
    }

    /// Length of `bars` bars in whole samples (rounded) — a sample-accurate loop length.
    public func loopSamples(bars: Int) -> Int {
        Int((loopSeconds(bars: bars) * sampleRate).rounded())
    }

    // MARK: - Body-seeded tempo

    /// Octave-fold a body-derived SEED tempo so a doubled rPPG pulse can't set a runaway
    /// beat (founder: "springt ständig auf 196 bpm"). A doubled estimate (≈196 bpm) yields
    /// a suggested tempo ~134–160; a real seated/resting body seeds ≤ ~110. So anything
    /// above ~130 is almost always a 2× artifact — halve it back into the musical range,
    /// then clamp to a playable window. Pure + deterministic (unit-tested in
    /// SeedTempoTests; lives here — not on the SwiftUI view — so Linux CI executes it).
    public static func seedTempo(_ t: Double) -> Double {
        var t = t
        while t > 130 { t /= 2 }
        return Swift.max(50, Swift.min(160, t))
    }

    /// Octave-fold a body tempo INTO a genre's BPM window (audit B4). `seedTempo`
    /// folds everything to 50–130, which made every genre play at resting-heart
    /// tempo — Punk (160–210) or Trap (130–150) were unreachable. Here the pulse
    /// still DRIVES the beat, but at the genre's rhythmic level: doubling/halving
    /// preserves the felt relationship to the heart (66 bpm body → 132 bpm Trap =
    /// the same pulse, double-time), and the final clamp guarantees the genre's
    /// identity window. Same runaway-safety as seedTempo: a 2× rPPG artifact folds
    /// back down instead of slamming the clock. Both while-loops terminate for any
    /// positive input (each strictly approaches the range from one side). Pure +
    /// deterministic (Linux-CI-tested in StudioCalculatorTests).
    public static func genreTempo(_ t: Double, into range: ClosedRange<Double>) -> Double {
        guard t.isFinite, t > 0, range.lowerBound > 0 else { return range.lowerBound }
        var t = t
        while t < range.lowerBound { t *= 2 }
        while t > range.upperBound { t /= 2 }
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, t))
    }

    // MARK: - Bar-aligned loop trim window (audit C6/C7)

    /// Where to cut EXACTLY one loop out of a longer capture so the written WAV
    /// loops seamlessly on the DAW grid. The capture ends "now"; the last downbeat
    /// was `secondsSinceBarStart` ago (PatternEngine stamps it), so the window is
    /// the `loopSeconds` immediately BEFORE that downbeat:
    ///   start = fileDuration − secondsSinceBarStart − loopSeconds
    /// Returns nil when the capture is too short for an aligned cut (caller falls
    /// back to an unaligned cut or an untrimmed export). Pure + deterministic
    /// (Linux-CI-tested in StudioCalculatorTests).
    public static func loopTrimWindow(fileDuration: Double, loopSeconds: Double,
                                      secondsSinceBarStart: Double)
        -> (start: Double, duration: Double)? {
        guard fileDuration.isFinite, fileDuration > 0,
              loopSeconds.isFinite, loopSeconds > 0 else { return nil }
        let ago = secondsSinceBarStart.isFinite ? Swift.max(0, secondsSinceBarStart) : 0
        let start = fileDuration - ago - loopSeconds
        guard start >= 0 else { return nil }
        return (start, loopSeconds)
    }

    // MARK: - Evolve hold ("halten wenn eingerastet", founder 2026-07-04)

    /// Whether the ~30 s AUTOMATIC evolve tick should re-seed the take, or HOLD.
    /// The founder's "nervig": the music re-rolled every evolve tick even when the
    /// pulse was calmly locked, so a meditative phrase never settled. Rule:
    ///   • pulse NOT settled → HOLD (don't chase warm-up / motion noise);
    ///   • settled, no baseline yet → RE-SEED (first lock captures the phrase);
    ///   • settled WITH a baseline → re-seed ONLY when the body meaningfully moved
    ///     (heart rate ≥ `bpmThreshold`, or coherence ≥ `coherenceThreshold`),
    ///     otherwise HOLD the current take.
    /// The no-body case (no usable frame at all) is handled by the caller, which
    /// keeps a bodyless demo loop gently evolving. Pure + Linux-CI-tested.
    public static func shouldReseedOnEvolve(settled: Bool, hasBaseline: Bool,
                                            currentBPM: Double, baselineBPM: Double,
                                            currentCoherence: Double, baselineCoherence: Double,
                                            bpmThreshold: Double = 5,
                                            coherenceThreshold: Double = 0.15) -> Bool {
        guard settled else { return false }
        guard hasBaseline else { return true }
        let bpmDrift = abs(currentBPM - baselineBPM)
        let cohDrift = abs(currentCoherence - baselineCoherence)
        let driftFinite = bpmDrift.isFinite && cohDrift.isFinite
        // A non-finite reading can't prove stability — re-seed rather than freeze on junk.
        guard driftFinite else { return true }
        return bpmDrift >= bpmThreshold || cohDrift >= coherenceThreshold
    }
}
