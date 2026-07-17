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

    // MARK: - composeLaneOverrides (Slice A — the per-lane compose fan-out)

    func testComposeLaneOverrides_noOverrides_returnsEmpty() {
        // Today's document shape: roll lane + a plain secondary MIDI lane + audio +
        // bio — nobody carries an override, so the fan-out composes NOTHING (empty
        // dictionary = today's sound, bit-identical).
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let lanes = [roll,
                     TimelineLane(name: "MIDI 2", kind: .midi),
                     TimelineLane(name: "Audio 1", kind: .audio),
                     TimelineLane(name: "Bio", kind: .midi, isBio: true)]
        let out = LaneComposerInput.composeLaneOverrides(base: base(), lanes: lanes,
                                                         rollLane: roll.id)
        XCTAssertTrue(out.isEmpty)
    }

    func testComposeLaneOverrides_overrideLane_getsNotes() {
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let solo = TimelineLane(name: "Solo", kind: .midi, genreOverride: .classical)
        let plain = TimelineLane(name: "MIDI 3", kind: .midi)
        let out = LaneComposerInput.composeLaneOverrides(base: base(),
                                                         lanes: [roll, solo, plain],
                                                         rollLane: roll.id)
        XCTAssertEqual(out.count, 1)
        XCTAssertNotNil(out[solo.id])
        XCTAssertFalse(out[solo.id]?.isEmpty ?? true)   // classical composes real notes
        XCTAssertNil(out[plain.id])                     // no override → not in the result
        XCTAssertNil(out[roll.id])                      // the roll lane is the primary take
    }

    func testComposeLaneOverrides_isDeterministic() {
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let a = TimelineLane(name: "A", kind: .midi, genreOverride: .classical)
        let b = TimelineLane(name: "B", kind: .midi,
                             mood: MoodProfile(liveliness: 0.9), variationSeed: 0x77)
        let lanes = [roll, a, b]
        let first = LaneComposerInput.composeLaneOverrides(base: base(), lanes: lanes,
                                                           rollLane: roll.id)
        let second = LaneComposerInput.composeLaneOverrides(base: base(), lanes: lanes,
                                                            rollLane: roll.id)
        XCTAssertEqual(first, second)   // Note ids included — fully seeded, no Date/random
    }

    func testComposeLaneOverrides_sharesStructureSkeleton_andDerivesDetailSeed() {
        // The fan-out must equal a hand-built per-lane input: overrides applied, the
        // SHARED skeleton pinned (BioVariationMaze pattern — same piece, different
        // detail), and the detail seed derived variationSeed ?? base.seed ^ fold(laneID).
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let lane = TimelineLane(name: "Genre only", kind: .midi, genreOverride: .classical)
        let out = LaneComposerInput.composeLaneOverrides(base: base(), lanes: [roll, lane],
                                                         rollLane: roll.id)
        var expected = LaneComposerInput.apply(lane, to: base())
        expected.structureSeed = base().structureSeed ?? base().seed
        expected.seed = base().seed ^ NoteOperators.fold(lane.id)   // no variationSeed set
        XCTAssertEqual(out[lane.id], BioComposer.compose(expected).notes)
    }

    func testComposeLaneOverrides_nilStructureSeed_pinsSkeletonToBaseSeed() {
        // A base WITHOUT a structure seed: the skeleton is pinned to base.seed (the
        // BioVariationMaze convention), so a variationSeed-only lane shifts DETAIL
        // only — never the shared skeleton.
        var noSkeleton = base()
        noSkeleton.structureSeed = nil
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let lane = TimelineLane(name: "Var only", kind: .midi, variationSeed: 0xDEAD)
        let out = LaneComposerInput.composeLaneOverrides(base: noSkeleton,
                                                         lanes: [roll, lane],
                                                         rollLane: roll.id)
        var expected = LaneComposerInput.apply(lane, to: noSkeleton)
        expected.structureSeed = noSkeleton.seed
        XCTAssertEqual(out[lane.id], BioComposer.compose(expected).notes)
    }

    func testComposeLaneOverrides_excludesRollAudioAndBioLanes() {
        // Even WITH overrides set, the roll lane (primary take), audio lanes and the
        // bio lane never enter the per-lane fan-out.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi, genreOverride: .classical)
        let audio = TimelineLane(name: "Audio 1", kind: .audio, genreOverride: .classical)
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true,
                               genreOverride: .classical)
        let out = LaneComposerInput.composeLaneOverrides(base: base(),
                                                         lanes: [roll, audio, bio],
                                                         rollLane: roll.id)
        XCTAssertTrue(out.isEmpty)
    }
}
