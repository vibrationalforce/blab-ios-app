//
//  AudioOutputGuardTests.swift
//  Echoelmusic — the last thing between the DSP graph and the speaker.
//

import XCTest
@testable import Echoelmusic

final class AudioOutputGuardTests: XCTestCase {

    /// Run a source array through the guard into a fresh destination.
    private func guarded(_ source: [Float], count: Int? = nil) -> [Float] {
        var dst = [Float](repeating: -999, count: source.count)
        let n = count ?? source.count
        source.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { out in
                guard let s = src.baseAddress, let o = out.baseAddress else { return }
                AudioOutputGuard.copySilencingNonFinite(from: s, to: o, count: n)
            }
        }
        return dst
    }

    func testFiniteAudioPassesThroughBitExact() {
        // The guard must be inaudible on every normal block — no clamping, no
        // rounding, no gain change. The 3.7 / -12.25 entries are the load-bearing
        // ones: they falsify any implementation that "helpfully" clamps to [-1, 1],
        // which would be a tone change hiding inside a safety net.
        //
        // Compared by BIT PATTERN, not `==`. `-0.0 == 0.0` is true, so `==` would
        // pass an implementation that normalises negative zero away — and the test
        // claims bit-exactness, so it has to actually check it.
        let source: [Float] = [0, 1, -1, 0.5, -0.5, 1e-30, -0.0, 3.7, -12.25]
        XCTAssertEqual(guarded(source).map(\.bitPattern), source.map(\.bitPattern))
    }

    func testNonFiniteSamplesBecomeSilence() {
        let out = guarded([0.5, .nan, -0.5, .infinity, 0.25, -.infinity])
        XCTAssertEqual(out, [0.5, 0, -0.5, 0, 0.25, 0])
    }

    func testOnlyTheBadSamplesAreSilenced_notTheWholeBlock() {
        // A single bad sample must not mute the block. Muting on any NaN would turn a
        // one-sample click into a dropout, which is the more damaging failure.
        var source = [Float](repeating: 0.8, count: 512)
        source[300] = .nan
        let out = guarded(source)
        XCTAssertEqual(out[300], 0)
        XCTAssertEqual(out[299], 0.8)
        XCTAssertEqual(out[301], 0.8)
        XCTAssertEqual(out.filter { $0 == 0.8 }.count, 511)
    }

    func testWritesExactlyCountSamples_andNotOneMore() {
        // The render path passes `count` ≤ the scratch length and zero-fills the rest
        // itself, so the guard must not touch anything past `count`.
        var source = [Float](repeating: 0.3, count: 8)
        source[6] = .nan
        let out = guarded(source, count: 4)
        XCTAssertEqual(Array(out[0..<4]), [0.3, 0.3, 0.3, 0.3])
        XCTAssertEqual(Array(out[4..<8]), [-999, -999, -999, -999],
                       "the guard wrote past the requested count")
    }

    func testNonPositiveCountWritesNothingInsteadOfTrapping() {
        // Zero is the ordinary case (a render block can legitimately be asked for
        // no frames). NEGATIVE is why the `count > 0` guard is not dead code: this
        // runs on the audio thread, where `0..<(-1)` is a trap — i.e. the whole
        // app dies rather than one block being wrong. A caller passing a negative
        // count is already broken; it must not be fatal.
        XCTAssertEqual(guarded([1, 2, 3], count: 0), [-999, -999, -999])
        XCTAssertEqual(guarded([1, 2, 3], count: -1), [-999, -999, -999])
    }
}
