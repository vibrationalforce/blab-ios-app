// AudioClipRegionTests.swift
// Echoelmusic — pure audio-clip region (trim/loop/frame) math.

import XCTest
@testable import Echoelmusic

final class AudioClipRegionTests: XCTestCase {

    func testInitClampsAndOrders() {
        let r = AudioClipRegion(startSeconds: -5, endSeconds: -1, gain: 9)
        XCTAssertEqual(r.startSeconds, 0)
        XCTAssertGreaterThan(r.endSeconds, r.startSeconds)
        XCTAssertEqual(r.gain, 2, "gain clamps to 2")
    }

    func testDuration() {
        let r = AudioClipRegion(startSeconds: 1.0, endSeconds: 3.5)
        XCTAssertEqual(r.durationSeconds, 2.5, accuracy: 1e-9)
    }

    func testFrameConversionClamps() {
        let r = AudioClipRegion(startSeconds: 1.0, endSeconds: 2.0)
        // 48k, file is 1.5 s long (72000 frames) — region wants 1..2 s but only 1.5 s exists.
        let total: Int64 = 72_000
        let start = r.startFrame(sampleRate: 48_000, totalFrames: total)
        let n = r.frameCount(sampleRate: 48_000, totalFrames: total)
        XCTAssertEqual(start, 48_000)
        XCTAssertEqual(start + n, total, "clamped so it never reads past the file")
    }

    func testFrameCountFull() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 1)
        XCTAssertEqual(r.frameCount(sampleRate: 44_100, totalFrames: 44_100), 44_100)
    }

    func testOneShotPlayheadFinishes() {
        let r = AudioClipRegion(startSeconds: 0.5, endSeconds: 1.5, loop: false)
        XCTAssertEqual(r.filePosition(atElapsed: 0) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.filePosition(atElapsed: 0.5) ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertNil(r.filePosition(atElapsed: 1.0), "one-shot ends at its duration")
        XCTAssertFalse(r.isActive(atElapsed: 1.1))
    }

    func testLoopPlayheadWraps() {
        let r = AudioClipRegion(startSeconds: 2.0, endSeconds: 4.0, loop: true) // 2 s region
        XCTAssertEqual(r.filePosition(atElapsed: 0) ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(r.filePosition(atElapsed: 1.0) ?? -1, 3.0, accuracy: 1e-9)
        XCTAssertEqual(r.filePosition(atElapsed: 2.5) ?? -1, 2.5, accuracy: 1e-9, "wraps after 2 s")
        XCTAssertEqual(r.filePosition(atElapsed: 4.25) ?? -1, 2.25, accuracy: 1e-9)
        XCTAssertTrue(r.isActive(atElapsed: 9999), "loop never finishes")
    }

    func testCodableRoundTrip() throws {
        let r = AudioClipRegion(startSeconds: 0.25, endSeconds: 3.0, loop: true, gain: 0.8)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(AudioClipRegion.self, from: data)
        XCTAssertEqual(back, r)
    }
}
