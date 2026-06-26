// MicrotonalTuning.swift
// Echoel — tone systems beyond 12-TET. The existing `Scale`/`MusicalKey` model
// is strictly 12 equal semitones (integer offsets), so it cannot express quarter
// tones, just intonation, Arabic maqām neutral steps, Indonesian gamelan, or
// non-octave systems. This adds a tuning model in CENTS (1200 = octave) that can.
//
// It is the substrate the vocal pitch-correction ("autotune") snaps to: `snap`
// returns the nearest in-scale frequency PLUS the signed cent error a corrector
// must remove. Anchored to the concert-pitch reference (Kammerton, A4 Hz) at a
// chosen root note (Tonart) via `TuningReference`, so pitch correction is linked
// to key and Kammerton by construction.
//
// HONESTY: the world tunings below are REPRESENTATIVE. Maqām, gamelan and rāga
// tunings vary by region, ensemble and even by instrument; there is no single
// canonical cent table. Values follow widely-cited theoretic references (e.g.
// 24-TET Arabic theory; ~5-EDO sléndro) and are documented as approximations,
// not absolute truth. Concert-pitch alternates (432/442 …) are factual reference
// choices — no esoteric claim is attached to any of them.

import Foundation

/// A tuning / tone system: ascending pitches within one repeating period.
///
/// `degreesCents` are cent offsets from the tonic (1/1 = 0 cents), ascending,
/// within one `periodCents` (1200 = octave). The scale repeats every period;
/// most systems repeat at the octave, a few (Bohlen–Pierce) at the tritave.
public struct TuningSystem: Codable, Sendable, Equatable, Identifiable, Hashable {

    /// Broad grouping for UI organisation.
    public enum Family: String, Codable, Sendable, CaseIterable {
        case equalTemperament   // 12, 19, 24, 31 … equal divisions
        case justIntonation     // whole-number frequency ratios
        case world              // traditional regional systems (representative)
        case xenharmonic        // non-octave / experimental
    }

    public var id: String
    public var name: String
    public var family: Family
    /// Ascending cent offsets within one period; first entry is always 0.
    public var degreesCents: [Double]
    /// Size of one repeat in cents (1200 = octave).
    public var periodCents: Double

    public init(id: String, name: String, family: Family,
                degreesCents: [Double], periodCents: Double = 1200.0) {
        self.id = id
        self.name = name
        self.family = family
        self.degreesCents = degreesCents
        self.periodCents = periodCents
    }

    /// Number of pitches per period.
    public var degreeCount: Int { degreesCents.count }

    /// Frequency of an absolute scale degree (may be negative or beyond one
    /// period — it wraps, shifting by `periodCents` each period) from a 1/1
    /// reference frequency.
    public func frequency(degree d: Int, reference referenceHz: Double) -> Double {
        let n = degreesCents.count
        guard n > 0, referenceHz > 0 else { return referenceHz }
        let period = Int((Double(d) / Double(n)).rounded(.down))
        let within = d - period * n            // 0 ..< n, even for negative d
        let totalCents = Double(period) * periodCents + degreesCents[within]
        return referenceHz * pow(2.0, totalCents / 1200.0)
    }

    /// Snap an arbitrary frequency to the nearest in-scale pitch.
    ///
    /// Returns the target frequency, the signed cent error (`+` = input is sharp
    /// of the target, so a corrector should pull DOWN by that many cents), and
    /// the absolute degree chosen. This is the autotune target function.
    public func snap(frequencyHz freq: Double,
                     reference referenceHz: Double) -> (frequencyHz: Double, cents: Double, degree: Int) {
        let n = degreesCents.count
        guard n > 0, referenceHz > 0, freq > 0 else { return (freq, 0, 0) }
        let cents = 1200.0 * log2(freq / referenceHz)
        let centerPeriod = Int((cents / periodCents).rounded(.down))
        var bestDegree = 0
        var bestDelta = Double.greatestFiniteMagnitude
        var bestCents = 0.0
        // Search the period the input lands in plus its neighbours, so a pitch
        // near a period boundary still finds the truly nearest degree.
        for p in (centerPeriod - 1)...(centerPeriod + 1) {
            for i in 0..<n {
                let total = Double(p) * periodCents + degreesCents[i]
                let delta = abs(cents - total)
                if delta < bestDelta {
                    bestDelta = delta
                    bestCents = total
                    bestDegree = p * n + i
                }
            }
        }
        let targetHz = referenceHz * pow(2.0, bestCents / 1200.0)
        return (targetHz, cents - bestCents, bestDegree)
    }

    /// The 1/1 reference frequency for this tuning placed at `rootMidi`
    /// (the Tonart root), derived from the concert-pitch reference (Kammerton).
    public static func reference(rootMidi: Int, tuning: TuningReference) -> Double {
        tuning.frequency(forMIDINote: rootMidi)
    }
}

// MARK: - Library of tone systems (traditional → modern)

public extension TuningSystem {

    /// Equal division of the octave into `n` steps.
    static func equal(_ n: Int, id: String, name: String) -> TuningSystem {
        let step = 1200.0 / Double(n)
        return TuningSystem(id: id, name: name, family: .equalTemperament,
                            degreesCents: (0..<n).map { Double($0) * step })
    }

    // 5-limit just intonation cent values (rounded to 0.001 cent).
    private static let justMajorCents:  [Double] = [0, 203.910, 386.314, 498.045, 701.955, 884.359, 1088.269]
    private static let justMinorCents:  [Double] = [0, 203.910, 315.641, 498.045, 701.955, 813.686, 1017.596]
    private static let pythagoreanCents: [Double] = [0, 203.910, 407.820, 498.045, 701.955, 905.865, 1109.775]
    // Quarter-comma meantone (12 chromatic degrees): pure 5:4 major thirds (386¢), the
    // historical keyboard temperament — sweeter triads than 12-TET, a wide "wolf" aside.
    private static let meantoneCents: [Double] = [0, 76.0, 193.2, 310.3, 386.3, 503.4,
                                                  579.5, 696.6, 772.6, 889.7, 1006.8, 1082.9]

    /// A curated, representative span: equal temperaments, just intonation, Arabic
    /// maqām (24-TET theoretic), Indonesian gamelan, Japanese, and a non-octave
    /// xenharmonic system. 12-TET is first so it is the safe default.
    static let library: [TuningSystem] = [
        // — Equal temperaments —
        .equal(12, id: "edo12", name: "12-TET (standard)"),
        .equal(24, id: "edo24", name: "24-TET (quarter tones)"),
        .equal(19, id: "edo19", name: "19-TET"),
        .equal(31, id: "edo31", name: "31-TET"),

        // — Just intonation —
        TuningSystem(id: "just-major", name: "Just Intonation — Major",
                     family: .justIntonation, degreesCents: justMajorCents),
        TuningSystem(id: "just-minor", name: "Just Intonation — Minor",
                     family: .justIntonation, degreesCents: justMinorCents),
        TuningSystem(id: "pythagorean", name: "Pythagorean (diatonic)",
                     family: .justIntonation, degreesCents: pythagoreanCents),
        TuningSystem(id: "meantone-quarter", name: "1/4-comma Meantone (chromatic)",
                     family: .justIntonation, degreesCents: meantoneCents),

        // — World (representative; regional/ensemble variation is real) —
        TuningSystem(id: "maqam-rast", name: "Maqām Rāst (24-TET theoretic)",
                     family: .world, degreesCents: [0, 200, 350, 500, 700, 900, 1050]),
        TuningSystem(id: "maqam-bayati", name: "Maqām Bayātī (24-TET theoretic)",
                     family: .world, degreesCents: [0, 150, 300, 500, 700, 800, 1000]),
        TuningSystem(id: "maqam-hijaz", name: "Maqām Ḥijāz",
                     family: .world, degreesCents: [0, 100, 400, 500, 700, 800, 1000]),
        TuningSystem(id: "gamelan-slendro", name: "Gamelan Sléndro (≈5-EDO)",
                     family: .world, degreesCents: [0, 240, 480, 720, 960]),
        TuningSystem(id: "gamelan-pelog", name: "Gamelan Pélog (representative)",
                     family: .world, degreesCents: [0, 120, 270, 540, 670, 785, 950]),
        TuningSystem(id: "hirajoshi", name: "Hirajōshi (Japanese pentatonic)",
                     family: .world, degreesCents: [0, 200, 300, 700, 800]),

        // — Xenharmonic / non-octave —
        // Bohlen–Pierce: 13 equal divisions of the tritave (3:1 = 1901.955 cents).
        TuningSystem(id: "bohlen-pierce", name: "Bohlen–Pierce (non-octave)",
                     family: .xenharmonic,
                     degreesCents: (0..<13).map { Double($0) * (1901.955 / 13.0) },
                     periodCents: 1901.955)
    ]

    /// Look up a system by its stable id; falls back to 12-TET.
    static func named(_ id: String) -> TuningSystem {
        library.first { $0.id == id } ?? library[0]
    }

    /// Cent deviation from 12-TET for a note `semitones` above the tonic: snap that
    /// 12-TET position to this system's nearest scale degree within the octave and
    /// return the difference. 12-TET → 0 everywhere (identical playback). Only
    /// meaningful for octave-period systems; non-octave systems (Bohlen–Pierce)
    /// have no defined chromatic retune, so they return 0.
    func centsDeviation(forSemitone semitones: Int) -> Double {
        guard abs(periodCents - 1200) < 1, !degreesCents.isEmpty else { return 0 }
        let s = ((semitones % 12) + 12) % 12
        let target = Double(s) * 100.0
        var best = 0.0
        var bestDelta = Double.greatestFiniteMagnitude
        for c in degreesCents where abs(c - target) < bestDelta {
            bestDelta = abs(c - target)
            best = c
        }
        return best - target
    }

    /// 12-entry cent-deviation table indexed by ABSOLUTE pitch class (0 = C … 11 = B)
    /// for a given key-root pitch class. Feeds the synth's per-note retune so a take
    /// in that key snaps to this system's intonation; 12-TET returns all zeros.
    func pitchClassCents(root: Int) -> [Double] {
        (0..<12).map { centsDeviation(forSemitone: $0 - root) }
    }
}
