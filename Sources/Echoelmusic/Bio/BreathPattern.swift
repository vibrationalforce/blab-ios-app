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
    /// ⛔ WHY IT MATTERS — and the first version of this paragraph named the WRONG consumer.
    /// It said "`bioNormalized` folds a measured breath rate into the arousal the MUSIC
    /// follows". Both halves are false, and two places in this repo already said so before I
    /// wrote it: `bioNormalized`'s only caller is `RecordController.captureBio` — a recorded
    /// automation lane, not a live audio path — and `RecordController.onStep` opens
    /// `guard armed else { return }` while `arm()` has ZERO callers in `Sources/`. The #433
    /// entry and `RespirationEstimator`'s own doc both record that dormancy; I re-committed the
    /// claim they strike. The consumers that ARE live:
    ///   · `ModulationMatrix` — `.breathRate` has a producer, so it reaches `FXModCarrier`'s
    ///     carrier picker and can be routed onto any FX parameter in a session.
    ///   · `BioEventPublisher` → `BioEventGraph` breath onsets → OSC `/echoelmusic/bio/breath/*`.
    ///   · `BreathGuideView`'s "drive the ball from your MEASURED breath" mode, which gates on
    ///     `breathRate > 0` — so a pattern that never publishes a rate leaves that toggle stuck
    ///     on "Start the camera" WITH the camera already running.
    /// (`BreathArp` and the composer's inhale bias read breath PHASE, not rate; they are not
    /// covered by this property and must not be cited for it.)
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
    /// ⛔ THE ASSUMPTION THE WHOLE MODEL RESTS ON, and the first version left it unstated while
    /// calling the remaining risk bounded: **exactly one upward zero-crossing per breath cycle**.
    /// Every number above is a statement about the rate implied by ONE crossing interval. The
    /// holds are precisely what can break that, and the first version waved at them ("nothing
    /// here measures that") as if the residue were a detail. It is not — it is the claim.
    ///   · Under the hold model THIS FILE ships (amplitude plateaus, see `sample`), the
    ///     assumption survives: 19 crossings in 300 s for box against 18.75 expected, 16 for
    ///     4-7-8 against 15.8. The 8 s trend follower chases a plateau asymptotically and never
    ///     crosses back.
    ///   · Under the arguably more physiological model — no respiratory drive during a hold, so
    ///     HR RELAXES toward baseline — 4-7-8's 7 s hold produces a SECOND crossing per cycle
    ///     and the estimator publishes a confident ≈6.3/min: almost exactly twice the paced
    ///     3.158, sitting in the middle of the band, indistinguishable from resonance breathing.
    ///     Measured robust across relaxation time constants of 1–5 s; it only falls silent once
    ///     the relaxation is slower than the hold itself. 4-7-8's second harmonic is 0.105 Hz,
    ///     which is the frequency this estimator is tuned for — the mechanism is not exotic.
    /// So "0 of 131, silent at every pulse" is a property of the PLATEAU, not of the estimator,
    /// and the plausible failure for 4-7-8 is a FABRICATED IN-BAND RATE — strictly worse than the
    /// silence this note warns about, and the failure class this repo has already paid for twice
    /// (#424's 3.5/min rail, #426's one-sided filter). Neither hold model is device-measured.
    /// Resolving that needs a strap or a device take, not a third model.
    public var pacedRateIsReportable: Bool {
        RespirationEstimator.reportableRange.contains(ratePerMinute)
    }

    /// The honest one-liner for a pattern paced outside the readable band, or `nil`.
    ///
    /// ⛔ THE FIRST VERSION OF THIS STRING WAS FALSE FOR BOX — and the paragraph directly above
    /// it already said so, in the same commit. It read "Echoel can't read your breath rate at
    /// this pace — the guide still works, the live breath readout won't follow it", i.e. it
    /// promised SILENCE. Box does not go silent: it publishes a rate at roughly five of every
    /// six resting pulses and reads about 3% HIGH. A caption telling the user a LIVE readout is
    /// dead is the lying-control class inverted, and it shipped two dozen lines under a doc
    /// comment stating the opposite. The lesson is not "check the copy" — it is that a caption
    /// derived from a boolean inherits only what the boolean knows, and this boolean knows
    /// "outside the band", not "silent".
    ///
    /// What survives is the part decidable from the arithmetic alone, with no model in it: the
    /// paced rate is BELOW `reportableRange`, and the estimator only ever publishes a rate
    /// INSIDE it. Therefore the readout can never show this pace — it shows nothing, or it shows
    /// a number that is higher. One sentence covering both branches, claiming neither.
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
            : "This pace is slower than Echoel's breath readout can report — the breath "
                + "number stays blank or reads high."
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
