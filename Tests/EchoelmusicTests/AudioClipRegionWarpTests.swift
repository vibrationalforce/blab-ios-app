// AudioClipRegionWarpTests.swift
// Echoel — P2 warp/tempo-conform PURE core: AudioClipRegion gains warpEnabled +
// nativeBPM and the pitch-preserving stretch-rate/duration math (delegating to the
// already-tested TempoMatch). Foundation-only → runs on Linux CI; the actual offline
// AVAudioUnitTimePitch render is the device-gated next cycle. Verifies backward-compat
// decode, clamping, rate, and warped-duration.

import XCTest
@testable import Echoelmusic

final class AudioClipRegionWarpTests: XCTestCase {

    // MARK: Backward-compatible decode (regions saved before warp)

    func testDecode_legacyRegionWithoutWarpKeys_defaultsToNoWarp() throws {
        let json = """
        {"startSeconds":0.5,"endSeconds":2.5,"loop":true,"gain":0.8,
         "fadeInSeconds":0.1,"fadeOutSeconds":0.2}
        """.data(using: .utf8)!
        let region = try JSONDecoder().decode(AudioClipRegion.self, from: json)
        XCTAssertFalse(region.warpEnabled)
        XCTAssertEqual(region.nativeBPM, 0)
        XCTAssertEqual(region.startSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(region.endSeconds, 2.5, accuracy: 1e-9)
        XCTAssertTrue(region.loop)
        XCTAssertEqual(region.effectiveStretchRate(projectBPM: 128), 1.0, accuracy: 1e-12)
    }

    func testEncodeDecode_roundTrip_preservesWarp() throws {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                warpEnabled: true, nativeBPM: 120)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(AudioClipRegion.self, from: data)
        XCTAssertEqual(back, r)
        XCTAssertTrue(back.warpEnabled)
        XCTAssertEqual(back.nativeBPM, 120, accuracy: 1e-9)
    }

    // MARK: nativeBPM clamping

    func testInit_negativeOrNaNNativeBPM_becomesZero() {
        XCTAssertEqual(AudioClipRegion(nativeBPM: -50).nativeBPM, 0)
        XCTAssertEqual(AudioClipRegion(nativeBPM: .nan).nativeBPM, 0)
        XCTAssertEqual(AudioClipRegion(nativeBPM: 0).nativeBPM, 0)
    }

    func testInit_absurdNativeBPM_clampsToRange() {
        XCTAssertEqual(AudioClipRegion(nativeBPM: 5).nativeBPM,
                       AudioClipRegion.nativeBPMRange.lowerBound, accuracy: 1e-9)   // 20
        XCTAssertEqual(AudioClipRegion(nativeBPM: 10_000).nativeBPM,
                       AudioClipRegion.nativeBPMRange.upperBound, accuracy: 1e-9)   // 400
    }

    // MARK: Stretch-rate math

    func testEffectiveRate_warpDisabled_isUnity() {
        let r = AudioClipRegion(warpEnabled: false, nativeBPM: 120)
        XCTAssertEqual(r.effectiveStretchRate(projectBPM: 140), 1.0, accuracy: 1e-12)
    }

    func testEffectiveRate_unknownNative_isUnity() {
        let r = AudioClipRegion(warpEnabled: true, nativeBPM: 0)
        XCTAssertEqual(r.effectiveStretchRate(projectBPM: 140), 1.0, accuracy: 1e-12)
    }

    func testEffectiveRate_projectFaster_isRatio() {
        let r = AudioClipRegion(warpEnabled: true, nativeBPM: 120)
        XCTAssertEqual(r.effectiveStretchRate(projectBPM: 180), 1.5, accuracy: 1e-9)
    }

    func testEffectiveRate_clampedToMusicalRange() {
        let slow = AudioClipRegion(warpEnabled: true, nativeBPM: 120)
        XCTAssertEqual(slow.effectiveStretchRate(projectBPM: 20),
                       TempoMatch.rateRange.lowerBound, accuracy: 1e-9)             // floor 0.25
        let fast = AudioClipRegion(warpEnabled: true, nativeBPM: 20)
        XCTAssertEqual(fast.effectiveStretchRate(projectBPM: 400),
                       TempoMatch.rateRange.upperBound, accuracy: 1e-9)             // ceiling 4.0
    }

    // MARK: Warped duration

    func testWarpedDuration_unityWhenOff() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4,
                                warpEnabled: false, nativeBPM: 120)
        XCTAssertEqual(r.warpedDurationSeconds(projectBPM: 140),
                       r.durationSeconds, accuracy: 1e-9)
    }

    func testWarpedDuration_fasterProjectShortensClip() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                warpEnabled: true, nativeBPM: 120)
        XCTAssertEqual(r.warpedDurationSeconds(projectBPM: 240), 1.0, accuracy: 1e-9)
    }

    func testWarpedDuration_slowerProjectLengthensClip() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                warpEnabled: true, nativeBPM: 120)
        XCTAssertEqual(r.warpedDurationSeconds(projectBPM: 60), 4.0, accuracy: 1e-9)
    }
}
