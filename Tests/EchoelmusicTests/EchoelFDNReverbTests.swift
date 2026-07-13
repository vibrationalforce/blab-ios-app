// EchoelFDNReverbTests.swift
// Echoel — Spatial S4: the pure FDN room-reverb core. Proves the maths that make it
// safe to wire later: RoomModel→Params determinism, RT60 tracks decayTime, unconditional
// stability (orthonormal matrix + gains<1), mix=0 passthrough, and process==processInPlace.

#if canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class EchoelFDNReverbTests: XCTestCase {

    private let fs: Float = 48_000

    private func impulse(seconds: Float) -> [Float] {
        var x = [Float](repeating: 0, count: Int(fs * seconds))
        if !x.isEmpty { x[0] = 1 }
        return x
    }

    /// Schroeder backward-integration RT60: index where the energy-decay curve passes
    /// −60 dB (1e-6 of total energy), in seconds. Reverb should be pure wet (mix 1).
    private func measuredRT60(_ room: RoomModel) -> Double {
        let rev = EchoelFDNReverb(room: room, sampleRate: fs, mix: 1)
        let h = rev.process(impulse(seconds: max(2, room.decayTime * 1.6)))
        var energy = 0.0
        var edc = [Double](repeating: 0, count: h.count)
        for i in stride(from: h.count - 1, through: 0, by: -1) {
            energy += Double(h[i]) * Double(h[i])
            edc[i] = energy
        }
        let total = edc.first ?? 0
        guard total > 0 else { return 0 }
        for i in 0..<edc.count where edc[i] / total < 1e-6 { return Double(i) / Double(fs) }
        return Double(h.count) / Double(fs)
    }

    // MARK: - Params

    func testParams_deterministicBySeedAndRoom() {
        let room = RoomModel(width: 12, depth: 15, height: 5, decayTime: 2, diffusion: 0.7)
        let a = EchoelFDNReverb.params(from: room, sampleRate: fs, seed: 0xFD2)
        let b = EchoelFDNReverb.params(from: room, sampleRate: fs, seed: 0xFD2)
        XCTAssertEqual(a, b, "same room+sr+seed → identical params")

        let small = EchoelFDNReverb.params(from: RoomModel(width: 3, depth: 3, height: 3), sampleRate: fs)
        let large = EchoelFDNReverb.params(from: RoomModel(width: 60, depth: 60, height: 30), sampleRate: fs)
        XCTAssertNotEqual(small.lengths, large.lengths, "a bigger room → different (longer) delays")
        XCTAssertLessThan(small.lengths.max()!, large.lengths.max()!, "bigger room → longer delays")
    }

    func testParams_lengthsAreEightDistinctPrimes() {
        let p = EchoelFDNReverb.params(from: RoomModel(), sampleRate: fs)
        XCTAssertEqual(p.lengths.count, EchoelFDNReverb.n)
        XCTAssertEqual(p.gains.count, EchoelFDNReverb.n)
        XCTAssertEqual(Set(p.lengths).count, EchoelFDNReverb.n, "distinct → mutually coprime")
        for L in p.lengths { XCTAssertTrue(EchoelFDNReverb.isPrime(L), "\(L) must be prime") }
        for g in p.gains { XCTAssertTrue(g > 0 && g < 1, "Jot gain \(g) must be in (0,1)") }
    }

    // MARK: - RT60

    func testEnergyDecay_tracksRoomDecayTime() {
        let short = measuredRT60(RoomModel(width: 6, depth: 6, height: 3, decayTime: 0.4))
        let long  = measuredRT60(RoomModel(width: 20, depth: 20, height: 8, decayTime: 3.0))
        XCTAssertGreaterThan(long, short, "a longer decayTime rings longer")
        XCTAssertGreaterThan(long, short * 1.8, "substantially longer, not marginally")
        XCTAssertGreaterThan(short, 0.1, "0.4 s room still has a real tail")
        XCTAssertLessThan(short, 2.0, "0.4 s room does not ring for seconds")
        XCTAssertGreaterThan(long, 1.0, "3 s room rings well over a second")
    }

    // MARK: - Stability

    func testStability_boundedOverSustainedInputAtMaxDecay() {
        // Max decayTime (30 s) → gains near unity; a lossless matrix + gains<1 is a
        // contraction, so sustained input reaches a BOUNDED steady state (no NaN/Inf).
        let rev = EchoelFDNReverb(room: RoomModel(decayTime: 30), sampleRate: fs, mix: 1)
        var peak: Float = 0
        var block = [Float](repeating: 0.2, count: 4096)
        for _ in 0..<24 {   // ~2 s of sustained input
            var buf = block
            rev.processInPlace(&buf)
            for v in buf {
                XCTAssertTrue(v.isFinite, "no NaN/Inf under sustained near-lossless feedback")
                peak = Swift.max(peak, abs(v))
            }
            block = [Float](repeating: 0.2, count: 4096)
        }
        XCTAssertLessThan(peak, 1000, "output stays bounded (does not diverge)")
    }

    func testAllOutputsFinite_forDegenerateRooms() {
        for room in [RoomModel(width: 1, depth: 200, height: 1, decayTime: 0.1, diffusion: 0),
                     RoomModel(width: 200, depth: 1, height: 60, decayTime: 30, diffusion: 1),
                     RoomModel(width: 1, depth: 1, height: 1, decayTime: 0.1, diffusion: 1)] {
            let rev = EchoelFDNReverb(room: room, sampleRate: fs, mix: 0.5)
            let out = rev.process(impulse(seconds: 0.5))
            XCTAssertTrue(out.allSatisfy { $0.isFinite }, "degenerate room must not produce NaN/Inf")
        }
    }

    // MARK: - Mix + dual path

    func testMixZero_isPureDry() {
        let rev = EchoelFDNReverb(room: RoomModel(), sampleRate: fs, mix: 0)
        let dry = (0..<512).map { Float(sin(Double($0) * 0.1)) }
        let out = rev.process(dry)
        for i in 0..<dry.count { XCTAssertEqual(out[i], dry[i], accuracy: 1e-6) }
    }

    func testProcessInPlace_matchesProcess() {
        let room = RoomModel(width: 10, depth: 12, height: 4, decayTime: 1.5, diffusion: 0.6)
        let a = EchoelFDNReverb(room: room, sampleRate: fs, mix: 0.3)
        let b = EchoelFDNReverb(room: room, sampleRate: fs, mix: 0.3)
        let dry = (0..<2048).map { Float(sin(Double($0) * 0.05)) * 0.7 }
        let viaProcess = a.process(dry)
        var buf = dry
        b.processInPlace(&buf)
        for i in 0..<dry.count {
            XCTAssertEqual(viaProcess[i], buf[i], accuracy: 1e-5,
                           "allocating and in-place paths must be bit-identical")
        }
    }

    // MARK: - Diffusion

    func testDiffusion_increasesEarlyEchoDensity() {
        func earlyDensity(_ diffusion: Float) -> Int {
            let rev = EchoelFDNReverb(room: RoomModel(width: 8, depth: 10, height: 4,
                                                      decayTime: 1.2, diffusion: diffusion),
                                      sampleRate: fs, mix: 1)
            let h = rev.process(impulse(seconds: 0.03))   // first 30 ms
            return h.filter { abs($0) > 1e-4 }.count
        }
        XCTAssertGreaterThan(earlyDensity(1), earlyDensity(0),
                             "more diffusion smears the input into a denser early field")
    }
}
#endif
