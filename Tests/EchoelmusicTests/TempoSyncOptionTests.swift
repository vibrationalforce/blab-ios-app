// TempoSyncOptionTests.swift
// Echoel — tempo-synced FX/LFO rate options resolved against a BPM.

import XCTest
@testable import Echoelmusic

final class TempoSyncOptionTests: XCTestCase {

    func testHertzAt120BPM() {
        XCTAssertEqual(TempoSyncOption(.quarter).hertz(bpm: 120), 2.0, accuracy: 1e-9, "1/4 = 2 Hz")
        XCTAssertEqual(TempoSyncOption(.eighth).hertz(bpm: 120), 4.0, accuracy: 1e-9, "1/8 = 4 Hz")
        XCTAssertEqual(TempoSyncOption(.quarter, .triplet).hertz(bpm: 120), 3.0, accuracy: 1e-9,
                       "1/4 triplet = 3 Hz")
        XCTAssertEqual(TempoSyncOption(.quarter, .dotted).hertz(bpm: 120), 4.0 / 3.0, accuracy: 1e-9,
                       "dotted 1/4 ≈ 1.333 Hz")
    }

    func testSecondsAndMilliseconds() {
        let o = TempoSyncOption(.eighth)
        XCTAssertEqual(o.seconds(bpm: 120), 0.25, accuracy: 1e-9)
        XCTAssertEqual(o.milliseconds(bpm: 120), 250, accuracy: 1e-6)
    }

    func testClampedRateCapsToLFORange() {
        // 1/16 at 200 BPM = 13.33 Hz → clamp to an 8 Hz ceiling.
        let fast = TempoSyncOption(.sixteenth)
        XCTAssertEqual(fast.clampedRate(bpm: 200, in: 0.05...8), 8.0, accuracy: 1e-6)
        // A slow division clamps up to the floor.
        let slow = TempoSyncOption(.whole)
        XCTAssertEqual(slow.clampedRate(bpm: 60, in: 0.05...8), 0.25, accuracy: 1e-6)
    }

    func testClampedSecondsCapsToDelayWindow() {
        // 1/1 at 60 BPM = 4 s → clamp to a 1.5 s delay window.
        XCTAssertEqual(TempoSyncOption(.whole).clampedSeconds(bpm: 60, in: 0.02...1.5), 1.5, accuracy: 1e-6)
    }

    func testCommonListIsDistinctAndLabelled() {
        let common = TempoSyncOption.common
        XCTAssertEqual(common.count, 15, "5 divisions × 3 feels")
        XCTAssertEqual(Set(common.map(\.id)).count, common.count, "ids unique")
        XCTAssertEqual(Set(common.map(\.label)).count, common.count, "labels unique")
        XCTAssertTrue(common.contains { $0.label == "1/4" })
        XCTAssertTrue(common.contains { $0.label == "1/8·" })
        XCTAssertTrue(common.contains { $0.label == "1/8T" })
    }
}
