//
//  ColorOctave.swift
//  Echoelmusic — Hans Cousto's "Cosmic Octave" colour convention.
//
//  The octave law made visible: a tone transposed up by whole octaves (×2ⁿ) keeps its
//  pitch class. Raised ~40 octaves a musical tone lands in the visible-light band, so
//  every pitch class has a colour. This is the SAME octave transposition the renderer
//  already does (MetalBioView.toneWavelengthNm); ColorOctave adds Cousto's EXPLICIT
//  note→colour convention (Cousto, *The Cosmic Octave*, 1978) as first-class, testable
//  data so the UI and the visual can speak it directly and consistently.
//
//  ⚠️ Framing: the octave-transposition MATH is exact physics; the specific note↔colour
//  assignment is Cousto's CONVENTION (a creative tuning), and a colour shown on a screen
//  is a gamut-limited approximation of a spectral light. We present it as such — never as
//  a perceptual fact, and never with health / chakra / Solfeggio claims. See
//  scratchpads/RESEARCH_SOUND_TO_COLOR.md and PLAN_COLORMUSIC_TONESYSTEMS.md.
//
//  Pure value type (no UIKit/Metal) — Linux-testable.
//

import Foundation

/// Hans Cousto's cosmic-octave colour convention: pitch class → visible colour, plus the
/// octave-transposition maths to take any tone frequency into the visible band.
public enum ColorOctave {

    /// Octaves from the audio band to Cousto's colour band. 2⁴⁰ takes a ~430 Hz tone to
    /// ~475 THz (C ≈ green, 631 nm) — matching Cousto's published "Farbfrequenzen".
    public static let octavesToLight = 40
    /// 2⁴⁰ as a Double (1_099_511_627_776).
    public static let lightFactor = 1_099_511_627_776.0
    /// Speed of light in nm·Hz (c = 299_792_458 m/s → 2.99792458e17 nm/s).
    private static let cNmHz = 2.997_924_58e17

    // MARK: - Octave maths (exact physics)

    /// The visible-light frequency (THz) a tone maps to, transposed `octavesToLight` up.
    /// e.g. 432 Hz → ≈ 475 THz.
    public static func colorFrequencyTHz(forToneHz hz: Double) -> Double {
        guard hz > 0, hz.isFinite else { return 0 }
        return hz * lightFactor / 1e12
    }

    /// The wavelength (nm) a tone maps to in the visible band (λ = c / f). e.g. 432 Hz →
    /// ≈ 631 nm. Not clamped — callers decide how to treat out-of-band values.
    public static func wavelengthNm(forToneHz hz: Double) -> Double {
        let f = hz * lightFactor
        guard f > 0, f.isFinite else { return 0 }
        return cNmHz / f
    }

    // MARK: - Cousto note → colour convention

    /// 12-tone colour wheel, indexed by pitch class (0 = C … 11 = B/H), as sRGB 0…1.
    /// Values transcribed from Cousto's colour octave (the founder's reference chart):
    /// F#→Rot, G→Rotorange, G#→Orange, A→Gelborange, A#→Gelb, H→Gelbgrün, C→Grün,
    /// C#→Blaugrün, D→Blau, D#→Blauviolett, E→Violett, F→Rotviolett.
    public static let wheel: [RGB] = [
        RGB(0.000, 0.784, 0.000),   // 0  C   Grün
        RGB(0.000, 0.784, 0.627),   // 1  C#  Blaugrün
        RGB(0.000, 0.353, 1.000),   // 2  D   Blau
        RGB(0.294, 0.000, 0.784),   // 3  D#  Blauviolett
        RGB(0.580, 0.000, 0.827),   // 4  E   Violett
        RGB(0.784, 0.000, 0.549),   // 5  F   Rotviolett
        RGB(1.000, 0.000, 0.000),   // 6  F#  Rot
        RGB(1.000, 0.271, 0.000),   // 7  G   Rotorange
        RGB(1.000, 0.549, 0.000),   // 8  G#  Orange
        RGB(1.000, 0.749, 0.000),   // 9  A   Gelborange
        RGB(1.000, 1.000, 0.000),   // 10 A#  Gelb
        RGB(0.678, 1.000, 0.184),   // 11 H/B Gelbgrün
    ]

    /// Cousto colour names per pitch class (German, as on the reference chart).
    public static let names: [String] = [
        "Grün", "Blaugrün", "Blau", "Blauviolett", "Violett", "Rotviolett",
        "Rot", "Rotorange", "Orange", "Gelborange", "Gelb", "Gelbgrün",
    ]

    /// Reference C0 (Hz), MIDI 12 — matches SpectralColor so pitch classes agree app-wide.
    private static let c0Hz = 16.351_597_831_287_414

    /// Continuous pitch class [0,12) of a frequency (octave-equivalent, 0 = C). Tuning-
    /// agnostic: any Kammerton / microtonal pitch lands at its true position on the wheel.
    public static func pitchClass(ofFrequency hz: Double) -> Double {
        guard hz > 0, hz.isFinite else { return 0 }
        var pc = (12.0 * log2(hz / c0Hz)).truncatingRemainder(dividingBy: 12.0)
        if pc < 0 { pc += 12.0 }
        return pc
    }

    /// Cousto colour for a discrete pitch class (0…11; wraps).
    public static func color(pitchClass pc: Int) -> RGB {
        let i = ((pc % 12) + 12) % 12
        return wheel[i]
    }

    /// Cousto colour name for a discrete pitch class (0…11; wraps).
    public static func name(pitchClass pc: Int) -> String {
        let i = ((pc % 12) + 12) % 12
        return names[i]
    }

    /// Cousto colour for ANY frequency — interpolates between the two neighbouring
    /// pitch-class colours by the fractional semitone, so glides/microtones read as a
    /// smooth slide along the colour wheel (a prism, not 12 hard steps). Works for any
    /// tuning because it keys off the continuous pitch class.
    public static func color(forFrequencyHz hz: Double) -> RGB {
        guard hz > 0, hz.isFinite else { return wheel[0] }
        let pc = pitchClass(ofFrequency: hz)
        let lo = Int(floor(pc)) % 12
        let hi = (lo + 1) % 12
        let t = pc - floor(pc)
        return RGB.lerp(wheel[lo], wheel[hi], t)
    }

    // MARK: - RGB

    /// Plain sRGB triple in 0…1 (decoupled from SwiftUI/SpectralColor's LinearRGB so this
    /// stays a pure, Linux-testable value type).
    public struct RGB: Equatable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

        /// Component-wise linear interpolation, t clamped to 0…1.
        public static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            let u = Swift.min(1.0, Swift.max(0.0, t))
            return RGB(a.r + (b.r - a.r) * u,
                       a.g + (b.g - a.g) * u,
                       a.b + (b.b - a.b) * u)
        }
    }
}
