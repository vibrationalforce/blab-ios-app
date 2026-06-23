// SpaceReverbTests.swift
// Echoel — the "room-in-room" convolution space core: synthetic IRs (early-reflection
// inner room + diffuse tail outer room) and the parallel blend. Pure + deterministic.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class SpaceReverbTests: XCTestCase {

    // MARK: - Impulse responses

    func testEarlyReflectionIR_directHitThenFrontLoadedDecay() {
        let ir = SpaceReverb.earlyReflectionIR(taps: 256, seed: 1)
        XCTAssertEqual(ir.count, 256)
        XCTAssertEqual(ir[0], 1, accuracy: 1e-6, "direct sound at tap 0")
        XCTAssertTrue(ir.allSatisfy { $0.isFinite })
        let first = ir[0..<128].reduce(Float(0)) { $0 + $1 * $1 }
        let second = ir[128..<256].reduce(Float(0)) { $0 + $1 * $1 }
        XCTAssertGreaterThan(first, second, "early reflections are front-loaded")
    }

    func testTailIR_finiteAndExponentiallyDecaying() {
        let ir = SpaceReverb.tailIR(taps: 512, seed: 2)
        XCTAssertEqual(ir.count, 512)
        XCTAssertTrue(ir.allSatisfy { $0.isFinite })
        let firstQ = ir[0..<128].reduce(Float(0)) { $0 + $1 * $1 }
        let lastQ = ir[384..<512].reduce(Float(0)) { $0 + $1 * $1 }
        XCTAssertGreaterThan(firstQ, lastQ, "tail energy decays over time")
    }

    func testIRsAreDeterministicBySeed() {
        XCTAssertEqual(SpaceReverb.tailIR(taps: 64, seed: 7), SpaceReverb.tailIR(taps: 64, seed: 7))
        XCTAssertNotEqual(SpaceReverb.tailIR(taps: 64, seed: 7), SpaceReverb.tailIR(taps: 64, seed: 8))
        XCTAssertEqual(SpaceReverb.earlyReflectionIR(taps: 64, seed: 3),
                       SpaceReverb.earlyReflectionIR(taps: 64, seed: 3))
    }

    // MARK: - Processing

    private func smallSpace(mix: Float, blend: Float) -> SpaceReverb {
        SpaceReverb(sampleRate: 1000, maxBlock: 64, erMillis: 10, tailSeconds: 0.05,
                    mix: mix, blend: blend)
    }

    func testMixZeroIsPureDry() {
        let rv = smallSpace(mix: 0, blend: 0.5)
        let dry = (0..<64).map { Float($0 % 5) - 2 }
        let out = rv.process(dry)
        XCTAssertEqual(out.count, 64)
        for i in 0..<64 { XCTAssertEqual(out[i], dry[i], accuracy: 1e-5, "mix 0 = pure dry") }
    }

    func testWetSpreadsEnergyOverTimeAndStaysFinite() {
        let rv = smallSpace(mix: 1, blend: 1)
        var impulse = [Float](repeating: 0, count: 64); impulse[0] = 1
        let out = rv.process(impulse)
        XCTAssertEqual(out.count, 64)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        let later = out[1..<64].reduce(Float(0)) { $0 + abs($1) }
        XCTAssertGreaterThan(later, 0, "a wet space spreads energy beyond the direct sample")
    }

    func testRoomInRoomBlendAddsLateEnergy() {
        func lateEnergy(_ blend: Float) -> Float {
            let rv = smallSpace(mix: 1, blend: blend)
            var imp = [Float](repeating: 0, count: 64); imp[0] = 1
            let out = rv.process(imp)
            return out[20..<64].reduce(Float(0)) { $0 + $1 * $1 }
        }
        XCTAssertGreaterThan(lateEnergy(1.0), lateEnergy(0.0),
                             "more room-in-room blend → more late (outer-room tail) energy")
    }

    func testProcessInPlaceMatchesProcess() {
        // Two fresh, identically-seeded instances must produce bit-identical wet
        // output from `process` (allocating) and `processInPlace` (real-time-safe).
        let a = smallSpace(mix: 0.6, blend: 0.8)
        let b = smallSpace(mix: 0.6, blend: 0.8)
        let dry = (0..<64).map { Float(sin(Double($0) * 0.4)) }
        let ref = a.process(dry)
        var buf = dry
        b.processInPlace(&buf)
        XCTAssertEqual(buf.count, 64)
        for i in 0..<64 {
            XCTAssertEqual(buf[i], ref[i], accuracy: 1e-5, "in-place == process at sample \(i)")
        }
    }

    func testSetSpaceClampsAndUpdates() {
        let rv = smallSpace(mix: 0.5, blend: 0.5)
        rv.setSpace(mix: 2, blend: -1)
        XCTAssertEqual(rv.mix, 1, accuracy: 1e-6, "mix clamps to 1")
        XCTAssertEqual(rv.blend, 0, accuracy: 1e-6, "blend clamps to 0")
    }
}
#endif
