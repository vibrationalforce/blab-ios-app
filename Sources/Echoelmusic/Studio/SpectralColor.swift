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

    /// Approximate visible wavelength (nm) → RGB (Bruton-style piecewise ramp with
    /// end-of-range intensity falloff). Used as a perceptual *visualization* mapping,
    /// not a colorimetric claim.
    public static func wavelengthToLinearRGB(_ wl: Double) -> LinearRGB {
        var r = 0.0, g = 0.0, b = 0.0
        switch wl {
        case ..<440:      r = -(wl - 440) / (440 - 380); g = 0;                      b = 1
        case 440..<490:   r = 0;                         g = (wl - 440) / (490 - 440); b = 1
        case 490..<510:   r = 0;                         g = 1;                      b = -(wl - 510) / (510 - 490)
        case 510..<580:   r = (wl - 510) / (580 - 510);  g = 1;                      b = 0
        case 580..<645:   r = 1;                         g = -(wl - 645) / (645 - 580); b = 0
        default:          r = 1;                         g = 0;                      b = 0
        }
        // Dim the deep-violet and deep-red extremes (eye sensitivity falloff).
        let factor: Double
        switch wl {
        case ..<420:      factor = 0.3 + 0.7 * (wl - 380) / (420 - 380)
        case 420...700:   factor = 1.0
        default:          factor = max(0.3, 0.3 + 0.7 * (780 - wl) / (780 - 700))
        }
        return LinearRGB(r: clamp01(r * factor), g: clamp01(g * factor), b: clamp01(b * factor))
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
