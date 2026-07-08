//
//  LookBlendMap.swift
//  Echoelmusic — Studio
//
//  ONE long slider, stufenlos through the looks (founder 2026-07-07: "möglichst
//  einfache Steuerung per langem slider, der durch alle Modi stufenlos überblendet").
//  The Metal renderer already crossfades two looks (style + styleB + blend), so a
//  continuous slider position maps to a (a, b, frac) triple: position 1.4 renders
//  40 % of the way from look 1 into look 2.
//
//  CUSTOMIZABLE sequence (founder 2026-07-08: "das menü überarbeiten damit man das
//  was im slider passiert selbst customizen kann … mehr Optionen"): the SEQUENCE the
//  slider fades through is user-chosen from the full look library, persisted as a
//  compact "3,5,7,2" string. All mapping is pure value maths — unit-tested — and takes
//  the active sequence as a parameter, so the same functions serve any custom order.
//

import Foundation

enum LookBlendMap {

    /// The CURATED library of Metal field looks (style index → display name), canonical
    /// order. Indices match MetalBioView's `style` selector. CURATION (founder
    /// 2026-07-08: "Weniger ist mehr … wir brauchen auch nicht so viele Looks"): six
    /// looks, each with a real sound/bio link — Rings (heartbeat interference),
    /// Cymatics (pitch → plate modes), Water (breath), Prism (spectral dispersion of
    /// the heard tone), Aurora (calm immersive default), Lissajous (tone-frequency
    /// figures). RETIRED from the UI (still compiled in the shader, reversible by
    /// re-adding a row): 2 Plasma, 7 Depth, 8 Scope, 9 Fractal — decorative fields
    /// without a distinct sound link; `sequence(from:)` drops their persisted indices
    /// gracefully.
    static let library: [(index: Int, name: String)] = [
        (0, "Rings"), (1, "Cymatics"), (3, "Water"),
        (4, "Prism"), (5, "Aurora"), (6, "Lissajous")
    ]

    /// Default slider sequence — calm to structural, each stop sound-linked
    /// (Water · Aurora · Cymatics · Prism).
    static let defaultSequence = [3, 5, 1, 4]

    /// The @AppStorage key both sliders read for the custom sequence.
    static let storageKey = "visual.sliderLooks"

    /// Display name for a style index (falls back gracefully for an unknown index).
    static func name(for index: Int) -> String {
        library.first { $0.index == index }?.name ?? "Look \(index)"
    }

    /// Parse the persisted "3,5,7,2" string into a valid, de-duplicated sequence of
    /// KNOWN look indices. Empty/garbage falls back to the calm default so the slider
    /// is never broken by a bad stored value.
    static func sequence(from raw: String) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        for token in raw.split(separator: ",") {
            guard let i = Int(token.trimmingCharacters(in: .whitespaces)),
                  library.contains(where: { $0.index == i }),
                  !seen.contains(i) else { continue }
            seen.insert(i)
            out.append(i)
        }
        return out.isEmpty ? defaultSequence : out
    }

    /// Serialize a sequence back to the compact storage string.
    static func string(from sequence: [Int]) -> String {
        sequence.map(String.init).joined(separator: ",")
    }

    /// Toggle a look in/out of a sequence, keeping canonical (library) order and never
    /// dropping below one look (a zero-look slider has nothing to fade). Returns the new
    /// sequence.
    static func toggling(_ index: Int, in sequence: [Int]) -> [Int] {
        if sequence.contains(index) {
            let next = sequence.filter { $0 != index }
            return next.isEmpty ? sequence : next          // keep at least one
        }
        // Insert in canonical library order so the slider reads left→right sensibly.
        let order = library.map(\.index)
        return order.filter { sequence.contains($0) || $0 == index }
    }

    /// The slider's full range for a sequence: 0 … count-1. 0 when only one look is
    /// selected (callers should then show the single look, not a degenerate slider).
    static func maxPosition(for sequence: [Int]) -> Double {
        Double(max(1, sequence.count) - 1)
    }

    /// A continuous slider position resolved into the renderer's crossfade triple.
    struct Blend: Equatable {
        var a: Int        // primary style index
        var b: Int        // secondary style index (== a at exact stops)
        var frac: Float   // 0 = pure a … 1 = pure b
    }

    /// Map a slider position (0…maxPosition, clamped) to the crossfade triple for the
    /// given sequence.
    static func blend(at position: Double, sequence: [Int]) -> Blend {
        let looks = sequence.isEmpty ? defaultSequence : sequence
        let maxP = Double(looks.count - 1)
        let p = min(max(position.isFinite ? position : 0, 0), max(0, maxP))
        let i = min(looks.count - 1, Int(p))
        let frac = Float(p - Double(i))
        if frac < 0.001 || i >= looks.count - 1 {
            return Blend(a: looks[i], b: looks[i], frac: 0)   // pure look, no B pass
        }
        return Blend(a: looks[i], b: looks[i + 1], frac: frac)
    }

    /// Reconstruct the slider position from persisted style/styleB/blend against a
    /// sequence — so the slider reopens where the user left it. A style not in the
    /// sequence (e.g. after the sequence was edited) reads as position 0.
    static func position(a: Int, b: Int, frac: Float, sequence: [Int]) -> Double {
        let looks = sequence.isEmpty ? defaultSequence : sequence
        guard let i = looks.firstIndex(of: a) else { return 0 }
        let f = min(max(frac.isFinite ? frac : 0, 0), 1)
        guard f > 0.001, i < looks.count - 1, looks[i + 1] == b else { return Double(i) }
        return Double(i) + Double(f)
    }

    /// Name of the look nearest a slider position (for the readout label).
    static func nearestName(at position: Double, sequence: [Int]) -> String {
        let looks = sequence.isEmpty ? defaultSequence : sequence
        let maxP = Double(looks.count - 1)
        let p = min(max(position.isFinite ? position : 0, 0), max(0, maxP))
        let i = min(looks.count - 1, Int(p.rounded()))
        return name(for: looks[max(0, i)])
    }
}
