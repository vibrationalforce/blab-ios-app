//
//  SpectralColor.swift
//  Echoelmusic — Studio
//
//  Maps pitch (and chords) to colour the perceptually-honest way, per the cited
//  research (scratchpads/RESEARCH_SOUND_TO_COLOR.md):
//
//    • Pitch-class → hue on an OKLCH hue circle (12 equal 30° steps). Pitch-class is
//      circular (octave-equivalent: C→C); the visible spectrum is a LINE, so we do
//      NOT route pitch through wavelength→RGB (that would break at the red/violet
//      ends). The OKLCH hue circle is a closed loop with the non-spectral magenta /
//      "line of purples" synthesized for us — exactly what closes pitch-class cleanly.
//    • Higher pitch → lighter (OKLab L). Robust cross-modal correspondence.
//    • Louder → more chroma/saturation. Robust correspondence.
//    • Chords mix amplitude-weighted in OKLab (perceptual), NOT summed in RGB — RGB
//      sums wash to white; an OKLab average lets a dense cluster fall toward neutral
//      (low chroma) instead of blowing out. Partials are capped.
//
//  The specific pitch-class→hue table is a CONVENTION (note→hue is idiosyncratic /
//  synesthete-specific), exposed via `hueOffsetDegrees`, not a scientific claim.
//
//  Pure value type, Foundation-only. Output is LINEAR sRGB [0,1] (gamut-clamped) so
//  the Metal shader / lighting can consume it directly; `hue01` gives the bare hue.
//

import Foundation

/// Linear sRGB in [0,1] (not gamma-encoded). Clamp-gamut.
public struct LinearRGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
}

/// A colour in OKLab (perceptual): L lightness, a/b opponent axes.
public struct OKLab: Equatable, Sendable {
    public var L: Double, a: Double, b: Double
    public init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }
}

public enum SpectralColor {

    // MARK: Convention / tuning
    /// Hue offset (degrees) for the pitch-class→hue convention. A preset, not a fact.
    public static let hueOffsetDegrees = 0.0
    /// Reference C0 (Hz) for pitch-class, and the lightness range over the audible band.
    private static let c0Hz = 16.351597831287414       // MIDI 12 = C0
    private static let lightLowHz = 55.0               // A1 — bottom of the L ramp
    private static let lightOctaves = 6.0              // ~A1…A7 spans the L ramp
    private static let lMin = 0.45, lMax = 0.82        // OKLab lightness range
    /// Max OKLab chroma at full amplitude — capped to stay (mostly) in sRGB gamut.
    private static let maxChroma = 0.13
    /// Cap on how many chord partials are mixed (avoids mush + cost).
    private static let maxPartials = 6
    /// Neutral fallback (no/!valid input): mid-grey from L only.
    public static let neutral = SpectralColor.oklabToLinear(OKLab(L: 0.6, a: 0, b: 0))

    // MARK: Pitch → perceptual colour

    /// Pitch-class [0,12) of a frequency (octave-equivalent). 0 = C.
    public static func pitchClass(ofFrequency hz: Double) -> Double {
        guard hz > 0, hz.isFinite else { return 0 }
        let semis = 12.0 * log2(hz / c0Hz)
        var pc = semis.truncatingRemainder(dividingBy: 12.0)
        if pc < 0 { pc += 12.0 }
        return pc
    }

    /// Bare hue [0,1) for the pitch-class (octave-equivalent). Feeds e.g. a hue knob.
    public static func hue01(forFrequency hz: Double) -> Double {
        guard hz > 0, hz.isFinite else { return 0 }
        let deg = pitchClass(ofFrequency: hz) / 12.0 * 360.0 + hueOffsetDegrees
        var h = deg.truncatingRemainder(dividingBy: 360.0)
        if h < 0 { h += 360.0 }
        return h / 360.0
    }

    /// A single note as OKLab: hue from pitch-class, L from pitch height, chroma from
    /// amplitude. The building block for both display and mixing.
    public static func oklab(forFrequency hz: Double, amplitude: Double = 1) -> OKLab {
        guard hz > 0, hz.isFinite else { return OKLab(L: 0.6, a: 0, b: 0) }
        let amp = Swift.min(1.0, Swift.max(0.0, amplitude.isFinite ? amplitude : 0))

        // Hue (radians) from pitch-class.
        let hueRad = (pitchClass(ofFrequency: hz) / 12.0 * 360.0 + hueOffsetDegrees) * .pi / 180.0

        // Lightness rises with pitch height (clamped to the visible-comfortable band).
        let heightNorm = Swift.min(1.0, Swift.max(0.0, log2(hz / lightLowHz) / lightOctaves))
        let L = lMin + (lMax - lMin) * heightNorm

        // Chroma from amplitude.
        let C = maxChroma * amp
        return OKLab(L: L, a: C * cos(hueRad), b: C * sin(hueRad))
    }

    /// A single note as linear sRGB (gamut-clamped).
    public static func color(forFrequency hz: Double, amplitude: Double = 1) -> LinearRGB {
        oklabToLinear(oklab(forFrequency: hz, amplitude: amplitude))
    }

    /// A chord/spectrum → one colour. Amplitude-weighted OKLab average of the loudest
    /// `maxPartials` notes (perceptual mix; dense clusters fall toward neutral, never
    /// blow out to white). Empty/!valid input → neutral grey.
    public static func color(forChord notes: [(hz: Double, amplitude: Double)]) -> LinearRGB {
        let valid = notes.filter { $0.hz > 0 && $0.hz.isFinite && $0.amplitude > 0 && $0.amplitude.isFinite }
        guard !valid.isEmpty else { return neutral }
        let top = valid.sorted { $0.amplitude > $1.amplitude }.prefix(maxPartials)

        var wSum = 0.0, L = 0.0, a = 0.0, b = 0.0
        for n in top {
            let lab = oklab(forFrequency: n.hz, amplitude: n.amplitude)
            let w = n.amplitude
            L += w * lab.L; a += w * lab.a; b += w * lab.b; wSum += w
        }
        guard wSum > 0 else { return neutral }
        return oklabToLinear(OKLab(L: L / wSum, a: a / wSum, b: b / wSum))
    }

    // MARK: Audible → visible spectrum (per-band donut visualization)

    /// Translate an audible frequency to a VISIBLE-spectrum colour by mapping the
    /// (log) audible range onto wavelengths 700 nm (low → red) … 400 nm (high → violet),
    /// then wavelength → RGB. Unlike `oklab(forFrequency:)` (octave-CYCLIC pitch-class
    /// hue, so partials of one note collapse onto one hue), this spreads the WHOLE
    /// spectrum across the whole visible range so fundamentals, partials and overtones
    /// each read as a DISTINCT colour — the founder's "translate the audible+feelable
    /// spectrum into the visible spectrum" for the concentric-donut visual.
    public static func visibleColor(forFrequency hz: Double, fMin: Double = 30, fMax: Double = 16000) -> LinearRGB {
        guard hz > 0, hz.isFinite, fMax > fMin, fMin > 0 else { return neutral }
        let t = clamp01(Foundation.log(hz / fMin) / Foundation.log(fMax / fMin))
        let wavelength = 700.0 - t * (700.0 - 400.0)   // low freq → 700 (red), high → 400 (violet)
        return wavelengthToLinearRGB(wavelength)
    }

    /// Approximate visible wavelength (nm) → linear sRGB, **colorimetrically** via the
    /// CIE 1931 colour-matching functions (Wyman/Sloan/Shirley 2013 analytic multi-lobe
    /// Gaussian fit) → XYZ → linear sRGB (D65), gamut-clamped. This replaces the older
    /// Bruton piecewise ramp so a shown spectral colour is physically faithful (the
    /// natural eye-sensitivity falloff dims the deep-red/violet ends for free). The
    /// SAME fit is mirrored in the Metal shader (MetalBioView.wavelengthToRGB) so every
    /// surface that shows a spectral colour agrees.
    /// Ref: Wyman, Sloan, Shirley, "Simple Analytic Approximations to the CIE XYZ Color
    /// Matching Functions", JCGT 2013.
    public static func wavelengthToLinearRGB(_ wl: Double) -> LinearRGB {
        let (x, y, z) = cie1931(wl)
        // CIE XYZ (D65) → linear sRGB.
        var r =  3.2406 * x - 1.5372 * y - 0.4986 * z
        var g = -0.9689 * x + 1.8758 * y + 0.0415 * z
        var b =  0.0557 * x - 0.2040 * y + 1.0570 * z
        // Clip out-of-gamut negatives, then normalize only if a channel exceeds 1 — this
        // preserves the CMFs' natural relative luminance (green bright, ends dim).
        r = Swift.max(0, r); g = Swift.max(0, g); b = Swift.max(0, b)
        let m = Swift.max(r, Swift.max(g, b))
        if m > 1 { r /= m; g /= m; b /= m }
        return LinearRGB(r: clamp01(r), g: clamp01(g), b: clamp01(b))
    }

    /// Analytic CIE 1931 2° colour-matching functions (Wyman et al. 2013). `wl` in nm.
    /// A piecewise single-/multi-lobe Gaussian fit accurate enough for real-time colour.
    public static func cie1931(_ wl: Double) -> (x: Double, y: Double, z: Double) {
        func g(_ x: Double, _ mu: Double, _ s1: Double, _ s2: Double) -> Double {
            let t = (x - mu) * (x < mu ? 1.0 / s1 : 1.0 / s2)
            return Foundation.exp(-0.5 * t * t)
        }
        let x = 1.056 * g(wl, 599.8, 37.9, 31.0)
              + 0.362 * g(wl, 442.0, 16.0, 26.7)
              - 0.065 * g(wl, 501.1, 20.4, 26.2)
        let y = 0.821 * g(wl, 568.8, 46.9, 40.5)
              + 0.286 * g(wl, 530.9, 16.3, 31.1)
        let z = 1.217 * g(wl, 437.0, 11.8, 36.0)
              + 0.681 * g(wl, 459.0, 26.0, 13.8)
        return (Swift.max(0, x), Swift.max(0, y), Swift.max(0, z))
    }

    /// The genuine physics linking a heard tone to a light colour: transpose the tone up
    /// by whole octaves until it lands in the visible band (~380–780 nm), then
    /// wavelength = c / f. Octave-equivalent (integer octaves) so it agrees with the
    /// immersive Metal `toneColour`. NOTE: per Echoel's own research this 2^n
    /// transposition is an *artistic* convention (audio ≈10 octaves, light ≈1), not a
    /// claim that a note "is" a colour — exposed for the explicit Spectral/physical mode.
    public static func visibleWavelength(forToneHz hz: Double) -> Double {
        guard hz > 0, hz.isFinite else { return 555.0 }
        let cNmPerSec = 2.99792458e17            // speed of light in nm/s
        // Octaves up so f lands near the green centre (~540 THz ≈ 555 nm), then λ=c/f.
        let n = (Foundation.log2(5.4e14 / hz)).rounded()
        let fLight = hz * Foundation.pow(2.0, n)
        let wl = cNmPerSec / fLight
        return Swift.min(780.0, Swift.max(380.0, wl))
    }

    // MARK: Tone → colour on the CLOSED spectral circle (purple-line seam)

    /// The visible band is barely more than ONE octave, so the naive octave
    /// transposition has a SEAM: tones landing at the deep-red (~780 nm) or
    /// deep-violet (~390 nm) edge hit near-zero CIE eye response and render
    /// BLACK — at A4 = 440 that is exactly the pitch class F (founder device
    /// report 2026-07-12: "Da fehlt jetzt gerade das F komplett als Farbe"),
    /// with G/E dim beside it. Colorimetry's own answer is the **CIE purple
    /// line**: the straight boundary of the chromaticity diagram connecting
    /// the red and violet spectral ends. Purples are real perceived colours
    /// (mixtures of red + violet light), just not monochromatic — so closing
    /// the tone circle across the purple line keeps the mapping physically
    /// honest AND makes every pitch class visible, exactly like the colour
    /// wheel closes. Inside the well-visible span (640…420 nm) the colour
    /// stays the pure spectral one; across the seam it blends 640 nm red ↔
    /// 420 nm violet.
    ///
    /// This is the ONE tone→colour used for RENDERING everywhere (grids,
    /// clouds, immersive bed — the Metal shader mirrors it). The raw
    /// `visibleWavelength(forToneHz:)` stays for physical wavelength
    /// READOUTS, where "F ≈ 780 nm edge" is the honest number.
    public static func toneLinearRGB(forToneHz hz: Double) -> LinearRGB {
        guard hz > 0, hz.isFinite else { return neutral }
        // Fold the tone into EXACTLY one light octave anchored at 780 nm:
        // t ∈ [0,1) is the position within the closed circle (λ = 780/2^t).
        let cNmPerSec = 2.99792458e17
        let fRef = cNmPerSec / 780.0
        let p = Foundation.log2(fRef / hz)
        var t = p.rounded(.up) - p            // = fract of the octave fold
        if t >= 1 { t -= 1 }                  // guard the exact-integer case
        let tRed    = Foundation.log2(780.0 / 640.0)   // ≈ 0.285 — last strong red
        let tViolet = Foundation.log2(780.0 / 420.0)   // ≈ 0.893 — last strong violet
        if t >= tRed && t <= tViolet {
            return wavelengthToLinearRGB(780.0 / Foundation.pow(2.0, t))
        }
        // Seam zone (deep red edge ↔ wrap ↔ deep violet edge): CIE purple line.
        let seam = tRed + 1 - tViolet
        let s = t < tRed ? (tRed - t) / seam : (tRed + 1 - t) / seam
        let red = wavelengthToLinearRGB(640)
        let violet = wavelengthToLinearRGB(420)
        var r = red.r + (violet.r - red.r) * s
        var g = red.g + (violet.g - red.g) * s
        var b = red.b + (violet.b - red.b) * s
        // Keep the seam as PRESENT as its spectral neighbours: an RGB mix of
        // two hues dips in its peak channel mid-way (max is convex), so lift
        // it back to the INTERPOLATED anchor peak. At s = 0/1 the factor is
        // exactly 1 → seamlessly continuous with the spectral span on both
        // boundaries; mid-purple gets its honest full presence.
        let m = Swift.max(r, Swift.max(g, b))
        let peakRed = Swift.max(red.r, Swift.max(red.g, red.b))
        let peakViolet = Swift.max(violet.r, Swift.max(violet.g, violet.b))
        let target = peakRed + (peakViolet - peakRed) * s
        if m > 1e-6 { let k = target / m; r *= k; g *= k; b *= k }
        return LinearRGB(r: clamp01(r), g: clamp01(g), b: clamp01(b))
    }

    // MARK: Tone → display-ready grid tint ("Je nach Kammerton … die Farbe des Notenrasters")

    /// Display-ready sRGB components (gamma-encoded 1/2.2, with a small white lift so
    /// deep red/violet still read on the near-black Echoel field) for the PHYSICAL
    /// colour of a heard tone — CIE fit of the octave-transposed frequency, so the
    /// tint shifts with the ACTUAL sounding frequency: Kammerton (A4), tuning cents,
    /// transpose all move it. The ONE helper every note-grid surface uses (touch
    /// fretboard, piano roll rows, note blocks), so all grids recolour identically
    /// when the concert pitch changes (founder 2026-07-12).
    public static func displayComponents(forToneHz hz: Double, lift: Double = 0.22)
        -> (r: Double, g: Double, b: Double) {
        // Closed-circle tone colour (purple-line seam) — F at 440 is a colour,
        // not a black column (founder 2026-07-12).
        let rgb = toneLinearRGB(forToneHz: hz)
        let l = clamp01(lift)
        func enc(_ c: Double) -> Double { l + (1 - l) * Foundation.pow(clamp01(c), 1.0 / 2.2) }
        return (enc(rgb.r), enc(rgb.g), enc(rgb.b))
    }

    // MARK: Pitch → place in the visual field ("an der richtigen Stelle")

    /// Where a sounding note LIVES in the immersive visual's square [-1,1]² field
    /// coordinate (founder 2026-07-08: colours appear only WHERE the corresponding
    /// tone sounds — from ANY source). Pure pitch space, source-agnostic (touch
    /// surface, piano roll, MIDI):
    ///   • x = the note's position WITHIN its octave (fraction of log2 above C) —
    ///     C at the left, rising rightward: the fretboard grid's column order.
    ///   • y = octave HEIGHT — low notes at the bottom like the grid's rows,
    ///     centred on octave 4 and clamped so extreme registers stay on screen.
    /// (+y is up, matching the shader's `pf` coordinate.)
    public static func notePosition(forHz hz: Double) -> (x: Double, y: Double) {
        guard hz > 0, hz.isFinite else { return (0, 0) }
        let p = Foundation.log2(hz / c0Hz)            // octaves above C0
        let oct = p.rounded(.down)
        let f = p - oct                               // [0,1) within the octave
        let x = (f - 0.5) * 1.5                       // ±0.75 across the width
        let y = Swift.min(0.8, Swift.max(-0.8, (oct - 4.0) * 0.55))
        return (x, y)
    }

    // MARK: OKLab → linear sRGB (Ottosson 2020)

    public static func oklabToLinear(_ c: OKLab) -> LinearRGB {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return LinearRGB(r: clamp01(r), g: clamp01(g), b: clamp01(bb))
    }

    private static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return Swift.min(1.0, Swift.max(0.0, x))
    }
}
