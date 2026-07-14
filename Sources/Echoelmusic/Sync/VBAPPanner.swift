// VBAPPanner.swift
// PURE 2D VBAP (Vector Base Amplitude Panning) gain solver — the self-contained
// immersive-panning core that lets EchoelRender place a mono source on the real
// (non-imaginary) loudspeaker ring WITHOUT any external decoder (IEM/Grapes) at
// runtime. Control-plane math only: Foundation-only, pure value types, no audio-thread
// work, no allocation contracts to honour beyond what a Swift dictionary needs. It maps
// a source azimuth to per-channel gains that a downstream (flag-gated) renderer applies.
//
// Coordinate convention is IEM/`Loudspeaker`'s (never diverge): azimuth 0 = front,
// +90 = LEFT, -90 = right, right-handed. All angle math is in DEGREES, wrapped to the
// half-open interval (-180, 180].
//
// Algorithm (2D vector base / tangent law):
//   * Use only the REAL (non-imaginary) speakers, sorted by azimuth.
//   * Find the adjacent pair whose arc brackets the source azimuth (wrap across ±180
//     handled).
//   * Solve p = g_a·û_a + g_b·û_b for the pair's unit vectors û = (cos θ, sin θ). This is
//     the tangent/constant-power law; both gains are ≥ 0 for a bracketing pair.
//   * Energy-normalize the pair so Σ gain² = 1.
//   * Source exactly on a speaker → that speaker 1, neighbour 0.
//   * Fewer than two real speakers → the single speaker gets gain 1 (empty → empty).

import Foundation

/// A stateless 2D VBAP gain solver over a `Loudspeaker` ring. See file header.
public enum VBAPPanner {

    /// Angles within this many degrees are treated as coincident (on-speaker snap,
    /// coincident-speaker guard). Well below any real ring spacing.
    private static let epsilonDeg = 1e-6

    /// Wrap an angle in degrees into the half-open interval (-180, 180].
    public static func wrapDeg(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a <= -180 { a += 360 }
        if a > 180 { a -= 360 }
        return a
    }

    /// Solve per-channel VBAP gains for a mono source at `sourceAzimuthDeg`.
    /// Returns a map of `Loudspeaker.channel` → gain (energy-normalized, Σ gain² = 1 for
    /// the active pair). Only the two bracketing real speakers get non-zero gains.
    ///
    /// - Parameters:
    ///   - sourceAzimuthDeg: source azimuth in degrees (IEM convention, any range —
    ///     wrapped internally).
    ///   - speakers: the loudspeaker layout; only real (non-imaginary) speakers are used.
    /// - Returns: channel → gain. Empty when there are no real speakers.
    public static func gains(sourceAzimuthDeg: Double, speakers: [Loudspeaker]) -> [Int: Double] {
        // Real ring only, sorted by wrapped azimuth (stable on channel for tie-safety).
        let ring = speakers
            .filter { !$0.isImaginary }
            .sorted { lhs, rhs in
                let la = wrapDeg(lhs.azimuth), ra = wrapDeg(rhs.azimuth)
                if la == ra { return lhs.channel < rhs.channel }
                return la < ra
            }

        guard !ring.isEmpty else { return [:] }
        guard ring.count >= 2 else { return [ring[0].channel: 1.0] }

        let src = wrapDeg(sourceAzimuthDeg)

        // Exact on-speaker → that speaker 1, everyone else 0.
        for spk in ring where abs(shortestArc(from: wrapDeg(spk.azimuth), to: src)) <= epsilonDeg {
            return [spk.channel: 1.0]
        }

        // Locate the bracketing adjacent pair. Each consecutive gap (including the wrap
        // gap from the last speaker CCW back to the first) covers a slice of the circle;
        // the source falls into exactly one.
        let n = ring.count
        for i in 0..<n {
            let a = ring[i]
            let b = ring[(i + 1) % n]
            let aAz = wrapDeg(a.azimuth)
            let bAz = wrapDeg(b.azimuth)
            // CCW span of the gap (0, 360). Speakers are ascending, so non-wrap gaps are
            // bAz - aAz; the final wrap gap is the remainder up to 360.
            let gap = positiveMod(bAz - aAz, 360)
            // How far the source sits into this gap, measured CCW from a.
            let into = positiveMod(src - aAz, 360)
            guard into < gap else { continue }

            if let pair = pairGains(sourceAz: src, azA: aAz, azB: bAz) {
                let normalized = normalizePair(pair.gA, pair.gB)
                return [a.channel: normalized.0, b.channel: normalized.1]
            }
            // Coincident/antipodal pair (det≈0): can't pan across it, fall back to the
            // nearer speaker at unit gain.
            let dA = abs(shortestArc(from: aAz, to: src))
            let dB = abs(shortestArc(from: bAz, to: src))
            return [(dA <= dB ? a : b).channel: 1.0]
        }

        // Unreachable for a well-formed ring, but stay total: nearest speaker gets it.
        let nearest = ring.min { abs(shortestArc(from: wrapDeg($0.azimuth), to: src))
                                 < abs(shortestArc(from: wrapDeg($1.azimuth), to: src)) }
        if let nearest { return [nearest.channel: 1.0] }
        return [:]
    }

    /// Energy-normalize an arbitrary gain map so Σ gain² = 1. A zero (or empty) map is
    /// returned unchanged (guard against divide-by-zero).
    public static func normalized(_ gains: [Int: Double]) -> [Int: Double] {
        let sumSq = gains.values.reduce(0) { $0 + $1 * $1 }
        guard sumSq > 0 else { return gains }
        let norm = sqrt(sumSq)
        guard norm != 0 else { return gains }
        var out = gains
        for (k, v) in gains { out[k] = v / norm }
        return out
    }

    // MARK: - Private math

    /// Vector-base solve for one bracketing pair. Returns raw (pre-normalization) gains,
    /// clamped to ≥ 0. `nil` when the speakers are coincident/antipodal (det ≈ 0).
    private static func pairGains(sourceAz: Double, azA: Double, azB: Double)
        -> (gA: Double, gB: Double)? {
        let ra = azA * .pi / 180, rb = azB * .pi / 180, rs = sourceAz * .pi / 180
        let ax = cos(ra), ay = sin(ra)
        let bx = cos(rb), by = sin(rb)
        let px = cos(rs), py = sin(rs)

        // det = sin(b - a); zero when coincident or antipodal.
        let det = ax * by - ay * bx
        guard abs(det) > 1e-12 else { return nil }

        // [gA gB] = p · L⁻¹  with L = [[ax ay],[bx by]].
        let gA = (px * by - py * bx) / det
        let gB = (-px * ay + py * ax) / det
        return (max(0, gA), max(0, gB))
    }

    /// Energy-normalize a single pair so gA² + gB² = 1 (guarded).
    private static func normalizePair(_ gA: Double, _ gB: Double) -> (Double, Double) {
        let norm = sqrt(gA * gA + gB * gB)
        guard norm > 0 else { return (gA, gB) }
        return (gA / norm, gB / norm)
    }

    /// Signed shortest arc from `a` to `b` in degrees, in (-180, 180].
    private static func shortestArc(from a: Double, to b: Double) -> Double {
        wrapDeg(b - a)
    }

    /// Non-negative remainder (Swift `%` keeps the dividend's sign).
    private static func positiveMod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}
