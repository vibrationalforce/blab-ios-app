//
//  BreathPattern.swift
//  Echoelmusic — Bio
//
//  A multi-phase breathing pattern: the sequence of inhale / hold / exhale / hold
//  segments a guide paces. Generalizes the single in→out BreathPacer curve to the
//  evidence-based techniques that include GENTLE HOLDS (box breathing, 4-7-8),
//  while keeping resonance breathing (~6/min, exhale-emphasis, NO holds) as the
//  default — that is the only Grade-A HRV intervention (Lehrer/Gevirtz; see
//  scratchpads/RESEARCH_RESONANCE_SCIENCE_2026-06-20.md). Holds are a DIFFERENT
//  technique (acute stress / focus), offered opt-in and clearly labelled, never
//  the recommended HRV path.
//
//  SAFETY (the guide must never be able to harm):
//    • Every segment is clamped to a safe, gentle duration — holds are capped at
//      `maxHoldSeconds` so the guide can never instruct a long/strained breath-hold.
//    • Holds are only ever "Hold" (gentle, brief) — never "hold as long as you can".
//    • Resonance (no-hold) is the default; holds are an explicit user choice.
//    • Self-observation, not therapy. Contraindications ship with BreathPacer and
//      the UI must show them BEFORE a hold-based session.
//
//  Pure, deterministic value type: the host samples `sample(atCycleTime:)` from its
//  own UI-rate loop. Amplitude is a smooth raised-cosine on the active segments and
//  flat on holds — no hard edges, continuous across segment boundaries.
//

import Foundation

/// The four kinds of breath segment. `holdFull` = lungs full, `holdEmpty` = empty.
public enum BreathSegmentKind: String, Codable, Sendable, Equatable {
    case inhale, holdFull, exhale, holdEmpty

    /// Gentle, non-strain instruction shown to the user. Holds say only "Hold".
    public var instruction: String {
        switch self {
        case .inhale:    return "Breathe in"
        case .exhale:    return "Breathe out"
        case .holdFull, .holdEmpty: return "Hold"
        }
    }

    var isHold: Bool { self == .holdFull || self == .holdEmpty }
}

/// One segment of a breathing cycle, with its (already safety-clamped) duration.
public struct BreathSegment: Equatable, Sendable {
    public let kind: BreathSegmentKind
    public let seconds: Double
}

public struct BreathPattern: Identifiable, Equatable, Sendable {

    // MARK: Safe bounds (seconds)
    /// Active phases (inhale/exhale) — long enough to be slow, capped so the guide
    /// never pushes an unsafely long single breath.
    public static let minActiveSeconds = 1.0
    public static let maxActiveSeconds = 15.0
    /// Holds are capped gentle so the guide can never instruct a strained breath-hold.
    /// Empty-lung holds provoke air-hunger faster, so they are capped tighter than
    /// full-lung holds.
    public static let maxHoldFullSeconds = 8.0
    public static let maxHoldEmptySeconds = 6.0

    public let id: String
    public let name: String
    public let segments: [BreathSegment]
    /// Honest, non-medical one-liner shown in the picker (technique + what it's for).
    public let evidence: String

    /// Builds a pattern, clamping every segment to its safe window. A segment that
    /// would clamp to zero is dropped (a pattern always keeps at least one segment).
    public init(id: String, name: String, evidence: String, segments rawSegments: [BreathSegment]) {
        self.id = id
        self.name = name
        self.evidence = evidence
        let clamped: [BreathSegment] = rawSegments.compactMap { seg in
            guard seg.seconds.isFinite, seg.seconds > 0 else { return nil }
            let cap: Double
            switch seg.kind {
            case .holdFull:  cap = Self.maxHoldFullSeconds
            case .holdEmpty: cap = Self.maxHoldEmptySeconds
            default:         cap = Self.maxActiveSeconds
            }
            let lo = seg.kind.isHold ? 0.0 : Self.minActiveSeconds
            let s = Swift.min(cap, Swift.max(lo, seg.seconds))
            return s > 0 ? BreathSegment(kind: seg.kind, seconds: s) : nil
        }
        self.segments = clamped.isEmpty
            ? [BreathSegment(kind: .inhale, seconds: Self.minActiveSeconds)]
            : clamped
    }

    /// Total cycle length (seconds). Always > 0.
    public var cycleSeconds: Double { segments.reduce(0) { $0 + $1.seconds } }

    /// Breaths per minute implied by the cycle length.
    public var ratePerMinute: Double { cycleSeconds > 0 ? 60.0 / cycleSeconds : 0 }

    /// True if the pattern contains any breath-hold (UI shows the contraindications
    /// before starting these).
    public var hasHolds: Bool { segments.contains { $0.kind.isHold } }

    /// ⭐ CAN ECHOEL READ BACK THE RATE THIS PATTERN PACES? Chained to the estimator's own
    /// published contract (`RespirationEstimator.reportableRange`) rather than restating its
    /// numbers here — a second copy of that bound is the #416 defect, and this is #426's form:
    /// one side asks the other instead of both remembering the same constant.
    ///
    /// It matters because the guide is not only a guide. `BreathGuideView` offers a
    /// "drive the ball from your MEASURED breath" mode, and `bioNormalized` folds a measured
    /// breath rate into the arousal the music follows. For a pattern outside the band, both go
    /// quiet — and nothing on screen says why, which is exactly the lying-control class this
    /// repo keeps closing.
    ///
    /// ⚠️ MEASURED, and the two out-of-band patterns fail DIFFERENTLY, which is why this is a
    /// property and the note below is not one sentence for both. Modelling only the mechanism
    /// in question — the breath period is read between zero-crossings of the heartbeat series,
    /// so a cycle is quantised to a whole number of beats, and a crossing is kept only if the
    /// rate it implies lands in the band — swept over pulses 45…110:
    ///   · resonance / coherent (6.0/min, +59% inside): 121 of 121 quantised branches accepted,
    ///     mean report 6.0140, i.e. +0.23%. Comfortably readable.
    ///   · box (3.75/min, **0.62% BELOW** the lower bound): 54 of 127 branches accepted, mean
    ///     report **3.8590 — a +2.91% HIGH bias**, and 12 of those 66 pulses accept nothing at
    ///     all. Pulse 60 is one of them, exactly: a 16 s cycle is exactly 16 beats there, both
    ///     quantisations give 3.75, and both are rejected. This is #426's one-sided filter in a
    ///     second place — it does not go silent, it reads high.
    ///   · 4-7-8 (3.1579/min, **16.3% below**): **0 of 131** branches accepted, silent at every
    ///     one of the 66 pulses. No jitter reaches back into the band from there.
    ///
    /// ⚠️ WHAT THIS MODEL DOES NOT COVER, stated rather than left to be found: it says nothing
    /// about what the estimator does DURING a hold. Box holds 8 of its 16 seconds and 4-7-8
    /// holds 7 of 19; the respiratory sinus arrhythmia across a held breath is not the smooth
    /// modulation the estimator assumes, and nothing here measures that. The claim is only the
    /// arithmetic one: even a perfectly tracked cycle at these paced rates is rejected or
    /// biased by the acceptance band alone.
    public var pacedRateIsReportable: Bool {
        RespirationEstimator.reportableRange.contains(ratePerMinute)
    }

    /// The honest one-liner to show beside a pattern the camera cannot read back, or `nil`.
    ///
    /// DERIVED, never stored: a hand-written caveat string on each pattern would drift the
    /// moment somebody retunes the band or edits a segment, and the drift would be invisible.
    /// Deriving it means the copy and the arithmetic cannot disagree.
    ///
    /// The wording deliberately does not call the technique broken — Box and 4-7-8 are
    /// established practices and are offered on purpose; it is Echoel's camera measurement that
    /// is not built for a rate this slow. No health claim, no instruction.
    public var measurementNote: String? {
        pacedRateIsReportable
            ? nil
            : "Echoel can't read your breath rate at this pace — the guide still works, "
                + "the live breath readout won't follow it."
    }

    /// Pure sample of the guide at a time within the cycle. `amplitude` [0,1] drives
    /// the ball (1 = lungs full). Raised-cosine on inhale/exhale, flat on holds.
    public func sample(atCycleTime time: Double) -> (amplitude: Double, instruction: String, kind: BreathSegmentKind) {
        let total = cycleSeconds
        guard total > 0 else { return (0, BreathSegmentKind.inhale.instruction, .inhale) }
        var t = time.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }

        var acc = 0.0
        for seg in segments {
            if t < acc + seg.seconds {
                let local = seg.seconds > 0 ? (t - acc) / seg.seconds : 0   // 0→1 within segment
                let amp: Double
                switch seg.kind {
                case .inhale:    amp = 0.5 * (1.0 - cos(Double.pi * local))  // 0→1
                case .exhale:    amp = 0.5 * (1.0 + cos(Double.pi * local))  // 1→0
                case .holdFull:  amp = 1.0
                case .holdEmpty: amp = 0.0
                }
                return (amp, seg.kind.instruction, seg.kind)
            }
            acc += seg.seconds
        }
        // Floating-point fallthrough at the very end of the cycle: report the last segment's end.
        let last = segments[segments.count - 1]
        let endAmp = (last.kind == .inhale || last.kind == .holdFull) ? 1.0 : 0.0
        return (endAmp, last.kind.instruction, last.kind)
    }
}

// MARK: - Curated patterns

public extension BreathPattern {

    /// Resonance breathing — the DEFAULT and only Grade-A HRV technique: ~6/min,
    /// exhale longer than inhale, no holds (Lehrer & Gevirtz).
    static let resonance = BreathPattern(
        id: "resonance", name: "Resonance",
        evidence: "~6 breaths/min, longer exhale. The best-evidenced way to raise HRV.",
        segments: [.init(kind: .inhale, seconds: 4), .init(kind: .exhale, seconds: 6)]
    )

    /// Coherent breathing — symmetric 5s/5s (~6/min), a gentle no-hold alternative.
    static let coherent = BreathPattern(
        id: "coherent", name: "Coherent",
        evidence: "Even 5s in, 5s out (~6/min). Simple, no holds.",
        segments: [.init(kind: .inhale, seconds: 5), .init(kind: .exhale, seconds: 5)]
    )

    /// Box breathing — 4-4-4-4 with holds. Popular for acute focus/stress; not an
    /// HRV-resonance technique. Opt-in.
    static let box = BreathPattern(
        id: "box", name: "Box",
        evidence: "4-4-4-4 with gentle holds. For focus/calm — not an HRV technique.",
        segments: [.init(kind: .inhale, seconds: 4), .init(kind: .holdFull, seconds: 4),
                   .init(kind: .exhale, seconds: 4), .init(kind: .holdEmpty, seconds: 4)]
    )

    /// 4-7-8 relaxing breath — inhale 4, gentle hold 7, long exhale 8. Opt-in.
    static let relaxing478 = BreathPattern(
        id: "relaxing478", name: "4-7-8",
        evidence: "In 4, gentle hold 7, out 8. A relaxing wind-down — not an HRV technique.",
        segments: [.init(kind: .inhale, seconds: 4), .init(kind: .holdFull, seconds: 7),
                   .init(kind: .exhale, seconds: 8)]
    )

    /// All curated patterns, resonance first (the recommended default). These
    /// factory patterns are the SUPPORTED construction path — each is verified to
    /// chain continuously (no amplitude jump across segment boundaries or the wrap).
    /// Arbitrary caller-built segment lists are clamped for safety but not checked
    /// for continuity, so prefer these.
    static let curated: [BreathPattern] = [resonance, coherent, box, relaxing478]

    /// Safety copy the UI MUST show — and require acknowledgement of — BEFORE any
    /// hold-based session (Box / 4-7-8). Resonance/Coherent (no holds) use the
    /// gentler `BreathPacer.contraindications` instead. The UI must never auto-select
    /// a hold pattern and must keep `resonance` preselected. Self-observation, not
    /// therapy or diagnosis.
    static let holdContraindications: [String] = [
        "Hold gently and only as briefly as the guide shows — never strain.",
        "Release the hold immediately if you feel any discomfort, dizziness, or air-hunger.",
        "Breath-holds are a focus/calm technique, not the HRV practice — for raising "
            + "HRV, use Resonance (no holds).",
        "If you have asthma/COPD, a heart condition, a panic/anxiety disorder, high "
            + "blood pressure, or are pregnant, do not do breath-holds without checking "
            + "with a healthcare provider first.",
        "This is for self-observation, not medical diagnosis or treatment."
    ]
}
