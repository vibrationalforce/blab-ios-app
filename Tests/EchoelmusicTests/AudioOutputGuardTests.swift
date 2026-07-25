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

    // MARK: - In-place form (buffer already written, then post-processed)

    /// Run an array through the in-place sweep and return it.
    private func swept(_ source: [Float], count: Int? = nil) -> [Float] {
        var buffer = source
        let n = count ?? source.count
        buffer.withUnsafeMutableBufferPointer { out in
            guard let o = out.baseAddress else { return }
            AudioOutputGuard.sweepNonFinite(o, count: n)
        }
        return buffer
    }

    func testInPlaceSweepSilencesNonFiniteAndLeavesTheRestBitExact() {
        // The in-place form cannot use the `-999` sentinel the copy form relies on
        // (source and destination are the same array), so the FIXTURE has to pin the
        // loop's lower bound instead: index 0 is non-finite, which a `1..<count`
        // off-by-one would leave untouched and this assertion would catch.
        let source: [Float] = [.nan, 0.25, -0.5, .infinity, -0.0, 3.7, -.infinity]
        let expected: [Float] = [0, 0.25, -0.5, 0, -0.0, 3.7, 0]
        XCTAssertEqual(swept(source).map(\.bitPattern), expected.map(\.bitPattern))
    }

    func testInPlaceSweepRespectsCount_andToleratesNonPositive() {
        // `frameCount` is what the render block was asked for; the sweep must not
        // touch the buffer beyond it. The NaN sits at exactly index `count` — the
        // FIRST out-of-range slot — so a `0...count` off-by-one would silence it and
        // fail here. Parking it further out would let that bug through.
        var source = [Float](repeating: 0.4, count: 8)
        source[4] = .nan
        let out = swept(source, count: 4)
        XCTAssertTrue(out[4].isNaN, "the sweep ran one past the requested count")
        XCTAssertEqual(Array(out[0..<4]), [0.4, 0.4, 0.4, 0.4])
        // Non-positive counts must return, not trap on the audio thread.
        XCTAssertEqual(swept([1, 2, 3], count: 0), [1, 2, 3])
        XCTAssertEqual(swept([1, 2, 3], count: -1), [1, 2, 3])
    }

    // MARK: - Scalar form (per-sample writers)

    func testScalarFormMatchesTheBufferFormSampleForSample() {
        // Honest about its own strength: the buffer form currently DELEGATES to the
        // scalar one, so this cannot fail as written — it is a tripwire against a
        // future re-split into two independent implementations, not a check on the
        // present code. Kept because that split is the realistic way the two forms
        // would drift, and a voice's behaviour must not depend on which entry point
        // its render block happens to use.
        let source: [Float] = [0, 1, -1, 0.5, -0.0, 3.7, .nan, .infinity, -.infinity, 1e-30]
        let viaBuffer = guarded(source)
        let viaScalar = source.map { AudioOutputGuard.silencingNonFinite($0) }
        XCTAssertEqual(viaScalar.map(\.bitPattern), viaBuffer.map(\.bitPattern))
    }

    func testScalarFormSilencesOnlyNonFinite() {
        XCTAssertEqual(AudioOutputGuard.silencingNonFinite(.nan), 0)
        XCTAssertEqual(AudioOutputGuard.silencingNonFinite(.infinity), 0)
        XCTAssertEqual(AudioOutputGuard.silencingNonFinite(-.infinity), 0)
        // Loud is not the same as broken — a limiter's job, not this one's.
        XCTAssertEqual(AudioOutputGuard.silencingNonFinite(-12.25), -12.25)
        XCTAssertEqual(AudioOutputGuard.silencingNonFinite(1e-30), 1e-30)
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
