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
    /// ⚠️ THE PARAMETER IS CALLED `bpm` AND THE WHOLE DOC BELOW IS ABOUT TEMPO, but the
    /// arithmetic is dimensionless and Slice 3 added a SECOND caller in a different unit:
    /// `BioComposer.composeHarmonic` tilts its pad VELOCITY (0…1) within
    /// `BioComposer.padVelocityWindow`. Nothing here needs changing for that — the guards,
    /// the in-range promise and the zero-tilt no-op are all unit-free — but a reader must not
    /// take `bpm` as a contract, and anyone tightening a guard around a tempo assumption has
    /// two callers to satisfy, not one.
    ///
    /// ⭐ WHY THIS EXISTS, AND WHY IT IS NOT A SECOND COPY OF THE BODY→TEMPO MAPPING (#403
    /// Slice 2). Three reasons, strongest first — and note the ORDER, because the first two
    /// versions of this paragraph led with the weakest one and measured it on a flattering
    /// genre.
    ///
    /// **1. Coherence erases the body completely, and that is not genre-dependent.**
    /// `BioComposer.tempo(for:)` pulls the suggested tempo toward `resonancePulseBPM` (72) as
    /// coherence rises; at full coherence EVERY performer's suggested tempo is exactly 72,
    /// whatever their heart is doing. `genreTempo(72, into: 46…78)` is 72 for all of them. A
    /// calm room full of people gets one tempo. That is the total collapse, it happens before
    /// any fold, and the tilt is the only thing downstream that still knows who is playing.
    ///
    /// **2. The tilt is the HABITUAL rate; the live mapping is THIS MOMENT's.** They are two
    /// different measurements of the same person, which is exactly why stacking them is not
    /// double-counting. A habitually fast heart caught in a calm minute still leans forward.
    ///
    /// **3. The octave fold also collapses — but less than the first version of this
    /// paragraph claimed, and NOT on the genre it named.** Walked over the SHIPPED DEFAULT
    /// `.selfObservation` (46…78), which is what a fresh install actually opens on:
    ///
    ///     46…78 → 46…78          passes through, full resolution
    ///     79…84 → 78             six bodies, one tempo
    ///     85…92 → 46             eight bodies, one tempo — and SLOWER than the 84
    ///
    /// Over `tempoTilt`'s own 50…90 domain that is 29 of 41 BPM values passing through
    /// untouched: on the default genre the fold destroys nothing for roughly three quarters
    /// of performers, and there the tilt AMPLIFIES rather than restores (legitimately, per 2).
    /// The narrower a window, the more it collapses — on contemplation (44…66) 68…76 all
    /// become 66 and 78…88 all become 44.
    ///
    /// ⛔ TWO EARLIER VERSIONS OF THIS BLOCK WERE WRONG AND BOTH SURVIVED A COMMIT. The first
    /// said "41 % of one octave collapses onto the FLOOR", quoting `genreTempo`'s description
    /// of the bug #237 FIXED as if it were current. The second fixed that but walked
    /// CONTEMPLATION while calling it the default — it is not; `StudioDefaultKeys` ships
    /// `.selfObservation`. Picking the genre where your argument looks best and labelling it
    /// "the default" is a subtler version of the same defect. Both are recorded here because
    /// this is the paragraph a future session reads before deciding whether the tilt is
    /// legitimate at all.
    ///
    /// ⚠️ THE GENRE ALWAYS WINS, BY CONSTRUCTION, and that is the whole safety argument. The
    /// move is a FRACTION OF THE REMAINING HEADROOM toward the window's edge, so for any
    /// window of finite width the result cannot leave `range` for any tilt — no clamp is
    /// doing the work, the shape is. (The `headroom.isFinite` guard below is what makes
    /// "finite width" true rather than assumed: both bounds can be finite while their
    /// DIFFERENCE overflows, and `genreTempo` twelve lines up already treats a hostile range
    /// as in-scope because "the loop is the caller's to feed".) #81 already cost this repo one
    /// round of "erst individuell, dann klingt alles gleich"; a tilt that could cross a genre
    /// boundary would be the same mistake pointing the other way. At an edge the tilt does
    /// nothing in that direction, which is correct: the genre owns its own boundary.
    ///
    /// ⚠️ WHAT THE TILT COSTS, stated because no other doc states it. `genreTempo`'s stated
    /// purpose is an exact POWER-OF-TWO relationship to the pulse ("66 bpm body → 132 bpm
    /// Trap = the same pulse, double-time"). A tilt multiplies that by a non-dyadic factor:
    /// on trap a body folded to 132 lands at 138.3 at full forward tilt, a ratio of 2.096
    /// rather than 2. In the PASS-THROUGH band the lock is 1:1 and the tilt is what breaks
    /// it — 55 becomes 51.15 or 58.85. That is a real trade against a real property, not an
    /// oversight: the epic's premise is that a take must sound like the PERSON, and an exact
    /// octave lock to this minute's rate is precisely what makes two people sound alike. It
    /// is bounded (≤ 35 % of headroom) and it is the founder's call to reverse.
    ///
    /// ⚠️ NaN POLICY DIVERGES FROM `genreTempo` ON PURPOSE, and the neighbours should not be
    /// read as inconsistent by accident: `genreTempo` OWNS the sanitising (NaN → the window's
    /// floor) because it is the entry point from the body; `tilted` sits downstream of it and
    /// passes a non-finite `bpm` through unchanged rather than inventing a plausible number
    /// out of a caller error. In production `genreTempo` always hands this a finite value.
    ///
    /// ⚠️ AND THE IN-RANGE PROMISE IS ABOUT ACCEPTED INPUTS. Every input the guard accepts
    /// comes back inside `range`. A REJECTED input (tilt 0, non-finite tilt, degenerate
    /// window) is returned untouched — in range or not, because `tilted(200, within: 44…66,
    /// by: 0)` is 200. Returning the caller's own number unchanged is the only failure mode
    /// that cannot make a take worse than having no signature at all.
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
        // `clamped(to:)` rather than the nested `min(max(…))` CLAUDE.md names as a shipped
        // permanent-silence cause. Both inputs are already proven finite one line up, so this
        // is consistency with the rest of `DSP/` (EchoelDelayLine, EchoelDDSP both use it),
        // not a fix — and `Core/FloatingPointClamp.swift` is Foundation-only, so it does not
        // breach this file's no-Core-types rule.
        let anchor = bpm.clamped(to: range)
        let amount = tilt.clamped(to: -1...1)
        let headroom = amount > 0 ? range.upperBound - anchor : anchor - range.lowerBound
        // Both bounds can be finite while their DIFFERENCE is not (±greatestFiniteMagnitude
        // is a legal `ClosedRange<Double>`), and an infinite headroom would carry the result
        // straight out of the window the doc above promises it can never leave. No shipped
        // `MusicStyle.tempoRange` can produce it; the promise is absolute, so the guard is too.
        guard headroom.isFinite else { return bpm }
        return anchor + amount * headroom * maxTiltShare
    }

    /// How much of the headroom a full tilt may take. 0.35 is a judgement, not a measurement,
    /// and is named here so it can be argued with instead of being found inline: on the
    /// shipped default `.selfObservation` (46…78) a body folded to 62 moves at most ±5.6 BPM
    /// — audibly a different pace for the same preset, and still unmistakably that genre.
    ///
    /// ⛔ IT IS A FRACTION, SO THE ABSOLUTE MOVE SCALES WITH WINDOW WIDTH — and an earlier
    /// version of this line ended "nowhere near another genre's tempo", which is false the
    /// moment you leave the calm windows it was measured on. Klezmer (90…170) travels up to
    /// ±14 BPM from centre and jazz (80…150) ±12.25; a jazz take sweeping 24.5 BPM crosses
    /// the whole of deepHouse (120…126) and techHouse (124…130) on the way. **The genre
    /// safety argument is unaffected** — the take never leaves ITS OWN window, which is what
    /// #81 was about — but "nowhere near another genre" was a different, wrong claim, and it
    /// is the kind that gets quoted later as if it had been measured.
    ///
    /// ⚠️ ITS HONEST LIMIT, because the founder's ask ("soll er individuell nach der Person
    /// klingen") is not genre-conditional and this constant is: both call sites `.rounded()`
    /// to whole BPM, so on a NARROW window the tilt can round away entirely. Psytrance
    /// (140…150) has a full-tilt reach of 3.5 BPM and only ±1.75 from mid-window, so any
    /// |tilt| below ≈0.29 lands back on the untilted integer. Same for upliftingTrance
    /// (136…144), techHouse (124…130), acidTechno (130…139). On those genres the signature
    /// has to be carried by STRUCTURE (the Slice 1 seed fold), not by tempo — raising this
    /// number to compensate would trade a real risk of genre drift for a few tenths of a BPM.
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
