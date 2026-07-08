// LightScienceInfo.swift
// Echoelmusic — the "app as a school" entries for LIGHT. Echoelmusic drives real light
// (Art-Net / sACN) and colour (SpectralColor); this teaches the actual, peer-
// reviewed photobiology behind wavelengths — FACTS + self-observation only.
//
// HARD BRAND LINE (logged in inspiration.csv / vision-gate): Echoelmusic uses this
// science to map and EXPLAIN light honestly. It makes NO medical/therapeutic
// claim, treats no condition, and is NOT light therapy. "Show the number, never
// promise the benefit." Sources are peer-reviewed (PMC/NIH) — see citations.
//
// Pure Foundation (no SwiftUI) so the copy is unit-tested alongside BioMetric.

import Foundation

/// A light-science topic Echoelmusic can explain — grounded in real wavelengths.
public enum LightScienceTopic: String, CaseIterable, Identifiable, Sendable {
    case circadianBlue, greenLight, redNearInfrared, colourEmotion, scope

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .circadianBlue:    return "Blue light & the body clock (~480 nm)"
        case .greenLight:       return "Green light (~525 nm)"
        case .redNearInfrared:  return "Red & near-infrared (~620–850 nm)"
        case .colourEmotion:    return "Colour & emotion"
        case .scope:            return "What Echoelmusic’s light is — and is not"
        }
    }

    /// One-line gist for a list row.
    public var summary: String {
        switch self {
        case .circadianBlue:    return "The wavelength your inner clock reads most."
        case .greenLight:       return "Where daytime vision is most sensitive."
        case .redNearInfrared:  return "Long waves that reach deeper into tissue."
        case .colourEmotion:    return "Shared, learned colour associations."
        case .scope:            return "Science for self-observation, not therapy."
        }
    }

    /// The approximate physical wavelength (nm) for the physically-defined topics —
    /// the honest anchor for representing an ACTUAL light wavelength (distinct from
    /// the pitch→hue convention in SpectralColor). nil for the non-physical topics.
    public var wavelengthNm: Int? {
        switch self {
        case .circadianBlue:    return 480
        case .greenLight:       return 525
        case .redNearInfrared:  return 660
        case .colourEmotion, .scope: return nil
        }
    }

    public var detail: String {
        switch self {
        case .circadianBlue:
            return "Short-wavelength blue light, peaking around 480 nm, is the main signal that sets the human body clock. It is sensed by melanopsin in a special class of retinal cells (ipRGCs) wired straight to the brain’s master clock (the suprachiasmatic nucleus). Morning blue light tends to raise alertness; blue light late at night tends to delay the clock. Echoelmusic can map and explain this wavelength — it does not prescribe it. (Source: peer-reviewed circadian/blue-light reviews, PMC/NIH.)"
        case .greenLight:
            return "Green light around 525 nm sits near the peak of daytime (cone) vision, so it reads as very bright while only weakly driving the melanopsin clock signal compared with blue. That distinct response is why green is studied separately from blue in light science. Echoelmusic represents it accurately as a wavelength; it makes no health claim. (Source: peer-reviewed light-physiology reviews.)"
        case .redNearInfrared:
            return "Long-wavelength red (~620–700 nm) and near-infrared (~700–850 nm) light penetrate tissue more deeply because skin absorbs them weakly; in photobiomodulation research they are absorbed by mitochondrial cytochrome-c-oxidase. Echoelmusic only displays and explains these wavelengths as light — it is not a medical device and makes no health claim. (Source: peer-reviewed photobiomodulation reviews, PMC/NIH.)"
        case .colourEmotion:
            return "Across 130+ studies from 60+ countries, people share systematic colour–emotion associations: red with high arousal and energy, blue and green with calm and low arousal, bright colours with positive feeling. These are learned, perceptual associations after the brain processes the image — not direct effects on cells. Echoelmusic uses them as an honest aesthetic mapping for its visuals and light. (Source: global colour–emotion meta-analysis, 1895–2022.)"
        case .scope:
            return "Echoelmusic maps and explains light by real wavelength so your music and body can drive colour, visuals and DMX/Art-Net fixtures honestly. This is for creative expression and self-observation. It is NOT light therapy, makes no medical or wellness claim, diagnoses nothing, and treats no condition. If you are exploring light for health reasons, talk to a qualified clinician."
        }
    }
}
