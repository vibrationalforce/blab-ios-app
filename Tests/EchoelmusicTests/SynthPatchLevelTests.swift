// SynthPatchLevelTests.swift
// Echoel — per-instrument output level (SynthPatch.outputLevel + loudness
// normalisation). Guards the founder ask 2026-07-11: "Play surface sounds …
// teils zu laut oder zu leise … Level pro Instrument" — the factory sounds must
// be loudness-MATCHED, no instrument much louder/quieter than the next. Pure
// value-type maths → no Accelerate/AVAudio needed.

import XCTest
@testable import Echoelmusic

final class SynthPatchLevelTests: XCTestCase {

    // MARK: - The heuristic

    func testLoudnessEstimate_brighterReadsLouder() {
        let dark = SynthPatch.loudnessEstimate(harmonicLevel: 0.8, brightness: 0.1,
                                               sustain: 0.7, noiseLevel: 0, unisonVoices: nil)
        let bright = SynthPatch.loudnessEstimate(harmonicLevel: 0.8, brightness: 0.9,
                                                 sustain: 0.7, noiseLevel: 0, unisonVoices: nil)
        XCTAssertGreaterThan(bright, dark, "a brighter sound reads louder")
    }

    func testLoudnessEstimate_unisonAndSustainAddLoudness() {
        let base = SynthPatch.loudnessEstimate(harmonicLevel: 0.8, brightness: 0.5,
                                               sustain: 0.4, noiseLevel: 0, unisonVoices: nil)
        let stacked = SynthPatch.loudnessEstimate(harmonicLevel: 0.8, brightness: 0.5,
                                                  sustain: 0.4, noiseLevel: 0, unisonVoices: 4)
        let sustained = SynthPatch.loudnessEstimate(harmonicLevel: 0.8, brightness: 0.5,
                                                    sustain: 0.95, noiseLevel: 0, unisonVoices: nil)
        XCTAssertGreaterThan(stacked, base, "unison voices add loudness")
        XCTAssertGreaterThan(sustained, base, "more sustain reads louder")
    }

    // MARK: - Factory calibration

    func testFactoryPatchesCarryACalibratedLevel() {
        for p in SynthPatch.factory {
            let level = try XCTUnwrap(p.outputLevel, "\(p.name): factory patch must be calibrated")
            XCTAssertGreaterThanOrEqual(level, 0.45, "\(p.name): level not below the trim floor")
            XCTAssertLessThanOrEqual(level, 1.4, "\(p.name): level not above the trim ceiling")
        }
    }

    func testNormalisationShrinksTheLoudnessSpread() {
        // The whole point of "angleichen": after trimming, the factory sounds are much
        // closer in loudness than the raw designs were.
        func est(_ p: SynthPatch) -> Float {
            SynthPatch.loudnessEstimate(harmonicLevel: p.harmonicLevel, brightness: p.brightness,
                                        sustain: p.sustain, noiseLevel: p.noiseLevel,
                                        unisonVoices: p.unisonVoices)
        }
        let raw = SynthPatch.factory.map { est($0) }               // pre-trim
        let trimmed = SynthPatch.factory.map { est($0) * $0.level } // post-trim effective loudness
        let rawSpread = (raw.max() ?? 0) - (raw.min() ?? 0)
        let trimmedSpread = (trimmed.max() ?? 0) - (trimmed.min() ?? 0)
        XCTAssertLessThan(trimmedSpread, rawSpread * 0.5,
                          "normalisation at least halves the loudness spread across the roster")
    }

    func testWarmPadDefaultStaysNearUnity() {
        // The reference is tuned to the warm default, so the flagship pad isn't yanked.
        guard let warm = SynthPatch.factory.first(where: { $0.name == "Warm Pad" }) else {
            return XCTFail("Warm Pad missing")
        }
        XCTAssertEqual(warm.level, 1.0, accuracy: 0.25, "the default pad stays close to unity")
    }

    // MARK: - Codable / migration

    func testOutputLevelRoundTripsThroughCodable() throws {
        var p = SynthPatch(name: "Trimmed")
        p.outputLevel = 0.7
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(SynthPatch.self, from: data)
        XCTAssertEqual(back.outputLevel, 0.7)
        XCTAssertEqual(back.level, 0.7, accuracy: 1e-6)
    }

    func testPatchSavedBeforeLevelDecodesToUnity() throws {
        // A patch JSON that predates outputLevel (key absent) must decode as unity —
        // it was designed at full level. Encode a patch, strip the key, decode.
        let p = SynthPatch(name: "Legacy")   // outputLevel nil
        let data = try JSONEncoder().encode(p)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "outputLevel")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(SynthPatch.self, from: stripped)
        XCTAssertNil(back.outputLevel, "absent key decodes to nil")
        XCTAssertEqual(back.level, 1.0, "nil level means unity — legacy patches unchanged")
    }
}
