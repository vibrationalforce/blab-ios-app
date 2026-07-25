//
//  AudioOutputGuardPCMBufferTests.swift
//  Echoelmusic — the buffer-shaped half of the non-finite guard.
//
//  The render blocks write into an AudioBufferList; the player nodes replay an
//  AVAudioPCMBuffer we filled. Same rule, different container.
//

#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import Echoelmusic

final class AudioOutputGuardPCMBufferTests: XCTestCase {

    /// A deinterleaved float buffer with `channels` channels of `frames` frames.
    private func makeBuffer(channels: AVAudioChannelCount, frames: AVAudioFrameCount,
                            capacity: AVAudioFrameCount? = nil) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels))
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity ?? frames))
        buffer.frameLength = frames
        return buffer
    }

    private func write(_ samples: [Float], to buffer: AVAudioPCMBuffer, channel: Int) throws {
        let data = try XCTUnwrap(buffer.floatChannelData)
        for (i, s) in samples.enumerated() { data[channel][i] = s }
    }

    private func read(_ buffer: AVAudioPCMBuffer, channel: Int, count: Int) throws -> [Float] {
        let data = try XCTUnwrap(buffer.floatChannelData)
        return (0..<count).map { data[channel][$0] }
    }

    func testFiniteAudioIsUntouched_bitExact() throws {
        // The sweep runs over every clip the user imports. If it altered finite audio
        // at all it would be a tone change applied to their material — worse than the
        // fault it guards against.
        let source: [Float] = [0, 1, -1, 0.5, -0.5, 1e-30, -0.0, 3.7, -12.25, 0.125]
        let buffer = try makeBuffer(channels: 1, frames: AVAudioFrameCount(source.count))
        try write(source, to: buffer, channel: 0)

        AudioOutputGuard.sweepNonFinite(buffer)

        let out = try read(buffer, channel: 0, count: source.count)
        XCTAssertEqual(out.map(\.bitPattern), source.map(\.bitPattern),
                       "compared by bit pattern so -0.0 is actually checked")
    }

    func testNonFiniteSamplesBecomeSilence() throws {
        let source: [Float] = [0.5, .nan, -0.5, .infinity, 0.25, -.infinity]
        let buffer = try makeBuffer(channels: 1, frames: AVAudioFrameCount(source.count))
        try write(source, to: buffer, channel: 0)

        AudioOutputGuard.sweepNonFinite(buffer)

        XCTAssertEqual(try read(buffer, channel: 0, count: source.count),
                       [0.5, 0, -0.5, 0, 0.25, 0])
    }

    func testEveryChannelIsSwept_notJustTheFirst() throws {
        // A stereo import with a fault in the RIGHT channel only. Sweeping channel 0
        // and calling it done is the obvious way to get this wrong, and it would be
        // inaudible in a mono check.
        let buffer = try makeBuffer(channels: 2, frames: 4)
        try write([0.1, 0.2, 0.3, 0.4], to: buffer, channel: 0)
        try write([0.1, .nan, 0.3, .infinity], to: buffer, channel: 1)

        AudioOutputGuard.sweepNonFinite(buffer)

        XCTAssertEqual(try read(buffer, channel: 0, count: 4), [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(try read(buffer, channel: 1, count: 4), [0.1, 0, 0.3, 0])
    }

    func testSweepsFrameLength_notFrameCapacity() throws {
        // A shorter-than-capacity render is normal (the last block of a clip). The
        // tail past frameLength is not part of the audio and must not be walked —
        // and asserting it stays untouched is what pins that.
        let buffer = try makeBuffer(channels: 1, frames: 4, capacity: 8)
        try write([0.5, .nan, 0.5, 0.5, .nan, .nan, .nan, .nan], to: buffer, channel: 0)

        AudioOutputGuard.sweepNonFinite(buffer)

        XCTAssertEqual(try read(buffer, channel: 0, count: 4), [0.5, 0, 0.5, 0.5])
        let tail = try read(buffer, channel: 0, count: 8)[4...]
        XCTAssertTrue(tail.allSatisfy { $0.isNaN }, "the sweep ran past frameLength")
    }

    func testEmptyBufferIsSafe() throws {
        let buffer = try makeBuffer(channels: 1, frames: 0, capacity: 4)
        AudioOutputGuard.sweepNonFinite(buffer)   // must not trap
        XCTAssertEqual(buffer.frameLength, 0)
    }

    func testIntegerFormatIsIgnoredRatherThanMisread() throws {
        // `floatChannelData` is nil for a non-float format. Reinterpreting those bytes
        // as Float would corrupt real audio — and an integer sample cannot be NaN or
        // infinite in the first place, so there is nothing to sweep.
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000,
                          channels: 1, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let data = try XCTUnwrap(buffer.int16ChannelData)
        for i in 0..<4 { data[0][i] = Int16(1000 + i) }

        AudioOutputGuard.sweepNonFinite(buffer)   // no-op, must not trap

        XCTAssertEqual((0..<4).map { data[0][$0] }, [1000, 1001, 1002, 1003],
                       "an integer buffer must come back untouched")
    }
}
#endif
