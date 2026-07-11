#if canImport(Accelerate)
// AnalogWarmthTests.swift
// Echoel — the anti-"plastic" lever (founder 2026-07-11: "Vermeide kaltes
// überladenes Plastik synthie gedudel"). Guards the pure analog-warmth soft-
// saturation contract: bit-identical at 0, unity slope at zero, odd, monotonic,
// bounded — so it is safe ahead of the resonant filter — plus the SynthPatch
// warmth default + Codable back-compat (old patches stay clean).

import XCTest
@testable import Echoelmusic

final class AnalogWarmthTests: XCTestCase {

    // MARK: - The pure shaper

    func testDriveZeroIsBitIdentical() {
        for x in stride(from: -2.0 as Float, through: 2.0, by: 0.13) {
            XCTAssertEqual(EchoelDDSP.analogWarmth(x, drive: 0), x,
                           "drive 0 must return the input unchanged (the raw synth path)")
            XCTAssertEqual(EchoelDDSP.analogWarmth(x, drive: -0.5), x,
                           "negative drive is treated as off")
        }
    }

    func testUnitySlopeAtZero_quietPassagesUntouched() {
        // A whisper-level sample should pass through with a negligible change.
        let x: Float = 1e-4
        let out = EchoelDDSP.analogWarmth(x, drive: 0.3)
        XCTAssertEqual(out, x, accuracy: 1e-6,
                       "near-zero samples must not be coloured — warmth acts on peaks")
    }

    func testCompressesPeaks() {
        // A loud peak should be pulled DOWN (harmonics gained, level tamed).
        let x: Float = 1.5
        let out = EchoelDDSP.analogWarmth(x, drive: 0.5)
        XCTAssertLessThan(out, x, "a hot peak must be softened, not amplified")
        XCTAssertGreaterThan(out, 0, "still same sign — the shaper is monotonic")
    }

    func testOddSymmetry() {
        for x in stride(from: 0.05 as Float, through: 2.0, by: 0.17) {
            let pos = EchoelDDSP.analogWarmth(x, drive: 0.4)
            let neg = EchoelDDSP.analogWarmth(-x, drive: 0.4)
            XCTAssertEqual(neg, -pos, accuracy: 1e-6, "warmth must be odd (odd harmonics only)")
        }
    }

    func testMonotonicAndBounded() {
        var prev = EchoelDDSP.analogWarmth(-8, drive: 0.6)
        for x in stride(from: -8.0 as Float, through: 8.0, by: 0.05) {
            let out = EchoelDDSP.analogWarmth(x, drive: 0.6)
            XCTAssertTrue(out.isFinite, "output must stay finite for any input")
            XCTAssertGreaterThanOrEqual(out + 1e-6, prev, "shaper must be monotonic (no fold-back)")
            prev = out
        }
        // The wet path is bounded by 1/a ≈ 0.625; the dry blend keeps growth gentle.
        XCTAssertLessThan(EchoelDDSP.analogWarmth(1000, drive: 1.0), 1.0,
                          "full-wet saturation is bounded well under a huge input")
    }

    // MARK: - SynthPatch integration (pure struct — Linux-safe)

    func testPatchHasWarmDefault() {
        let p = SynthPatch(name: "Init")
        XCTAssertGreaterThan(p.warmth, 0, "the out-of-box sound carries mild warmth, not cold sines")
    }

    func testBrightLeadCarriesExtraWarmth() {
        guard let bright = SynthPatch.factory.first(where: { $0.name == "Bright Lead" }),
              let pad = SynthPatch.factory.first(where: { $0.name == "Warm Pad" }) else {
            return XCTFail("expected factory leads present")
        }
        XCTAssertGreaterThan(bright.warmth, pad.warmth,
                             "the shrill bright lead is warmed more than the already-warm pad")
    }

    func testOldPatchDecodesClean() throws {
        // A patch JSON saved before warmthDrive existed must decode to clean (nil → 0),
        // so we never retro-colour a user's saved sound.
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000C1","name":"Legacy",
         "attack":0.5,"decay":0.5,"sustain":0.8,"release":2.0,"envelopeCurve":"exponential",
         "harmonicity":0.88,"harmonicLevel":0.8,"brightness":0.25,"noiseLevel":0.01,
         "noiseColor":"pink","spectralShape":"dark","filterCutoff":220,"filterResonance":0.1,
         "lfoToFilterDepth":0.15,"filterLFORate":0.2,"filterLFODepth":0.3,
         "reverbMix":0.25,"reverbDecay":2.0,"vibratoRate":0,"vibratoDepth":0,
         "timbreProfile":"","timbreBlend":0}
        """
        let patch = try JSONDecoder().decode(SynthPatch.self, from: Data(json.utf8))
        XCTAssertNil(patch.warmthDrive, "absent field decodes to nil")
        XCTAssertEqual(patch.warmth, 0, "a legacy patch stays exactly as it was designed")
    }
}
#endif
