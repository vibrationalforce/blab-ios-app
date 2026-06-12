// GenrePatchesTests.swift
// Echoel — guards the genre sound-design patches. The critical invariant: the
// enum-valued params (noiseColor / spectralShape / envelopeCurve) must use the
// EchoelDDSP rawValues (Capitalized), or SynthPatch.apply silently ignores them
// and the patch never changes the timbre. Also asserts every param is in a sane
// range and the three styles really differ.

import XCTest
@testable import Echoelmusic

final class GenrePatchesTests: XCTestCase {

    private let known: [MusicStyle: String] = [
        .dubTechno: "Dub Chord",
        .trap: "Trap Bell",
        .selfObservation: "Calm Pad"
    ]

    func testEveryStyleNamesItsPatch() {
        for style in MusicStyle.allCases {
            XCTAssertEqual(style.synthPatch.name, known[style])
        }
    }

    func testEnumRawValuesAreValid() {
        // The landmine: a lowercase rawValue (e.g. "dark") fails the enum lookup
        // and the param is left unchanged. These must round-trip through the
        // actual EchoelDDSP enums.
        for style in MusicStyle.allCases {
            let p = style.synthPatch
            XCTAssertNotNil(EchoelDDSP.NoiseColor(rawValue: p.noiseColor),
                            "\(style): noiseColor '\(p.noiseColor)' is not a valid EchoelDDSP rawValue")
            XCTAssertNotNil(EchoelDDSP.SpectralShape(rawValue: p.spectralShape),
                            "\(style): spectralShape '\(p.spectralShape)' is not a valid EchoelDDSP rawValue")
            XCTAssertNotNil(EchoelDDSP.EnvelopeCurve(rawValue: p.envelopeCurve),
                            "\(style): envelopeCurve '\(p.envelopeCurve)' is not a valid EchoelDDSP rawValue")
        }
    }

    func testParamsAreInSaneRanges() {
        for style in MusicStyle.allCases {
            let p = style.synthPatch
            for (label, v) in [("attack", p.attack), ("decay", p.decay),
                               ("sustain", p.sustain), ("release", p.release),
                               ("harmonicity", p.harmonicity), ("harmonicLevel", p.harmonicLevel),
                               ("brightness", p.brightness), ("noiseLevel", p.noiseLevel),
                               ("reverbMix", p.reverbMix), ("vibratoDepth", p.vibratoDepth)] {
                XCTAssertGreaterThanOrEqual(v, 0, "\(style).\(label) must be >= 0")
            }
            XCTAssertLessThanOrEqual(p.sustain, 1)
            XCTAssertLessThanOrEqual(p.brightness, 1)
            XCTAssertLessThanOrEqual(p.reverbMix, 1)
            XCTAssertGreaterThan(p.filterCutoff, 0, "\(style) cutoff must be positive")
            XCTAssertGreaterThan(p.reverbDecay, 0)
        }
    }

    func testGenresSoundDistinct() {
        let dub = MusicStyle.dubTechno.synthPatch
        let trap = MusicStyle.trap.synthPatch
        let pad = MusicStyle.selfObservation.synthPatch
        // Dub is dark, trap is bright.
        XCTAssertLessThan(dub.brightness, trap.brightness, "dub is darker than trap")
        XCTAssertEqual(dub.spectralShape, "Dark")
        XCTAssertEqual(trap.spectralShape, "Bell")
        // The pad attacks slowly (a swell), the others are immediate.
        XCTAssertGreaterThan(pad.attack, dub.attack)
        XCTAssertGreaterThan(pad.attack, trap.attack)
        // All three are distinct patches.
        XCTAssertNotEqual(dub.id, trap.id)
        XCTAssertNotEqual(dub.id, pad.id)
        XCTAssertNotEqual(trap.id, pad.id)
    }
}
