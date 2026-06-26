//
//  PlanetTone.swift
//  Echoelmusic — Hans Cousto's planetary tones ("Planetentöne") as a creative tuning.
//
//  Cousto's method: take a planet's astronomical period (orbit/day/precession), invert it
//  to a frequency, and octave-transpose (×2ⁿ) into the audible band. The result is a pitch
//  you can tune the instrument to. This is the deterministic MATH (a frequency from an
//  orbital period); ANY claimed effect of a "planet tone" is metaphysical, not physics —
//  so we present it as ASTRONOMY + creative tuning, never as healing/energy/chakra. The
//  published Hz values are Cousto/Planetware's canonical set.
//
//  Selecting a planet sets the Kammerton (a4Hz) so the planet's tone is in tune at its
//  nearest note — e.g. the Earth-year tone (136.10 Hz, C#) tunes A4 ≈ 432 Hz. Pure value
//  type (no audio/UI) — Linux-testable.
//

import Foundation

/// One Cousto planetary tone: the audible frequency + the concert-A that tunes to it.
public struct PlanetTone: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Cousto's published audible planetary tone (Hz).
    public let toneHz: Double

    public init(id: String, name: String, toneHz: Double) {
        self.id = id; self.name = name; self.toneHz = toneHz
    }

    /// MIDI note nearest to the tone (12-TET, A4 = 440).
    public var nearestMidi: Int {
        Int((69.0 + 12.0 * log2(toneHz / 440.0)).rounded())
    }

    /// Note name nearest to the tone (e.g. "C#").
    public var nearestNoteName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
        return names[((nearestMidi % 12) + 12) % 12]
    }

    /// The concert pitch (a4Hz) that tunes the instrument so this planet's tone lands
    /// exactly on its nearest 12-TET note. Always close to 440 (a ≤50¢ correction), so it
    /// sits inside the Kammerton field's range.
    public var a4Hz: Double {
        toneHz / pow(2.0, Double(nearestMidi - 69) / 12.0)
    }
}

/// Cousto's canonical planetary tones (audible Hz). Sun…Pluto + Earth day/year/Platonic.
public enum PlanetTones {
    public static let all: [PlanetTone] = [
        PlanetTone(id: "sun",        name: "Sun",                 toneHz: 126.22),
        PlanetTone(id: "moon",       name: "Moon (synodic)",      toneHz: 210.42),
        PlanetTone(id: "mercury",    name: "Mercury",             toneHz: 141.27),
        PlanetTone(id: "venus",      name: "Venus",               toneHz: 221.23),
        PlanetTone(id: "earth-year", name: "Earth — year (OM)",   toneHz: 136.10),
        PlanetTone(id: "earth-day",  name: "Earth — day",         toneHz: 194.18),
        PlanetTone(id: "earth-plato",name: "Earth — Platonic year", toneHz: 172.06),
        PlanetTone(id: "mars",       name: "Mars",                toneHz: 144.72),
        PlanetTone(id: "jupiter",    name: "Jupiter",             toneHz: 183.58),
        PlanetTone(id: "saturn",     name: "Saturn",              toneHz: 147.85),
        PlanetTone(id: "uranus",     name: "Uranus",              toneHz: 207.36),
        PlanetTone(id: "neptune",    name: "Neptune",             toneHz: 211.44),
        PlanetTone(id: "pluto",      name: "Pluto",               toneHz: 140.25),
    ]

    public static func named(_ id: String) -> PlanetTone? {
        all.first { $0.id == id }
    }
}
