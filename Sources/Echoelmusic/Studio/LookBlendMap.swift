//
//  LookBlendMap.swift
//  Echoelmusic — Studio
//
//  ONE long slider, stufenlos through the looks (founder 2026-07-07: "möglichst
//  einfache Steuerung per langem slider, der durch alle Modi stufenlos überblendet").
//  The Metal renderer already crossfades two looks (style + styleB + blend), so a
//  continuous slider position maps to a (a, b, frac) triple: position 1.4 renders
//  40 % of the way from look 1 into look 2. Pure value maths — unit-tested, and the
//  SINGLE source of truth for the surfaced look order (was duplicated as `calmLooks`
//  in FloatingVisualWindow + EchoelStudioView).
//

import Foundation

enum LookBlendMap {

    /// The surfaced looks, in slider order — the calm, liquid fields:
    /// Water · Aurora · Depth Caustics · Plasma (MetalBioView style indices).
    /// The busy/technical looks stay in the shader but aren't on the slider.
    static let looks = [3, 5, 7, 2]

    /// Display names matching `looks` (the slider itself has no per-stop labels).
    static let names = ["Water", "Aurora", "Depth", "Plasma"]

    /// The slider's full range: 0 … count-1 (3.0 for four looks).
    static var maxPosition: Double { Double(looks.count - 1) }

    /// A continuous slider position resolved into the renderer's crossfade triple.
    struct Blend: Equatable {
        var a: Int        // primary style index
        var b: Int        // secondary style index (== a at exact stops)
        var frac: Float   // 0 = pure a … 1 = pure b
    }

    /// Map a slider position (0…maxPosition, clamped) to the crossfade triple.
    static func blend(at position: Double) -> Blend {
        let p = min(max(position.isFinite ? position : 0, 0), maxPosition)
        let i = min(looks.count - 1, Int(p))
        let frac = Float(p - Double(i))
        // At (or numerically at) a stop, render the pure look — no wasted B pass.
        if frac < 0.001 || i >= looks.count - 1 {
            return Blend(a: looks[i], b: looks[i], frac: 0)
        }
        return Blend(a: looks[i], b: looks[i + 1], frac: frac)
    }

    /// Reconstruct the slider position from persisted style/styleB/blend state —
    /// so the slider reopens where the user left it. A style that isn't on the
    /// slider (retired/busy look) reads as position 0.
    static func position(a: Int, b: Int, frac: Float) -> Double {
        guard let i = looks.firstIndex(of: a) else { return 0 }
        let f = min(max(frac.isFinite ? frac : 0, 0), 1)
        guard f > 0.001, i < looks.count - 1, looks[i + 1] == b else { return Double(i) }
        return Double(i) + Double(f)
    }

    /// Name of the look nearest a slider position (for the readout label).
    static func nearestName(at position: Double) -> String {
        let p = min(max(position.isFinite ? position : 0, 0), maxPosition)
        let i = min(names.count - 1, Int(p.rounded()))
        return names[max(0, i)]
    }
}
