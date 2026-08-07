//
//  RRAdjacency.swift
//  Echoelmusic — Bio
//
//  Which RR intervals are GENUINELY NEXT TO EACH OTHER IN TIME.
//
//  RMSSD and pNN50 read CONSECUTIVE pairs. Feeding them a series that has had beats
//  removed from the middle manufactures a difference that no heart produced: the two
//  survivors either side of a removal are adjacent in the ARRAY and seconds apart in the
//  BODY. `HRVMetrics` has said so since it grew its `segments:` overloads, and the strap
//  path (`PolarH10BioPublisher`) has used them via `RRIntervalHygiene.acceptedSegments`
//  ever since.
//
//  ⭐ THE CAMERA COULD NOT USE THAT ROUTE, AND THAT IS THE WHOLE REASON THIS FILE EXISTS.
//  `RRIntervalHygiene` decides WHICH beats to accept (band + Malik) and returns the runs
//  as a by-product. `CameraAnalyzer` has ALREADY made that decision, twice and with its
//  own rules — a `continue` past every peak difference outside 0.3…1.5 s, then an IQR
//  rejection over the survivors — and it compacts both times, so by the time anyone sees
//  `rrIntervals` the gaps are invisible. Running `RRIntervalHygiene` over that array would
//  not recover them; it would apply a THIRD, different acceptance policy to a series whose
//  adjacency was already destroyed, and Malik's 20 % step is tuned for a chest strap, not
//  for rPPG. This type therefore changes NO acceptance decision at all. It only answers
//  which of the already-accepted intervals sit next to each other, from evidence the
//  analyzer already keeps: the absolute time of each interval's SECOND beat.
//
//  The test is exact rather than statistical. Interval `i` covers the beats ending at
//  `endTimes[i]`, so its own start is `endTimes[i] − intervals[i]`. It follows `i−1`
//  immediately iff that start IS `endTimes[i−1]` — the same beat. Any dropped beat leaves
//  a hole and the equality fails.
//
//  ⭐ ON A GAP-FREE SERIES THIS IS EXACTLY A NO-OP, and that is arithmetic rather than a
//  measurement: no holes means one run, `rmssd(rrMs:)` divides by `count − 1` and
//  `rmssd(segments:)` by the pair count, which for a single run is the same integer. Pinned
//  bit-for-bit by `RMSSDReadsOnlyAdjacentBeatsTests`. That is the claim that makes the slice
//  safe to land blind: a well-placed finger's numbers cannot move.
//
//  ⚠️ WHAT IT BUYS WHEN THE CONTACT IS POOR, measured before it was written rather than claimed
//  after. Transcribing `CameraAnalyzer`'s interval pipeline and driving it with a 60 bpm RSA
//  series (10 s windows, 600 seeds per row), pooling across gaps INFLATES both metrics by an
//  amount that grows with the artifact rate:
//
//      injected dropped/spurious   RMSSD flat → segmented    pNN50 flat → segmented
//      0 % / 0 %                   30.75 → 30.76  (−0.03 %)   7.1 → 7.1   (0.0 pp)
//      5 % / 5 %                   52.55 → 51.11  (+2.8 %)   12.8 → 10.5  (2.3 pp)
//      15 % / 10 %                119.62 → 114.00 (+4.9 %)   25.4 → 22.3  (3.1 pp)
//      25 % / 15 %                173.42 → 160.11 (+8.3 %)   36.8 → 32.7  (4.1 pp)
//      35 % / 20 %                226.37 → 206.62 (+9.6 %)   47.5 → 45.4  (2.2 pp)
//
//  ⛔ THE FIRST ROW IS NOT THE CLEAN-TAKE ROW, and calling it that was wrong twice over — the
//  label said "none" and the ⭐ above used to point AT it for the no-op claim, while the number
//  beside it (30.75 → 30.76) is neither identical nor even in the stated direction. Injecting
//  zero artifacts does not produce a gap-free series: the band `continue` and the IQR pass still
//  reject beats, so that row already contains holes. Its −0.03 % is the residual of a handful of
//  them, and its sign is not meaningful at that magnitude. The no-op claim is real; it belongs
//  to the ⭐ paragraph, which proves it by construction, not to a model row that looked like it.
//  **A row labelled "none" is a claim, and it has to be checked against what the model actually
//  did, not against what the label suggests.**
//
//  ⛔ THE ARTIFACT RATES ARE ASSUMPTIONS, NOT MEASUREMENTS. Nothing in this repo records
//  how often a device take drops or invents a beat; the rows above are a model driven at
//  chosen rates, so the SHAPE — monotone and one-directional ABOVE the residual, and exactly
//  zero on a genuinely gap-free series — is the finding and the individual percentages are
//  illustrative. (⛔ That parenthetical read "one-directional, zero at zero", which the first
//  row falsifies on both halves: the model's zero-injection row is neither zero nor positive.
//  The exact-zero statement is true of a gap-free series, which is a different thing from a
//  zero-injection model run.) A single take can show far more — the
//  worst seed in a 3000-seed sweep read +15420 %, and that number is deliberately NOT
//  quoted as a worst case: its segmented denominator was 0.2 ms, so it measures a small
//  divisor and not a large error.
//
//  Pure value math, no platform imports — testable anywhere, unlike `CameraAnalyzer`
//  itself, which lives inside `#if canImport(AVFoundation)`.
//

import Foundation

public enum RRAdjacency {

    /// How far apart the reconstructed start of one interval may sit from the end of the
    /// previous one before they count as separated by a dropped beat.
    ///
    /// Derived from both sides rather than picked. BELOW it: the only error in play is
    /// floating point. The times are `systemUptime` seconds (order 1e5–1e6 on a device that
    /// has been up a while) and the interval makes a ×1000 then ÷1000 round trip through
    /// milliseconds, so the residue is a few ulps — order 1e-10 s. ABOVE it: the smallest
    /// hole a real dropped beat can leave is one peak spacing, and `CameraAnalyzer`'s
    /// refractory refuses peaks closer than **0.3 s** (`refractorySeconds` clamps with
    /// `max(0.3, …)` and falls back to 0.3). So this sits ~1e6 above the noise and ~3e3 below
    /// the smallest thing it must detect, and no plausible drift in either direction reaches
    /// it. ⛔ The first version of this paragraph wrote "~0.2 s" for the refractory and 1e-9
    /// for the residue — both wrong, both in the SAFE direction, which is exactly why nothing
    /// would have caught them: a margin quoted too small still reads as a margin.
    public static let toleranceSeconds = 1e-4

    /// Split intervals into runs of genuinely consecutive ones.
    ///
    /// - Parameters:
    ///   - intervalsMs: accepted RR intervals, in milliseconds, in time order.
    ///   - endTimesSeconds: absolute time of each interval's SECOND beat, 1:1 with
    ///     `intervalsMs` and in the same order.
    ///
    /// Returns one run per unbroken stretch. A length-1 run carries no successive
    /// difference and is kept anyway: `HRVMetrics.rmssd(segments:)` and `pnn50(segments:)`
    /// skip it, `sdnn(segments:)` deliberately excludes it, and dropping it here would take
    /// that decision away from the metric that owns it.
    ///
    /// ⚠️ Returns `[]` when the two arrays disagree in length. That is not defensive noise:
    /// they are produced together and are 1:1 by construction, so a mismatch means an edit
    /// broke one side, and indexing on a broken invariant would silently pair each interval
    /// with someone else's timestamp — an HRV number computed from mismatched beats, which
    /// is worse than no number. The camera publisher already refuses to ingest respiration
    /// on exactly this check, for exactly this reason.
    public static func segments(intervalsMs: [Double],
                                endTimesSeconds: [Double]) -> [[Double]] {
        guard intervalsMs.count == endTimesSeconds.count else { return [] }
        var runs: [[Double]] = []
        var current: [Double] = []
        for i in intervalsMs.indices {
            if !current.isEmpty {
                let start = endTimesSeconds[i] - intervalsMs[i] / 1000.0
                let contiguous = abs(start - endTimesSeconds[i - 1]) <= toleranceSeconds
                if !contiguous {
                    runs.append(current)
                    current = []
                }
            }
            current.append(intervalsMs[i])
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Number of dropped-beat holes the series carries — one less than the run count, and 0
    /// for an empty series.
    ///
    /// ⚠️ NO PRODUCTION CALLER TODAY, said plainly instead of implied. The first version of
    /// this doc argued it "is exposed because 'how much did we remove' is the honest companion
    /// to any HRV figure derived from a filtered series" — a good argument for a number that
    /// nothing surfaces, which is this repo's most-repeated defect shape: a justification
    /// written as if the wiring existed. It is kept because the surfacing IS worth doing
    /// (`RRIntervalHygiene.acceptedFraction` makes the same case on the strap side and does
    /// have a reader) and because the one line costs nothing — but until a readout or a
    /// breadcrumb prints it, it is test-only, and it must not be cited as evidence that a take
    /// reports its own gap count.
    public static func gapCount(intervalsMs: [Double],
                                endTimesSeconds: [Double]) -> Int {
        max(0, segments(intervalsMs: intervalsMs, endTimesSeconds: endTimesSeconds).count - 1)
    }
}
