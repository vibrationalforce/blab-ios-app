// LatencyCompensationTests.swift
// Echoel — aligning a take to the beat. The recording lands late by the
// round-trip latency; compensation removes exactly that head offset so the
// vocal lines up with the transport (the keystone for recording over Bluetooth).

import XCTest
@testable import Echoelmusic

final class LatencyCompensationTests: XCTestCase {

    func testTotalSeconds_sumsComponents() {
        let c = LatencyCompensation(outputLatency: 0.12, inputLatency: 0.03, extraSeconds: 0.01)
        XCTAssertEqual(c.totalSeconds, 0.16, accuracy: 1e-9)
    }

    func testTotalSeconds_neverNegative() {
        let c = LatencyCompensation(outputLatency: 0.01, inputLatency: 0.0, extraSeconds: -0.5)
        XCTAssertEqual(c.totalSeconds, 0, "a negative nudge can't push the offset below zero")
    }

    func testFrameOffset_roundsAtSampleRate() {
        // 0.02 + 0.01 = 0.03 s at 48 kHz = 1440 frames.
        let c = LatencyCompensation(outputLatency: 0.02, inputLatency: 0.01)
        XCTAssertEqual(c.frameOffset(sampleRate: 48_000), 1440)
        XCTAssertEqual(c.frameOffset(sampleRate: 44_100), 1323)
    }

    func testFrameOffset_zeroSampleRate_isSafe() {
        let c = LatencyCompensation(outputLatency: 0.2, inputLatency: 0.05)
        XCTAssertEqual(c.frameOffset(sampleRate: 0), 0)
    }

    func testAligned_dropsLatencyHead() {
        let c = LatencyCompensation(outputLatency: 0.001, inputLatency: 0.0) // 0.001 s
        let sr = 1000.0                                  // → 1 frame offset
        let samples: [Float] = [9, 1, 2, 3, 4]
        let out = c.aligned(samples, sampleRate: sr)
        XCTAssertEqual(out, [1, 2, 3, 4], "the late head sample is removed")
    }

    func testAligned_noOffset_returnsInput() {
        let c = LatencyCompensation()                    // zero latency
        let samples: [Float] = [1, 2, 3]
        XCTAssertEqual(c.aligned(samples, sampleRate: 48_000), samples)
    }

    func testAligned_recordingShorterThanOffset_returnsEmpty() {
        let c = LatencyCompensation(outputLatency: 1.0, inputLatency: 0.0) // 1 s
        let sr = 1000.0                                  // → 1000 frame offset
        let samples: [Float] = [1, 2, 3]                 // far shorter
        XCTAssertEqual(c.aligned(samples, sampleRate: sr), [])
    }

    func testCodableRoundTrip() throws {
        let c = LatencyCompensation(outputLatency: 0.18, inputLatency: 0.02, extraSeconds: -0.005)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(LatencyCompensation.self, from: data)
        XCTAssertEqual(back, c)
    }
}
