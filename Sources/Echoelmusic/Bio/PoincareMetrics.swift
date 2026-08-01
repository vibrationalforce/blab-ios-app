//
//  PoincareMetrics.swift
//  Echoelmusic — Bio
//
//  The Poincaré plot: RR(n) against RR(n+1), plus its two standard descriptors
//  SD1 and SD2. Founder ask 2026-08-01, on the Field panel: "sei kreativ aber achte
//  auch auf den evidenzbasierten gesundheitlichen benefit". Of everything that could
//  hang there, THIS is the half with published grounding — an oscilloscope and a
//  spectrum are craft instruments; the Poincaré plot is the standard non-linear HRV
//  picture and its two axes have accepted definitions.
//
//  ⭐ WHY A PICTURE OF THE HEARTBEAT AND NOT ANOTHER NUMBER: the SHAPE is the
//  information. A relaxed, coherent state draws a wide comet along the diagonal; a
//  tense or shallow-breathing one draws a tight ball; a missed or doubled beat throws
//  a visible satellite off the cloud. That last property is why it earns a place in a
//  panel a performer actually watches — it is simultaneously a body readout and a
//  plain-sight quality check on the sensor, which matters here because the camera path
//  is the approximate one (a chest strap gives clean beat-to-beat directly).
//
//  DEFINITIONS. SD1 is the dispersion of the cloud PERPENDICULAR to the line of
//  identity (short-term, beat-to-beat); SD2 is the dispersion ALONG it (long-term).
//  Both are computed here GEOMETRICALLY — the point cloud projected onto its two 45°
//  axes — which is the definition itself:
//      SD1 = SD of (RR(n) − RR(n+1)) / √2
//      SD2 = SD of (RR(n) + RR(n+1)) / √2
//
//  ⚠️ AND NOT via the familiar algebraic identity, which is where this file started and
//  where it was WRONG. The textbook relations (Brennan, Palaniswami & Kamen 2001, IEEE
//  TBME 48(11):1342–1347) are
//      SD1² = ½·SDSD²          SD2² = 2·SDNN² − ½·SDSD²
//  and the second one is an APPROXIMATION: SDNN is taken over all N intervals while the
//  cloud has only N−1 points, so the two are not the same sample set. Measured over
//  200 000 random 3–8-beat series, `2·SDNN² − ½·SDSD²` came out NEGATIVE in **7.5 %** of
//  them — a NaN under the square root, not the "few ulps" rounding case a clamp is for.
//  SD1 is unaffected (both routes agree to the last bit, because the perpendicular
//  projection IS ±SDSD/√2), so only SD2 was ever at stake.
//
//  The cleanest demonstration is the alternating series 800, 840, 800, 840 … : every
//  point is (800, 840) or (840, 800), so every point sums to 1640 and the cloud has
//  ZERO extent along the identity line. Geometry says SD2 = 0. The identity says 4.04.
//  Zero is the truth; 4.04 is the artefact of mixing two sample sets. `PoincareMetricsTests`
//  pins that case, so nobody can "simplify" this back into the algebraic form.
//
//  ⛔ MY FIRST VERSION OF THIS HEADER ALSO GOT THE DANGER BACKWARDS, which is worth
//  recording because it is this repo's named recurring failure — mechanism plausible,
//  justification false. It warned that reusing `HRVMetrics.sdnn` (the SAMPLE deviation,
//  ÷n−1) instead of a population one "can drive the term negative". Measured: that
//  combination produced **zero** negatives in the same 200 000 trials — a sample SD is
//  LARGER, so it makes the subtraction safer, not riskier. The real hazard was the
//  formula, not the convention. A confident wrong reason in a file about physiology is
//  exactly the kind the next session cannot refute, so it is corrected here rather than
//  quietly deleted.
//
//  NOT A DIAGNOSIS. These are descriptive statistics of an interval series, for
//  self-observation (CLAUDE.md safety section). Nothing here interprets a shape as a
//  health state, and no caller may add that.
//
//  Pure value maths, Foundation only, so the blocking bundle can test it without a
//  sensor, a view or an audio graph.
//
//  ⛔ CONSUMER-FREE FOR EXACTLY ONE CYCLE, said out loud because this repo keeps a shelf
//  of doorless files and a new one is not automatically innocent. The view and its door
//  are #347 Slice 3b, next cycle. The split is deliberate: the MATHS is the part that has
//  to be right — a mislabelled SD1 is a lying control in the one area where the app
//  touches physiology — and it is the part the blocking bundle can actually check. If
//  Slice 3b does not land, this file is a defect: delete it rather than let it sit.
//

import Foundation

enum PoincareMetrics {

    /// One plotted beat pair, in milliseconds: the current interval against the next.
    struct Point: Equatable {
        let rr: Double      // RR(n)   — x
        let next: Double    // RR(n+1) — y
    }

    /// The descriptors of the cloud. `sd1`/`sd2` in milliseconds.
    struct Descriptors: Equatable {
        /// Perpendicular spread — short-term, beat-to-beat variability.
        let sd1: Double
        /// Spread along the identity line — long-term variability.
        let sd2: Double
        /// SD1/SD2, dimensionless — `nil` when `sd2` is zero and there is nothing to
        /// divide by. Optional rather than a substituted number: a cloud with no extent
        /// along the diagonal is a real, describable state (see the alternating series in
        /// the file header), and printing "∞" or a silent 0 for it would be a claim.
        let ratio: Double?
        /// How many beat PAIRS the numbers rest on. Meant to be SHOWN next to them: six
        /// points and six hundred deserve different confidence, and hiding that behind a
        /// tidy "SD1 24 ms" is how a readout starts overstating itself.
        let pairs: Int
    }

    /// Physiologically plausible RR window in milliseconds — 250 ms (240 bpm) to
    /// 2000 ms (30 bpm), the same band `CameraRPPGBioPublisher` applies before replaying
    /// RR through the respiration estimator.
    ///
    /// "Same band", not "the same constant": that site writes strict inequalities
    /// (`ms > 250 && ms < 2000`), so an interval of exactly 250.0 or 2000.0 ms passes here
    /// and not there. Immaterial for a picture, and said plainly so the next reader does
    /// not go looking for a shared constant that does not exist.
    static let plausibleMs: ClosedRange<Double> = 250...2000

    /// Below this spread (in ms) a cloud is FLAT, not narrow — the value is arithmetic
    /// residue, not a measurement, and nothing may be divided by it.
    ///
    /// It exists because "sd2 > 0" is not the same test as "sd2 is real", and the
    /// difference is not theoretical: the alternating series in the file header has an
    /// exactly-zero spread along the diagonal in real arithmetic and returns **2.3e−13**
    /// in `Double`, from which `sd1/sd2` is **1.2e14**. A guard of `sd2 > 0` lets that
    /// through and prints it. Measured, not estimated — and the reason this constant is
    /// named rather than inlined as a magic `1e-6`.
    ///
    /// 1e−6 ms is a picosecond of heart-rate variability: seven orders above the residue
    /// double precision produces at RR scale (~1e−13), and nine below the smallest spread
    /// any sensor here can resolve (rPPG beats land on video frames, ~30 ms apart).
    static let degenerateSpreadMs = 1e-6

    /// Keep only intervals that could be a heartbeat. An rPPG series in particular carries
    /// dropouts that surface as one impossible 4-second "interval"; left in, a single such
    /// point rescales the whole plot and squashes the real cloud into a dot.
    static func plausible(_ rrMs: [Double]) -> [Double] {
        rrMs.filter { $0.isFinite && plausibleMs.contains($0) }
    }

    /// The scatter itself: consecutive pairs of the (already filtered) series.
    ///
    /// Pairs come from ADJACENT entries only — that is the definition, and it is also why
    /// filtering must happen BEFORE this call and not inside it: dropping an implausible
    /// interval joins its two neighbours into a pair that never occurred. Passing raw input
    /// is therefore wrong in a way that still draws a plausible-looking picture. Call
    /// `plausible(_:)` first, as `descriptors(rrMs:)` does.
    static func points(_ rrMs: [Double]) -> [Point] {
        guard rrMs.count >= 2 else { return [] }
        return (0..<(rrMs.count - 1)).map { Point(rr: rrMs[$0], next: rrMs[$0 + 1]) }
    }

    /// SD1/SD2 for a raw RR series, or `nil` when there is not enough to say.
    ///
    /// `nil` and not zeros: a cloud of two beats has no meaningful perpendicular spread,
    /// and "SD1 0 ms" is a claim rather than an absence. `HRVMetrics` returns 0 for that
    /// case because its callers already treat 0 as unknown by convention; a view drawing a
    /// picture has no such convention, so the type carries it instead.
    ///
    /// Needs at least 3 plausible intervals: two intervals give a single point, and one
    /// point has no spread in either direction.
    static func descriptors(rrMs: [Double]) -> Descriptors? {
        let rr = plausible(rrMs)
        guard rr.count >= 3 else { return nil }

        // Project each point onto the two 45° axes. The √2 is the rotation, not a fudge:
        // (x−y)/√2 is the signed distance from the identity line, (x+y)/√2 the coordinate
        // along it.
        let root2 = 2.0.squareRoot()
        var perpendicular: [Double] = []
        var along: [Double] = []
        perpendicular.reserveCapacity(rr.count - 1)
        along.reserveCapacity(rr.count - 1)
        for i in 1..<rr.count {
            perpendicular.append((rr[i - 1] - rr[i]) / root2)
            along.append((rr[i - 1] + rr[i]) / root2)
        }

        // Snap a residue-sized spread to a clean zero before anyone reads it. Reporting
        // "SD2 0.0000000000002 ms" and reporting "SD2 0.0 ms" are the same statement about
        // the body; only one of them looks like a measurement.
        let sd1 = collapsed(populationSD(perpendicular))
        let sd2 = collapsed(populationSD(along))
        guard sd1.isFinite, sd2.isFinite else { return nil }

        return Descriptors(sd1: sd1,
                           sd2: sd2,
                           ratio: sd2 >= degenerateSpreadMs ? sd1 / sd2 : nil,
                           pairs: rr.count - 1)
    }

    /// Snap a residue-sized value to exactly zero. See `degenerateSpreadMs`.
    private static func collapsed(_ v: Double) -> Double {
        v < degenerateSpreadMs ? 0 : v
    }

    /// Population standard deviation (÷n) of the projected cloud.
    ///
    /// Population and not sample because these are the moments of a FINITE point set that
    /// is fully in hand — the cloud on screen is the whole population, not a draw from a
    /// larger one. (`HRVMetrics.sdnn` uses ÷n−1, correctly, because SDNN is reported as an
    /// estimate of an underlying process. Two different questions, two different divisors;
    /// neither is a bug in the other.)
    private static func populationSD(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let n = Double(xs.count)
        let mean = xs.reduce(0, +) / n
        var sumSq = 0.0
        for x in xs {
            let d = x - mean
            sumSq += d * d
        }
        return (sumSq / n).squareRoot()
    }
}
