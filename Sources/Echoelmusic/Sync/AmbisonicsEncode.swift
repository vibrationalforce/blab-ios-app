// AmbisonicsEncode.swift
// PURE Ambisonics encoding-gains helper — the ALTERNATIVE renderer path to `VBAPPanner`
// for the self-contained `EchoelRender`. Given a mono source DIRECTION (azimuth/elevation),
// it returns the per-channel encoding coefficients that place that source into an
// Ambisonics soundfield, which a downstream (flag-gated) decoder later renders onto the
// real loudspeaker ring — WITHOUT any external encoder (IEM/Grapes) at runtime.
//
// Channel ordering: ACN (Ambisonic Channel Number), n = l·(l+1) + m.
// Normalization:    SN3D (Schmidt semi-normalized) — the AmbiX house norm; W is always 1.
// Together ACN + SN3D = the AmbiX exchange convention, so these coefficients feed any
// AmbiX-native decoder unchanged.
//
// Control-plane math only: Foundation-only, pure static functions, no state, no audio-thread
// work, no allocation contracts beyond what a returned `[Double]` needs. Compiles on Linux.
//
// Coordinate convention is IEM/`Loudspeaker`'s / AmbiX's (never diverge): azimuth 0 = front,
// +90 = LEFT, -90 = right (right-handed); elevation 0 = ear level, + = up. This matches the
// AmbiX definition (azimuth counter-clockwise, left positive), so no sign inversion is applied.
//
// Real SN3D spherical harmonics up to 3rd order, in azimuth φ / elevation θ, with
// cₑ = cos θ, sₑ = sin θ (no Condon–Shortley phase, per Ambisonics convention):
//
//   ACN 0  (l0 m0 ) W : 1
//   ACN 1  (l1 m-1) Y : cₑ·sin φ
//   ACN 2  (l1 m0 ) Z : sₑ
//   ACN 3  (l1 m1 ) X : cₑ·cos φ
//   ACN 4  (l2 m-2)   : (√3/2)·cₑ²·sin 2φ
//   ACN 5  (l2 m-1)   : √3·sₑ·cₑ·sin φ
//   ACN 6  (l2 m0 )   : (3·sₑ² − 1)/2
//   ACN 7  (l2 m1 )   : √3·sₑ·cₑ·cos φ
//   ACN 8  (l2 m2 )   : (√3/2)·cₑ²·cos 2φ
//   ACN 9  (l3 m-3)   : √(5/8)·cₑ³·sin 3φ
//   ACN 10 (l3 m-2)   : √(15/4)·sₑ·cₑ²·sin 2φ
//   ACN 11 (l3 m-1)   : √(3/8)·(5·sₑ² − 1)·cₑ·sin φ
//   ACN 12 (l3 m0 )   : (5·sₑ³ − 3·sₑ)/2
//   ACN 13 (l3 m1 )   : √(3/8)·(5·sₑ² − 1)·cₑ·cos φ
//   ACN 14 (l3 m2 )   : √(15/4)·sₑ·cₑ²·cos 2φ
//   ACN 15 (l3 m3 )   : √(5/8)·cₑ³·cos 3φ

import Foundation

/// A stateless Ambisonics (ACN / SN3D) encoder for a mono point source. See file header.
public enum AmbisonicsEncode {

    /// Highest Ambisonic order this helper supports.
    public static let maxOrder = 3

    /// SN3D encoding coefficients for a mono source at the given direction.
    ///
    /// - Parameters:
    ///   - azimuthDeg: source azimuth in degrees (Echoel/AmbiX: 0 = front, +90 = LEFT).
    ///   - elevationDeg: source elevation in degrees (0 = ear level, + = up).
    ///   - order: Ambisonic order, clamped to `0...3`.
    /// - Returns: `(clampedOrder + 1)²` coefficients in ACN order, SN3D-normalized.
    ///   Index 0 (W) is always `1.0` for any direction (SN3D).
    public static func coefficients(azimuthDeg: Double,
                                    elevationDeg: Double,
                                    order: Int) -> [Double] {
        let clampedOrder = min(max(order, 0), maxOrder)

        let az = azimuthDeg * .pi / 180
        let el = elevationDeg * .pi / 180
        let ce = cos(el)   // cos θ — horizontal-projection factor, ≥ 0 for el ∈ [-90, 90]
        let se = sin(el)   // sin θ — the up component

        // (clampedOrder + 1)² coefficients, pre-sized so we only ever index-assign.
        var coeffs = [Double](repeating: 0, count: (clampedOrder + 1) * (clampedOrder + 1))

        // --- Order 0: W (always 1.0 in SN3D) ---
        coeffs[0] = 1.0
        if clampedOrder == 0 { return coeffs }

        // --- Order 1: Y, Z, X ---
        coeffs[1] = ce * sin(az)   // ACN 1  Y
        coeffs[2] = se             // ACN 2  Z
        coeffs[3] = ce * cos(az)   // ACN 3  X
        if clampedOrder == 1 { return coeffs }

        let ce2 = ce * ce
        let se2 = se * se
        let sqrt3 = 3.0.squareRoot()

        // --- Order 2 ---
        coeffs[4] = (sqrt3 / 2) * ce2 * sin(2 * az)   // ACN 4  (m = -2)
        coeffs[5] = sqrt3 * se * ce * sin(az)         // ACN 5  (m = -1)
        coeffs[6] = (3 * se2 - 1) / 2                 // ACN 6  (m =  0)
        coeffs[7] = sqrt3 * se * ce * cos(az)         // ACN 7  (m =  1)
        coeffs[8] = (sqrt3 / 2) * ce2 * cos(2 * az)   // ACN 8  (m =  2)
        if clampedOrder == 2 { return coeffs }

        let ce3 = ce2 * ce
        let se3 = se2 * se
        let kL3m3 = (5.0 / 8.0).squareRoot()   // √(5/8)  ≈ 0.790569
        let kL3m2 = (15.0 / 4.0).squareRoot()  // √(15/4) ≈ 1.936492
        let kL3m1 = (3.0 / 8.0).squareRoot()   // √(3/8)  ≈ 0.612372

        // --- Order 3 ---
        coeffs[9]  = kL3m3 * ce3 * sin(3 * az)                 // ACN 9  (m = -3)
        coeffs[10] = kL3m2 * se * ce2 * sin(2 * az)            // ACN 10 (m = -2)
        coeffs[11] = kL3m1 * (5 * se2 - 1) * ce * sin(az)      // ACN 11 (m = -1)
        coeffs[12] = (5 * se3 - 3 * se) / 2                    // ACN 12 (m =  0)
        coeffs[13] = kL3m1 * (5 * se2 - 1) * ce * cos(az)      // ACN 13 (m =  1)
        coeffs[14] = kL3m2 * se * ce2 * cos(2 * az)            // ACN 14 (m =  2)
        coeffs[15] = kL3m3 * ce3 * cos(3 * az)                 // ACN 15 (m =  3)
        return coeffs
    }

    /// The number of coefficients an encode at `order` produces: `(clampedOrder + 1)²`.
    public static func coefficientCount(order: Int) -> Int {
        let clampedOrder = min(max(order, 0), maxOrder)
        return (clampedOrder + 1) * (clampedOrder + 1)
    }
}
