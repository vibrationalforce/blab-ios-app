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
//  tense or shallow-breathing one draws a tight ball. Two numbers cannot say "wide in
//  one direction, narrow in the other" as directly as an image of the cloud can.
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
//  cloud has only N−1 points, so the two are not the same sample set.
//
//  ⛔ TWO REASONS TO REJECT IT, AND THE FIRST VERSION OF THIS HEADER LED WITH THE WEAKER ONE.
//  It headlined that `2·SDNN² − ½·SDSD²` goes NEGATIVE (a NaN under the square root) in ~8 %
//  of short series. True — but that rate is almost entirely an N=3 effect and vanishes at the
//  window lengths this file actually sees:
//      N = 3 → 23 % · 4 → 8 % · 5 → 4 % · 6 → 1.7 % · 7 → 0.8 % · 8 → 0.3 % · 10 → 0.05 %
//      N ≥ 20 → 0.00 %
//  A Poincaré window here is dozens of beats, so **the NaN is not the production problem**.
//  The real one does not shrink with N at all: the identity gives the WRONG ANSWER even when
//  it is positive — 4.0406 where the truth is 0, on the series below. Systematic error, not
//  a domain error, is why geometry wins.
//
//  ⛔ AND THE DIVISORS ARE PART OF THE CLAIM, which the first version left out entirely — it
//  wrote "3–8-beat series, 7.5 %" with no divisor named, and the rate depends on both:
//      SDNN ÷n,   SDSD ÷n    →  ~8 % negative  (3–7 intervals) · ~6 % (3–8)
//      SDNN ÷n,   SDSD ÷n−1  → ~30 %           (3–7)
//      SDNN ÷n−1, SDSD ÷n−1  → ~14 %           (3–7)
//      SDNN ÷n−1, SDSD ÷n    →   0 %           (3–7) — and this row is a THEOREM, not a
//          measurement: with both denominators equal to N−1 the sign is that of
//          `4·Σ(xᵢ−x̄)² − Σ(dᵢ−d̄)²`, and `Σdᵢ² ≤ 4·Σ(xᵢ−x̄)²` holds for every series.
//  ⛔ QUOTED TO THE NEAREST PERCENT ON PURPOSE. The second version of this header printed
//  7.6 / 6.3 / 29.7 / 13.6 to one decimal from 200 000 Monte-Carlo trials, whose standard
//  error is ~0.06 pp — so the last digit moved with the seed, and two of the four entries
//  were on the wrong side of it (7.6 converges to 7.5; 13.6 to 13.7). A protocol that cannot
//  support the precision it prints is the same defect as a number with no protocol at all,
//  one decimal place smaller. Protocol, for anyone re-deriving: N uniform over the stated
//  range, RR uniform 400–1400 ms, ≥1e7 trials for a second digit.
//
//  SD1 is unaffected by any of this: the perpendicular projection IS ±SDSD/√2, so the two
//  routes are the SAME quantity analytically. Numerically they differ in the last digits,
//  from float summation order — order 1e−13 to 1e−12 relative depending on the series, and
//  deliberately quoted as an order and not a figure: it is a maximum over random draws of a
//  catastrophic-cancellation ratio, which is heavy-tailed and has no bound to quote. (The
//  first version said "agree to the last bit", which is false; the second said "up to
//  5.3e−13", which is a made-up ceiling — the same overstatement in a more convincing
//  costume.) Only SD2 was ever at stake.
//
//  The cleanest demonstration is the alternating series 800, 840, 800, 840 … : every
//  point is (800, 840) or (840, 800), so every point sums to 1640 and the cloud has
//  ZERO extent along the identity line. Geometry says SD2 = 0. The identity says 4.0406
//  with both deviations population, or 11.4286 with a sample SDNN — two different wrong
//  answers, which is itself the tell. `PoincareMetricsTests` pins that case, so nobody
//  can "simplify" this back into the algebraic form.
//
//  ⛔ MY FIRST VERSION OF THIS HEADER ALSO GOT THE DANGER BACKWARDS, which is worth
//  recording because it is this repo's named recurring failure — mechanism plausible,
//  justification false. It warned that reusing `HRVMetrics.sdnn` (the SAMPLE deviation,
//  ÷n−1) instead of a population one "can drive the term negative". Measured: that
//  combination produced **zero** negatives in the same trials — a sample SD is LARGER, so
//  it makes the subtraction safer, not riskier (it is the last row of the table above).
//  The real hazard was the formula, not the convention.
//
//  DIVISOR, and why the reference implementations disagree with each other. Both
//  deviations here are POPULATION (÷n) over the cloud's own points — the same choice
//  pyHRV makes (`numpy.std`, ddof=0 by default). NeuroKit2 uses ddof=1 and therefore
//  reads √(n/(n−1)) higher: +8.0 % at 7 pairs, +2.6 % at 20, converging away. So SD1 and
//  SD2 are only comparable across tools when the divisor is stated — but the RATIO is
//  divisor-invariant (the factor cancels; measured max relative difference ~1e−15), and that
//  is the number to quote against literature — WITH the caveat in the next paragraph, which
//  the first version of this line omitted while calling the ratio the safe one.
//
//  ⛔ HYGIENE PUTS A WALL INTO THE PICTURE, and this file is the one that has to say so.
//  `RRIntervalHygiene` rejects any beat differing by more than 20 % from its predecessor
//  (Malik). SD1 is the spread of exactly that quantity, so NO ACCEPTED POINT CAN LIE OUTSIDE
//  A ±20 % WEDGE around the identity line — the filter is not only removing artifacts, it is
//  bounding the shape. `RRIntervalHygiene`'s header admits the cost as an RMSSD number
//  (~18 % understatement during slow resonance breathing); the consequence unique to DRAWING
//  the cloud belongs here. Measured on a sinusoidal RSA series (mean 900 ms, 6 breaths/min):
//      600 ms peak-to-peak swing → SD1, SD2 and the ratio all unchanged, acceptance 1.00
//      800 ms swing              → SD1 −33 %, SD2 +12 %, **ratio −40 %**, acceptance 0.79
//  So the ratio is the MOST biased of the three, not the safest, and the bias is phase-locked
//  to the deep slow breathing this product is built to reward. The saving grace is that
//  acceptance falls under `minAcceptedFractionForHRV` in that regime, so a view obeying the
//  bar refuses to state the numbers at all. That is why the bar is load-bearing here and not
//  merely tidy — and it is closer to luck than to design, which is the honest way to put it.
//
//  ⚠️ ONE MORE THING THE POOLING DOES. Perpendicular values pooled across segments are all
//  real successive differences, so SD1 is clean. The ALONG axis is an absolute level, so a
//  pooled SD2 across disjoint runs partly measures the offset BETWEEN them rather than
//  variability within any of them (on the dirty test vector, SD2 is literally half the level
//  difference between two unrelated two-beat runs). Defensible — it is what SDNN does — but
//  it means SD2 and the ratio are not literature-comparable in a gappy record.
//
//  ⛔ GAPS ARE NOT CLOSED — the defect the first version of this file shipped, and the
//  repo had already decided the question. It filtered implausible intervals into a
//  COMPACTED array and then paired adjacent entries, so the two beats either side of a
//  removed one became a "consecutive" pair that never occurred. `RRIntervalHygiene`
//  ("THE PART THAT IS EASY TO GET WRONG" in its own header) names exactly that trap for
//  RMSSD and solves it by returning SEGMENTS; `HRVMetrics.rmssd(segments:)` already
//  consumes them. This file now does the same.
//
//  Measured cost, with the protocol stated because a bare percentage here would be the
//  same unreproducible claim as the one two paragraphs up. Take the 10-beat window used in
//  the tests; simulate ONE missed beat by replacing an adjacent pair with its SUM (that is
//  what a dropped beat physically is); compare SD1 from compacted survivors against SD1
//  from segments, at each of the 9 possible positions:
//      −6.8 % … +11.5 % for seven of them · 0.0 % when the artifact lands at the very tail
//      (nothing to join it to) · **+851 %** when it lands at the HEAD.
//  The head case is not an outlier to discount — it is `RRIntervalHygiene`'s own documented
//  hole (the first interval of a window is band-checked but never Malik-checked, because
//  there is no anchor yet), so a head artifact survives hygiene AND gets a fabricated
//  partner under compaction. Note also that compaction is not reliably an OVER-estimate:
//  three positions read low. There is no correction factor to apply; the pairing has to be
//  right.
//
//  Four dropouts, same window, all 15 non-overlapping placements: the segmented path
//  REFUSES TO ANSWER in 8 of them (fewer than two pairs survive), and across the 7 where
//  both paths produce a number they differ by −12 % … +14 749 %. ⛔ An earlier version
//  quoted only that maximum, bare — in the sentence right after declaring that a bare
//  percentage is not a claim. And the maximum was the weaker half anyway: the point worth
//  making is that at four dropouts compaction ALWAYS returns a confident number while the
//  honest path usually returns none.
//
//  ⛔ AND THE JUSTIFICATION THAT WENT WITH IT IS STRUCK. The first header argued the plot
//  doubles as a sensor check because "a missed or doubled beat throws a visible satellite
//  off the cloud". Under hygiene it does not: an artifact is REJECTED, so it is neither
//  plotted nor paired. The honest sensor check is the surviving FRACTION —
//  `Analysis.acceptedFraction`, carried here for exactly that reason — against the bar the
//  repo already set, `RRIntervalHygiene.minAcceptedFractionForHRV` (0.8). A view that
//  shows SD1/SD2 while that bar is unmet is stating a number built from a spliced record.
//
//  NOT A DIAGNOSIS. These are descriptive statistics of an interval series, for
//  self-observation (CLAUDE.md safety section). Nothing here interprets a shape as a
//  health state, and no caller may add that.
//
//  Pure value maths, Foundation only, so the blocking bundle can test it without a
//  sensor, a view or an audio graph.
//
//  CONSUMER: `AnalysisPoincareView` (#347 Slice 3b), doored from the Field panel's "Body"
//  section and guarded by `Tests/CISmoke/PoincareViewDoorTests.swift`.
//
//  ⛔ THE TWO HEADERS BEFORE THIS ONE BOTH PLEDGED "CONSUMER-FREE FOR (EXACTLY / ONE MORE)
//  CYCLE", and the pledge was kept — 3b landed the very next commit — but the phrasing is
//  worth recording as a trap rather than deleted as spent. "ONE MORE" is a promise that can
//  be re-made verbatim forever, and re-making it is precisely how this repo grew its shelf of
//  doorless files. A renewal has to be visibly a SECOND one, or it is not a renewal, it is a
//  default. The split also cost something real: every defect review found in the core was a
//  CONTRACT with the view that did not exist yet — which points get paired, what the plot is
//  claimed to prove, whether the numbers may be stated — so shipping the maths alone froze
//  the wrong shape into a tested file twice over.
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
        /// How many beat PAIRS the numbers rest on, counted WITHIN segments. Meant to be
        /// SHOWN next to them: six points and six hundred deserve different confidence,
        /// and hiding that behind a tidy "SD1 24 ms" is how a readout starts overstating
        /// itself. Note this is NOT `intervals − 1` once anything was rejected — every
        /// gap costs a pair, which is the visible trace of the hygiene.
        let pairs: Int
    }

    /// Everything a view needs, from ONE call — the cloud and the numbers computed from
    /// the SAME segments.
    ///
    /// Separate `points(...)` and `descriptors(...)` calls are still available and still
    /// tested, but a view must use this: with two entry points a caller can draw one set
    /// of beats and label it with statistics derived from another, and the picture would
    /// look entirely reasonable while doing it.
    struct Analysis: Equatable {
        let points: [Point]
        /// `nil` when fewer than `minimumPairs` genuinely consecutive pairs survived.
        ///
        /// ⛔ THE OPTIONALITY IS HERE AND NOT ON `Analysis`, and the first version had it the
        /// other way round — which broke the one thing this type exists for. `analyse` used to
        /// return `nil` whenever the descriptors were unstatable, i.e. exactly when hygiene had
        /// shredded the record into singletons, i.e. exactly when `acceptedFraction` was the
        /// number worth showing. The view's fallback for "no analysis" is "Waiting for beats",
        /// so a catastrophically dirty sensor and a sensor that is not running printed the SAME
        /// SENTENCE, and the refusal machinery below was unreachable in the case it was built
        /// for. Points and the fraction are always statable; only the summary is not.
        let descriptors: Descriptors?
        /// Fraction of the RAW intervals that survived hygiene, 0…1. The honest sensor
        /// check (see the file header): compare against
        /// `RRIntervalHygiene.minAcceptedFractionForHRV` before showing SD1/SD2 as a
        /// figure about the body.
        let acceptedFraction: Double
    }

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
    /// 1e−6 ms is a NANOsecond of heart-rate variability (the first version of this line
    /// said picosecond, which is a thousand times smaller): seven orders above the residue
    /// double precision produces at RR scale (~1e−13 ms), and six orders below the finest
    /// quantum any sensor here delivers — the Polar strap reports RR in 1/1024 s steps,
    /// 0.977 ms, and the camera path lands beats on video frames ~30 ms apart.
    static let degenerateSpreadMs = 1e-6

    /// Fewest beat pairs that can carry a spread. One point has no dispersion in any
    /// direction, and reporting 0 for it would be a claim rather than an absence.
    static let minimumPairs = 2

    /// Runs of genuinely consecutive accepted intervals.
    ///
    /// Delegates to `RRIntervalHygiene` rather than re-deriving a band here: one hygiene
    /// definition per repo, and that one carries the Malik ectopic rule and the honest
    /// note about what it costs during strong RSA. A thin named wrapper rather than a
    /// direct call at each site, so the dependency is visible in this file's own API and
    /// the tests can pin it.
    static func segments(_ rrMs: [Double]) -> [[Double]] {
        RRIntervalHygiene.acceptedSegments(rrMs: rrMs)
    }

    /// The scatter itself: consecutive pairs, taken WITHIN each segment and never across
    /// the boundary between two.
    ///
    /// The boundary is the whole point. A rejected interval leaves a gap; pairing across
    /// it would invent a beat-to-beat transition that never happened — and, being a single
    /// ordinary-looking dot, it would be invisible in the picture it corrupts.
    static func points(segments: [[Double]]) -> [Point] {
        var out: [Point] = []
        out.reserveCapacity(segments.reduce(0) { $0 + max(0, $1.count - 1) })
        for segment in segments where segment.count >= 2 {
            for i in 0..<(segment.count - 1) {
                let a = segment[i]
                let b = segment[i + 1]
                // Non-finite cannot arrive through `segments(_:)` — hygiene rejects it — but
                // this function is directly callable with a hand-built array, and a NaN
                // coordinate in a `Canvas` loop reads as a rendering bug rather than a data
                // one. The file's own doc says hostile input must never reach a coordinate;
                // saying it only about the path that happens to be wired is not the same
                // promise.
                guard a.isFinite, b.isFinite else { continue }
                out.append(Point(rr: a, next: b))
            }
        }
        return out
    }

    /// SD1/SD2 over the pooled within-segment pairs, or `nil` when there are fewer than
    /// `minimumPairs` of them.
    ///
    /// `nil` and not zeros: a cloud of one point has no meaningful spread, and "SD1 0 ms"
    /// is a claim rather than an absence. `HRVMetrics` returns 0 for that case because its
    /// callers already treat 0 as unknown by convention; a view drawing a picture has no
    /// such convention, so the type carries it instead.
    static func descriptors(segments: [[Double]]) -> Descriptors? {
        // Project each point onto the two 45° axes. The √2 is the rotation, not a fudge:
        // (x−y)/√2 is the signed distance from the identity line, (x+y)/√2 the coordinate
        // along it.
        let root2 = 2.0.squareRoot()
        var perpendicular: [Double] = []
        var along: [Double] = []
        for segment in segments where segment.count >= 2 {
            for i in 1..<segment.count {
                perpendicular.append((segment[i - 1] - segment[i]) / root2)
                along.append((segment[i - 1] + segment[i]) / root2)
            }
        }
        guard perpendicular.count >= minimumPairs else { return nil }

        // Snap a residue-sized spread to a clean zero before anyone reads it. Reporting
        // "SD2 0.0000000000002 ms" and reporting "SD2 0.0 ms" are the same statement about
        // the body; only one of them looks like a measurement.
        let sd1 = collapsed(populationSD(perpendicular))
        let sd2 = collapsed(populationSD(along))
        guard sd1.isFinite, sd2.isFinite else { return nil }

        return Descriptors(sd1: sd1,
                           sd2: sd2,
                           ratio: sd2 >= degenerateSpreadMs ? sd1 / sd2 : nil,
                           pairs: perpendicular.count)
    }

    /// THE entry point for a view: hygiene once, then the cloud and the numbers from the
    /// same segments, plus the acceptance fraction that says whether to trust them.
    ///
    /// `nil` ONLY when there was no input at all. Anything else — even a record hygiene
    /// rejects entirely — comes back as an `Analysis` whose `descriptors` may be `nil`, so
    /// the caller can tell "nothing is arriving" from "what arrives is unusable". See
    /// `Analysis.descriptors`.
    static func analyse(rrMs: [Double]) -> Analysis? {
        guard !rrMs.isEmpty else { return nil }
        let segs = segments(rrMs)
        // The fraction is derived from THESE segments rather than from a second
        // `RRIntervalHygiene.accepted(rrMs:)` call, which would run the same gate again. Same
        // answer today, but this method's whole claim is that its parts come from ONE pass —
        // deriving one of them separately made that true by coincidence instead of by
        // construction.
        let survivors = segs.reduce(0) { $0 + $1.count }
        return Analysis(points: points(segments: segs),
                        descriptors: descriptors(segments: segs),
                        acceptedFraction: Double(survivors) / Double(rrMs.count))
    }

    /// Descriptors for a raw series. Convenience over `analyse(rrMs:)` for callers that
    /// want only the numbers — never for a view, which must draw and label from one call.
    static func descriptors(rrMs: [Double]) -> Descriptors? {
        descriptors(segments: segments(rrMs))
    }

    /// Snap a residue-sized value to exactly zero. See `degenerateSpreadMs`.
    private static func collapsed(_ v: Double) -> Double {
        v < degenerateSpreadMs ? 0 : v
    }

    /// Population standard deviation (÷n) of the projected cloud.
    ///
    /// Population and not sample because these are the moments of a FINITE point set that
    /// is fully in hand — the cloud on screen is the whole population, not a draw from a
    /// larger one, and it is the convention pyHRV follows (see the header note on the
    /// divisor and on NeuroKit2's opposite choice). (`HRVMetrics.sdnn` uses ÷n−1,
    /// correctly, because SDNN is reported as an estimate of an underlying process. Two
    /// different questions, two different divisors; neither is a bug in the other.)
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
