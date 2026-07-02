// MusicStyleSwingTests.swift
// Echoel — guards the per-genre swing (GROOVE CYCLE 2). Swing feeds
// PatternEngine.setSwing on Generate; it must stay in the engine's [0, 0.5] window,
// the swung genres must actually swing, and the genres that would be hurt by grid
// swing (rigid electronic, straight rock/metal, classical rubato, ambient) must
// stay dead straight at 0.

import XCTest
@testable import Echoelmusic

final class MusicStyleSwingTests: XCTestCase {

    func testSwingInEngineRange() {
        // PatternEngine clamps to [0, 0.5]; values must already be inside it so the
        // authored feel is what actually plays (no silent clamp surprises).
        for style in MusicStyle.allCases {
            XCTAssertGreaterThanOrEqual(style.swing, 0, "\(style) swing must be >= 0")
            XCTAssertLessThanOrEqual(style.swing, 0.5, "\(style) swing must be <= 0.5")
        }
    }

    func testSwungGenresActuallySwing() {
        // The genres whose identity includes shuffle/bounce must carry real swing.
        XCTAssertGreaterThan(MusicStyle.jazz.swing, 0.30, "jazz is defined by its swung 8ths")
        XCTAssertGreaterThan(MusicStyle.rocknroll.swing, 0.20, "rock'n'roll shuffles")
        XCTAssertGreaterThan(MusicStyle.rocksteady.swing, 0.15, "rocksteady has a laid-back bounce")
        XCTAssertGreaterThan(MusicStyle.ska.swing, 0.10)
    }

    func testStraightGenresStayStraight() {
        // Grid swing would damage these — they must be exactly 0.
        for style in [MusicStyle.psytrance, .rock, .heavyMetal, .doom,
                      .classical, .selfObservation, .synthwave, .earlySynth, .punk] {
            XCTAssertEqual(style.swing, 0, "\(style) must stay straight (no grid swing)")
        }
    }

    func testJazzIsTheMostSwung() {
        let maxSwing = MusicStyle.allCases.map { $0.swing }.max() ?? 0
        XCTAssertEqual(MusicStyle.jazz.swing, maxSwing, "jazz should be the most swung genre")
    }

    // MULTITIMBRAL Step 2b — every genre's lead timbre must resolve to a real
    // factory patch, or the lead voice silently keeps the previous/default sound.
    func testEveryGenreLeadPatchExistsInFactory() {
        let names = Set(SynthPatch.factory.map { $0.name })
        for style in MusicStyle.allCases {
            XCTAssertTrue(names.contains(style.leadPatchName),
                          "\(style) lead patch '\(style.leadPatchName)' is not in SynthPatch.factory")
        }
    }

    func testLeadTimbresAreGenreDistinct() {
        // The point of Step 2b is variety — the lead is not one fixed sound across
        // all genres. Expect several different lead patches in use.
        let distinct = Set(MusicStyle.allCases.map { $0.leadPatchName })
        XCTAssertGreaterThanOrEqual(distinct.count, 6,
                                    "leads should span several instruments, got \(distinct.sorted())")
    }
}
