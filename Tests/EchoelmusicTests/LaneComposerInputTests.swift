// LaneComposerInputTests.swift
// Pure, Linux-CI coverage for the per-track composition override seam: a lane's
// genre/mood/variation replace the matching global input fields; unset = passthrough.

import XCTest
@testable import Echoelmusic

final class LaneComposerInputTests: XCTestCase {

    private func base() -> BioComposer.Input {
        BioComposer.Input(key: MusicalKey(root: 0, scale: .dorian),
                          style: .dubTechno,
                          mood: MoodProfile(liveliness: 0.5),
                          seed: 0x1111,
                          structureSeed: 0x2222)
    }

    func testApply_noOverrides_isByteIdenticalPassthrough() {
        let lane = TimelineLane(name: "MIDI 2", kind: .midi)   // all overrides nil
        let out = LaneComposerInput.apply(lane, to: base())
        XCTAssertEqual(out.style, .dubTechno)
        XCTAssertEqual(out.mood, MoodProfile(liveliness: 0.5))
        XCTAssertEqual(out.seed, 0x1111)
        XCTAssertEqual(out.structureSeed, 0x2222)   // skeleton untouched
        XCTAssertFalse(LaneComposerInput.hasOverride(lane))
    }

    func testApply_genreOverride_replacesStyleOnly() {
        let lane = TimelineLane(name: "Bass", kind: .midi, genreOverride: .classical)
        let out = LaneComposerInput.apply(lane, to: base())
        XCTAssertEqual(out.style, .classical)
        XCTAssertEqual(out.seed, 0x1111)            // variation untouched
        XCTAssertEqual(out.structureSeed, 0x2222)   // cohesion skeleton untouched
        XCTAssertTrue(LaneComposerInput.hasOverride(lane))
    }

    func testApply_moodOverride_replacesMoodOnly() {
        let m = MoodProfile(liveliness: 0.9, darkness: 0.8)
        let lane = TimelineLane(name: "Pad", kind: .midi, mood: m)
        let out = LaneComposerInput.apply(lane, to: base())
        XCTAssertEqual(out.mood, m)
        XCTAssertEqual(out.style, .dubTechno)       // genre untouched
        XCTAssertTrue(LaneComposerInput.hasOverride(lane))
    }

    func testApply_variationSeed_replacesDetailSeedNotSkeleton() {
        let lane = TimelineLane(name: "Lead", kind: .midi, variationSeed: 0xDEAD_BEEF)
        let out = LaneComposerInput.apply(lane, to: base())
        XCTAssertEqual(out.seed, 0xDEAD_BEEF)       // detail = this lane's variation
        XCTAssertEqual(out.structureSeed, 0x2222)   // shared skeleton stays (cohesion)
        XCTAssertEqual(out.style, .dubTechno)
    }

    func testApply_allThree_composeThisLaneFully() {
        let m = MoodProfile(liveliness: 0.2, tension: 0.7)
        let lane = TimelineLane(name: "Solo", kind: .midi,
                                genreOverride: .classical, mood: m, variationSeed: 0x99)
        let out = LaneComposerInput.apply(lane, to: base())
        XCTAssertEqual(out.style, .classical)
        XCTAssertEqual(out.mood, m)
        XCTAssertEqual(out.seed, 0x99)
        XCTAssertEqual(out.structureSeed, 0x2222)
        // Body-driven fields the lane doesn't own pass through untouched.
        XCTAssertEqual(out.key.scale, .dorian)
        XCTAssertEqual(out.progressionPhase, base().progressionPhase)
    }
}
