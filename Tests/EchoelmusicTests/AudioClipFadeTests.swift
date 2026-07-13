// AudioClipFadeTests.swift
// Audio-clip fades (founder: "Fades bei Audio auch möglich?"): an AudioClipRegion
// carries fade-in / fade-out lengths, and a PURE gain envelope maps elapsed clip
// time → [0…1] so the player can bake the ramp into the scheduled buffer (no
// render-thread work). Legacy regions (no fade keys) decode to no fade.

import XCTest
import Foundation
@testable import Echoelmusic

final class AudioClipFadeTests: XCTestCase {

    // MARK: - Envelope shape

    func testNoFade_isUnityEverywhere() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4)
        for t in stride(from: 0.0, through: 4.0, by: 0.5) {
            XCTAssertEqual(r.fadeMultiplier(atElapsed: t), 1, accuracy: 1e-6)
        }
    }

    func testFadeIn_risesLinearlyFromSilence() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4, fadeInSeconds: 2)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 0), 0, accuracy: 1e-6)   // starts silent
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 2), 1, accuracy: 1e-6)   // full at fade-in end
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 3), 1, accuracy: 1e-6)
    }

    func testFadeOut_fallsLinearlyToSilence() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4, fadeOutSeconds: 2)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 0), 1, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 2), 1, accuracy: 1e-6)   // out starts at dur-fout
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 3), 0.5, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 4), 0, accuracy: 1e-6)   // silent at the very end
    }

    func testFadeInAndOut_together() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4, fadeInSeconds: 1, fadeOutSeconds: 1)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 1), 1, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 2), 1, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 3), 1, accuracy: 1e-6)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 4), 0, accuracy: 1e-6)
    }

    // MARK: - Guards: overlap, over-long, negatives, degenerate

    func testOverlongFades_dontOvershoot_fadeInWins() {
        // fadeIn + fadeOut > duration → they can't both run full; in wins, out fills
        // the remainder, and the multiplier never leaves [0,1].
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 2, fadeInSeconds: 3, fadeOutSeconds: 3)
        for t in stride(from: 0.0, through: 2.0, by: 0.25) {
            let g = r.fadeMultiplier(atElapsed: t)
            XCTAssertGreaterThanOrEqual(g, 0)
            XCTAssertLessThanOrEqual(g, 1)
        }
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 0), 0, accuracy: 1e-6)
    }

    func testNegativeAndNonFiniteFades_clampToZero() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4,
                                fadeInSeconds: -5, fadeOutSeconds: .nan)
        XCTAssertEqual(r.fadeInSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(r.fadeOutSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 0), 1, accuracy: 1e-6)
    }

    func testElapsedOutOfBounds_isClampedSafe() {
        let r = AudioClipRegion(startSeconds: 0, endSeconds: 4, fadeInSeconds: 1, fadeOutSeconds: 1)
        XCTAssertEqual(r.fadeMultiplier(atElapsed: -1), 0, accuracy: 1e-6)   // before start = fade-in floor
        XCTAssertEqual(r.fadeMultiplier(atElapsed: 99), 0, accuracy: 1e-6)   // past end = faded out
    }

    // MARK: - Codable legacy

    func testLegacyRegionJSON_decodesWithNoFade() throws {
        let legacy = """
        {"startSeconds":0,"endSeconds":4,"loop":false,"gain":1}
        """.data(using: .utf8) ?? Data()
        let r = try JSONDecoder().decode(AudioClipRegion.self, from: legacy)
        XCTAssertEqual(r.fadeInSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(r.fadeOutSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(r.endSeconds, 4, accuracy: 1e-9)
    }

    func testFadeRegion_roundTripsThroughJSON() throws {
        let r = AudioClipRegion(startSeconds: 1, endSeconds: 5, loop: false, gain: 0.8,
                                fadeInSeconds: 0.5, fadeOutSeconds: 1.5)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(AudioClipRegion.self, from: data)
        XCTAssertEqual(back, r)
    }
}
