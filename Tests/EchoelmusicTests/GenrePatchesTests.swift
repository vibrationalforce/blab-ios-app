// GenrePatchesTests.swift
// Echoel — guards the genre sound-design patches. The critical invariant: the
// enum-valued params (noiseColor / spectralShape / envelopeCurve) must use the
// EchoelDDSP rawValues (Capitalized), or SynthPatch.apply silently ignores them
// and the patch never changes the timbre. Also asserts every param is in a sane
// range and the three styles really differ.

import XCTest
@testable import Echoelmusic

final class GenrePatchesTests: XCTestCase {

    func testEveryStyleNamesItsPatch() {
        for style in MusicStyle.allCases {
            XCTAssertFalse(style.synthPatch.name.isEmpty, "\(style) patch needs a name")
        }
    }

    func testPatchNamesAndIDsAreUnique() {
        let names = MusicStyle.allCases.map { $0.synthPatch.name }
        XCTAssertEqual(Set(names).count, names.count, "every genre patch needs a distinct name")
        let ids = MusicStyle.allCases.map { $0.synthPatch.id }
        XCTAssertEqual(Set(ids).count, ids.count, "every genre patch needs a distinct stable id")
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

    func testTimbreProfilesAreValidWhenSet() {
        // SOUND CYCLE 1 landmine (same shape as the enum-rawValue one): a
        // timbreProfile that isn't an exact InstrumentTimbre rawValue, OR a profile
        // set with timbreBlend == 0, is silently ignored in SynthPatch.apply — the
        // genre falls back to the pure sine stack. Guard both.
        for style in MusicStyle.allCases {
            let p = style.synthPatch
            guard !p.timbreProfile.isEmpty else { continue }
            XCTAssertNotNil(EchoelDDSP.InstrumentTimbre(rawValue: p.timbreProfile),
                            "\(style): timbreProfile '\(p.timbreProfile)' is not a valid EchoelDDSP.InstrumentTimbre rawValue")
            XCTAssertGreaterThan(p.timbreBlend, 0,
                            "\(style): timbreProfile set but timbreBlend == 0 → silently ignored")
            XCTAssertLessThanOrEqual(p.timbreBlend, 1, "\(style): timbreBlend must be <= 1")
        }
    }

    func testNoGenreEmulatesARealInstrument() {
        // Founder 2026-07-07: "Real Instruments raus, das klingt trashig … wir wollen
        // tendenziell den warmen Synth-Sound, vermeide plastisch und verzerrt klingende
        // Real-Instrument-Emulationen." The real-instrument spectral BLEND (SOUND
        // CYCLE 1) is gone from every genre — the sound is pure warm synth, and genre
        // character comes from the synth's own envelope/brightness. Locks it in so a
        // future cycle can't quietly re-introduce a plastic instrument emulation.
        for style in MusicStyle.allCases {
            XCTAssertTrue(style.synthPatch.timbreProfile.isEmpty,
                          "\(style) must be pure warm synth — no real-instrument spectrum (got '\(style.synthPatch.timbreProfile)')")
            XCTAssertEqual(style.synthPatch.timbreBlend, 0,
                           "\(style) must not blend any real-instrument spectrum")
        }
    }

    func testUnisonIsInSaneRangeWhenSet() {
        for style in MusicStyle.allCases {
            let p = style.synthPatch
            if let v = p.unisonVoices {
                XCTAssertGreaterThanOrEqual(v, 1, "\(style) unisonVoices must be >= 1")
                XCTAssertLessThanOrEqual(v, 4, "\(style) unisonVoices unexpectedly large")
                // Unison without detune is pointless (voices stack in phase) — guard it.
                XCTAssertNotNil(p.unisonDetuneCents, "\(style) sets unisonVoices but no detune")
                if let d = p.unisonDetuneCents {
                    XCTAssertGreaterThan(d, 0, "\(style) unison detune must be > 0 to widen")
                    XCTAssertLessThanOrEqual(d, 50, "\(style) unison detune too wide")
                }
            }
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
        XCTAssertEqual(trap.spectralShape, "Natural")   // (was wrongly asserted "Bell")
        // The pad attacks slowly (a swell), the others are immediate.
        XCTAssertGreaterThan(pad.attack, dub.attack)
        XCTAssertGreaterThan(pad.attack, trap.attack)
        // All three are distinct patches.
        XCTAssertNotEqual(dub.id, trap.id)
        XCTAssertNotEqual(dub.id, pad.id)
        XCTAssertNotEqual(trap.id, pad.id)
    }

    /// Ultrascan 2026-07-22 step 1: the six "warm cluster" genres (the ones that
    /// previously shared cutoff 2600–3100 / brightness 0.34–0.46 and read as the same
    /// warm pad — the founder's "everything sounds like classic") must stay AUDIBLY
    /// spread. Guards against a future warm-only pass re-homogenising them (exactly the
    /// "9 genres on Soft Keys" collapse that hit the lead voice once).
    func testWarmClusterGenresAreMeasurablyDistinct() {
        let cluster: [MusicStyle] = [.classical, .jazz, .disco, .oriental, .rocksteady, .klezmer]
        let patches = cluster.map { $0.synthPatch }
        // No two share the same (cutoff, brightness) fingerprint.
        for i in 0..<patches.count {
            for j in (i + 1)..<patches.count {
                let a = patches[i], b = patches[j]
                let sameCutoff = abs(a.filterCutoff - b.filterCutoff) < 150
                let sameBright = abs(a.brightness - b.brightness) < 0.03
                XCTAssertFalse(sameCutoff && sameBright,
                    "\(cluster[i]) and \(cluster[j]) collapse to the same warm timbre (cutoff+brightness too close)")
            }
        }
        // The cluster spans a real cutoff range (dark organ ↔ lush disco), not one huddle.
        let cutoffs = patches.map { $0.filterCutoff }
        let span = (cutoffs.max() ?? 0) - (cutoffs.min() ?? 0)
        XCTAssertGreaterThan(span, 700,
            "warm-cluster cutoffs must span a real range so the genres read as different instruments")
        // Still WARM — none crossed into shrill territory (founder 2026-07-07 constraint).
        for (style, p) in zip(cluster, patches) {
            XCTAssertLessThan(p.brightness, 0.5, "\(style) must stay warm (brightness < 0.5)")
            XCTAssertNotEqual(p.spectralShape, "Metallic", "\(style) must not sound digital")
        }
    }
}
