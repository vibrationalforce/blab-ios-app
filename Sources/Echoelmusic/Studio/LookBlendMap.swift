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
    /// 2026-07-08, three passes: "Weniger ist mehr", "Prism soll weg", "Cymatics und
    /// Lissajous passt nicht zum Vibe"): four CALM, IMMERSIVE looks — the vibe is
    /// soft liquid light, not technical figures — each still bio/sound-linked:
    /// Rings (heartbeat interference), Water (breath ripples), Aurora (calm
    /// default), Depth (underwater light caustics — returned from retirement as
    /// the founder asked for other visuals in this register). All flash-safe,
    /// slow-motion fields: the calm register IS the health consideration.
    /// **Dish** (#1102, founder 2026-09-07: "reale Wasser Klang Bilder … wie als wenn ein
    /// Lautsprecher mit Wasser füllt") — a dish of water on a speaker, lit from above:
    /// the sounding pitch sets the ripple spacing, the loudness whether ripples appear at
    /// all (`FaradayDish`, real physics; silence is a mirror). It sits in the former
    /// Plasma slot and, like Rings, is NOT in `defaultSequence` — the founder toggles it
    /// in from the look row; the slider does not lengthen for anyone who does not.
    /// Its flash budget (0.4, folds: false → 1.00 Hz) is a row in `FlashGuardTests`,
    /// landed in the SAME commit as this row (an unbudgeted look can reach `main`).
    /// RETIRED from the UI (still compiled in the shader): 1 Cymatics, 4 Prism,
    /// 6 Lissajous, 8 Scope, 9 Fractal; `sequence(from:)` drops their persisted
    /// indices gracefully and the onAppear migration snaps a persisted retired
    /// style to the sequence's first look.
    /// ⛔ #1130 — THIS SAID RE-DOORING WAS "reversible by re-adding a row", AND FOR ONE
    /// OF THE FIVE THAT IS FALSE. All five now have a DERIVED flash rate written at
    /// `FlashGuard.fieldBudget(forStyle:)`, and **8 Scope comes out at 3.90 Hz — over the
    /// 3 Hz epilepsy law.** Adding its row would correctly turn the blocking suite red, so
    /// re-dooring Scope means calming the shader FIRST and only then adding the row. The
    /// other three derive legal (Cymatics 1.25, Prism 2.50, Lissajous 2.50); 9 Fractal is
    /// honestly unknown. Re-adding a row is the LAST step of re-dooring, never the whole of it.
    static let library: [(index: Int, name: String)] = [
        (0, "Rings"), (2, "Dish"), (3, "Water"), (5, "Aurora"), (7, "Depth")
    ]

    /// Default slider sequence — the calm liquid arc (Water · Aurora · Depth).
    static let defaultSequence = [3, 5, 7]

    /// The @AppStorage key both sliders read for the custom sequence.
    static let storageKey = "visual.sliderLooks"

    /// Style index of the Rings look — the ONLY field function the shader hands `density`
    /// (a.k.a. the "Detail" row) to. Named rather than spelled `0` at the three call sites,
    /// because the number alone gives a reader no way to see why Detail is special.
    static let ringsStyleIndex = 0

    /// True when the renderer would draw this style index AS Rings.
    ///
    /// Not `== ringsStyleIndex`, and the difference is the whole point of calling this a
    /// mirror: the shader clamps first (`let s = Float(min(max(style, 0), 9))`) and then
    /// buckets (`if (si < 0.5) field = fieldRings(...)`), so ANY index at or below 0 renders
    /// as Rings. A negative persisted style is close to unreachable — the launch snap and
    /// `lookScrub` only ever write library indices — but "close to unreachable" is not the
    /// same as "mirrors the renderer", and the first version of this function claimed the
    /// latter while doing the former.
    private static func rendersAsRings(_ index: Int) -> Bool { index <= ringsStyleIndex }

    /// #269 — HOW MUCH OF THE METAL FIELD THE "Detail" ROW CAN ACTUALLY SHAPE, 0…1.
    ///
    /// `visual.detail` → `ringDensity` → the shader's `density`, and `styleField` passes
    /// `density` to `fieldRings(d, density, phase, coh)` and to no other field function. So
    /// Detail only reaches the Metal picture through whatever share of the rendered field
    /// comes from Rings. With the shipped defaults — primary style 5 (Aurora), styleB 0,
    /// blend 0 — that share is ZERO, and dragging Detail does nothing visible.
    ///
    /// ⚠️ "the Metal field", not "the screen", and the narrower wording is a correction:
    /// `visual.detail` has a SECOND consumer, `SpectralDonutView(bandCount:)`, where it does
    /// change the picture.
    ///
    /// ⛔ AND THE SENTENCE THAT FOLLOWED IS RETRACTED (2026-09-05, #1003). It read: "That
    /// renderer is doorless today (its only mount sits behind a cover with no setter), so
    /// nothing a player can reach contradicts the caption — but a predicate that claims to
    /// cover 'the screen' would be wrong the day it is re-doored." **#747 re-doored it** —
    /// `visualPanel`'s "Full screen" button opened the cover, and the donut toggle lived
    /// inside it (past tense since #1105: #1069 deleted that cover, the door today is the Field
    /// panel's `Toggle(isOn: $spectralDonuts)`, #1065). So the caveat came true and nothing moved with it: for a whole stretch the
    /// VJ overlay told a player in donut mode that Detail "shapes the Rings look only", while
    /// Detail was the one control on that overlay actually reaching the renderer in front of
    /// them (`bandCount: max(8, Int(visualDetail))`).
    ///
    /// **This predicate itself is unchanged and still correct** — it answers "how much of the
    /// METAL field can Detail shape", and that question has nothing to do with donut mode.
    /// What was wrong is the CAPTION that consumed it, which is fixed at the caption. The
    /// lesson is about the shape of the note, not the maths: a comment that predicts its own
    /// expiry names no OWNER, so nothing goes red when the day arrives. The caption now reads
    /// `spectralDonuts` and a guard pins that it does.
    ///
    /// It mirrors the renderer's arithmetic rather than approximating it: the B field is
    /// evaluated only above a 0.001 blend threshold (`float2 fb = (blend > 0.001) ? … : fa`)
    /// and the two are mixed with weight `blend`. Both use a strict `>`, so they agree at
    /// exactly 0.001.
    ///
    /// ⚠️ IT READS THE STORED BLEND, THE SHADER SEES AN EASED ONE (`tau: 0.3`). That does not
    /// desynchronise the caption, and the reason is worth writing down rather than trusting:
    /// every slider move that can flip this value between zero and non-zero is a change of the
    /// (A, B) style PAIR, and a pair change SNAPS `uniforms.blend` to its target instead of
    /// easing it (the "Grafikterror" fix). Within one pair the easing only lags across the
    /// 0.001 boundary, i.e. within 0.1 % of an endpoint.
    ///
    /// It exists so the UI can say all this honestly. It deliberately does NOT gate, disable
    /// or hide the row — see the caption's own comment for why, which is NOT the reason the
    /// first draft gave.
    static func detailReach(style: Int, styleB: Int, blend: Double) -> Double {
        let b = blend.isFinite ? Swift.min(1, Swift.max(0, blend)) : 0
        let blending = b > 0.001                      // the shader's own threshold
        let aWeight = blending ? 1 - b : 1            // below the threshold, A is the picture
        let bWeight = blending ? b : 0
        return (rendersAsRings(style) ? aWeight : 0)
            + (rendersAsRings(styleB) ? bWeight : 0)
    }

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
