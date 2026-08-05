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
    /// the same pulse, double-time), and the fallback guarantees the genre's
    /// identity window. Same runaway-safety as seedTempo: a 2× rPPG artifact folds
    /// back down instead of slamming the clock. Pure + deterministic (pinned in the
    /// BLOCKING bundle, `Tests/CISmoke/GenreTempoFoldTests.swift`).
    ///
    /// ⛔ THE BUG THIS SHAPE EXISTS TO PREVENT (found 2026-07-29, shipped since B4).
    /// The previous body was two independent loops followed by a clamp:
    ///
    ///     while t < range.lowerBound { t *= 2 }
    ///     while t > range.upperBound { t /= 2 }
    ///     return max(lowerBound, min(upperBound, t))
    ///
    /// The second loop could halve a value straight PAST the floor, and nothing
    /// doubled it back — the clamp then pinned it to `lowerBound`. Because EVERY
    /// genre window here is narrower than an octave (contemplation 44…66 is a ratio
    /// of 1.5; psytrance 140…150 is 1.07), that was not a corner case: a body one
    /// BPM above the ceiling produced the SLOWEST tempo the genre allows.
    /// Traced on contemplation (44…66): 66 → 66, but 67 → 33.5 → **44**. 80 → **44**.
    /// 134 → 67 → 33.5 → **44**. Measured in log space — the fraction of ONE octave of
    /// body tempo that collapsed onto the floor, `log2(2·lo/hi)` — that is 41 % of
    /// contemplation (44…66), 24 % of Fläche (46…78) and 90 % of psytrance (140…150).
    /// The faster the body, the slower the music: the exact inverse of the one thing
    /// this app claims to do.
    ///
    /// The floor is still a legitimate answer when NO octave lands inside a
    /// sub-octave window — what changed is WHERE the crossover sits. It is now the
    /// geometric mean `√(2·lo·hi)` (76.2 bpm on contemplation), i.e. the point where
    /// halving and holding are equally far in musical terms. It used to sit one BPM
    /// above the ceiling.
    ///
    /// The shape below cannot regress that way, because it never returns a folded
    /// value it has not checked against BOTH bounds.
    public static func genreTempo(_ t: Double, into range: ClosedRange<Double>) -> Double {
        // `lowerBound.isFinite` is not decoration: `ClosedRange<Double>` happily holds
        // `.infinity...`, and the second loop below would spin forever on it
        // (`inf / 2 >= inf` is true and `folded` never changes). No shipped
        // `MusicStyle.tempoRange` can produce that — but the loop is the caller's to
        // feed, and a hang is a worse failure than a fallback.
        guard t.isFinite, t > 0, range.lowerBound > 0, range.lowerBound.isFinite else {
            return range.lowerBound
        }

        // Fold to the UNIQUE octave of `t` that sits in `[lowerBound, 2·lowerBound)`.
        // Both loops terminate for any finite t > 0, and neither can run away: the
        // first doubles at most ⌈log2(lowerBound / t)⌉ times and stops the instant it
        // reaches lowerBound, so it is bounded ABOVE by 2·lowerBound and can never
        // overflow; the second halves at most ⌈log2(t / lowerBound)⌉ times and stops
        // the instant another halving would cross lowerBound. Doubling and halving are
        // exact in binary floating point, so neither loop can stall on a value that
        // never changes.
        var folded = t
        while folded < range.lowerBound { folded *= 2 }
        while folded / 2 >= range.lowerBound { folded /= 2 }

        // An octave of the body lands inside the window — return it, whatever the
        // window's width. (For a window spanning a full octave this branch always
        // wins; for the narrower shipped ones it wins whenever the body's octave
        // happens to fall between the bounds, which is the common case.)
        if folded <= range.upperBound { return folded }

        // No octave lands inside — `folded` is the lowest one above the floor and it
        // overshoots the ceiling, so its half is necessarily below the floor. Those
        // two are the only neighbouring candidates. Choose by musical distance, i.e.
        // the smaller RATIO to its bound, not the smaller BPM difference: pushing a
        // 261.7 bpm candidate down to 150 (×0.57) is a bigger musical move than lifting
        // its half 130.9 up to 140 (×1.07), even though 111.7 BPM vs 9.1 BPM says the
        // opposite. Ratios are safe to compare directly — every term is > 0 here.
        let below = folded / 2
        let liftFromBelow = range.lowerBound / below      // ≥ 1
        let dropFromAbove = folded / range.upperBound     // > 1
        return dropFromAbove <= liftFromBelow ? range.upperBound : range.lowerBound
    }

    /// Nudge a genre-folded tempo toward one end of its window, without ever leaving it.
    ///
    /// ⭐ WHY THIS EXISTS, AND WHY IT IS NOT A SECOND COPY OF THE BODY→TEMPO MAPPING (#403
    /// Slice 2). `genreTempo` above OCTAVE-FOLDS, and its own doc measures what that costs:
    /// 41 % of one octave of body tempo collapses onto the floor on contemplation (44…66).
    /// Two performers whose hearts rest 30 BPM apart routinely fold to the SAME number — the
    /// founder's 2026-08-05 log shows exactly that, nine takes all reading the same tempo.
    /// This restores, AFTER the fold, a distinction the fold destroys. It is not a second
    /// opinion about the moment; it is the person, applied where the person had been erased.
    ///
    /// ⚠️ THE GENRE ALWAYS WINS, BY CONSTRUCTION, and that is the whole safety argument. The
    /// move is a FRACTION OF THE REMAINING HEADROOM toward the window's edge, so the result
    /// cannot leave `range` for any tilt — no clamp is doing the work, the shape is. #81
    /// already cost this repo one round of "erst individuell, dann klingt alles gleich"; a
    /// tilt that could cross a genre boundary would be the same mistake pointing the other
    /// way. At an edge the tilt does nothing in that direction, which is correct: the genre
    /// owns its own boundary.
    ///
    /// - Parameters:
    ///   - tilt: −1 (as slow as this genre allows this performer to be) … +1 (as fast).
    ///     **0 returns `bpm` unchanged**, which is what makes an unlearned performer
    ///     bit-identical to before #403.
    public static func tilted(_ bpm: Double,
                              within range: ClosedRange<Double>,
                              by tilt: Double) -> Double {
        // A non-finite tilt or a degenerate window is not a reason to move a tempo. Returning
        // the input un-nudged is the only answer that cannot make a take worse than no
        // signature at all.
        guard bpm.isFinite, tilt.isFinite, tilt != 0,
              range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound > range.lowerBound else { return bpm }
        let anchor = Swift.min(Swift.max(bpm, range.lowerBound), range.upperBound)
        let amount = Swift.min(Swift.max(tilt, -1), 1)
        let headroom = amount > 0 ? range.upperBound - anchor : anchor - range.lowerBound
        return anchor + amount * headroom * maxTiltShare
    }

    /// How much of the headroom a full tilt may take. 0.35 is a judgement, not a measurement,
    /// and is named here so it can be argued with instead of being found inline: on
    /// contemplation (44…66) a body folded to 55 moves at most ±3.9 BPM — audibly a different
    /// pace for the same preset, nowhere near another genre's tempo.
    public static let maxTiltShare: Double = 0.35

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
